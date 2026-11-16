// One-tap WhatsApp payment reminder (innovation report R1,
// docs/features/whatsapp-reminder-he.md). Every send is a user tap.
//
// Numbers, amounts and dates sit inside a Hebrew (RTL) sentence: each one is
// wrapped in LRI…PDI so "מס׳ 1024" / "₪1,180" / "12.11.2026" never flip or
// swap with the neighbouring words. Names (business / customer, Hebrew or
// Latin) get FSI…PDI. The link stands alone on its own line, never isolated
// (WhatsApp would otherwise pull the PDI into the tappable URL).

import '../../ui/money_text.dart' show ltrIsolate;
import '../money.dart';
import 'common_he.dart';
import 'document_he.dart';

/// First-strong isolate (FSI … PDI) around a name of either direction.
String fsiIsolate(String s) => '\u2068$s\u2069';

abstract final class ReminderHe {
  /// The per-row button in the overdue list.
  static const whatsApp = 'הזכר בווטסאפ';
  static String whatsAppA11y(String customer) => 'הזכר בווטסאפ ל$customer';

  /// C1: the opening line by how many reminders were already sent for what
  /// is open — the 1st friendly, the 2nd firmer, from the 3rd "נא להסדיר".
  /// Always polite; the "אם כבר שילמת" line stays in every tone.
  static String opening(int previous, String business) => switch (previous) {
    <= 0 => 'תזכורת ידידותית מ${fsiIsolate(business)}: ',
    1 => 'תזכורת נוספת מ${fsiIsolate(business)}: ',
    _ => 'נא להסדיר את התשלום ל${fsiIsolate(business)}: ',
  };

  /// The closing request, by the same count.
  static String ask(int previous) => switch (previous) {
    <= 0 => '',
    1 => ' נודה להסדרת התשלום בהקדם.',
    _ => ' נבקש להסדיר את התשלום עוד השבוע.',
  };

  /// The full WhatsApp text: greeting, business, type + number, amount due,
  /// due date and the document link. [previous]: reminders already sent.
  static String message({
    String? customerName,
    required String documentType,
    String? documentNumber,
    required BigInt amountMinor,
    String? dueDate,
    required String business,
    required String link,
    String? paymentUrl,
    int previous = 0,
  }) {
    final name = customerName?.trim() ?? '';
    final number = documentNumber == null || documentNumber.isEmpty
        ? ''
        : ' מס׳ ${ltrIsolate(documentNumber)}';
    final amount = ltrIsolate(formatMoney(amountMinor));
    final due = dueDate == null || dueDate.isEmpty
        ? ''
        : ' (לתשלום עד ${ltrIsolate(formatDateHe(dueDate))})';
    return [
      'שלום${name.isEmpty ? '' : ' ${fsiIsolate(name)}'},',
      '${opening(previous, business)}'
          '${docTypeLabel(documentType)}$number על סך $amount ממתינה לתשלום$due.'
          '${ask(previous)}',
      'לצפייה ולתשלום:',
      link,
      if (paymentUrl != null && paymentUrl.isNotEmpty) ...[
        'לתשלום מהיר:',
        paymentUrl,
      ],
      'אם כבר שילמת – תודה, ואפשר להתעלם מההודעה.',
    ].join('\n');
  }

  /// No phone → the system share sheet with this shorter text.
  static String short({
    required String documentType,
    String? documentNumber,
    required BigInt amountMinor,
    required String business,
    required String link,
  }) {
    final number = documentNumber == null || documentNumber.isEmpty
        ? ''
        : ' ${ltrIsolate(documentNumber)}';
    final amount = ltrIsolate(formatMoney(amountMinor));
    return 'תזכורת מ${fsiIsolate(business)}: ${docTypeLabel(documentType)}'
        '$number על סך $amount ממתינה לתשלום.\n$link';
  }

  /// C1 "מי חייב לי": one message for everything a customer owes —
  /// documents (type + number) and debt-book lines (the owner's note, e.g.
  /// "3 שיעורים"), the total, the document links and the business payment
  /// link. A debt-book line is not a document: it gets no number or link.
  static String customerMessage({
    String? customerName,
    required String business,
    required List<({String label, BigInt amountMinor})> items,
    required BigInt totalMinor,
    List<String> links = const [],
    String? paymentUrl,
    int previous = 0,
  }) {
    final name = customerName?.trim() ?? '';
    final total = ltrIsolate(formatMoney(totalMinor));
    return [
      'שלום${name.isEmpty ? '' : ' ${fsiIsolate(name)}'},',
      '${opening(previous, business)}יתרה של $total ממתינה לתשלום.'
          '${ask(previous)}',
      for (final i in items)
        '• ${fsiIsolate(i.label)} – ${ltrIsolate(formatMoney(i.amountMinor))}',
      if (links.isNotEmpty) ...['לצפייה:', ...links],
      if (paymentUrl != null && paymentUrl.isNotEmpty) ...[
        'לתשלום מהיר:',
        paymentUrl,
      ],
      'אם כבר שילמת – תודה, ואפשר להתעלם מההודעה.',
    ].join('\n');
  }

  /// A document line in [customerMessage]: "חשבונית מס מס׳ 1024".
  static String documentLine(String documentType, String? number) =>
      number == null || number.isEmpty
      ? docTypeLabel(documentType)
      : '${docTypeLabel(documentType)} מס׳ $number';

  /// "Last reminded" hint under the action / on the overdue row.
  static String lastReminded(int days) => switch (days) {
    <= 0 => 'נשלחה תזכורת היום',
    1 => 'נשלחה תזכורת אתמול',
    _ => 'נשלחה תזכורת לפני $days ימים',
  };
}
