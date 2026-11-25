import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adhkar_data.dart';
import 'app_theme.dart';
import 'prayer_times.dart';
import 'screens.dart' show arabicDigits;

final _adhkarRecord = _DevotionRecord('devotion.adhkar.v1');
final _tasbeehRecord = _DevotionRecord('devotion.tasbeeh.v1');

class _DevotionRecord {
  _DevotionRecord(this.key);

  final String key;
  Future<bool>? _pending;

  Future<Map<String, Object?>> read() async {
    await _pending;
    try {
      final stored = await SharedPreferencesAsync().getString(key);
      final decoded = stored == null ? null : jsonDecode(stored);
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // An unavailable or unreadable record does not prevent offline use.
    }
    return {};
  }

  Future<bool> write(Map<String, Object?> record) {
    final encoded = jsonEncode(record);
    final write = (_pending ?? Future.value(true)).then((_) async {
      try {
        await SharedPreferencesAsync().setString(key, encoded);
        return true;
      } catch (_) {
        return false;
      }
    });
    _pending = write;
    unawaited(
      write.then((_) {
        if (identical(_pending, write)) _pending = null;
      }),
    );
    return write;
  }
}

String _dayKey(DateTime local) => '${local.year}-${local.month}-${local.day}';

String _progressKey(AdhkarGroup group, Prayer? prayer, Dhikr dhikr) =>
    '${group.name}.${prayer?.name ?? 'daily'}.${dhikr.id}';

int _completedCount(
  Map<String, int> counts,
  AdhkarGroup group,
  Prayer? prayer,
) => group.entries.where((entry) {
  return (counts[_progressKey(group, prayer, entry)] ?? 0) >= entry.repetitions;
}).length;

const _fivePrayers = [
  Prayer.fajr,
  Prayer.dhuhr,
  Prayer.asr,
  Prayer.maghrib,
  Prayer.isha,
];

class AdhkarScreen extends StatefulWidget {
  const AdhkarScreen({super.key});

  @override
  State<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends State<AdhkarScreen>
    with WidgetsBindingObserver {
  final _counts = ValueNotifier<Map<String, int>>({});
  String _day = _dayKey(DateTime.now());
  Timer? _midnight;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDay();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final record = await _adhkarRecord.read();
    if (!mounted) return;
    final values = record['counts'];
    _refreshDay();
    if (record['day'] == _day && values is Map<String, Object?>) {
      _counts.value = {
        for (final entry in values.entries)
          if (entry.value case final int count when count > 0) entry.key: count,
      };
    }
    setState(() => _loaded = true);
  }

  void _refreshDay() {
    final now = DateTime.now();
    final today = _dayKey(now);
    if (today != _day) {
      _day = today;
      _counts.value = {};
    }
    _midnight?.cancel();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(nextDay.difference(now), _refreshDay);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDay();
  }

  Future<void> _save(Map<String, int> counts) async {
    _counts.value = counts;
    final saved = await _adhkarRecord.write({'day': _day, 'counts': counts});
    if (mounted && !saved) _showSaveError(context);
  }

  void _increment(AdhkarGroup group, Prayer? prayer, Dhikr entry) {
    if (_dayKey(DateTime.now()) != _day) _refreshDay();
    final key = _progressKey(group, prayer, entry);
    final current = _counts.value[key] ?? 0;
    if (current >= entry.repetitions) return;
    unawaited(HapticFeedback.selectionClick());
    unawaited(_save({..._counts.value, key: current + 1}));
  }

  void _reset(AdhkarGroup group, Prayer? prayer) {
    if (_dayKey(DateTime.now()) != _day) _refreshDay();
    final counts = Map<String, int>.of(_counts.value);
    for (final entry in group.entries) {
      counts.remove(_progressKey(group, prayer, entry));
    }
    unawaited(_save(counts));
  }

