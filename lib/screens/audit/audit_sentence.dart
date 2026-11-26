// C5 · one audit event → one plain Hebrew sentence + a detail line.
// Pure (no BuildContext): [money] formats minor units, so tests pass a plain
// formatter and the screen passes moneyText (which honours amount privacy).

import '../../util/labels/audit_he.dart';
import '../../util/labels/business_he.dart' show roleLabels;
import '../../util/labels/document_he.dart' show docTypeLabel;
import '../../util/labels/payment_he.dart' show paymentMethodLabel;
import 'audit_api.dart';

typedef MoneyFormat = String Function(BigInt minor);

String _actor(AuditEvent e) => switch (e.actorKind) {
  'SYSTEM' || 'INTEGRATION' => AuditHe.system,
  _ => e.actorName ?? e.actorEmail ?? AuditHe.someone,
};

String _member(AuditEvent e) =>
    e.memberName ?? e.memberEmail ?? AuditHe.someone;

String _role(String? r) => r == null ? AuditHe.unknown : roleLabels[r] ?? r;

/// "חשבונית מס 1044 ללקוח סטודיו כחול" (number and customer when known).
String _doc(AuditEvent e, {String? fallbackType}) {
  final type = e.documentType ?? fallbackType;
  final parts = [
    type == null ? 'מסמך' : docTypeLabel(type),
    ?e.documentNumber,
  ].join(' ');
  final customer = e.customerName;
  return customer == null ? parts : '$parts ללקוח $customer';
}

String _quote(AuditEvent e) {
  final head = ['הצעת מחיר', ?e.quoteNumber].join(' ');
  final customer = e.customerName;
  return customer == null ? head : '$head ללקוח $customer';
}

String? _amount(AuditEvent e, MoneyFormat money) {
  final m = BigInt.tryParse('${e.detail['amountMinor'] ?? ''}');
  return m == null ? null : money(m);
}

AuditChange? _change(AuditEvent e, String field) {
  for (final c in e.changes) {
    if (c.field == field) return c;
  }
  return null;
}

String _approvalSentence(AuditEvent e, String n, MoneyFormat money) {
  final approvals = _change(e, 'approvals');
  final threshold = _change(e, 'thresholdMinor');
  final cap = _change(e, 'cashierCapMinor');
  String m(String? v) {
    final b = BigInt.tryParse(v ?? '');
    return b == null ? AuditHe.unknown : money(b);
  }

  if (approvals?.after == 'off' && approvals?.before == 'on') {
    return '$n כיבה/תה את חובת האישור';
  }
  if (approvals?.after == 'on') {
    final t = threshold?.after;
    return t == null || t == '0'
        ? '$n הפעיל/ה חובת אישור לכל מסמך'
        : '$n הפעיל/ה חובת אישור למסמכים מ-${m(t)}';
  }
  if (threshold != null) {
    return '$n שינה/תה את סף האישור ל-${m(threshold.after)}';
  }
  if (cap != null) return '$n שינה/תה את תקרת הקופאי/ת ל-${m(cap.after)}';
  return '$n שמר/ה את מדיניות האישור';
}

