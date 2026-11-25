import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import 'alarms.dart';
import 'app_theme.dart';
import 'local_data.dart';
import 'prayer_times.dart';

const _prayerIcons = [
  Icons.nights_stay_outlined,
  Icons.wb_twilight_outlined,
  Icons.light_mode_outlined,
  Icons.cloud_outlined,
  Icons.wb_twilight_outlined,
  Icons.dark_mode_outlined,
];
const _numbers = [FontFeature.tabularFigures()];

String arabicDigits(Object value) => value.toString().replaceAllMapped(
  RegExp('[0-9]'),
  (match) => '٠١٢٣٤٥٦٧٨٩'[int.parse(match[0]!)],
);

String _dateText(DateTime date) =>
    arabicDigits(DateFormat('EEEE، d MMMM', 'ar').format(date));

String _pair(int value) => arabicDigits(value.toString().padLeft(2, '0'));

String _hour(DateTime time, bool use24Hour) {
  final hour = use24Hour ? time.hour : (time.hour + 11) % 12 + 1;
  return '${_pair(hour)}:${_pair(time.minute)}';
}

class TimeLabel extends StatelessWidget {
  const TimeLabel(
    this.time, {
    super.key,
    required this.use24Hour,
    this.color,
    this.size = 17,
  });
  final DateTime time;
  final bool use24Hour;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: _hour(time, use24Hour)),
        if (!use24Hour)
          TextSpan(
            text: time.hour < 12 ? ' ص' : ' م',
            style: TextStyle(fontSize: size * .72, fontWeight: FontWeight.w400),
          ),
      ],
    ),
    textDirection: TextDirection.ltr,
    style: TextStyle(
      fontSize: size,
      color: color,
      fontWeight: FontWeight.w600,
      fontFeatures: _numbers,
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 32),
        children: children,
      ),
    ),
  );
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({
    super.key,
    required this.calculator,
    required this.today,
    required this.offset,
    required this.clock,
    required this.onLocation,
    required this.onAlerts,
    this.onExactAlarm,
    this.onWeek,
    required this.onDay,
    required this.onPrayer,
  });
  final PrayerCalculator calculator;
  final DateTime today;
  final int offset;
  final ValueNotifier<DateTime> clock;
  final VoidCallback onLocation, onAlerts;
  final VoidCallback? onExactAlarm, onWeek;
  final ValueChanged<int> onDay;
  final ValueChanged<Prayer> onPrayer;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    final settings = calculator.settings;
    final day = calculator.forDay(civilKey(today, offset));
    return _Page(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: IbadaHeading('مواقيت الصلاة', subtitle: _dateText(today)),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'إعدادات التنبيهات',
              onPressed: onAlerts,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: onLocation,
              icon: Icon(
                settings.place.usesGps
                    ? Icons.my_location_rounded
                    : Icons.place_outlined,
                size: 19,
              ),
              label: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(settings.place.name),
                  if (!settings.confirmedPlace)
                    const Text(
                      'اختر موقعك لحساب مواقيتك',
                      style: TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
            if (onWeek != null)
              TextButton.icon(
                onPressed: onWeek,
                icon: const Icon(Icons.calendar_month_outlined, size: 19),
                label: const Text('جدول الأسبوع'),
              ),
          ],
        ),
        const SizedBox(height: 15),
        ValueListenableBuilder(
          valueListenable: clock,
          builder: (context, now, _) {
            final state = calculator.at(now);
            return _NextCard(
              next: state.next,
              progress: state.progress,
              remaining: state.next.time.difference(now),
              use24Hour: settings.use24Hour,
            );
          },
        ),
        if (onExactAlarm != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onExactAlarm,
              icon: const Icon(Icons.alarm_add_outlined, size: 20),
              label: const Text('فعّل المنبّه الدقيق'),
            ),
          ),
        const SizedBox(height: 20),
        IbadaHeading(
          offset == 0 ? 'صلوات اليوم' : _dateText(day.day),
          compact: true,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'اليوم السابق',
              onPressed: () => onDay(offset - 1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: offset == 0
                  ? Center(
                      child: Text(
                        'اليوم',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    )
                  : Center(
                      child: TextButton(
                        onPressed: () => onDay(0),
                        child: const Text('العودة لليوم'),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'اليوم التالي',
              onPressed: () => onDay(offset + 1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: clock,
          builder: (context, now, _) {
            final next = calculator.at(now).next;
            return _Panel(
              children: [
                for (final event in day.events)
                  _PrayerRow(
                    event: event,
                    isNext:
                        next.time == event.time && next.prayer == event.prayer,
                    use24Hour: settings.use24Hour,
                    alerts:
                        settings.alarms &&
                        settings.enabled.contains(event.prayer),
                    onTap: () => onPrayer(event.prayer),
                  ),
              ],
            );
          },
        ),
        if (day.estimated) const _EstimateNote(),
      ],
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({
    required this.next,
    required this.progress,
    required this.remaining,
    required this.use24Hour,
  });
  final PrayerEvent next;
  final double progress;
  final Duration remaining;
  final bool use24Hour;

  @override
  Widget build(BuildContext context) {
    final seconds = math.max(0, (remaining.inMilliseconds / 1000).ceil());
    final timer =
        '${_pair(seconds ~/ 3600)}:${_pair((seconds ~/ 60) % 60)}:${_pair(seconds % 60)}';
    return Material(
      color: IbadaColors.pine,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/materials/prayer-horizon.webp',
              fit: BoxFit.cover,
              alignment: Alignment.centerLeft,
              color: IbadaColors.horizonShade,
              colorBlendMode: BlendMode.srcOver,
              excludeFromSemantics: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'الصلاة القادمة',
                  style: TextStyle(
                    color: IbadaColors.pale,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      next.prayer.label,
                      style: const TextStyle(
                        color: IbadaColors.cream,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                    TimeLabel(
                      next.time,
                      use24Hour: use24Hour,
                      color: IbadaColors.cream,
                      size: 19,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'الوقت المتبقي',
                  style: TextStyle(color: IbadaColors.pale, fontSize: 13),
                ),
                Semantics(
                  label:
                      '${arabicDigits(seconds ~/ 3600)} ساعة و'
                      '${arabicDigits((seconds ~/ 60) % 60)} دقيقة',
                  excludeSemantics: true,
                  child: Text(
                    timer,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: IbadaColors.amber,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontFeatures: _numbers,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(8),
                    color: IbadaColors.amber,
                    backgroundColor: IbadaColors.pale.withValues(alpha: .28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return IbadaSurface(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i != 0)
              Divider(height: 1, indent: 13, endIndent: 13, color: colors.line),
            Semantics(container: true, child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.event,
    required this.isNext,
    required this.use24Hour,
    required this.alerts,
    required this.onTap,
  });
  final PrayerEvent event;
  final bool isNext, use24Hour, alerts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return ListTile(
      tileColor: isNext ? colors.tint : null,
      onTap: onTap,
      minTileHeight: 56,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 4, 16, 4),
      leading: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isNext ? colors.surface : colors.tint,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              _prayerIcons[event.prayer.index],
              color: colors.accent,
              size: 19,
            ),
          ),
        ),
      ),
      title: Text(
        event.prayer.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
          color: colors.ink,
        ),
      ),
      subtitle: isNext
          ? Text(
              'القادمة',
              style: TextStyle(color: colors.tintInk, fontSize: 12),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (event.prayer != Prayer.sunrise) ...[
            Icon(
              alerts
                  ? Icons.notifications_none_rounded
                  : Icons.notifications_off_outlined,
              size: 16,
              color: colors.muted,
              semanticLabel: alerts ? 'التنبيه مفعّل' : 'التنبيه متوقف',
            ),
            const SizedBox(width: 10),
          ],
          TimeLabel(
            event.time,
            use24Hour: use24Hour,
            color: colors.ink,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class _EstimateNote extends StatelessWidget {
  const _EstimateNote();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      'بعض المواقيت تقديرية لغياب الشفق أو الشروق أو الغروب في هذا اليوم.',
      style: TextStyle(color: IbadaColors.of(context).muted, fontSize: 12),
    ),
  );
}

class WeekScreen extends StatelessWidget {
  const WeekScreen({
    super.key,
    required this.calculator,
    required this.today,
    required this.onSelect,
  });
  final PrayerCalculator calculator;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return _Page(
      children: [
        IbadaHeading(calculator.settings.place.name, compact: true),
        const SizedBox(height: 20),
        for (var i = 0; i < 7; i++) ...[
          _Panel(
            children: [
              ListTile(
                title: Text(
                  i == 0
                      ? 'اليوم · ${_dateText(today)}'
                      : _dateText(civilKey(today, i)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => onSelect(civilKey(today, i)),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 15),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final day = calculator.forDay(civilKey(today, i));
                    final scale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    final columns = (constraints.maxWidth / (92 * scale))
                        .floor()
                        .clamp(1, 6);
                    final width = constraints.maxWidth / columns;
                    return Column(
                      children: [
                        Wrap(
                          runSpacing: 14,
                          children: [
                            for (final event in day.events)
                              SizedBox(
                                width: width,
                                child: Column(
                                  children: [
                                    Text(
                                      event.prayer.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    TimeLabel(
                                      event.time,
                                      use24Hour: calculator.settings.use24Hour,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        if (day.estimated) const _EstimateNote(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.status,
    required this.schedulingFailed,
    required this.onChange,
    required this.onPlace,
    required this.onAlerts,
    required this.onPermission,
    required this.onTest,
    this.media,
    this.mediaBusy = false,
    this.onSound,
    this.onImage,
  });
  final PrayerSettings settings;
  final AlarmStatus status;
  final bool schedulingFailed;
  final ValueChanged<PrayerSettings> onChange;
  final VoidCallback onPlace, onTest;
  final ValueChanged<bool> onAlerts;
  final ValueChanged<String> onPermission;
  final AlarmMedia? media;
  final bool mediaBusy;
  final VoidCallback? onSound, onImage;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    final alertMedia = media;
    return _Page(
      children: [
        const IbadaHeading(
          'الإعدادات',
          subtitle: 'التنبيهات والمواقيت والمظهر',
        ),
        const SizedBox(height: 21),
        const _SectionLabel('التنبيهات'),
        _Panel(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('تنبيهات الصلاة'),
              subtitle: const Text('صوت وإشعار في موعد الصلاة'),
              value: settings.alarms,
              onChanged: status.supported ? onAlerts : null,
            ),
            if (Theme.of(context).platform == TargetPlatform.android)
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: const Text('ملء الشاشة عند قفل الهاتف'),
                subtitle: const Text('يتطلب إذنًا من النظام'),
                value: settings.fullScreen,
                onChanged: (value) =>
                    onChange(settings.copyWith(fullScreen: value)),
              ),
            if (settings.alarms &&
                !status.notifications &&
                !(status.alarmKit && status.exact))
              _PermissionTile(
                'إذن الإشعارات',
                'السماح بظهور تنبيه الصلاة',
                () => onPermission('notifications'),
              ),
            if (settings.alarms &&
                status.supported &&
                !status.exact &&
                Theme.of(context).platform == TargetPlatform.android)
              _PermissionTile(
                'إذن المنبّه الدقيق',
                'التنبيه قد يتأخر بدونه',
                () => onPermission('exact'),
              ),
            if (settings.alarms &&
                !status.fullScreen &&
                settings.fullScreen &&
                status.supported &&
                Theme.of(context).platform == TargetPlatform.android)
              _PermissionTile(
                'إذن ملء الشاشة',
                'إظهار التنبيه فوق شاشة القفل',
                () => onPermission('fullScreen'),
              ),
            if (settings.alarms && status.alarmKit && !status.exact)
              _PermissionTile(
                'إذن منبّه iPhone',
                'تشغيل منبّه النظام على شاشة القفل',
                () => onPermission('exact'),
              ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('جرّب التنبيه'),
              subtitle: const Text('تجربة قصيرة قبل موعد الصلاة'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: status.supported ? onTest : null,
            ),
          ],
        ),
        if (schedulingFailed)
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: Text(
              'تعذّرت جدولة التنبيهات. راجع أذونات النظام وافتح التطبيق مرة أخرى.',
            ),
          ),
        if (alertMedia != null) ...[
          const SizedBox(height: 20),
          const _SectionLabel('تخصيص التنبيه'),
          _Panel(
            children: [
              ListTile(
                leading: const Icon(Icons.music_note_outlined),
                title: const Text('نغمة التنبيه'),
                subtitle: Text(
                  alertMedia.sound ??
                      (alertMedia.systemSounds ? 'نغمة عبادة' : 'نغمة النظام'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: mediaBusy ? null : onSound,
              ),
              if (alertMedia.imageSupported)
                ListTile(
                  leading: const Icon(Icons.wallpaper_outlined),
                  title: Text(
                    alertMedia.imageScope == 'notification'
                        ? 'صورة الإشعار الموسّع'
                        : 'خلفية شاشة التنبيه',
                  ),
                  subtitle: Text(
                    alertMedia.image ?? 'الخلفية الافتراضية',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: mediaBusy ? null : onImage,
                ),
            ],
          ),
          if (mediaBusy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
        const SizedBox(height: 9),
        Text(
          'تقدر تغيّر تنبيه كل صلاة وتضبط دقائقها بالضغط عليها في شاشة اليوم.',
          style: TextStyle(fontSize: 13, color: colors.muted, height: 1.55),
        ),
        const SizedBox(height: 19),
        const _SectionLabel('المواقيت'),
        _Panel(
          children: [
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('الموقع'),
              subtitle: Text(settings.place.name),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: onPlace,
            ),
            _ChoiceTile(
              title: 'طريقة الحساب',
              description: settings.resolvedMethod.label,
              icon: Icons.calculate_outlined,
              values: PrayerMethod.values,
              current: settings.method,
              label: (method) => method.label,
              onSelect: (method) => onChange(settings.copyWith(method: method)),
            ),
            _ChoiceTile(
              title: 'حساب العصر',
              description: settings.hanafi
                  ? 'الحنفي'
                  : 'الشافعي والمالكي والحنبلي',
              icon: Icons.light_mode_outlined,
              values: const [false, true],
              current: settings.hanafi,
              label: (hanafi) =>
                  hanafi ? 'الحنفي' : 'الشافعي والمالكي والحنبلي',
              onSelect: (hanafi) => onChange(settings.copyWith(hanafi: hanafi)),
            ),
            _ChoiceTile(
              title: 'خطوط العرض العليا',
              description: settings.latitudeRule.label,
              icon: Icons.public_outlined,
              values: LatitudeRule.values,
              current: settings.latitudeRule,
              label: (rule) => rule.label,
              onSelect: (rule) =>
                  onChange(settings.copyWith(latitudeRule: rule)),
            ),
          ],
        ),
        const SizedBox(height: 19),
        const _SectionLabel('المظهر'),
        _Panel(
          children: [
            _ChoiceTile(
              title: 'الوضع الفاتح والداكن',
              description: _appearanceLabel(settings.appearance),
              icon: Icons.brightness_6_outlined,
              values: const ['system', 'light', 'dark'],
              current: settings.appearance,
              label: _appearanceLabel,
              onSelect: (mode) => onChange(settings.copyWith(appearance: mode)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule_rounded),
              title: const Text('نظام ٢٤ ساعة'),
              value: settings.use24Hour,
              onChanged: (value) =>
                  onChange(settings.copyWith(use24Hour: value)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'بيانات المدن من GeoNames. حدود المناطق الزمنية من OpenStreetMap '
          'عبر Timezone Boundary Builder. المواقيت محسوبة فلكيًا وقد تختلف عن التقويم المحلي.',
          style: TextStyle(fontSize: 11, color: colors.muted, height: 1.8),
        ),
      ],
    );
  }
}

String _appearanceLabel(String mode) => switch (mode) {
  'light' => 'فاتح',
  'dark' => 'داكن',
  _ => 'إعدادات النظام',
};

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 3, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: TextStyle(
          color: IbadaColors.of(context).accent,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile(this.title, this.description, this.onTap);
  final String title, description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.info_outline_rounded),
    title: Text(title),
    subtitle: Text(description),
    trailing: const Icon(Icons.open_in_new_rounded, size: 19),
    onTap: onTap,
  );
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.values,
    required this.current,
    required this.label,
    required this.onSelect,
  });
  final String title, description;
  final IconData icon;
  final List<T> values;
  final T current;
  final String Function(T) label;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(description),
    trailing: const Icon(Icons.chevron_left_rounded),
    onTap: () async {
      final result = await showModalBottomSheet<T>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 21,
                    vertical: 6,
                  ),
                  child: _SectionLabel(title),
                ),
                for (final item in values)
                  ListTile(
                    title: Text(label(item)),
                    selected: item == current,
                    trailing: item == current
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, item),
                  ),
              ],
            ),
          ),
        ),
      );
      if (result != null && context.mounted) onSelect(result);
    },
  );
}

Future<void> showPrayerOptions(
  BuildContext context,
  PrayerSettings settings,
  Prayer prayer,
  ValueChanged<PrayerSettings> onChange,
) async {
  var minutes = settings.offsets[prayer] ?? 0;
  var enabled = settings.enabled.contains(prayer);
  final didSave = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      top: false,
      child: StatefulBuilder(
        builder: (context, update) => SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IbadaHeading(prayer.label, subtitle: 'تعديل الموعد بالدقائق'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: 'ناقص دقيقة',
                    onPressed: minutes <= -30
                        ? null
                        : () => update(() => minutes--),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      arabicDigits(minutes > 0 ? '+$minutes' : minutes),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 23),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'زائد دقيقة',
                    onPressed: minutes >= 30
                        ? null
                        : () => update(() => minutes++),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              if (prayer != Prayer.sunrise)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('تنبيه ${prayer.label}'),
                  value: enabled,
                  onChanged: (value) => update(() => enabled = value),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (didSave == true && context.mounted) {
    final alerts = {...settings.enabled};
    if (enabled && prayer != Prayer.sunrise) {
      alerts.add(prayer);
    } else {
      alerts.remove(prayer);
    }
    onChange(
      settings.copyWith(
        enabled: alerts,
        offsets: {...settings.offsets, prayer: minutes},
      ),
    );
  }
}

class LocationScreen extends StatefulWidget {
  const LocationScreen({
    super.key,
    required this.directory,
    required this.selected,
  });
  final CityDirectory directory;
  final Place selected;

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  late final Future<List<City>> _cities = widget.directory.load();
  String _query = '';
  String? _error;
  bool _locating = false;

  Future<void> _manual() async {
    final point = await showDialog<({double latitude, double longitude})>(
      context: context,
      builder: (_) => const _CoordinateDialog(),
    );
    if (!mounted || point == null) return;
    setState(() => _locating = true);
    try {
      final place = await widget.directory.coordinates(
        point.latitude,
        point.longitude,
      );
      if (mounted) Navigator.pop(context, place);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'تعذّر تحديد المنطقة الزمنية للإحداثيات.';
          _locating = false;
        });
      }
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final place = await widget.directory.current(askPermission: true);
      if (mounted) Navigator.pop(context, place);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is LocationProblem
              ? error.message
              : 'تعذّر تحديد موقعك. جرّب في مكان مفتوح أو اختر مدينة.';
          _locating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('اختر موقعك')),
      body: SafeArea(
        child: _Page(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'ابحث عن مدينة',
                hintText: 'القاهرة أو London',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              textInputAction: TextInputAction.search,
              onChanged: (text) => setState(() => _query = searchKey(text)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _locating ? null : _locate,
                  icon: const Icon(Icons.my_location_rounded, size: 19),
                  label: Text(
                    _locating ? 'جارٍ تحديد الموقع…' : 'استخدم موقعي الحالي',
                  ),
                ),
                TextButton.icon(
                  onPressed: _locating ? null : _manual,
                  icon: const Icon(Icons.pin_drop_outlined),
                  label: const Text('إدخال الإحداثيات يدويًا'),
                ),
              ],
            ),
            if (_locating)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  semanticsLabel: 'جارٍ تحديد الموقع',
                ),
              ),
            if (_error case final String error)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _SectionLabel(_query.isEmpty ? 'مدن مقترحة' : 'نتائج البحث'),
            FutureBuilder(
              future: _cities,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text('تعذّر فتح دليل المدن.');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final cities = snapshot.data!;
                const suggestions = [
                  'القاهرة',
                  'مكة المكرمة',
                  'الرياض',
                  'دبي',
                  'لندن',
                  'نيويورك',
                ];
                final List<Place> results;
                if (_query.isEmpty) {
                  results = [
                    for (final name in suggestions)
                      ...cities
                          .where((city) => city.place.name == name)
                          .take(1)
                          .map((city) => city.place),
                  ];
                } else {
                  final words = _query.split(RegExp(r'\s+'));
                  final matches = cities
                      .where((city) => words.every(city.search.contains))
                      .toList();
                  results = [
                    ...matches.where(
                      (city) => searchKey(city.place.name).startsWith(_query),
                    ),
                    ...matches.where(
                      (city) => !searchKey(city.place.name).startsWith(_query),
                    ),
                  ].take(45).map((city) => city.place).toList();
                }
                if (results.isEmpty) {
                  return Text(
                    'مفيش نتائج. جرّب اسم المدينة بالإنجليزية.',
                    style: TextStyle(color: colors.muted),
                  );
                }
                return _Panel(
                  children: [
                    for (final place in results)
                      ListTile(
                        leading: Icon(
                          Icons.location_on_outlined,
                          color: colors.accent,
                        ),
                        title: Text(
                          place.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          countryLabels[place.country] ?? place.country,
                        ),
                        trailing:
                            widget.selected.name == place.name &&
                                widget.selected.country == place.country
                            ? const Icon(Icons.check_rounded)
                            : const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.pop(context, place),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CoordinateDialog extends StatefulWidget {
  const _CoordinateDialog();

  @override
  State<_CoordinateDialog> createState() => _CoordinateDialogState();
}

class _CoordinateDialogState extends State<_CoordinateDialog> {
  final _form = GlobalKey<FormState>();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  double? _number(String value) {
    final normalized = value
        .trim()
        .replaceAll('٫', '.')
        .replaceAll('−', '-')
        .replaceAllMapped(
          RegExp('[٠-٩]'),
          (match) => '٠١٢٣٤٥٦٧٨٩'.indexOf(match[0]!).toString(),
        );
    return double.tryParse(normalized);
  }

  Widget _field(
    String label,
    TextEditingController controller,
    int limit,
  ) => TextFormField(
    controller: controller,
    textDirection: TextDirection.ltr,
    keyboardType: const TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    ),
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final number = _number(value ?? '');
      if (number == null || !number.isFinite || number.abs() > limit) {
        return 'ادخل رقمًا بين ${arabicDigits(-limit)} و${arabicDigits(limit)}';
      }
      return null;
    },
  );

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('إحداثيات الموقع'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field('خط العرض', _latitude, 90),
          const SizedBox(height: 12),
          _field('خط الطول', _longitude, 180),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, (
              latitude: _number(_latitude.text)!,
              longitude: _number(_longitude.text)!,
            ));
          }
        },
        child: const Text('استخدم الموقع'),
      ),
    ],
  );
}
