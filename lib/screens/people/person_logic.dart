// Pure rules of the customer page (כרטיס לקוח v2): which quick actions show
// and in what order, what the "עוד" sheet holds, the unified visits list
// (CRM jobs + calendar bookings) and the status card's lines. No widgets, so
// the rules are unit-tested directly.

import '../../api/models/models.dart';
import '../../state/customer_crm_store.dart';
import '../../util/labels/person_page_he.dart';
import '../calendar/calendar_api.dart' show Booking;

/// "יום ג׳ 25.11".
String dayWithWeekday(DateTime d) {
  final l = d.toLocal();
  final dd = l.day.toString().padLeft(2, '0');
  final mm = l.month.toString().padLeft(2, '0');
  return PersonPageHe.dayLabel(
    PersonPageHe.weekdayShort[l.weekday % 7],
    '$dd.$mm',
  );
}

/// "09:30".
String hhmm24(DateTime d) {
  final l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// "יום ג׳ 25.11 · 09:30".
String whenLabel(DateTime d) => '${dayWithWeekday(d)} · ${hhmm24(d)}';

/// What the member may do and what the customer has, for the action rules.
class PersonActionFacts {
  const PersonActionFacts({
    this.supplier = false,
    this.archived = false,
    this.hasPhone = false,
    this.hasWhatsapp = false,
    this.hasEmail = false,
    this.hasAddress = false,
    this.owes = false,
    this.canDraft = false,
    this.canPaymentIssue = false,
    this.canMoneyView = false,
    this.canCalendar = false,
    this.canManage = false,
    this.canRestore = false,
    this.crmReady = false,
    this.canRepeat = false,
    this.statement = false,
    this.canExpense = false,
  });

  final bool supplier;
  final bool archived;
  final bool hasPhone;
  final bool hasWhatsapp;
  final bool hasEmail;
  final bool hasAddress;
  final bool owes;
  final bool canDraft;
  final bool canPaymentIssue;
  final bool canMoneyView;
  final bool canCalendar;

  /// customer.manage (supplier.manage + BE-16 for a supplier).
  final bool canManage;

  /// 2611 §4: "החזר לפעיל" (an inactive customer, customer.manage).
  final bool canRestore;

  /// The CRM store is loaded and accepts edits.
  final bool crmReady;

  /// "כמו בפעם הקודמת" has a document to repeat.
  final bool canRepeat;

  /// "שליחת כרטסת" is available (BE-17 + cap).
  final bool statement;
  final bool canExpense;
}

/// Action ids that need the server (greyed while offline).
const serverActions = {
  'payment-request',
  'invoice',
  'book',
  'paid',
  'quote',
  'repeat',
  'debt',
  'statement',
  'portal',
  'terms',
  'archive',
  'restore',
  'expense',
};

/// The quick-action row (2 × 4): the priority list with what is not
/// available skipped and the next one pulled up; "עוד" last when the sheet
/// has something.
List<String> personRowActions(PersonActionFacts f) {
  final row = <String>[];
  final noContact = !f.hasPhone && !f.hasEmail;
  if (f.supplier) {
    if (f.hasPhone) row.add('call');
    if (f.hasWhatsapp) row.add('whatsapp');
    if (f.canExpense && !f.archived) row.add('expense');
    if (f.hasEmail) row.add('email');
  } else {
    if (noContact && f.canManage) {
      row.add('add-phone');
    } else {
      if (f.hasPhone) row.add('call');
      if (f.hasWhatsapp) row.add('whatsapp');
    }
    if (!f.archived) {
      if (f.canDraft) row.add(f.owes ? 'payment-request' : 'invoice');
      if (f.canCalendar) row.add('book');
      if (f.canPaymentIssue) row.add('paid');
      if (f.canDraft) row.add(f.owes ? 'invoice' : 'quote');
      if (f.canManage && f.crmReady) row.add('reminder');
    }
  }
  final visible = row.take(7).toList();
  if (personMoreActions(f, visible).isNotEmpty) visible.add('more');
  return visible;
}

/// The "עוד" sheet, in its fixed order, without what is already in [row]
/// and what the member may not do. "ארכוב" is always last.
List<String> personMoreActions(PersonActionFacts f, List<String> row) {
  final all = f.supplier
      ? <String>[if (f.canManage) 'edit', if (f.canManage) 'archive']
      : <String>[
          if (f.hasEmail) 'email',
          if (!f.archived && f.canRepeat && (f.canDraft || f.canPaymentIssue))
            'repeat',
          if (!f.archived && f.canDraft && f.canMoneyView) 'debt',
          if (!f.archived && f.canManage && f.crmReady) 'job',
          if (!f.archived && f.canManage && f.crmReady) 'note',
          if (f.hasAddress) 'navigate',
          if (f.statement && !f.archived) 'statement',
          // 0135: the customer's personal area (the code goes to the e-mail).
          if (!f.archived && f.canManage && f.canMoneyView && f.hasEmail)
            'portal',
          if (f.canManage) 'edit',
          if (f.canManage) 'terms',
          if (f.canManage) 'archive',
          if (f.archived && f.canRestore) 'restore',
        ];
  return [
    for (final id in all)
      if (!row.contains(id)) id,
  ];
}

/// One row of "ביקורים ופגישות": a CRM job or a calendar booking.
class VisitItem {
  const VisitItem.job(CustomerCrmJob this.job) : booking = null;
  const VisitItem.booking(Booking this.booking) : job = null;

  final CustomerCrmJob? job;
  final Booking? booking;

  DateTime get at => job?.scheduledAt ?? booking!.startsAt.toLocal();
  String get id => job != null ? 'job-${job!.id}' : 'booking-${booking!.id}';

  /// "נקבע" / "באיחור" / "בטיפול" / "ממתינה לאישור".
  String tag(DateTime now) {
    final b = booking;
    if (b != null) {
      return b.pending ? PersonPageHe.tagPending : PersonPageHe.tagScheduled;
    }
    final j = job!;
    if (j.status == CustomerCrmJobStatus.active) return PersonPageHe.tagActive;
    return j.scheduledAt.isBefore(now)
        ? PersonPageHe.tagOverdue
        : PersonPageHe.tagScheduled;
  }

  bool overdue(DateTime now) =>
      job != null &&
      job!.status == CustomerCrmJobStatus.scheduled &&
      job!.scheduledAt.isBefore(now);
}

/// Open jobs (also late ones) and the customer's coming bookings (confirmed
/// or waiting for approval), by date.
List<VisitItem> upcomingVisits(
  List<CustomerCrmJob> jobs,
  List<Booking> bookings,
  DateTime now,
) => [
  for (final j in jobs)
    if (j.status.isOpen) VisitItem.job(j),
  for (final b in bookings)
    if (!b.closed && b.endsAt.isAfter(now)) VisitItem.booking(b),
]..sort((a, b) => a.at.compareTo(b.at));

/// The status card's one "next thing".
class NextThing {
  const NextThing({required this.text, this.visit, this.reminder});
  final String text;
  final VisitItem? visit;
  final CustomerCrmReminder? reminder;
}

/// An overdue follow-up first (it is already due), else the nearest visit or
/// meeting; null when there is nothing.
NextThing? nextThing(
  List<VisitItem> visits,
  List<CustomerCrmReminder> reminders,
  DateTime now,
) {
  final late = [
    for (final r in reminders)
      if (!r.completed && !r.dueAt.isAfter(now)) r,
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  if (late.isNotEmpty) {
    return NextThing(
      text: PersonPageHe.nextFollowUp(late.first.title),
      reminder: late.first,
    );
  }
  if (visits.isEmpty) return null;
  final v = visits.first;
  final when = whenLabel(v.at);
  return NextThing(
    text: v.booking != null
        ? PersonPageHe.nextMeeting(when)
        : PersonPageHe.nextVisit(v.job!.title, when),
    visit: v,
  );
}

/// The status card's document line: the oldest overdue open document, else
/// the oldest open one.
class OpenDocLine {
  const OpenDocLine(this.doc, this.text, {required this.overdue});
  final DocumentSummary doc;
  final String text;
  final bool overdue;
}

DateTime? _date(String? iso) => iso == null ? null : DateTime.tryParse(iso);

OpenDocLine? oldestOpenDoc(
  List<DocumentSummary> docs,
  DateTime now,
  String Function(DocumentSummary) name,
) {
  final today = DateTime(now.year, now.month, now.day);
  final open = [
    for (final d in docs)
      if (d.isOpen && d.documentType != 'CREDIT_DOCUMENT') d,
  ];
  if (open.isEmpty) return null;
  bool late(DocumentSummary d) {
    final due = _date(d.dueDate);
    return due != null && due.isBefore(today);
  }

  final overdue = open.where(late).toList()
    ..sort((a, b) => _date(a.dueDate)!.compareTo(_date(b.dueDate)!));
  if (overdue.isNotEmpty) {
    final d = overdue.first;
    final days = today.difference(_date(d.dueDate)!).inDays;
    return OpenDocLine(
      d,
      PersonPageHe.docOverdue(name(d), days),
      overdue: true,
    );
  }
  open.sort((a, b) => (a.issueDate ?? '9999').compareTo(b.issueDate ?? '9999'));
  final d = open.first;
  final due = _date(d.dueDate);
  return OpenDocLine(
    d,
    due == null
        ? PersonPageHe.docOpen(name(d))
        : PersonPageHe.docDueBy(
            name(d),
            '${due.day.toString().padLeft(2, '0')}.${due.month.toString().padLeft(2, '0')}',
          ),
    overdue: false,
  );
}

/// The documents list: open ones first (oldest first), then the latest.
List<DocumentSummary> docsForCard(List<DocumentSummary> docs) {
  final open = docs.where((d) => d.isOpen).toList()
    ..sort((a, b) => (a.issueDate ?? '').compareTo(b.issueDate ?? ''));
  final rest = docs.where((d) => !d.isOpen).toList()
    ..sort((a, b) => (b.issueDate ?? '').compareTo(a.issueDate ?? ''));
  return [...open, ...rest];
}

/// Days since the newest document ('YYYY-MM-DD…'), null without one.
int? daysSinceLastDoc(String? lastDocumentAt, DateTime now) {
  final d = _date(lastDocumentAt);
  if (d == null) return null;
  final l = d.toLocal();
  return DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(l.year, l.month, l.day)).inDays;
}
