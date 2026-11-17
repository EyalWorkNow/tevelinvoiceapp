// ציר זמן ללקוח + תנאי תשלום (0110). Gender-free "event: entity" sentences.

import 'document_he.dart' show docTypeLabels;
import 'payment_he.dart' show paymentMethodLabel;

abstract final class TimelineHe {
  static const title = 'ציר זמן';
  static const rowSubtitle = 'כל מה שקרה עם הלקוח, מהחדש לישן';
  static const empty = 'עוד לא קרה כלום עם הלקוח הזה';
  static const emptyHint = 'מסמכים, תשלומים, הצעות מחיר והערות יופיעו כאן.';

  /// Walkthrough 2026-11-17 #12: a chip with nothing in it says so — not
  /// "nothing happened with this customer".
  static String emptyFiltered(String chip) => 'אין כאן $chip עדיין';
  static const emptyFilteredHint =
      'בחרו "הכל" כדי לראות את כל מה שקרה עם הלקוח.';

  /// A note written on the customer card (פתקים ומעקב), shown read-only here.
  static const fromCustomerCard = 'פתק מכרטיס הלקוח';
  static const loadMore = 'הצג עוד';
  static const today = 'היום';
  static const yesterday = 'אתמול';
  static const hiddenAmount = 'סכום מוסתר';
  static const chipAll = 'הכל';
  static const Map<String, String> chips = {
    'documents': 'מסמכים',
    'quotes': 'הצעות מחיר',
    'payments': 'תשלומים',
    'debts': 'חובות',
    'reminders': 'תזכורות',
    'recurring': 'חיוב חודשי',
    'corrections': 'בקשות תיקון',
    'notes': 'הערות',
    'calendar': 'פגישות',
  };

  // Notes.
  static const addNote = 'הוסף הערה';
  static const noteTitle = 'הערה';
  static const editNoteTitle = 'עריכת הערה';
  static const noteHint = 'למשל: ביקש להעביר את החשבונית לרו״ח';
  static const noteSave = 'שמור';
  static const noteEmpty = 'כתבו משהו בהערה';
  static const noteEdit = 'ערוך';
  static const noteDelete = 'מחק';
  static const noteDeleteConfirm = 'למחוק את ההערה?';
  static const noteEdited = 'נערכה';
  static const noteSaved = 'ההערה נשמרה';
  static const noteDeleted = 'ההערה נמחקה';

  // Payment terms.
  static const terms = 'תנאי תשלום';
  static const termsNone = 'לא הוגדרו';
  static const termsFromBusiness = 'ברירת המחדל של העסק';
  static const termsSheetSubtitle =
      'מסמך חדש ללקוח יקבל מהם תאריך לתשלום ואמצעי תשלום. אפשר לשנות בכל מסמך.';
  static const businessTermsTitle = 'תנאי תשלום ברירת מחדל';
  static const businessTermsSubtitle =
      'לכל לקוח שלא הוגדרו לו תנאים משלו. שוטף+30 = סוף החודש של המסמך ועוד 30 יום.';
  static const termsCustom = 'מותאם';
  static const termsCustomDays = 'מספר ימים';
  static const termsFromEom = 'מסוף החודש (שוטף)';
  static const termsFromIssue = 'מתאריך המסמך';
  static const termsNoTerms = 'ללא';
  static const preferredMethod = 'אמצעי תשלום מועדף';
  static const preferredNone = 'ללא';
  static const termsSave = 'שמור';
  static const termsSaved = 'תנאי התשלום נשמרו';
  static const daysInvalid = 'מספר ימים בין 0 ל־365';
  static String dueExample(String date) => 'מסמך שיופק היום: לתשלום עד $date';
}

String _doc(Map<String, dynamic> d) {
  final type = docTypeLabels[d['documentType']] ?? 'מסמך';
  final n = d['documentNumber'];
  return n is String && n.isNotEmpty ? '$type $n' : type;
}

String _quote(Map<String, dynamic> d) {
  final n = d['quoteNumber'];
  return n is String && n.isNotEmpty ? 'הצעת מחיר $n' : 'הצעת מחיר';
}

/// The chip of a payment row: a wallet transfer reads as ביט / פייבוקס.
String _method(Map<String, dynamic> d) => switch (d['wallet']) {
  'ביט' => 'BIT',
  'פייבוקס' => 'PAYBOX',
  _ => d['method'] is String ? d['method'] as String : 'OTHER',
};

