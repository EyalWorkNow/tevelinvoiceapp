// "ביקורים ופגישות" → "הכל": every CRM job of the customer (the existing
// CustomerCrmJobs cards: start / finish, checklist, navigate, reschedule…)
// and the customer's meetings from the calendar. Also the booking detail
// sheet a meeting row opens.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/customer_crm_store.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart' show NoticeMotion;
import '../../util/allowed_urls.dart';
import '../../util/crm_visit.dart';
import '../../util/labels/calendar_he.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/person_page_he.dart';
import '../../util/phone.dart';
import '../calendar/calendar_api.dart';
import '../calendar/booking_detail_sheet.dart';
import '../calendar/calendar_sync.dart' show bookingWhen;
import '../document/dialogs.dart' show toast;
import 'customer_crm_jobs.dart';
import 'person_crm_ops.dart';
import 'person_sections.dart' show ScrollEdgeHeader;
import 'person_logic.dart' show whenLabel;

Future<void> openPersonVisits(
  BuildContext context, {
  required PersonCrmOps ops,
  required List<Booking> bookings,
  required bool canEdit,
  required bool showMoney,
  String? phone,
  VoidCallback? onCreateDocument,
  VoidCallback? onChanged,
}) => Navigator.of(context).push(
  AppPageRoute<void>(
    builder: (_) => PersonVisitsPage(
      ops: ops,
      bookings: bookings,
      canEdit: canEdit,
      showMoney: showMoney,
      phone: phone,
      onCreateDocument: onCreateDocument,
      onChanged: onChanged,
    ),
    settings: const RouteSettings(name: '/person/visits'),
  ),
);

/// A meeting's details — the same sheet as in the יומן (approve / decline,
/// contact, block, cancel). Returns true when the booking changed.
Future<bool> showPersonBooking(BuildContext context, Booking booking) async {
  final action = await showBookingDetailSheet(
    context,
    booking,
    canOpenCustomer: false,
    inCalendar: false,
  );
  if (action == null || !context.mounted) return false;
  switch (action) {
    case BookingAction.approve:
      return _bookingAct(context, booking, approveBooking, CalendarHe.approved);
    case BookingAction.decline:
      return _bookingAct(context, booking, declineBooking, CalendarHe.declined);
    case BookingAction.block:
      final ok = await _confirmBooking(
        context,
        CalendarHe.blockTitle,
        '${booking.clientName}\n\n${CalendarHe.blockBody}',
        CalendarHe.blockConfirm,
        const Key('calendar-block-confirm'),
      );
      if (!ok || !context.mounted) return false;
      return _bookingAct(
        context,
        booking,
        blockBookingClient,
        CalendarHe.blocked,
      );
    case BookingAction.cancel:
      final ok = await _confirmBooking(
        context,
        CalendarHe.cancelTitle,
        '${booking.clientName} · ${bookingWhen(booking.startsAt)}'
        '\n\n${CalendarHe.cancelBody}',
        CalendarHe.cancelConfirm,
        const Key('calendar-cancel-confirm'),
      );
      if (!ok || !context.mounted) return false;
      return _bookingAct(
        context,
        booking,
        cancelBookingAsOwner,
        CalendarHe.cancelledToast,
      );
    case BookingAction.openCustomer:
      return false;
  }
}

Future<bool> _confirmBooking(
  BuildContext context,
  String title,
  String body,
  String confirm,
  Key key,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(CalendarHe.keep),
          ),
          TextButton(
            key: key,
            style: TextButton.styleFrom(foregroundColor: c.palette.danger),
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirm),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> _bookingAct(
  BuildContext context,
  Booking booking,
  Future<Booking> Function(String) action,
  String done,
) async {
  try {
    await action(booking.id);
    if (context.mounted) toast(context, done, motion: NoticeMotion.calendar);
    return true;
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return false;
  }
}

class PersonVisitsPage extends StatefulWidget {
  const PersonVisitsPage({
    super.key,
    required this.ops,
    required this.bookings,
    required this.canEdit,
    required this.showMoney,
    this.phone,
    this.onCreateDocument,
    this.onChanged,
  });

  final PersonCrmOps ops;
  final List<Booking> bookings;
  final bool canEdit;
  final bool showMoney;
  final String? phone;
  final VoidCallback? onCreateDocument;
  final VoidCallback? onChanged;