  void _openReader(BuildContext context, AdhkarGroup group, [Prayer? prayer]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdhkarReader(
          group: group,
          prayer: prayer,
          counts: _counts,
          increment: (entry) => _increment(group, prayer, entry),
          reset: () => _reset(group, prayer),
        ),
      ),
    );
  }

  void _openGroup(AdhkarGroup group) {
    if (group != AdhkarGroup.afterPrayer) {
      _openReader(context, group);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          appBar: AppBar(title: Text(group.title)),
          body: SafeArea(
            top: false,
            child: ValueListenableBuilder(
              valueListenable: _counts,
              builder: (_, counts, _) => _DevotionPage(
                children: [
                  const _PageHeading(
                    'اختر الصلاة',
                    'يُحفظ تقدّم كل صلاة على حدة.',
                  ),
                  for (final prayer in _fivePrayers)
                    _AdhkarTile(
                      title: prayer.label,
                      icon: Icons.schedule_outlined,
                      completed: _completedCount(counts, group, prayer),
                      total: group.entries.length,
                      onTap: () => _openReader(routeContext, group, prayer),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _counts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _counts,
    builder: (_, counts, _) => _DevotionPage(
      children: [
        const _PageHeading(
          'الأذكار',
          'اقرأ على مهل، وتابع ما قرأت خلال اليوم.',
        ),
        for (final group in AdhkarGroup.values)
          _AdhkarTile(
            title: group.title,
            icon: switch (group) {
              AdhkarGroup.morning => Icons.wb_sunny_outlined,
              AdhkarGroup.evening => Icons.wb_twilight_outlined,
              AdhkarGroup.afterPrayer => Icons.bookmark_border_rounded,
              AdhkarGroup.sleep => Icons.nightlight_outlined,
            },
            completed: group == AdhkarGroup.afterPrayer
                ? null
                : _completedCount(counts, group, null),
            total: group.entries.length,
            onTap: _loaded ? () => _openGroup(group) : null,
          ),
      ],
    ),
  );
}

class _AdhkarTile extends StatelessWidget {
  const _AdhkarTile({
    required this.title,
    required this.icon,
    required this.completed,
    required this.total,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final int? completed;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    final progress = completed;
    return _DevotionCard(
      child: ListTile(
        onTap: onTap,
        minVerticalPadding: 14,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: colors.tint,
          foregroundColor: colors.tintInk,
          child: Icon(progress == total ? Icons.check_rounded : icon),
        ),
        title: Text(
          title,
          style: TextStyle(color: colors.ink, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            progress == null
                ? 'اختر من الصلوات الخمس'
                : progress == total
                ? 'اكتملت القراءة'
                : progress == 0
                ? '${arabicDigits(total)} أذكار'
                : 'قرأت ${arabicDigits(progress)} من ${arabicDigits(total)}',
            style: TextStyle(color: colors.muted),
          ),
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class _AdhkarReader extends StatefulWidget {
  const _AdhkarReader({
    required this.group,
    required this.prayer,
    required this.counts,
    required this.increment,
    required this.reset,
  });

  final AdhkarGroup group;
  final Prayer? prayer;
  final ValueListenable<Map<String, int>> counts;
  final ValueChanged<Dhikr> increment;
  final VoidCallback reset;

  @override
  State<_AdhkarReader> createState() => _AdhkarReaderState();
}

class _AdhkarReaderState extends State<_AdhkarReader> {
  final _scroll = ScrollController();
  late int _index = _firstUnread();

  int _firstUnread() {
    final index = widget.group.entries.indexWhere(
      (entry) => _count(widget.counts.value, entry) < entry.repetitions,
    );
    return index < 0 ? 0 : index;
  }

  int _count(Map<String, int> counts, Dhikr entry) =>
      (counts[_progressKey(widget.group, widget.prayer, entry)] ?? 0).clamp(
        0,
        entry.repetitions,
      );

  void _goTo(int index) {
    setState(() => _index = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _reset() async {
    if (await _confirmReset(context, 'تصفير تقدّم هذه المجموعة؟') && mounted) {
      widget.reset();
      _goTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.group.entries;
    final entry = entries[_index];
    final title = widget.prayer == null
        ? widget.group.title
        : 'بعد صلاة ${widget.prayer!.label}';
    final colors = IbadaColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'تصفير تقدّم القراءة',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder(
          valueListenable: widget.counts,
          builder: (context, counts, _) {
            final complete = _completedCount(
              counts,
              widget.group,
              widget.prayer,
            );
            final count = _count(counts, entry);
            final isDone = count >= entry.repetitions;
            return _DevotionPage(
              controller: _scroll,
              children: [
                Text(
                  'الذكر ${arabicDigits(_index + 1)} من ${arabicDigits(entries.length)}',
                  style: TextStyle(color: colors.muted),
                ),
                LinearProgressIndicator(
                  value: complete / entries.length,
                  semanticsLabel:
                      'تقدّم المجموعة، ${arabicDigits(complete)} من ${arabicDigits(entries.length)}',
                  borderRadius: BorderRadius.circular(6),
                  minHeight: 5,
                ),
                _DevotionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          entry.text,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: colors.ink,
                            fontSize: 25,
                            height: 1.9,
                          ),
                        ),
                        if (entry.instruction
                            case final String instruction) ...[
                          const SizedBox(height: 15),
                          Text(
                            instruction,
                            style: TextStyle(color: colors.muted),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          entry.source,
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                if (entry.repetitions > 1)
                  Text(
                    '${arabicDigits(count)} من ${arabicDigits(entry.repetitions)} مرات',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                FilledButton.icon(
                  onPressed: isDone ? null : () => widget.increment(entry),
                  icon: Icon(isDone ? Icons.check_rounded : Icons.add_rounded),
                  label: Text(
                    isDone
                        ? 'تم الذكر'
                        : entry.repetitions == 1
                        ? 'تسجيل القراءة'
                        : 'عدّ مرة',
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _index == 0 ? null : () => _goTo(_index - 1),
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('السابق'),
                    ),
                    TextButton.icon(
                      onPressed: _index == entries.length - 1
                          ? null
                          : () => _goTo(_index + 1),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('التالي'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class TasbeehScreen extends StatefulWidget {
  const TasbeehScreen({super.key});

  @override
  State<TasbeehScreen> createState() => _TasbeehScreenState();
}

class _TasbeehScreenState extends State<TasbeehScreen> {
  static const _targets = [33, 99, 0];
  int _count = 0;
  int _target = 33;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final record = await _tasbeehRecord.read();
    if (!mounted) return;
    final count = record['count'];
    final target = record['target'];
    setState(() {
      if (count is int && count >= 0) _count = count;
      if (target is int && _targets.contains(target)) _target = target;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final saved = await _tasbeehRecord.write({
      'count': _count,
      'target': _target,
    });
    if (mounted && !saved) _showSaveError(context);
  }

  void _changeCount(int count) {
    setState(() => _count = count);
    unawaited(_save());
  }

  void _increment() {
    _changeCount(_count + 1);
    unawaited(
      _count == _target
          ? HapticFeedback.lightImpact()
          : HapticFeedback.selectionClick(),
    );
  }

  Future<void> _reset() async {
    if (await _confirmReset(context, 'تصفير عدّ السبحة؟') && mounted) {
      _changeCount(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    final reached = _target > 0 && _count >= _target;
    final formattedCount = arabicDigits(_count);
    return _DevotionPage(
      children: [
        const _PageHeading('السبحة', 'اضبط هدفك أو اختر العدّ الحر.'),
        _DevotionCard(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final target in _targets)
                      ChoiceChip(
                        label: Text(target == 0 ? 'حر' : arabicDigits(target)),
                        selected: _target == target,
                        onSelected: !_loaded
                            ? null
                            : (selected) {
                                if (!selected) return;
                                setState(() => _target = target);
                                unawaited(_save());
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Semantics(
                  button: true,
                  enabled: _loaded,
                  onTap: _loaded ? _increment : null,
                  label: 'زيادة العدّ',
                  value: formattedCount,
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 184,
                    height: 184,
                    child: Material(
                      color: IbadaColors.pine,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _loaded ? _increment : null,
                        splashColor: Colors.white24,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    formattedCount,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: IbadaColors.cream,
                                      fontSize: 49,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'اضغط للتسبيح',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: IbadaColors.pale,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_target > 0) ...[
                  const SizedBox(height: 17),
                  Text(
                    '$formattedCount من ${arabicDigits(_target)}',
                    style: TextStyle(color: colors.muted),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (_count / _target).clamp(0, 1),
                    minHeight: 5,
                    borderRadius: BorderRadius.circular(5),
                    semanticsLabel: 'تقدّم الهدف',
                  ),
                ],
                if (reached) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'أتممت الهدف',
                      style: TextStyle(color: colors.accent),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  children: [
                    IconButton(
                      tooltip: 'التراجع عن آخر عدّة',
                      onPressed: _count > 0
                          ? () => _changeCount(_count - 1)
                          : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    TextButton.icon(
                      onPressed: _count > 0 ? _reset : null,
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('تصفير العدّ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<bool> _confirmReset(BuildContext context, String question) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('تصفير'),
            ),
          ],
        ),
      ) ??
      false;
}

void _showSaveError(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(content: Text('تعذّر حفظ التقدّم على الجهاز.')),
  );
}

class _DevotionPage extends StatelessWidget {
  const _DevotionPage({required this.children, this.controller});

  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView.separated(
        controller: controller,
        padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 20, 28),
        itemCount: children.length,
        itemBuilder: (_, index) => children[index],
        separatorBuilder: (_, _) => const SizedBox(height: 12),
      ),
    ),
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading(this.title, this.subtitle);

  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                color: colors.ink,
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: colors.muted, fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _DevotionCard extends StatelessWidget {
  const _DevotionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return Material(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
      child: child,
    );
  }
}
