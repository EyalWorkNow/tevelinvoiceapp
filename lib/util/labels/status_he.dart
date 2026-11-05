// Status labels (INT). Raw server statuses (V1 chips) + the V2 list statuses
// of §15.5 (DocStatus / QuoteListStatus in util/status_map.dart).

import '../status_map.dart';

const Map<String, String> statusLabels = {
  'DRAFT': 'טיוטה',
  'VALIDATING': 'באימות',
  'READY_TO_FINALIZE': 'מוכן להפקה',
  'WAITING_FOR_ALLOCATION': 'ממתין להקצאה',
  'PENDING_APPROVAL': 'ממתין לאישור',
  'FINALIZED': 'הופק',
  'ARTIFACT_PENDING': 'ממתין למסמך',
  'SIGNED': 'חתום',
  'ARCHIVED': 'הופק',
  'SENT': 'נשלח',
  'UPLOADED': 'הועלה',
  'NEEDS_REVIEW': 'לבדיקה',
  'READY_TO_APPROVE': 'מוכן לאישור',
  'APPROVED': 'אושר',
  'REJECTED': 'נדחה',
  'DUPLICATE': 'כפול',
  'ERROR': 'שגיאה',
  'ACCEPTED': 'אושרה',
};

String statusLabel(String status) => statusLabels[status] ?? status;

/// Semantic colour of a status chip (maps onto palette ok/warn/danger/muted).
enum Tone { ok, warn, danger, info, neutral }

const Map<String, Tone> _statusTones = {
  'FINALIZED': Tone.ok,
  'ARCHIVED': Tone.ok,
  'SIGNED': Tone.ok,
  'APPROVED': Tone.ok,
  'ACCEPTED': Tone.ok,
  'SENT': Tone.info,
  'VALIDATING': Tone.warn,
  'READY_TO_FINALIZE': Tone.warn,
  'WAITING_FOR_ALLOCATION': Tone.warn,
  'ARTIFACT_PENDING': Tone.warn,
  'PENDING_APPROVAL': Tone.warn,
  'NEEDS_REVIEW': Tone.warn,
  'READY_TO_APPROVE': Tone.warn,
  'UPLOADED': Tone.info,
  'REJECTED': Tone.danger,
  'DUPLICATE': Tone.danger,
  'ERROR': Tone.danger,
};

Tone statusTone(String status) => _statusTones[status] ?? Tone.neutral;

/// §15.5 list label of an invoice-family document (F10: 5 statuses + "הופק").
const Map<DocStatus, String> docStatusLabels = {
  DocStatus.draft: 'טיוטה',
  DocStatus.pendingApproval: 'ממתין לאישור',
  DocStatus.awaitingPayment: 'ממתין לתשלום',
  DocStatus.overdue: 'באיחור',
  DocStatus.paid: 'שולם',
  DocStatus.cancelled: 'בוטל',
  DocStatus.issued: 'הופק',
};

/// §15.5 quote list labels.
const Map<QuoteListStatus, String> quoteStatusLabels = {
  QuoteListStatus.draft: 'טיוטה',
  QuoteListStatus.withCustomer: 'אצל הלקוח',
  QuoteListStatus.accepted: 'אושרה',
  QuoteListStatus.converted: 'הפכה לחשבונית',
  QuoteListStatus.notRelevant: 'לא רלוונטית',
};

/// Attribute words shown next to the status (never a status themselves).
const Map<DocAttribute, String> docAttributeLabels = {
  DocAttribute.waitingTaxAuthority: 'ממתין לרשות המסים',
  DocAttribute.waitingSignature: 'ממתין לחתימה',
  DocAttribute.sent: 'נשלח',
  DocAttribute.viewed: 'נצפה',
};

const Map<DocStatus, Tone> docStatusTones = {
  DocStatus.draft: Tone.neutral,
  DocStatus.pendingApproval: Tone.warn,
  DocStatus.awaitingPayment: Tone.warn,
  DocStatus.overdue: Tone.danger,
  DocStatus.paid: Tone.ok,
  DocStatus.cancelled: Tone.neutral,
  DocStatus.issued: Tone.ok,
};

const Map<QuoteListStatus, Tone> quoteStatusTones = {
  QuoteListStatus.draft: Tone.neutral,
  QuoteListStatus.withCustomer: Tone.info,
  QuoteListStatus.accepted: Tone.ok,
  QuoteListStatus.converted: Tone.ok,
  QuoteListStatus.notRelevant: Tone.neutral,
};
