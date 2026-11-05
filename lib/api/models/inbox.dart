// Home / inbox models (squad A). P0: GET /dashboard (BE-01) + composed cards.
// P1: GET /mobile/inbox (BE-05) → HomeData.fromJson. BE-05 cards carry the
// first document's words in `detail` (customerName, documentType,
// rejection.reason, dueBy, step, shaamStatus/refreshTokenExpiresAt); the
// client cache keeps them flat. fromJson reads both.

import 'document.dart';
import 'json.dart';

/// GET /dashboard → {summary, recent}. Summary is snake_case.
class DashboardSummary {
  const DashboardSummary({
    required this.monthIncomeMinor,
    required this.monthIncomeCount,
    required this.monthExpensesMinor,
    required this.unpaidCount,
    required this.unpaidBalanceMinor,
    this.unpaidTotalMinor,
    this.overdueTotalMinor,
    this.overdueCount,
    required this.reviewCount,
    required this.openQuotes,
    required this.pendingApproval,
    required this.recent,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final s = jMap(json['summary']);
    return DashboardSummary(
      monthIncomeMinor: jBig(s['month_income']),
      monthIncomeCount: jInt(s['month_income_count'] ?? 0),
      monthExpensesMinor: jBig(s['month_expenses']),
      unpaidCount: jInt(s['unpaid_count'] ?? 0),
      unpaidBalanceMinor: jBig(s['unpaid_balance']),
      unpaidTotalMinor: jBigOrNull(s['unpaid_total']),
      overdueTotalMinor: jBigOrNull(s['overdue_total']),
      overdueCount: jIntOrNull(s['overdue_count']),
      reviewCount: jInt(s['review_count'] ?? 0),
      openQuotes: jInt(s['open_quotes'] ?? 0),
      pendingApproval: jInt(s['pending_approval'] ?? 0),
      recent: [
        for (final r in (json['recent'] as List? ?? const []))
          DocumentSummary.fromJson(r as Map<String, dynamic>)
      ],
    );
  }

  final BigInt monthIncomeMinor;
  final int monthIncomeCount;
  final BigInt monthExpensesMinor;
  final int unpaidCount;
  final BigInt unpaidBalanceMinor;

  /// BE-01 (null on a server without it).
  final BigInt? unpaidTotalMinor;
  final BigInt? overdueTotalMinor;
  final int? overdueCount;

  final int reviewCount;
  final int openQuotes;
  final int pendingApproval;

  /// Last 8 documents (no customerName / balance — use GET /documents).
  final List<DocumentSummary> recent;
}

// ---- "לטיפול" cards (§6.H.1) -------------------------------------------------

/// Card kinds of §6.H.1, in priority order (first = most urgent).
enum InboxKind {
  approvalNeeded('APPROVAL_NEEDED'),
  myRejected('MY_REJECTED'),
  taxInvoiceDue('TAX_INVOICE_DUE'),
  allocationProblem('ALLOCATION_PROBLEM'),
  signingLocked('SIGNING_LOCKED'),
  unfinished('UNFINISHED'),
  overdue('OVERDUE'),
  quoteAccepted('QUOTE_ACCEPTED'),
  expenseReview('EXPENSE_REVIEW'),
  paymentReceived('PAYMENT_RECEIVED'),
  shaamRenew('SHAAM_RENEW'),
  setup('SETUP'),
  reportReady('REPORT_READY'),
  continuityGap('CONTINUITY_GAP');

  const InboxKind(this.wire);

  /// Server name (BE-05 `kind`).
  final String wire;

