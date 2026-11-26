// "יומן" meeting details (spec §9, like iOS's event sheet): the client's
// name, date and time, status; the customer row (→ the customer page when
// the meeting is linked to one); call / WhatsApp / e-mail; for a request
// "אישור" / "דחייה"; "חסימת הלקוח"; and "ביטול הפגישה" in red at the bottom.
// The chosen action runs after the sheet closes (its own confirm dialog).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/phone.dart';
import 'calendar_api.dart';
import 'calendar_sync.dart' show hhmm;

enum BookingAction { approve, decline, block, cancel, openCustomer }

Future<BookingAction?> showBookingDetailSheet(
  BuildContext context,
  Booking booking, {
  required bool canOpenCustomer,
  bool inCalendar = true,
}) => showAppSheet<BookingAction>(
  context,
  builder: (sheet) => BookingDetailSheet(
    booking: booking,
    canOpenCustomer: canOpenCustomer,
    inCalendar: inCalendar,
  ),
);

class BookingDetailSheet extends StatelessWidget {
  const BookingDetailSheet({
    super.key,
    required this.booking,
    required this.canOpenCustomer,
    this.inCalendar = true,
  });

  final Booking booking;
  final bool canOpenCustomer;

  /// False when opened from the customer page: the move hint points to the
  /// יומן (dragging works there).
  final bool inCalendar;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = booking;
    final start = b.startsAt.toLocal();
    final wa = waPhone(b.clientPhone);
    void pick(BookingAction a) => Navigator.of(context).pop(a);
    final linked = b.customerId != null && canOpenCustomer;
    final status = b.pending
        ? (CalendarHe.pending, p.warn)
        : b.closed
        ? (CalendarHe.closedLabel(b.status, b.cancelledBy), p.danger)
        : (CalendarHe.statusConfirmed, p.ok);
    return Column(
      key: const Key('booking-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(b.clientName, style: AppText.title),
        const SizedBox(height: Space.s),
        Text(
          CalendarHe.longDay(start),
          style: AppText.body.copyWith(color: p.ink),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${hhmm(b.startsAt)}–${hhmm(b.endsAt)}',
              textDirection: TextDirection.ltr,
              style: AppText.body.copyWith(color: p.muted),
            ),
            const SizedBox(width: Space.s),
            Container(
              key: const Key('booking-detail-status'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: p.tint(status.$2),
                borderRadius: BorderRadius.circular(Radii.chip),
              ),
              child: Text(
                status.$1,
                style: AppText.caption.copyWith(fontSize: 13, color: status.$2),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        _Group(
          children: [
            ListTile(
              key: const Key('booking-detail-customer'),
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              leading: PersonAvatar(name: b.clientName),
              title: PersonName(
                b.clientName,
                style: AppText.body.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                b.customerId != null
                    ? [
                        b.clientPhone,
                        b.clientEmail,
                      ].where((x) => x.isNotEmpty).join(' · ')
                    : CalendarHe.fromLink,
                maxLines: 2,
                style: AppText.caption.copyWith(fontSize: 13, color: p.muted),
              ),
              trailing: linked
                  ? Icon(Iconsax.arrow_left_2, size: 18, color: p.muted)
                  : null,
              onTap: linked ? () => pick(BookingAction.openCustomer) : null,
            ),
            if (!b.closed)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  0,
                  Space.l,
                  Space.m,
                ),
                child: Row(
                  children: [
                    if (b.clientPhone.isNotEmpty)
                      _Contact(
                        key: const Key('booking-detail-call'),
                        icon: Iconsax.call,
                        label: CalendarHe.call,
                        onTap: () => unawaited(
                          launchAllowed(
                            Uri(scheme: 'tel', path: b.clientPhone),
                          ),
                        ),
                      ),
                    if (wa != null)
                      _Contact(
                        icon: Iconsax.message,
                        label: CalendarHe.whatsapp,
                        onTap: () => unawaited(
                          launchAllowed(whatsAppUri(phone: wa, text: '')),
                        ),
                      ),
                    if (b.clientEmail.isNotEmpty)
                      _Contact(
                        icon: Iconsax.sms,
                        label: CalendarHe.email,
                        onTap: () => unawaited(
                          launchAllowed(
                            Uri(scheme: 'mailto', path: b.clientEmail),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        if (b.notes != null && b.notes!.isNotEmpty) ...[
          const SizedBox(height: Space.m),
          _Group(
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CalendarHe.notes,
                      style: AppText.caption.copyWith(
                        fontSize: 13,
                        color: p.muted,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(b.notes!, style: AppText.body),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (b.pending) ...[
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('booking-detail-approve'),
                  onPressed: () => pick(BookingAction.approve),
                  child: const Text(CalendarHe.approve),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: OutlinedButton(
                  key: const Key('booking-detail-decline'),
                  onPressed: () => pick(BookingAction.decline),
                  child: const Text(CalendarHe.decline),
                ),
              ),
            ],
          ),
        ],
        if (b.confirmed && b.startsAt.isAfter(DateTime.now()))
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(
              inCalendar ? CalendarHe.dragHint : CalendarHe.moveInCalendar,
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(fontSize: 13, color: p.muted),
            ),
          ),
        if (!b.closed) ...[
          const SizedBox(height: Space.l),
          _Group(
            children: [
              _DangerRow(
                key: const Key('booking-detail-block'),
                label: CalendarHe.blockClient,
                onTap: () => pick(BookingAction.block),
              ),
              if (!b.pending) ...[
                Divider(height: 1, color: p.line),
                _DangerRow(
                  key: const Key('booking-detail-cancel'),
                  label: CalendarHe.cancelBooking,
                  onTap: () => pick(BookingAction.cancel),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.canvas,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.l),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppText.body.copyWith(
          color: context.palette.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _Contact extends StatelessWidget {
  const _Contact({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Column(
                children: [
                  Icon(icon, size: 20, color: p.ink),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: AppText.caption.copyWith(fontSize: 12, color: p.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
