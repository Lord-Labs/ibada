import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'alarms.dart';
import 'app_theme.dart';
import 'devotion.dart';
import 'local_data.dart';
import 'prayer_times.dart';
import 'screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = LocalData();
  final settings = await data.load();
  runApp(IbadaApp(data: data, settings: settings));
}

@pragma('vm:entry-point')
Future<void> refreshPrayerAlarms() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.ibada/alarms');
  var refreshed = false;
  try {
    final data = LocalData();
    final settings = await data.load();
    await data.refreshTimeZones(settings.place.zone);
    await PrayerAlarms().replace(PrayerCalculator(settings), DateTime.now());
    refreshed = true;
  } finally {
    await channel.invokeMethod<void>('complete', refreshed);
  }
}

class IbadaApp extends StatefulWidget {
  const IbadaApp({super.key, required this.data, required this.settings});
  final LocalData data;
  final PrayerSettings settings;

  @override
  State<IbadaApp> createState() => _IbadaAppState();
}

class _IbadaAppState extends State<IbadaApp> {
  late PrayerSettings settings = widget.settings;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'عبادة',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ibadaTheme(Brightness.light),
    darkTheme: ibadaTheme(Brightness.dark),
    themeMode: switch (settings.appearance) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    home: _Home(
      data: widget.data,
      initial: settings,
      onAppearance: (updated) => setState(() => settings = updated),
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({
    required this.data,
    required this.initial,
    required this.onAppearance,
  });
  final LocalData data;
  final PrayerSettings initial;
  final ValueChanged<PrayerSettings> onAppearance;

  @override
  State<_Home> createState() => _HomeState();
}

enum _Tab { today, adhkar, tasbeeh, settings }

typedef _MediaChoice = ({
  String label,
  IconData icon,
  String action,
  String? preset,
});

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  final _cities = CityDirectory();
  final _alarms = PrayerAlarms();
  final _clock = ValueNotifier(DateTime.now());
  final _messages = GlobalKey<ScaffoldMessengerState>();
  late PrayerSettings _settings = widget.initial;
  late PrayerCalculator _calculator = PrayerCalculator(_settings);
  late DateTime _date = civilKey(_calculator.localTime(_clock.value));
  AlarmStatus _status = PrayerAlarms.unknown;
  AlarmMedia? _media;
  Future<void> _writes = Future.value();
  late final Timer _ticker;
  bool _refreshing = false;
  bool _repositioning = false;
  bool _handlingPermission = false;
  bool _schedulingFailed = false;
  bool _mediaBusy = false;
  _Tab _tab = _Tab.today;
  int _dayOffset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_resume());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_requestStartupPermissions());
    });
  }

  void _tick() {
    _clock.value = DateTime.now();
    final today = civilKey(_calculator.localTime(_clock.value));
    if (today != _date) {
      setState(() => _date = today);
      unawaited(_refreshZones());
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  Future<void> _resume() async {
    _tick();
    unawaited(_refreshZones());
    await _readStatus();
    if (!mounted) return;
    _schedule();
    if (_settings.place.usesGps) await _refreshPosition();
  }

  Future<void> _requestStartupPermissions() async {
    if (!_alarms.supported ||
        !await widget.data.claimStartupPermissions() ||
        !mounted) {
      return;
    }

    if (!_settings.confirmedPlace) {
      try {
        await _cities.requestPermission();
      } on Exception {
        // The city picker remains available if the system cannot use location.
      }
      if (!mounted) return;
      if (!_settings.confirmedPlace) unawaited(_refreshPosition(initial: true));
    }

    await _request('startupNotifications');
    if (mounted && _status.notifications && !_settings.alarms) {
      _update(_settings.copyWith(alarms: true));
    }
  }

  Future<void> _refreshPosition({bool initial = false}) async {
    if (_repositioning) return;
    final previous = _settings.place;
    _repositioning = true;
    try {
      final updated = await _cities.current(askPermission: false);
      if (!mounted || !identical(previous, _settings.place)) return;
      final moved =
          updated.zone != previous.zone ||
          (updated.latitude - previous.latitude).abs() > .02 ||
          (updated.longitude - previous.longitude).abs() > .02;
      if (initial ? !_settings.confirmedPlace : moved) {
        _update(_settings.copyWith(place: updated, confirmedPlace: true));
      }
    } on Exception {
      // Keep the current place available while GPS is unavailable.
    } finally {
      _repositioning = false;
    }
  }

  Future<void> _refreshZones() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (await widget.data.refreshTimeZones(_settings.place.zone) && mounted) {
        setState(() {
          _calculator = PrayerCalculator(_settings);
          _date = civilKey(_calculator.localTime(_clock.value));
        });
        _schedule();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _readStatus() async {
    if (!_alarms.supported) return;
    try {
      final status = await _alarms.status();
      if (mounted) setState(() => _status = status);
    } on PlatformException {
      if (mounted) setState(() => _status = PrayerAlarms.unknown);
    }
  }

  void _schedule({bool save = false}) {
    final calculator = _calculator;
    _writes = _writes.then((_) async {
      try {
        if (save) await widget.data.save(calculator.settings);
        if (_alarms.supported && identical(_calculator, calculator)) {
          await _alarms.replace(calculator, DateTime.now());
          await _readStatus();
        }
        if (mounted && _schedulingFailed) {
          setState(() => _schedulingFailed = false);
        }
      } on Exception {
        if (mounted) setState(() => _schedulingFailed = true);
      }
    });
  }

  void _update(PrayerSettings settings) {
    setState(() {
      _settings = settings;
      _calculator = PrayerCalculator(settings);
      _date = civilKey(_calculator.localTime(_clock.value));
    });
    if (settings.appearance != widget.initial.appearance) {
      widget.onAppearance(settings);
    }
    _schedule(save: true);
  }

  Future<bool> _choosePlace() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) =>
            LocationScreen(directory: _cities, selected: _settings.place),
      ),
    );
    if (place == null || !mounted) return false;
    _update(_settings.copyWith(place: place, confirmedPlace: true));
    setState(() => _dayOffset = 0);
    return true;
  }

  Future<void> _openWeek() async {
    final day = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            top: false,
            child: WeekScreen(
              calculator: _calculator,
              today: _date,
              onSelect: (day) => Navigator.pop(context, day),
            ),
          ),
        ),
      ),
    );
    if (day != null && mounted) {
      setState(() => _dayOffset = day.difference(_date).inDays);
    }
  }

  void _selectTab(_Tab tab) {
    setState(() {
      _tab = tab;
      if (tab == _Tab.today) _dayOffset = 0;
    });
    if (tab == _Tab.settings) unawaited(_readMedia());
  }

  Future<void> _readMedia() async {
    if (!_alarms.supported) return;
    try {
      final media = await _alarms.media();
      if (mounted) setState(() => _media = media);
    } on Exception {
      if (mounted) setState(() => _media = null);
    }
  }

  Future<void> _chooseAlertMedia({required bool image}) async {
    final media = _media;
    if (_mediaBusy || media == null) return;
    final List<_MediaChoice> choices = image
        ? [
            (
              label: 'الخلفية الافتراضية',
              icon: Icons.wallpaper_outlined,
              action: 'resetImage',
              preset: null,
            ),
            if (media.imagePreset)
              (
                label: 'أفق المساء',
                icon: Icons.landscape_outlined,
                action: 'setImagePreset',
                preset: 'horizon',
              ),
            (
              label: 'اختيار صورة من الجهاز',
              icon: Icons.add_photo_alternate_outlined,
              action: 'pickImage',
              preset: null,
            ),
          ]
        : [
            (
              label: media.systemSounds ? 'نغمة عبادة' : 'نغمة النظام',
              icon: Icons.notifications_outlined,
              action: 'resetSound',
              preset: null,
            ),
            for (final preset in media.soundPresets.entries)
              (
                label: preset.value,
                icon: Icons.record_voice_over_outlined,
                action: 'setSoundPreset',
                preset: preset.key,
              ),
            if (media.soundPreset)
              (
                label: 'نغمة عبادة الهادئة',
                icon: Icons.music_note_outlined,
                action: 'setSoundPreset',
                preset: 'soft',
              ),
            if (media.systemSounds)
              (
                label: 'اختيار نغمة من الهاتف',
                icon: Icons.library_music_outlined,
                action: 'pickTone',
                preset: null,
              ),
            (
              label: 'اختيار ملف صوتي',
              icon: Icons.audio_file_outlined,
              action: 'pickSound',
              preset: null,
            ),
          ];
    final selected = await showModalBottomSheet<_MediaChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
          children: [
            ListTile(
              title: Text(image ? 'صورة التنبيه' : 'نغمة التنبيه'),
              subtitle: image && media.imageScope == 'notification'
                  ? const Text(
                      'تظهر الصورة عند توسيع الإشعار العادي على iPhone.',
                    )
                  : !image && media.soundPresets.isNotEmpty
                  ? const Text('مقاطع أذان مدمجة تعمل بدون إنترنت.')
                  : null,
            ),
            for (final choice in choices)
              ListTile(
                leading: Icon(choice.icon),
                title: Text(choice.label),
                selected:
                    choice.label ==
                    (image
                        ? media.image ?? choices.first.label
                        : media.sound ?? choices.first.label),
                onTap: () => Navigator.pop(sheetContext, choice),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _mediaBusy = true);
    try {
      await _alarms.changeMedia(selected.action, selected.preset);
      await _readMedia();
      if (mounted) _schedule();
    } on PlatformException catch (error) {
      if (mounted) _message(error.message ?? 'تعذّر تغيير تخصيص التنبيه.');
    } finally {
      if (mounted) setState(() => _mediaBusy = false);
    }
  }

  void _message(String message) {
    _messages.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _request(String permission) async {
    if (_handlingPermission) return;
    _handlingPermission = true;
    try {
      await _alarms.request(permission);
      await _readStatus();
      if (mounted) _schedule();
    } on PlatformException {
      if (mounted) _message('تعذّر فتح إعدادات التنبيه.');
    } finally {
      _handlingPermission = false;
    }
  }

  Future<void> _setAlerts(bool enabled) async {
    if (enabled && !_settings.confirmedPlace && !await _choosePlace()) return;
    if (!mounted) return;
    _update(_settings.copyWith(alarms: enabled));
    if (enabled && !_status.notifications) await _request('notifications');
  }

  Future<void> _testAlert() async {
    await _readStatus();
    if (!mounted) return;
    final android = Theme.of(context).platform == TargetPlatform.android;
    if (android && !_status.exact) {
      _message('فعّل إذن المنبّه الدقيق لجدولة التجربة خلال ١٥ ثانية.');
      return;
    }
    if (!_status.notifications && (android || !_status.exact)) {
      _message('فعّل إذن الإشعارات أولًا.');
      return;
    }
    try {
      await _alarms.test(_settings.fullScreen);
      if (mounted) {
        _message('هيظهر تنبيه تجريبي خلال ١٥ ثانية. تقدر تقفل الشاشة دلوقتي.');
      }
    } on PlatformException {
      _message('تعذّر جدولة التنبيه التجريبي.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = IbadaColors.of(context);
    final style = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: ScaffoldMessenger(
        key: _messages,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: switch (_tab) {
              _Tab.adhkar => const AdhkarScreen(),
              _Tab.tasbeeh => const TasbeehScreen(),
              _Tab.settings => SettingsScreen(
                settings: _settings,
                status: _status,
                schedulingFailed: _schedulingFailed,
                onChange: _update,
                onPlace: _choosePlace,
                onAlerts: _setAlerts,
                onPermission: _request,
                onTest: _testAlert,
                media: _media,
                mediaBusy: _mediaBusy,
                onSound: () => _chooseAlertMedia(image: false),
                onImage: () => _chooseAlertMedia(image: true),
              ),
              _Tab.today => TodayScreen(
                calculator: _calculator,
                today: _date,
                offset: _dayOffset,
                clock: _clock,
                onLocation: _choosePlace,
                onAlerts: () => _selectTab(_Tab.settings),
                onWeek: _openWeek,
                onExactAlarm:
                    Theme.of(context).platform == TargetPlatform.android &&
                        _settings.alarms &&
                        _status.supported &&
                        _status.notifications &&
                        !_status.exact
                    ? () => _request('exact')
                    : null,
                onDay: (offset) => setState(() => _dayOffset = offset),
                onPrayer: (prayer) =>
                    showPrayerOptions(context, _settings, prayer, _update),
              ),
            },
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.line)),
            ),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: NavigationBar(
                  selectedIndex: _tab.index,
                  labelBehavior: MediaQuery.textScalerOf(context).scale(12) > 16
                      ? NavigationDestinationLabelBehavior.onlyShowSelected
                      : NavigationDestinationLabelBehavior.alwaysShow,
                  onDestinationSelected: (index) =>
                      _selectTab(_Tab.values[index]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.wb_twilight_outlined),
                      label: 'اليوم',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_stories_outlined),
                      label: 'الأذكار',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.blur_circular_rounded),
                      label: 'السبحة',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_rounded),
                      label: 'الإعدادات',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
