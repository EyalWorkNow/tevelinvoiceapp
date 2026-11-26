// "יומן" day view (spec §9, like iOS Calendar): a week strip on top (swipe =
// a week, tap = that day), the full date, and a 24-hour timeline below
// (swipe sideways = a day; in Hebrew the next day comes from the left).
// Working hours on white, the rest light grey; a red "now" line on today.
// Blocks: a side colour bar on a light tint — confirmed = brand, a request
// waiting for approval = a dashed amber outline, busy from the phone = grey.
// Tap a block → its details; long-press an empty hour → a new meeting there;
// long-press a confirmed meeting and drag it → move (snapped to 15 minutes).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import 'calendar_api.dart';
import 'calendar_layout.dart';
import 'calendar_screen.dart' show AgendaItem;
import 'calendar_sync.dart' show hhmm;

/// Pixels per hour on the timeline.
const double hourHeight = 60;
const double _pxPerMinute = hourHeight / 60;
const double _labelWidth = 54;
const double _topPad = 10;
const int _base = 10000;

class CalendarDayView extends StatefulWidget {
  const CalendarDayView({
    super.key,
    required this.day,
    required this.today,
    required this.now,
    required this.itemsFor,
    required this.workingFor,
    required this.isBlocked,
    required this.onDayChanged,
    required this.onTapItem,
    required this.onLongPressEmpty,
    required this.onMove,
  });

  final DateTime day;
  final DateTime today;
  final DateTime Function() now;
  final List<AgendaItem> Function(DateTime day) itemsFor;
  final List<(int, int)> Function(DateTime day) workingFor;
  final bool Function(DateTime day) isBlocked;
  final ValueChanged<DateTime> onDayChanged;
  final ValueChanged<AgendaItem> onTapItem;
  final ValueChanged<DateTime> onLongPressEmpty;

  /// Asks and moves; true when the meeting moved.
  final Future<bool> Function(Booking booking, DateTime start) onMove;

  @override
  State<CalendarDayView> createState() => CalendarDayViewState();
}

class CalendarDayViewState extends State<CalendarDayView> {
  late final DateTime _origin = dayOf(widget.day);
  late final DateTime _originWeek = weekStart(widget.day);
  late final PageController _days = PageController(initialPage: _base);
  late final PageController _weeks = PageController(initialPage: _base);
  late DateTime _day = dayOf(widget.day);

  DateTime _dayAt(int page) =>
      DateTime(_origin.year, _origin.month, _origin.day + page - _base);

  int _pageOf(DateTime day) => _base + dayOf(day).difference(_origin).inDays;

  int _weekPageOf(DateTime day) =>
      _base + (weekStart(day).difference(_originWeek).inDays / 7).round();

