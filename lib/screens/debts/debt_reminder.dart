// C1 · one WhatsApp reminder for everything a customer owes (user tap only).
//
// One open document and nothing in the debt book → the existing per-document
// reminder (sendPaymentReminder: document link + payment link). Otherwise one
// message that lists the documents and the debt-book lines ([ReminderHe
// .customerMessage]). The tone escalates by the server's count of reminders
// already sent for what is open (1st friendly, 2nd firmer, 3rd "נא להסדיר").
// The reminder is recorded on the server (and this device) for every item.

import '../../api/debts_api.dart';
import '../../api/inbox_api.dart' show shareLinkFor;
import '../../state/business_context.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/reminder_he.dart';
import '../../util/payment_reminder.dart';
import '../../util/phone.dart';
import '../document/sheets/s6_share.dart' show sendPaymentReminder, textSharer;

/// Document links in one customer message (each is one share-link call).
const int reminderLinksMax = 3;

/// Lines listed in one customer message.
const int reminderItemsMax = 10;

Future<void> remindDebtor(Debtor d, {DateTime? now}) async {
  final previous = d.reminderCount;
  final paymentUrl = businessContext.profile?.paymentLinkUrl;
  if (d.documents.length == 1 && d.debtEntries.isEmpty) {
    final doc = d.documents.single;
    await sendPaymentReminder(
      documentId: doc.id,
      documentType: doc.documentType,
      documentNumber: doc.documentNumber,
      openMinor: doc.openMinor,
      dueDate: doc.dueDate,
      customerName: d.customerName,
      phone: d.phone,
      link: () => shareLinkFor(doc.id),
      paymentUrl: paymentUrl,
      now: now,
      previous: previous,
    );
    return;
  }
  final links = <String>[];
  for (final doc in d.documents.take(reminderLinksMax)) {
    try {
      links.add(await shareLinkFor(doc.id));
    } on Object {
      // The message still lists the document; only its link is missing.
    }
  }
  final text = ReminderHe.customerMessage(
    customerName: d.customerName,
    business: businessContext.displayName,
    items: [
      for (final doc in d.documents)
        (
          label: ReminderHe.documentLine(doc.documentType, doc.documentNumber),
          amountMinor: doc.openMinor,
        ),
      for (final e in d.debtEntries)
        (label: e.note, amountMinor: e.amountMinor),
    ].take(reminderItemsMax).toList(),
    totalMinor: d.totalMinor,
    links: links,
    paymentUrl: paymentUrl,
    previous: previous,
  );
  final wa = waPhone(d.phone);
  var opened = false;
  if (wa != null) {
    opened = await launchAllowed(whatsAppUri(phone: wa, text: text));
  }
  if (!opened) await textSharer(text);
  await ReminderLog.recordMany(
    documentIds: [for (final doc in d.documents) doc.id],
    debtEntryIds: [for (final e in d.debtEntries) e.id],
    at: now,
    channel: opened ? 'WHATSAPP' : 'SHARE',
  );
}
