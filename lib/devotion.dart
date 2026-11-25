import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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

  Future<void> _openGroup(AdhkarGroup group) async {
    if (group != AdhkarGroup.afterPrayer) {
      _openReader(context, group);
      return;
    }
    final prayer = await showModalBottomSheet<Prayer>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: _DevotionPage(
          shrinkWrap: true,
          children: [
            const IbadaHeading('أذكار بعد الصلاة', subtitle: 'اختر الصلاة'),
            ValueListenableBuilder(
              valueListenable: _counts,
              builder: (_, counts, _) => IbadaSurface(
                child: Column(
                  children: [
                    for (final prayer in _fivePrayers)
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(prayer.label),
                        subtitle: Text(
                          _groupProgress(
                            _completedCount(counts, group, prayer),
                            group.entries.length,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.pop(sheetContext, prayer),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && prayer != null) _openReader(context, group, prayer);
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
        const IbadaHeading('الأذكار', subtitle: 'تقدّمك محفوظ خلال اليوم'),
        for (final group in AdhkarGroup.values)
          _AdhkarTile(
            title: group.title,
            icon: switch (group) {
              AdhkarGroup.morning => Icons.light_mode_outlined,
              AdhkarGroup.evening => Icons.wb_twilight_rounded,
              AdhkarGroup.afterPrayer => Icons.bookmark_border_rounded,
              AdhkarGroup.sleep => Icons.bedtime_outlined,
            },
            warm: group == AdhkarGroup.morning || group == AdhkarGroup.evening,
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

String _groupProgress(int completed, int total) => switch (completed) {
  0 => '${arabicDigits(total)} أذكار',
  _ when completed == total => 'اكتملت القراءة',
  _ => 'قرأت ${arabicDigits(completed)} من ${arabicDigits(total)}',
};

class _AdhkarTile extends StatelessWidget {
  const _AdhkarTile({
    required this.title,
    required this.icon,
    required this.warm,
    required this.completed,
    required this.total,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool warm;
  final int? completed;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    final progress = completed;
    return IbadaSurface(
      child: ListTile(
        onTap: onTap,
        minVerticalPadding: 16,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: ExcludeSemantics(
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: warm ? colors.sand : colors.tint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              progress == total ? Icons.check_rounded : icon,
              color: warm ? colors.sandInk : colors.tintInk,
            ),
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                progress == null
                    ? 'اختر الصلاة'
                    : _groupProgress(progress, total),
                style: TextStyle(color: colors.muted, height: 1.45),
              ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                ExcludeSemantics(
                  child: LinearProgressIndicator(
                    value: progress / total,
                    minHeight: 4,
                    backgroundColor: colors.tint,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Icon(Icons.chevron_left_rounded, color: colors.accent),
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

  Future<void> _openIndex() async {
    final entries = widget.group.entries;
    final index = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: _DevotionPage(
          shrinkWrap: true,
          children: [
            const IbadaHeading('قائمة الأذكار'),
            IbadaSurface(
              child: Column(
                children: [
                  for (final (index, entry) in entries.indexed)
                    ListTile(
                      selected: index == _index,
                      leading: Text(arabicDigits(index + 1)),
                      title: Text(entry.title),
                      trailing:
                          _count(widget.counts.value, entry) ==
                              entry.repetitions
                          ? const Icon(Icons.check_rounded, semanticLabel: 'تم')
                          : null,
                      onTap: () => Navigator.pop(sheetContext, index),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted && index != null) _goTo(index);
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
          PopupMenuButton<String>(
            tooltip: 'خيارات القراءة',
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (_) => _reset(),
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'reset',
                child: Text('تصفير تقدّم القراءة'),
              ),
            ],
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
            final isDone = count == entry.repetitions;
            final firstUnread = entries.indexWhere(
              (item) => _count(counts, item) < item.repetitions,
            );
            final last = _index == entries.length - 1;
            return Column(
              children: [
                Expanded(
                  child: _DevotionPage(
                    controller: _scroll,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                            'الذكر ${arabicDigits(_index + 1)} من ${arabicDigits(entries.length)}',
                            style: TextStyle(
                              color: colors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'قائمة الأذكار',
                            onPressed: _openIndex,
                            icon: const Icon(
                              Icons.format_list_numbered_rtl_rounded,
                            ),
                          ),
                        ],
                      ),
                      LinearProgressIndicator(
                        value: complete / entries.length,
                        semanticsLabel:
                            'تقدّم المجموعة، ${arabicDigits(complete)} من ${arabicDigits(entries.length)}',
                        backgroundColor: colors.tint,
                        borderRadius: BorderRadius.circular(6),
                        minHeight: 5,
                      ),
                      IbadaSurface(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              IbadaHeading(entry.title, compact: true),
                              const SizedBox(height: 16),
                              SelectableText(
                                entry.text,
                                key: ValueKey(entry.id),
                                style: TextStyle(
                                  color: colors.ink,
                                  fontSize: 24,
                                  height: 1.95,
                                ),
                              ),
                              if (entry.instruction
                                  case final String instruction) ...[
                                const SizedBox(height: 16),
                                Text(
                                  instruction,
                                  style: TextStyle(
                                    color: colors.muted,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 17),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Text(
                                entry.source,
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _DevotionActions(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _index == 0
                                  ? null
                                  : () => _goTo(_index - 1),
                              child: const Text('السابق'),
                            ),
                          ),
                          if (entry.repetitions > 1)
                            Flexible(
                              child: Text(
                                '${arabicDigits(count)} من ${arabicDigits(entry.repetitions)} مرات',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          Expanded(
                            child: TextButton(
                              onPressed: !last
                                  ? () => _goTo(_index + 1)
                                  : !isDone
                                  ? null
                                  : firstUnread < 0
                                  ? () => Navigator.pop(context)
                                  : () => _goTo(firstUnread),
                              child: Text(
                                !last
                                    ? 'التالي'
                                    : firstUnread < 0
                                    ? 'إنهاء'
                                    : 'متابعة',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        onPressed: isDone
                            ? null
                            : () => widget.increment(entry),
                        icon: Icon(
                          isDone ? Icons.check_rounded : Icons.add_rounded,
                        ),
                        label: Text(
                          isDone
                              ? 'تم الذكر'
                              : entry.repetitions == 1
                              ? 'تسجيل القراءة'
                              : 'عدّ مرة',
                        ),
                      ),
                    ],
                  ),
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
    final countSummary = _target == 0
        ? 'العدّ: $formattedCount'
        : '$formattedCount من ${arabicDigits(_target)}';
    return Column(
      children: [
        Expanded(
          child: _DevotionPage(
            children: [
              const IbadaHeading('السبحة', subtitle: 'اختر هدف التسبيح'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final target in _targets)
                    ChoiceChip(
                      label: Text(
                        target == 0 ? 'عدّ حر' : arabicDigits(target),
                      ),
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
              IbadaSurface(
                color: colors.tint,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      Text(
                        formattedCount,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          color: colors.tintInk,
                          fontSize: 58,
                          height: 1.18,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_target > 0) ...[
                        const SizedBox(height: 16),
                        ExcludeSemantics(
                          child: SizedBox(
                            width: 264,
                            height: 22,
                            child: CustomPaint(
                              painter: _BeadProgress(
                                filled: (_count * 33 ~/ _target).clamp(0, 33),
                                active: colors.accent,
                                inactive: colors.accent.withValues(alpha: .26),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (reached)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Semantics(
                            liveRegion: true,
                            child: const Text('أتممت الهدف'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _count > 0 ? _reset : null,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('تصفير العدّ'),
                ),
              ),
            ],
          ),
        ),
        _DevotionActions(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: ExcludeSemantics(
                  child: Text(
                    countSummary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.tintInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      value: countSummary,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 64),
                        ),
                        onPressed: _loaded ? _increment : null,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text(
                          'اضغط للتسبيح',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(56, 56),
                    ),
                    tooltip: 'التراجع عن آخر عدّة',
                    onPressed: _count > 0
                        ? () => _changeCount(_count - 1)
                        : null,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BeadProgress extends CustomPainter {
  const _BeadProgress({
    required this.filled,
    required this.active,
    required this.inactive,
  });

  final int filled;
  final Color active, inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / 33;
    final radius = math.min(3.1, step * .34);
    final activePaint = Paint()..color = active;
    final inactivePaint = Paint()..color = inactive;
    for (var i = 0; i < 33; i++) {
      final y = size.height * (.34 + .34 * math.sin(i * math.pi / 32));
      canvas.drawCircle(
        Offset(size.width - step * (i + .5), y),
        radius,
        i < filled ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_BeadProgress oldDelegate) =>
      filled != oldDelegate.filled ||
      active != oldDelegate.active ||
      inactive != oldDelegate.inactive;
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
  const _DevotionPage({
    required this.children,
    this.controller,
    this.shrinkWrap = false,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: shrinkWrap ? 1 : null,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView.separated(
        controller: controller,
        shrinkWrap: shrinkWrap,
        padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
        itemCount: children.length,
        itemBuilder: (_, index) => children[index],
        separatorBuilder: (_, _) => const SizedBox(height: 12),
      ),
    ),
  );
}

class _DevotionActions extends StatelessWidget {
  const _DevotionActions({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IbadaColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: child,
          ),
        ),
      ),
    );
  }
}