  static InboxKind? fromWire(String? s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// The one-at-a-time SETUP card, in its fixed order (§6.H.1).
enum SetupStep {
  recoveryCodes('RECOVERY_CODES'),
  logo('LOGO'),
  paymentLink('PAYMENT_LINK'),
  team('TEAM_MEMBER');

  const SetupStep(this.wire);
  final String wire;

  static SetupStep? fromWire(String? s) {
    if (s == 'TEAM') return team; // caches written before BE-05
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// One "לטיפול" card. Built on the client from P0 sources, or read from
/// GET /mobile/inbox (BE-05) `cards[]`.
class InboxItem {
  const InboxItem({
    required this.kind,
    this.count = 1,
    this.amountMinor,
    this.documentIds = const [],
    this.expenseIds = const [],
    this.customerName,
    this.documentNumber,
    this.documentType,
    this.reason,
    this.dueDate,
    this.daysLeft,
    this.setupStep,
  });

  /// [now] turns BE-05 `detail.refreshTokenExpiresAt` into [daysLeft].
  factory InboxItem.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final d = jMap(json['detail']);
    String? pick(String key) => jStr(d[key]) ?? jStr(json[key]);
    final rejection = d['rejection'];
    return InboxItem(
      kind: InboxKind.fromWire(jStr(json['kind']))!,
      count: jIntOrNull(json['count']) ?? 1,
      amountMinor: jBigOrNull(json['amountMinor']),
      documentIds: jStrings(json['documentIds']),
      expenseIds: jStrings(json['expenseIds']),
      customerName: pick('customerName'),
      documentNumber: pick('documentNumber'),
      documentType: pick('documentType'),
      reason: rejection is Map ? jStr(rejection['reason']) : jStr(json['reason']),
      dueDate: jStr(d['dueBy']) ?? jStr(json['dueDate']),
      daysLeft: jIntOrNull(json['daysLeft']) ?? _shaamDaysLeft(d, now ?? DateTime.now()),
      setupStep: SetupStep.fromWire(pick('step')),
    );
  }

  final InboxKind kind;
  final int count;
  final BigInt? amountMinor;
  final List<String> documentIds;

  /// EXPENSE_REVIEW (BE-05): the expenses behind the card, newest first.
  final List<String> expenseIds;

  /// Single-document cards: who / which (title words).
  final String? customerName;
  final String? documentNumber;
  final String? documentType;

  /// MY_REJECTED: the approver's reason (BE-37 `rejection.reason`).
  final String? reason;

  /// TAX_INVOICE_DUE: issue the 305 by this date ('YYYY-MM-DD').
  final String? dueDate;

  /// SHAAM_RENEW: days until the tax-authority connection expires.
  final int? daysLeft;
  final SetupStep? setupStep;

  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'count': count,
        if (amountMinor != null) 'amountMinor': amountMinor.toString(),
        'documentIds': documentIds,
        if (expenseIds.isNotEmpty) 'expenseIds': expenseIds,
        'customerName': ?customerName,
        'documentNumber': ?documentNumber,
        'documentType': ?documentType,
        'reason': ?reason,
        'dueDate': ?dueDate,
        'daysLeft': ?daysLeft,
        if (setupStep != null) 'step': setupStep!.wire,
      };
}

/// BE-05 SHAAM_RENEW detail → days left (EXPIRED / REAUTH_REQUIRED = 0);
/// null when the detail is not about the tax-authority connection.
int? _shaamDaysLeft(Map<String, dynamic> d, DateTime now) {
  final status = jStr(d['shaamStatus']);
  if (status == 'EXPIRED' || status == 'REAUTH_REQUIRED') return 0;
  final expires = DateTime.tryParse(jStr(d['refreshTokenExpiresAt']) ?? '');
  if (expires == null) return status == null ? null : 0;
  final days = expires.difference(now).inHours ~/ 24;
  return days < 0 ? 0 : days;
}

/// BE-05 `recent[]` rows say `cancelled` instead of voidedAt/creditedMinor;
/// keep the F10 word "בוטל" by marking them voided.
Map<String, dynamic> _recentRow(Map<String, dynamic> r) =>
    r['cancelled'] == true && r['voidedAt'] == null ? {...r, 'voidedAt': 'cancelled'} : r;

/// What H shows: money card numbers, sorted cards, recent rows.
/// Cached per business so H paints before the network (F9).
class HomeData {
  const HomeData({
    this.openMinor,
    this.overdueMinor,
    this.cards = const [],
    this.recent = const [],
    this.hasDocuments = true,
  });

  /// GET /mobile/inbox (BE-05) and the client cache use the same shape.
  factory HomeData.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final money = json['money'];
    final recent = json['recent'] as List? ?? const [];
    return HomeData(
      openMinor: money is Map<String, dynamic> ? jBigOrNull(money['openMinor']) : null,
      overdueMinor: money is Map<String, dynamic> ? jBigOrNull(money['overdueMinor']) : null,
      cards: [
        for (final c in (json['cards'] as List? ?? const []))
          if (c is Map<String, dynamic> && InboxKind.fromWire(jStr(c['kind'])) != null)
            InboxItem.fromJson(c, now: now)
      ],
      recent: [
        for (final r in recent) DocumentSummary.fromJson(_recentRow(r as Map<String, dynamic>))
      ],
      hasDocuments: json['hasDocuments'] is bool ? json['hasDocuments'] as bool : recent.isNotEmpty,
    );
  }

  /// "מגיע לך" (null = no money card: no `money.view`, or unknown).
  final BigInt? openMinor;

  /// "מתוכם באיחור".
  final BigInt? overdueMinor;

  /// Sorted by §6.H.1 priority, already filtered by capability.
  final List<InboxItem> cards;

  /// Newest first (H shows 5).
  final List<DocumentSummary> recent;

  /// False for a brand-new business (no document at all yet).
  final bool hasDocuments;

  Map<String, dynamic> toJson() => {
        'money': openMinor == null
            ? null
            : {'openMinor': openMinor.toString(), 'overdueMinor': (overdueMinor ?? BigInt.zero).toString()},
        'cards': [for (final c in cards) c.toJson()],
        'recent': [for (final r in recent) r.toJson()],
        'hasDocuments': hasDocuments,
      };
}

/// GET /approvals → {approvals:[{id, documentType, totalMinor, currency,
/// submittedBy, submittedByEmail, submittedAt}]}.
class ApprovalRow {
  const ApprovalRow({required this.id, required this.documentType, required this.totalMinor, this.submittedBy});

