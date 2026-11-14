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

  /// The full WhatsApp text: greeting, business, type + number, amount due,
  /// due date and the document link.
  static String message({
    String? customerName,
    required String documentType,
    String? documentNumber,
    required BigInt amountMinor,
    String? dueDate,
    required String business,
    required String link,
    String? paymentUrl,
  }) {
    final name = customerName?.trim() ?? '';
    final number = documentNumber == null || documentNumber.isEmpty
        ? ''
        : ' מס׳ ${ltrIsolate(documentNumber)}';
    final amount = ltrIsolate(formatMoney(amountMinor, trimZeroAgorot: true));
    final due = dueDate == null || dueDate.isEmpty
        ? ''
        : ' (לתשלום עד ${ltrIsolate(formatDateHe(dueDate))})';
    return [
      'שלום${name.isEmpty ? '' : ' ${fsiIsolate(name)}'},',
      'תזכורת ידידותית מ${fsiIsolate(business)}: '
          '${docTypeLabel(documentType)}$number על סך $amount ממתינה לתשלום$due.',
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
    final amount = ltrIsolate(formatMoney(amountMinor, trimZeroAgorot: true));
    return 'תזכורת מ${fsiIsolate(business)}: ${docTypeLabel(documentType)}'
        '$number על סך $amount ממתינה לתשלום.\n$link';
  }

  /// "Last reminded" hint under the action / on the overdue row.
  static String lastReminded(int days) => switch (days) {
    <= 0 => 'נשלחה תזכורת היום',
    1 => 'נשלחה תזכורת אתמול',
    _ => 'נשלחה תזכורת לפני $days ימים',
  };
}