  @override
  State<PersonVisitsPage> createState() => _PersonVisitsPageState();
}

class _PersonVisitsPageState extends State<PersonVisitsPage> {
  final _store = CustomerCrmStore.instance;
  bool _scrolled = false;

  Future<void> _launch(Uri? uri) async {
    if (uri == null) return;
    final opened = await launchAllowed(uri);
    if (!opened && mounted) toast(context, CustomerCrmHe.launchError);
  }

  @override
  Widget build(BuildContext context) {
    final ops = widget.ops;
    final p = context.palette;
    final bookings = [...widget.bookings]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScrollEdgeHeader(
              scrolled: _scrolled,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.page,
                  _scrolled ? Space.xs : Space.s,
                  Space.page,
                  _scrolled ? Space.xs : Space.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          PersonPageHe.visits,
                          style: _scrolled
                              ? AppText.title
                              : AppText.displayTitle,
                        ),
                      ),
                    ),
                    const DesignBackButton(),
                  ],
                ),
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final v = ScrollEdgeHeader.next(_scrolled, n);
                  if (v != _scrolled) setState(() => _scrolled = v);
                  return false;
                },
                child: AnimatedBuilder(
                  animation: _store,
                  builder: (context, _) {
                    final loaded = _store.isLoadedFor(ops.businessId);
                    final jobs = loaded
                        ? _store.entryFor(ops.customerId).jobs
                        : const <CustomerCrmJob>[];
                    final enabled = widget.canEdit && ops.ready;
                    return ListView(
                      key: const Key('person-visits-page'),
                      padding: const EdgeInsets.fromLTRB(
                        Space.page,
                        Space.s,
                        Space.page,
                        Space.xl,
                      ),
                      children: [
                        if (loaded)
                          CustomerCrmJobs(
                            jobs: jobs,
                            enabled: enabled,
                            showMoney: widget.showMoney,
                            onEdit: (job) => unawaited(
                              ops.editJob(
                                context,
                                job: job,
                                showMoney: widget.showMoney,
                              ),
                            ),
                            onRepeat: (job) => unawaited(
                              ops.editJob(
                                context,
                                job: job,
                                repeat: true,
                                showMoney: widget.showMoney,
                              ),
                            ),
                            onDelete: (job) =>
                                unawaited(ops.deleteJob(context, job)),
                            onStatus: (job, status) => unawaited(
                              ops.setJobStatus(context, job, status),
                            ),
                            onReschedule: (job, days) =>
                                unawaited(ops.reschedule(context, job, days)),
                            onChecklist: (job, id, done) => unawaited(
                              ops.setChecklist(context, job, id, done),
                            ),
                            onNavigate: (job) =>
                                unawaited(_launch(crmVisitMapUri(job))),
                            onMessage: waPhone(widget.phone) == null
                                ? null
                                : (job) => unawaited(
                                    _launch(
                                      crmVisitMessageUri(job, widget.phone),
                                    ),
                                  ),
                            onCreateDocument: widget.onCreateDocument,
                          ),
                        if (bookings.isNotEmpty) ...[
                          const SizedBox(height: Space.l),
                          Text(
                            PersonPageHe.calendarBookings,
                            style: AppText.headline.copyWith(color: p.muted),
                          ),
                          const SizedBox(height: Space.s),
                          for (final b in bookings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: Space.s),
                              child: AppCard(
                                onTap: () async {
                                  final changed = await showPersonBooking(
                                    context,
                                    b,
                                  );
                                  if (changed && mounted) {
                                    widget.onChanged?.call();
                                    Navigator.of(this.context).pop();
                                  }
                                },
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        whenLabel(b.startsAt),
                                        style: AppText.body,
                                      ),
                                    ),
                                    Text(
                                      b.pending
                                          ? PersonPageHe.tagPending
                                          : b.closed
                                          ? CalendarHe.closedLabel(
                                              b.status,
                                              b.cancelledBy,
                                            )
                                          : PersonPageHe.tagScheduled,
                                      style: AppText.secondary.copyWith(
                                        color: b.pending
                                            ? p.warn
                                            : b.closed
                                            ? p.danger
                                            : p.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
