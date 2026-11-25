// "יומן" list view (spec §9): every meeting by day from today on, like the
// iOS list. Requests waiting for approval come first, with "אישור" /
// "דחייה" right on the row. A tap opens the meeting's details.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/ds.dart';
import '../../util/labels/calendar_he.dart';
import 'calendar_api.dart';
import 'calendar_day_view.dart' show DashedOutline;
import 'calendar_screen.dart' show AgendaItem;
import 'calendar_sync.dart' show hhmm;

class CalendarListView extends StatelessWidget {
  const CalendarListView({
    super.key,
    required this.today,
    required this.pending,
    required this.days,
    required this.busyIds,
    required this.onTap,
    required this.onApprove,
    required this.onDecline,
    this.header,
    this.scroll,
  });

  final DateTime today;
  final List<Booking> pending;

  /// The days from today on that have something, each with its items.
  final List<(DateTime, List<AgendaItem>)> days;
  final Set<String> busyIds;
  final ValueChanged<AgendaItem> onTap;
  final ValueChanged<Booking> onApprove;
  final ValueChanged<Booking> onDecline;

  /// Above the list (the sync line).
  final Widget? header;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      key: const Key('calendar-list'),
      controller: scroll,
      padding: EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        MediaQuery.paddingOf(context).bottom + Space.xl,
      ),
      children: [
        ?header,
        if (pending.isNotEmpty) ...[
          _DayHeader(
            key: const Key('calendar-pending'),
            text: CalendarHe.pendingCount(pending.length),
            color: p.warn,
          ),
          for (final b in pending)
            _Row(
              item: AgendaItem.booking(b),
              showDate: true,
              busy: busyIds.contains(b.id),
              onTap: onTap,
              onApprove: onApprove,
              onDecline: onDecline,
            ),
        ],
        if (days.isEmpty && pending.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: Space.xl),
            child: EmptyState(
              icon: Iconsax.calendar_1,
              title: CalendarHe.empty,
              message: CalendarHe.emptyBody,
            ),
          ),
        for (final (day, items) in days) ...[
          _DayHeader(
            key: Key('calendar-list-day-${ymd(day)}'),
            text: day == today
                ? '${CalendarHe.today} · ${CalendarHe.longDay(day)}'
                : CalendarHe.longDay(day),
            color: day == today ? p.ink : p.muted,
          ),
          for (final i in items)
            _Row(
              item: i,
              busy: i.booking != null && busyIds.contains(i.booking!.id),
              onTap: onTap,
              onApprove: onApprove,
              onDecline: onDecline,
            ),
        ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({super.key, required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppText.secondary.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onApprove,
    required this.onDecline,
    this.showDate = false,
  });

  final AgendaItem item;
  final bool busy;
  final bool showDate;
  final ValueChanged<AgendaItem> onTap;
  final ValueChanged<Booking> onApprove;
  final ValueChanged<Booking> onDecline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = item.booking;
    final closed = b?.closed ?? false;
    final pending = b?.pending ?? false;
    final bar = b == null
        ? p.muted
        : pending
        ? p.warn
        : closed
        ? p.line
        : Color.lerp(p.accent, p.accentInk, .28)!;
    final start = item.startsAt.toLocal();
    final title = b == null
        ? (item.busy!.mine ? CalendarHe.busyBlock : CalendarHe.busyOther)
        : b.clientName;
    final sub = [
      if (showDate)
        '${CalendarHe.days[start.weekday % 7]} ${start.day}.${start.month}',
      if (b != null && b.notes != null && b.notes!.isNotEmpty) b.notes!,
    ].join(' · ');
    final row = Opacity(
      opacity: closed ? .55 : 1,
      child: InkWell(
        key: Key(
          'calendar-row-${b?.id ?? 'busy-${start.millisecondsSinceEpoch}'}',
        ),
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hhmm(start),
                      textDirection: TextDirection.ltr,
                      style: AppText.secondary.copyWith(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        decoration: closed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      hhmm(item.endsAt),
                      textDirection: TextDirection.ltr,
                      style: AppText.caption.copyWith(
                        fontSize: 13,
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s),
              SizedBox(
                width: 4,
                height: 40,
                child: pending
                    ? CustomPaint(
                        painter: DashedOutline(color: p.warn, radius: 2),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: bar,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: b == null ? p.muted : p.ink,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          fontSize: 13,
                          color: p.muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (closed)
                Text(
                  CalendarHe.closedLabel(b!.status, b.cancelledBy),
                  key: Key('booking-cancelled-${b.id}'),
                  style: AppText.caption.copyWith(
                    fontSize: 13,
                    color: p.danger,
                  ),
                ),
              if (pending)
                Text(
                  CalendarHe.pending,
                  key: Key('booking-pending-${b!.id}'),
                  style: AppText.caption.copyWith(fontSize: 13, color: p.warn),
                ),
            ],
          ),
        ),
      ),
    );
    if (!pending) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 76, bottom: Space.s),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: Key('booking-approve-${b!.id}'),
                  onPressed: busy ? null : () => onApprove(b),
                  child: const Text(CalendarHe.approve),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlinedButton(
                  key: Key('booking-decline-${b.id}'),
                  onPressed: busy ? null : () => onDecline(b),
                  child: const Text(CalendarHe.decline),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
