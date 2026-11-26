// "יומן" month view (spec §9, like iOS Calendar): months one under the other
// in one continuous vertical scroll, 7 columns from Sunday (right to left),
// the month's name above its first day, a dot under days with meetings
// (amber for a request waiting for approval), today in a filled brand
// circle, blocked dates (vacation) shaded grey. A tap zooms into that day.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import 'calendar_api.dart' show ymd;
import 'calendar_layout.dart';

/// The weekday letters row that stays above the scrolling months.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Text(
                CalendarHe.weekdayLetters[i],
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                  fontSize: 13,
                  color: i == 6 ? p.muted.withValues(alpha: .7) : p.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CalendarMonthView extends StatefulWidget {
  const CalendarMonthView({
    super.key,
    required this.today,
    required this.focusMonth,
    required this.marks,
    required this.isBlocked,
    required this.onDay,
    this.onMonthVisible,
    this.monthsBack = 12,
    this.monthsAhead = 24,
  });

  final DateTime today;

  /// The month scrolled to on open.
  final DateTime focusMonth;
  final Map<DateTime, DayMarks> marks;
  final bool Function(DateTime day) isBlocked;

  /// A day was tapped; [origin] is the tap in global coordinates (zoom).
  final void Function(DateTime day, Offset origin) onDay;

  /// A month was built (its meetings may need loading).
  final ValueChanged<DateTime>? onMonthVisible;
  final int monthsBack;
  final int monthsAhead;

  static const double titleHeight = 52;
  static const double rowHeight = 62;

  static double heightOf(DateTime month) =>
      titleHeight + weekRows(month) * rowHeight;

  @override
  State<CalendarMonthView> createState() => CalendarMonthViewState();
}

class CalendarMonthViewState extends State<CalendarMonthView> {
  late final DateTime _first = addMonths(
    monthOf(widget.today),
    -widget.monthsBack,
  );
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetOf(widget.focusMonth),
  );

  int get _count => widget.monthsBack + widget.monthsAhead + 1;

  double _offsetOf(DateTime month) {
    final index = monthsBetween(_first, monthOf(month)).clamp(0, _count - 1);
    var y = 0.0;
    for (var i = 0; i < index; i++) {
      y += CalendarMonthView.heightOf(addMonths(_first, i));
    }
    return y;
  }

  /// "היום": scroll back to this month.
  Future<void> showMonth(DateTime month) async {
    if (!_scroll.hasClients) return;
    final target = _offsetOf(
      month,
    ).clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(
      target,
      duration: context.motion(350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const Key('calendar-month-list'),
    controller: _scroll,
    padding: EdgeInsets.only(
      bottom: MediaQuery.paddingOf(context).bottom + Space.xl,
    ),
    itemCount: _count,
    itemBuilder: (context, i) {
      final month = addMonths(_first, i);
      final notify = widget.onMonthVisible;
      if (notify != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => notify(month));
      }
      return _Month(
        key: Key('calendar-month-${month.year}-${month.month}'),
        month: month,
        today: widget.today,
        marks: widget.marks,
        isBlocked: widget.isBlocked,
        onDay: widget.onDay,
      );
    },
  );
}

class _Month extends StatelessWidget {
  const _Month({
    super.key,
    required this.month,
    required this.today,
    required this.marks,
    required this.isBlocked,
    required this.onDay,
  });

  final DateTime month;
  final DateTime today;
  final Map<DateTime, DayMarks> marks;
  final bool Function(DateTime day) isBlocked;
  final void Function(DateTime day, Offset origin) onDay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final blanks = leadingBlanks(month);
    final length = daysInMonth(month);
    final rows = weekRows(month);
    final current = monthOf(today) == month;
    return SizedBox(
      height: CalendarMonthView.heightOf(month),
      child: LayoutBuilder(
        builder: (context, c) {
          final cell = c.maxWidth / 7;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: CalendarMonthView.titleHeight,
                child: Padding(
                  // Above the month's first day, like iOS.
                  padding: EdgeInsetsDirectional.only(
                    start: blanks * cell + Space.s,
                    top: Space.m,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      month.year == today.year
                          ? CalendarHe.months[month.month - 1]
                          : CalendarHe.monthYear(month),
                      style: AppText.title.copyWith(
                        fontSize: 22,
                        color: current ? p.ink : p.ink.withValues(alpha: .92),
                      ),
                    ),
                  ),
                ),
              ),
              for (var r = 0; r < rows; r++)
                SizedBox(
                  height: CalendarMonthView.rowHeight,
                  child: Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _cell(
                            context,
                            r * 7 + col - blanks + 1,
                            length,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cell(BuildContext context, int dayNumber, int length) {
    if (dayNumber < 1 || dayNumber > length) return const SizedBox.expand();
    final p = context.palette;
    final day = DateTime(month.year, month.month, dayNumber);
    final isToday = day == today;
    final blocked = isBlocked(day);
    final m = marks[day];
    final weekend = day.weekday == DateTime.saturday;
    return Semantics(
      button: true,
      label: CalendarHe.longDay(day),
      child: GestureDetector(
        key: Key('calendar-day-${ymd(day)}'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          HapticFeedback.selectionClick();
          onDay(day, d.globalPosition);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: blocked ? p.line.withValues(alpha: .55) : null,
            border: Border(top: BorderSide(color: p.line, width: .8)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 6),
              Container(
                key: isToday ? const Key('calendar-today-circle') : null,
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(color: p.accent, shape: BoxShape.circle)
                    : null,
                child: Text(
                  '$dayNumber',
                  style: AppText.body.copyWith(
                    fontSize: 18,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday
                        ? p.accentInk
                        : blocked || weekend
                        ? p.muted
                        : p.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              if (m != null && m.any)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.meetings > 0) _Dot(color: p.muted),
                    if (m.meetings > 0 && m.pending > 0)
                      const SizedBox(width: 3),
                    if (m.pending > 0) _Dot(color: p.warn),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