const _channels = {
  'EMAIL': 'במייל',
  'WHATSAPP': 'בוואטסאפ',
  'LINK': 'בקישור',
  'SHARE': '',
};

const _runStatus = {
  'DRAFTED': 'נוצרה טיוטה',
  'SUBMITTED': 'נשלח לאישור',
  'WAITING_ALLOCATION': 'ממתין למספר הקצאה',
  'ISSUED': 'הופק',
  'SKIPPED': 'דולג',
  'REMOVED': 'הוסר',
  'FAILED': 'לא הופק',
};

String _with(String what, String? channel) {
  final c = _channels[channel] ?? '';
  return c.isEmpty ? what : '$what $c';
}

/// "נקבעה פגישה · 01.12 09:00" (startsAtIsrael = "YYYY-MM-DD HH:MM").
String _meeting(String what, Map<String, dynamic> d) {
  final at = d['startsAtIsrael'];
  if (at is! String || at.length < 16) return what;
  return '$what · ${at.substring(8, 10)}.${at.substring(5, 7)} ${at.substring(11, 16)}';
}

/// The headline of one timeline row.
String timelineSentence(String kind, Map<String, dynamic> d) {
  final note = d['note'] is String ? d['note'] as String : '';
  return switch (kind) {
    'document.issued' => 'הופק: ${_doc(d)}',
    'document.sent' => '${_with('נשלח', d['channel'] as String?)}: ${_doc(d)}',
    'document.viewed' => 'הלקוח צפה: ${_doc(d)}',
    'document.voided' => 'בוטל: ${_doc(d)}',
    'quote.created' => '${_quote(d)} נוצרה',
    'quote.sent' => _with('${_quote(d)} נשלחה', d['channel'] as String?),
    'quote.viewed' => 'הלקוח צפה ב${_quote(d)}',
    'quote.accepted' =>
      d['byCustomer'] == true
          ? '${_quote(d)} אושרה על ידי הלקוח'
          : '${_quote(d)} אושרה',
    'quote.declined' => '${_quote(d)} נדחתה',
    'quote.expired' => 'פג התוקף של ${_quote(d)}',
    'quote.cancelled' => '${_quote(d)} בוטלה',
    'quote.converted' => '${_quote(d)} הפכה למסמך',
    'quote.status' => '${_quote(d)} עודכנה',
    'payment.recorded' => 'התקבל תשלום · ${paymentMethodLabel(_method(d))}',
    'payment.voided' => 'תשלום בוטל',
    'debt.created' => note.isEmpty ? 'נרשם חוב' : 'נרשם חוב: $note',
    'debt.paid' => note.isEmpty ? 'חוב נסגר' : 'חוב נסגר: $note',
    'debt.deleted' => note.isEmpty ? 'חוב נמחק' : 'חוב נמחק: $note',
    'reminder.sent' => _with(
      d['auto'] == true ? 'נשלחה תזכורת אוטומטית' : 'נשלחה תזכורת תשלום',
      d['channel'] as String?,
    ),
    'recurring.started' =>
      'הוגדר חיוב חודשי${d['title'] is String ? ': ${d['title']}' : ''}',
    'recurring.run' =>
      'חיוב חודשי ${d['period'] ?? ''}: ${_runStatus[d['status']] ?? ''}'
          .trim(),
    'correction.requested' =>
      '${d['requestKind'] == 'CREDIT' ? 'בקשת זיכוי' : 'בקשת תיקון'}: ${_doc(d)}',
    'correction.closed' =>
      d['status'] == 'DISMISSED' ? 'בקשת התיקון נסגרה' : 'בקשת התיקון טופלה',
    'calendar.booked' => _meeting('נקבעה פגישה', d),
    'calendar.cancelled' =>
      d['cancelledBy'] == 'CLIENT'
          ? _meeting('הלקוח ביטל פגישה', d)
          : _meeting('בוטלה פגישה', d),
    'note' => (d['body'] as String?) ?? '',
    _ => 'עדכון',
  };
}

/// "שוטף+30 · העברה" for a terms value (null when nothing is set).
String? termsSummary(String? terms, String? method) {
  final parts = [?terms, if (method != null) paymentMethodLabel(method)];
  return parts.isEmpty ? null : parts.join(' · ');
}