  factory ApprovalRow.fromJson(Map<String, dynamic> json) => ApprovalRow(
        id: json['id'] as String,
        documentType: jStr(json['documentType']) ?? '',
        totalMinor: jBig(json['totalMinor']),
        submittedBy: jStr(json['submittedBy']),
      );

  final String id;
  final String documentType;
  final BigInt totalMinor;
  final String? submittedBy;
}

/// GET /quotes row (L chip "הצעות"). Squad B owns the full Quote model; this
/// is the list projection L needs: {id, title, status, customerId,
/// customerName, totalMinor, createdAt, convertedDocumentId}.
class QuoteRow {
  const QuoteRow({
    required this.id,
    required this.status,
    required this.totalMinor,
    this.title,
    this.customerName,
    this.createdAt,
    this.convertedDocumentId,
    this.validUntil,
  });

  factory QuoteRow.fromJson(Map<String, dynamic> json) => QuoteRow(
        id: json['id'] as String,
        status: jStr(json['status']) ?? 'DRAFT',
        totalMinor: jBig(jPick(json, ['totalMinor', 'total_minor'])),
        title: jStr(json['title']),
        customerName: jStr(jPick(json, ['customerName', 'customer_name'])),
        createdAt: jStr(jPick(json, ['createdAt', 'created_at'])),
        convertedDocumentId: jStr(jPick(json, ['convertedDocumentId', 'converted_document_id'])),
        validUntil: jStr(jPick(json, ['validUntil', 'valid_until'])),
      );

  final String id;
  final String status;
  final BigInt totalMinor;
  final String? title;
  final String? customerName;

  /// 'YYYY-MM-DD'.
  final String? createdAt;
  final String? convertedDocumentId;

  /// 'YYYY-MM-DD' (GET /quotes `validUntil`).
  final String? validUntil;

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'totalMinor': totalMinor.toString(),
        'title': title,
        'customerName': customerName,
        'createdAt': createdAt,
        'convertedDocumentId': convertedDocumentId,
        'validUntil': validUntil,
      };
}