/// The sentence of [e]: who did what to which entity.
String auditSentence(AuditEvent e, {required MoneyFormat money}) {
  final n = _actor(e);
  final amount = _amount(e, money);
  final fieldNames = (e.detail['fields'] as List? ?? const []).map((f) => '$f');
  return switch (e.type) {
    'document.draft_created' =>
      '$n יצר/ה טיוטה: ${_doc(e, fallbackType: '${e.detail['documentType'] ?? ''}')}',
    'document.cloned' => '$n שכפל/ה ${_doc(e)}',
    'document.draft_deleted' => '$n מחק/ה טיוטה של ${_doc(e)}',
    'document.approval_submitted' => '$n שלח/ה לאישור ${_doc(e)}',
    'document.approval_approved' => '$n אישר/ה ${_doc(e)}',
    'document.approval_rejected' => '$n דחה/תה ${_doc(e)}',
    'document.finalized' => '$n הפיק/ה ${_doc(e)}',
    'receipt.issued' => '$n הפיק/ה ${_doc(e, fallbackType: 'RECEIPT')}',
    'document.credited' =>
      '$n זיכה/תה ${_doc(e)}${amount == null ? '' : ' ב-$amount'}',
    'document.voided' => '$n ביטל/ה ${_doc(e)}',
    'document.sent' => '$n שלח/ה במייל ${_doc(e)}',
    'document.whatsapp_sent' => '$n שלח/ה בווטסאפ ${_doc(e)}',
    'document.shared' => '$n יצר/ה קישור ללקוח: ${_doc(e)}',
    'document.share_revoked' => '$n ביטל/ה את הקישור של ${_doc(e)}',
    'document.signed' => '${_doc(e)} נחתם/ה דיגיטלית',
    'document.allocation_requested' => '$n ביקש/ה מספר הקצאה: ${_doc(e)}',
    'document.allocation_cancelled' =>
      '$n ביטל/ה את בקשת מספר ההקצאה: ${_doc(e)}',
    'quote.created' => '$n יצר/ה ${_quote(e)}',
    'quote.converted' => '$n המיר/ה למסמך את ${_quote(e)}',
    'quote.cancelled' => '$n ביטל/ה את ${_quote(e)}',
    'quote.deleted' => '$n מחק/ה טיוטה של הצעת מחיר',
    'quote.emailed' => '$n שלח/ה במייל את ${_quote(e)}',
    'quote.accepted_by_customer' =>
      '${AuditHe.customerSide} אישר/ה ${_quote(e)}',
    // 0116 "מסמך לחתימה".
    'sign_request.created' => '$n יצר/ה מסמך לחתימה',
    'sign_request.sent' => '$n שלח/ה מסמך לחתימה',
    'sign_request.reminded' => '$n שלח/ה תזכורת לחתימה',
    'sign_request.viewed' => '${AuditHe.customerSide} פתח/ה את המסמך לחתימה',
    'sign_request.completed' => '${AuditHe.customerSide} חתם/ה על המסמך',
    'sign_request.cancelled' => '$n ביטל/ה בקשת חתימה',
    // 0134 "טופס 101" (no employee details in the log).
    'employee.created' => '$n הוסיף/ה עובד/ת',
    'employee.updated' => '$n עדכן/ה פרטי עובד/ת',
    'form101.sent' => '$n שלח/ה טופס 101',
    'form101.resent' => '$n שלח/ה שוב טופס 101',
    'form101.code_renewed' => '$n יצר/ה קוד כניסה חדש לטופס 101',
    'form101.verified' => 'עובד/ת אימת/ה את הכניסה לטופס 101',
    'form101.completed' => 'עובד/ת חתם/ה על טופס 101',
    'form101.cancelled' => '$n ביטל/ה טופס 101',
    'form101.owner_viewed' => '$n צפה/תה בטופס 101',
    'form101.pdf_viewed' => '$n פתח/ה טופס 101 חתום',
    'form101.attachment_viewed' => '$n פתח/ה צרופה של טופס 101',
    'form101.sent_to_accountant' => '$n שלח/ה טופס 101 לרואה החשבון',
    'payment.recorded' =>
      '$n רשם/ה תשלום${amount == null ? '' : ' של $amount'}'
          '${e.documentId == null ? '' : ' על ${_doc(e)}'}',
    'payment.voided' =>
      '$n ביטל/ה תשלום${e.documentId == null ? '' : ' על ${_doc(e)}'}',
    'document.pending_payment_added' => '$n רשם/ה תשלום ממתין על ${_doc(e)}',
    'document.pending_payment_cancelled' =>
      '$n ביטל/ה תשלום ממתין על ${_doc(e)}',
    'cardcom.customer_payment_verified' =>
      'התקבל תשלום בכרטיס אשראי${e.documentId == null ? '' : ' על ${_doc(e)}'}',
    'business.member_invited' =>
      '$n הזמין/ה את ${_member(e)} בתור ${_role(e.detail['role'] as String?)}',
    'business.member_created' =>
      '$n הוסיף/ה את ${_member(e)} בתור ${_role(e.detail['role'] as String?)}',
    'business.member_role_changed' => () {
      final c = _change(e, 'role');
      return '$n שינה/תה את התפקיד של ${_member(e)} '
          '${AuditHe.from(_role(c?.before), _role(c?.after))}';
    }(),
    'business.member_permissions_changed' =>
      '$n שינה/תה את ההרשאות של ${_member(e)}',
    'business.member_revoked' => '$n הסיר/ה את ${_member(e)} מהעסק',
    'business.invitation_revoked' => '$n ביטל/ה הזמנה לצוות',
    'business.invitation_resent' => '$n שלח/ה שוב הזמנה ל${_member(e)}',
    'business.ownership_transfer_requested' =>
      '$n ביקש/ה להעביר את הבעלות על העסק',
    'business.ownership_transferred' =>
      '$n העביר/ה את הבעלות על העסק ל${_member(e)}',
    'business.approval_policy_changed' => _approvalSentence(e, n, money),
    'business.sequence_start_set' => () {
      final c = _change(e, 'numberingStart');
      return '$n קבע/ה שהמספור יתחיל מ-${c?.after ?? AuditHe.unknown}';
    }(),
    'business.branding_changed' => '$n שינה/תה את עיצוב המסמכים',
    'business.profile_updated' =>
      fieldNames.contains('bank')
          ? '$n שינה/תה את פרטי הבנק'
          : '$n עדכן/ה את פרטי העסק',
    'business.computerized_documents_changed' =>
      '$n שינה/תה את הגדרת המסמכים הממוחשבים',
    'business.delivery_settings_changed' => '$n שינה/תה את הגדרות השליחה',
    'business.delivery_consent_policy_changed' =>
      '$n שינה/תה את מדיניות ההסכמה לקבלת מסמכים',
    'business.accountant_automation_updated' =>
      '$n שינה/תה את השליחה האוטומטית לרואה החשבון',
    'business.turnover_opening_set' => '$n עדכן/ה את מחזור הפתיחה של השנה',
    'business.type_changed' => 'סוג העסק שונה',
    'cardcom.merchant_configured' => '$n חיבר/ה סליקת אשראי',
    'cardcom.merchant_disconnected' => '$n ניתק/ה את סליקת האשראי',
    'signing.identity_created' => '$n יצר/ה זהות לחתימה דיגיטלית',
    'signing.identity_revoked' => '$n ביטל/ה זהות לחתימה דיגיטלית',
    'customer.updated' => '$n עדכן/ה את הפרטים של ${e.customerName ?? 'לקוח'}',
    'customer.archived' => '$n סימן/ה את ${e.customerName ?? 'הלקוח'} כלא פעיל',
    'customer.restored' => '$n החזיר/ה את ${e.customerName ?? 'הלקוח'} לפעיל',
    'customer.reminder_cadence_set' =>
      '$n שינה/תה את תדירות התזכורות של ${e.customerName ?? 'לקוח'}',
    'customer.erased' => '$n מחק/ה את הפרטים האישיים של לקוח',
    'expense.approved' => '$n אישר/ה הוצאה',
    'expense.rejected' => '$n דחה/תה הוצאה',
    'expense.deleted' => '$n מחק/ה הוצאה',
    'export.generated' => '$n הפיק/ה קובץ ייצוא',
    'export.downloaded' => '$n הוריד/ה קובץ ייצוא',
    'report.sent' => '$n שלח/ה דוח',
    'customer.statement_sent' => '$n שלח/ה כרטסת ל${e.customerName ?? 'לקוח'}',
    // Stage C: debt book (C1), retainers (C4), correction requests (C6).
    'debt_entry.created' =>
      '$n רשם/ה חוב בפנקס${amount == null ? '' : ' של $amount'}',
    'debt_entry.updated' => '$n עדכן/ה חוב בפנקס',
    'debt_entry.paid' =>
      '$n סגר/ה בקבלה חוב בפנקס${amount == null ? '' : ' של $amount'}',
    'debt_entry.deleted' => '$n מחק/ה חוב מהפנקס',
    'payment_reminder.sent' => '$n שלח/ה תזכורת תשלום',
    'document.correction_requested' => '$n ביקש/ה תיקון של ${_doc(e)}',
    'document.correction_dismissed' =>
      '$n סגר/ה בלי תיקון את הבקשה על ${_doc(e)}',
    'recurring.template_created' => '$n הגדיר/ה חשבונית חודשית',
    'recurring.template_updated' => '$n עדכן/ה חשבונית חודשית',
    'recurring.drafts_created' => 'נוצרו טיוטות חודשיות לאישור',
    'recurring.run_skipped' => '$n דילג/ה החודש על חשבונית חודשית',
    'recurring.run_removed' => '$n הסיר/ה חשבונית מהחבילה החודשית',
    _ => '$n ביצע/ה פעולה',
  };
}