  /// "היום" / a tap in the strip.
  void showDay(DateTime day, {bool animate = true}) {
    final page = _pageOf(day);
    if (!_days.hasClients) return;
    if (animate && (page - _days.page!.round()).abs() <= 7) {
      unawaited(
        _days.animateToPage(
          page,
          duration: context.motion(280),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _days.jumpToPage(page);
    }
  }

  void _onDayPage(int page) {
    final day = _dayAt(page);
    HapticFeedback.selectionClick();
    setState(() => _day = day);
    widget.onDayChanged(day);
    final week = _weekPageOf(day);
    if (_weeks.hasClients && _weeks.page?.round() != week) {
      unawaited(
        _weeks.animateToPage(
          week,
          duration: context.motion(250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    _days.dispose();
    _weeks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        const _WeekLetters(),
        SizedBox(
          height: 48,
          child: PageView.builder(
            key: const Key('calendar-week-strip'),
            controller: _weeks,
            itemBuilder: (context, page) {
              final start = DateTime(
                _originWeek.year,
                _originWeek.month,
                _originWeek.day + (page - _base) * 7,
              );
              return Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _StripDay(
                        day: DateTime(start.year, start.month, start.day + i),
                        selected: _day,
                        today: widget.today,
                        onTap: showDay,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Text(
            CalendarHe.longDay(_day),
            key: const Key('calendar-day-title'),
            style: AppText.secondary.copyWith(
              color: p.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Divider(height: 1, color: p.line),
        Expanded(
          child: PageView.builder(
            key: const Key('calendar-day-pages'),
            controller: _days,
            onPageChanged: _onDayPage,
            itemBuilder: (context, page) {
              final day = _dayAt(page);
              return DayTimeline(
                key: Key('calendar-timeline-${ymd(day)}'),
                day: day,
                isToday: day == widget.today,
                now: widget.now,
                items: widget.itemsFor(day),
                working: widget.workingFor(day),
                blocked: widget.isBlocked(day),
                onTapItem: widget.onTapItem,
                onLongPressEmpty: widget.onLongPressEmpty,
                onMove: widget.onMove,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekLetters extends StatelessWidget {
  const _WeekLetters();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Row(
      children: [
        for (final l in CalendarHe.weekdayLetters)
          Expanded(
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(
                fontSize: 12,
                color: context.palette.muted,
              ),
            ),
          ),
      ],
    ),
  );
}

class _StripDay extends StatelessWidget {
  const _StripDay({
    required this.day,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime day;
  final DateTime selected;
  final DateTime today;
  final void Function(DateTime day) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isSel = day == selected;
    final isToday = day == today;
    final fill = isSel ? (isToday ? p.accent : p.charcoal) : null;
    final fg = isSel ? (isToday ? p.accentInk : p.onCharcoal) : p.ink;
    return Semantics(
      button: true,
      selected: isSel,
      label: CalendarHe.longDay(day),
      child: GestureDetector(
        key: Key('calendar-strip-${ymd(day)}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(day),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: isToday && !isSel
                  ? Border.all(color: p.accent, width: 2.5)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: AppText.body.copyWith(
                fontSize: 18,
                fontWeight: isSel || isToday
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One day's 24-hour timeline.
class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.day,
    required this.isToday,
    required this.now,
    required this.items,
    required this.working,
    required this.blocked,
    required this.onTapItem,
    required this.onLongPressEmpty,
    required this.onMove,
  });

  final DateTime day;
  final bool isToday;
  final DateTime Function() now;
  final List<AgendaItem> items;
  final List<(int, int)> working;
  final bool blocked;
  final ValueChanged<AgendaItem> onTapItem;
  final ValueChanged<DateTime> onLongPressEmpty;
  final Future<bool> Function(Booking booking, DateTime start) onMove;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _firstOffset(),
  );
  Timer? _tick;
  String? _dragId;
  double _dragDy = 0;
  bool _saving = false;

  /// Opens an hour before the now line (today), the first meeting, or the
  /// working day's start.
  double _firstOffset() {
    var minute = 8 * 60;
    if (widget.isToday) {
      final n = widget.now();
      minute = n.hour * 60 + n.minute - 60;
    } else {
      final starts = [
        for (final i in widget.items) i.startsAt.toLocal().hour * 60,
        if (widget.working.isNotEmpty) widget.working.first.$1,
      ];
      if (starts.isNotEmpty) {
        minute = starts.reduce((a, b) => a < b ? a : b) - 30;
      }
    }
    return (minute.clamp(0, 15 * 60)) * _pxPerMinute;
  }

  @override
  void initState() {
    super.initState();
    if (widget.isToday) {
      _tick = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool _movable(AgendaItem i) {
    final b = i.booking;
    return b != null && b.confirmed && b.startsAt.isAfter(widget.now());
  }

  Future<void> _drop(Booking b) async {
    final minutes = snappedMinutes(_dragDy, pixelsPerMinute: _pxPerMinute);
    if (minutes == 0) {
      setState(() => _dragId = null);
      return;
    }
    setState(() => _saving = true);
    final target = b.startsAt.toLocal().add(Duration(minutes: minutes));
    await widget.onMove(b, target);
    if (mounted) {
      setState(() {
        _dragId = null;
        _dragDy = 0;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final entries = layoutDay(widget.items, widget.day);
    final grey = Color.alphaBlend(p.line.withValues(alpha: .45), p.canvas);
    final height = 24 * hourHeight + _topPad * 2;
    return SingleChildScrollView(
      controller: _scroll,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final area = c.maxWidth - _labelWidth - Space.s;
            return Stack(
              children: [
                // Off hours grey, working hours white (blocked day: all grey).
                Positioned.fill(child: ColoredBox(color: grey)),
                if (!widget.blocked)
                  for (final w in widget.working)
                    Positioned(
                      top: _topPad + w.$1 * _pxPerMinute,
                      height: (w.$2 - w.$1) * _pxPerMinute,
                      left: 0,
                      right: 0,
                      child: ColoredBox(
                        key: Key('calendar-working-${w.$1}'),
                        color: p.surface,
                      ),
                    ),
                // Long-press on an empty hour → a new meeting there.
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('calendar-timeline-empty'),
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: (d) {
                      final minute =
                          ((d.localPosition.dy - _topPad) / _pxPerMinute)
                              .clamp(0, 24 * 60 - 1)
                              .toInt();
                      HapticFeedback.lightImpact();
                      widget.onLongPressEmpty(
                        DateTime(
                          widget.day.year,
                          widget.day.month,
                          widget.day.day,
                        ).add(Duration(minutes: minute - minute % 30)),
                      );
                    },
                  ),
                ),
                for (var h = 0; h <= 24; h++) ..._hourLine(context, h),
                for (final e in entries) _positioned(context, e, area),
                if (widget.isToday) ..._nowLine(context),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _hourLine(BuildContext context, int h) {
    final p = context.palette;
    final y = _topPad + h * hourHeight;
    return [
      PositionedDirectional(
        top: y,
        start: _labelWidth,
        end: 0,
        child: IgnorePointer(child: Container(height: .8, color: p.line)),
      ),
      if (h < 24)
        PositionedDirectional(
          top: y - 8,
          start: 0,
          width: _labelWidth - 6,
          child: IgnorePointer(
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: AppText.caption.copyWith(fontSize: 12, color: p.muted),
            ),
          ),
        ),
    ];
  }

  List<Widget> _nowLine(BuildContext context) {
    final p = context.palette;
    final n = widget.now();
    final y = _topPad + (n.hour * 60 + n.minute) * _pxPerMinute;
    return [
      PositionedDirectional(
        top: y - .75,
        start: _labelWidth - 4,
        end: 0,
        child: IgnorePointer(
          child: Container(
            key: const Key('calendar-now-line'),
            height: 1.5,
            color: p.danger,
          ),
        ),
      ),
      PositionedDirectional(
        top: y - 5,
        start: _labelWidth - 9,
        child: IgnorePointer(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
          ),
        ),
      ),
      PositionedDirectional(
        top: y - 10,
        start: 2,
        width: _labelWidth - 12,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: p.danger,
              borderRadius: BorderRadius.circular(Radii.chip),
            ),
            child: Text(
              hhmm(n),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: AppText.caption.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: p.onDanger,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _positioned(BuildContext context, TimelineEntry e, double area) {
    final item = e.item;
    final id = item.booking?.id;
    final dragging = id != null && id == _dragId;
    final width = area / e.columns;
    final dy = dragging
        ? snappedMinutes(_dragDy, pixelsPerMinute: _pxPerMinute) * _pxPerMinute
        : 0.0;
    final top = _topPad + e.startMinute * _pxPerMinute + dy;
    final h = (e.minutes * _pxPerMinute).clamp(22.0, double.infinity);
    Widget block = EventBlock(
      key: Key('calendar-block-${id ?? 'busy-${e.startMinute}-${e.column}'}'),
      item: item,
      lifted: dragging,
      compact: h < 40,
      timeOverride: dragging
          ? item.startsAt.toLocal().add(
              Duration(
                minutes: snappedMinutes(_dragDy, pixelsPerMinute: _pxPerMinute),
              ),
            )
          : null,
    );
    final booking = item.booking;
    block = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _saving ? null : () => widget.onTapItem(item),
      onLongPressStart: booking != null && _movable(item) && !_saving
          ? (_) {
              HapticFeedback.lightImpact();
              setState(() {
                _dragId = booking.id;
                _dragDy = 0;
              });
            }
          : null,
      onLongPressMoveUpdate: booking != null && _movable(item)
          ? (d) => setState(() => _dragDy = d.offsetFromOrigin.dy)
          : null,
      onLongPressEnd: booking != null && _movable(item)
          ? (_) => unawaited(_drop(booking))
          : null,
      child: block,
    );
    return PositionedDirectional(
      top: top,
      height: h - 1,
      start: _labelWidth + e.column * width,
      width: width - 2,
      child: block,
    );
  }
}

/// A meeting / busy block, like iOS: a colour bar on the start side and a
/// light tint of the same colour; a pending request has a dashed outline.
class EventBlock extends StatelessWidget {
  const EventBlock({
    super.key,
    required this.item,
    this.lifted = false,
    this.compact = false,
    this.timeOverride,
  });

  final AgendaItem item;
  final bool lifted;
  final bool compact;

  /// While dragged: the new start.
  final DateTime? timeOverride;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = item.booking;
    final pending = b?.pending ?? false;
    final busy = b == null;
    final bar = busy
        ? p.muted
        : pending
        ? p.warn
        : Color.lerp(p.accent, p.accentInk, .28)!;
    final tint = busy
        ? Color.alphaBlend(p.line.withValues(alpha: .9), p.surface)
        : pending
        ? Color.alphaBlend(p.warn.withValues(alpha: .1), p.surface)
        : Color.alphaBlend(p.accent.withValues(alpha: .38), p.surface);
    final start = timeOverride ?? item.startsAt.toLocal();
    final end = start.add(item.endsAt.difference(item.startsAt));
    final title = busy
        ? (item.busy!.mine ? CalendarHe.busyBlock : CalendarHe.busyOther)
        : b.clientName;
    final time = '${hhmm(start)}–${hhmm(end)}';
    final text = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 3, 6, 2),
      child: compact
          ? Text(
              '$title · ${ltrIsolate(hhmm(start))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: busy ? p.muted : p.ink,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: busy ? p.muted : p.ink,
                  ),
                ),
                Text(
                  pending ? '$time · ${CalendarHe.pending}' : time,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: pending ? null : TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: AppText.caption.copyWith(
                    fontSize: 12,
                    color: pending ? p.warn : p.muted,
                  ),
                ),
              ],
            ),
    );
    final body = Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(6),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: p.ink.withValues(alpha: .25),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: bar),
          Expanded(child: text),
        ],
      ),
    );
    return Opacity(
      opacity: lifted ? .92 : 1,
      child: pending
          ? CustomPaint(
              foregroundPainter: DashedOutline(color: p.warn, radius: 6),
              child: body,
            )
          : body,
    );
  }
}

/// A dashed rounded outline (a request waiting for approval).
class DashedOutline extends CustomPainter {
  const DashedOutline({required this.color, this.radius = 6});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(.7),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutline old) =>
      old.color != color || old.radius != radius;
}