String _value(String field, String? v, MoneyFormat money) {
  if (v == null) return AuditHe.unknown;
  if (field.endsWith('Minor')) {
    final m = BigInt.tryParse(v);
    return m == null ? v : money(m);
  }
  return switch (field) {
    'approvals' ||
    'logo' ||
    'footerNote' => v == 'on' ? AuditHe.on : AuditHe.off,
    'role' => _role(v),
    _ => v,
  };
}

/// The line under the sentence: time · before→after · reason · method.
String auditDetailLine(AuditEvent e, {required MoneyFormat money}) {
  final parts = <String>[e.time];
  final skipRole = e.type == 'business.member_role_changed';
  for (final c in e.changes) {
    final label = AuditHe.fields[c.field];
    if (label == null) continue;
    // Bank and owner: the sentence says it all.
    if (c.field == 'bank' || c.field == 'owner') continue;
    if (c.field == 'permissions') continue; // codes, not words
    if (skipRole && c.field == 'role') continue;
    if (e.type == 'business.member_revoked') continue;
    if (c.before == null && c.after == null) continue;
    parts.add(
      c.before == null
          ? '$label: ${_value(c.field, c.after, money)}'
          : '$label: ${AuditHe.from(_value(c.field, c.before, money), _value(c.field, c.after, money))}',
    );
  }
  final reason = e.detail['reason'];
  if (reason is String && reason.isNotEmpty) {
    parts.add('${AuditHe.reason}: $reason');
  }
  final method = e.detail['method'];
  if (method is String && e.type == 'payment.recorded') {
    parts.add(paymentMethodLabel(method));
  }
  return parts.where((p) => p.isNotEmpty).join(' · ');
}
