// Accountant multi-business (2026-11-22; docs: tevel-accountant-contract.md).
//
//   GET    /mobile/accountant/clients                    → AccountantOverview
//   PUT    /mobile/accountant/profile {officeName}
//   POST   /mobile/accountant/access-requests {contact, role}
//   POST   /mobile/accountant/access-requests/:id/resend
//   DELETE /mobile/accountant/access-requests/:id
//   GET    /mobile/access-requests/:token                (the owner)
//   POST   /mobile/access-requests/:token/decide
//   POST   /mobile/accountant/clients/:businessId/leave
//   GET/POST/DELETE /reports/period-review               (X-Business-Id)
//
// /mobile/* are account-level (no X-Business-Id). A server without the
// endpoints answers 404 → null where the app has a fallback.

import 'client.dart';
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

/// Readiness below this counts as "needs attention" (the readiness threshold).
const int accountantReadyThreshold = 90;

class AccountantTasks {
  const AccountantTasks({
    this.expensesToApprove = 0,
    this.paymentsWithoutReceipt = 0,
    this.taxInvoicesDue = 0,
    this.numberingGaps = 0,
    this.correctionsAnswered = 0,
  });

  factory AccountantTasks.fromJson(Map<String, dynamic> j) => AccountantTasks(
    expensesToApprove: jIntOrNull(j['expensesToApprove']) ?? 0,
    paymentsWithoutReceipt: jIntOrNull(j['paymentsWithoutReceipt']) ?? 0,
    taxInvoicesDue: jIntOrNull(j['taxInvoicesDue']) ?? 0,
    numberingGaps: jIntOrNull(j['numberingGaps']) ?? 0,
    correctionsAnswered: jIntOrNull(j['correctionsAnswered']) ?? 0,
  );

  final int expensesToApprove;
  final int paymentsWithoutReceipt;
  final int taxInvoicesDue;
  final int numberingGaps;
  final int correctionsAnswered;

  int get total =>
      expensesToApprove +
      paymentsWithoutReceipt +
      taxInvoicesDue +
      numberingGaps +
      correctionsAnswered;
}

class AccountantClient {
  const AccountantClient({
    required this.businessId,
    required this.legalName,
    required this.role,
    this.readiness,
    this.tasks = const AccountantTasks(),
    this.openTasks = 0,
    this.lastReviewedPeriod,
    this.ownerPhone,
  });

  factory AccountantClient.fromJson(Map<String, dynamic> j) {
    final tasks = AccountantTasks.fromJson(jMap(j['tasks']));
    return AccountantClient(
      businessId: jStr(j['businessId']) ?? '',
      legalName: jStr(j['legalName']) ?? '',
      role: jStr(j['role']) ?? '',
      readiness: (j['readiness'] is num)
          ? (j['readiness'] as num).round().clamp(0, 100)
          : null,
      tasks: tasks,
      openTasks: jIntOrNull(j['openTasks']) ?? tasks.total,
      lastReviewedPeriod: jStr(j['lastReviewedPeriod']),
      ownerPhone: jStr(j['ownerPhone']),
    );
  }

  final String businessId;
  final String legalName;
  final String role;

  /// 0-100, current period; null = not allowed / not computed.
  final int? readiness;
  final AccountantTasks tasks;
  final int openTasks;

  /// 'YYYY-MM' or null.
  final String? lastReviewedPeriod;
  final String? ownerPhone;

  /// At least one open task, or a readiness below the threshold.
  bool get needsAttention =>
      openTasks > 0 ||
      (readiness != null && readiness! < accountantReadyThreshold);
}

enum AccessRequestStatus { pending, declined, expired, unknown }

class AccessRequest {
  const AccessRequest({
    required this.id,
    required this.contact,
    required this.role,
    required this.status,
    this.createdAt,
    this.expiresAt,
  });

  factory AccessRequest.fromJson(Map<String, dynamic> j) => AccessRequest(
    id: jStr(j['id']) ?? '',
    contact: jStr(j['contact']) ?? '',
    role: jStr(j['role']) ?? 'ACCOUNTANT_REP',
    status: switch (jStr(j['status'])) {
      'PENDING' => AccessRequestStatus.pending,
      'DECLINED' => AccessRequestStatus.declined,
      'EXPIRED' => AccessRequestStatus.expired,
      _ => AccessRequestStatus.unknown,
    },
    createdAt: DateTime.tryParse(jStr(j['createdAt']) ?? ''),
    expiresAt: DateTime.tryParse(jStr(j['expiresAt']) ?? ''),
  );

  final String id;
  final String contact;

  /// ACCOUNTANT_REP | ACCOUNTANT.
  final String role;
  final AccessRequestStatus status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
}

class AccountantOverview {
  const AccountantOverview({
    required this.isAccountant,
    this.officeName,
    this.clients = const [],
    this.requests = const [],
  });

  factory AccountantOverview.fromJson(Map<String, dynamic> j) {
    final profile = jMap(j['profile']);
    return AccountantOverview(
      isAccountant: profile['isAccountant'] == true,
      officeName: jStr(profile['officeName']),
      clients: [
        for (final c
            in (j['clients'] is List ? j['clients'] as List : const []))
          if (c is Map<String, dynamic>) AccountantClient.fromJson(c),
      ],
      requests: [
        for (final r
            in (j['requests'] is List ? j['requests'] as List : const []))
          if (r is Map<String, dynamic>) AccessRequest.fromJson(r),
      ],
    );
  }

  final bool isAccountant;
  final String? officeName;
  final List<AccountantClient> clients;
  final List<AccessRequest> requests;

  int get needingAttention => clients.where((c) => c.needsAttention).length;

  List<AccessRequest> get pending => [
    for (final r in requests)
      if (r.status == AccessRequestStatus.pending) r,
  ];

  AccountantClient? clientOf(String businessId) {
    for (final c in clients) {
      if (c.businessId == businessId) return c;
    }
    return null;
  }
}

/// null = the server has no accountant endpoints (404).
Future<AccountantOverview?> fetchAccountantClients() async {
  try {
    return AccountantOverview.fromJson(
      await _api.get('/mobile/accountant/clients'),
    );
  } on ApiException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

/// Marks the user as an accountant (onboarding "אני רו״ח") / renames the office.
Future<String> saveAccountantProfile(String officeName) async {
  final j = await _api.put('/mobile/accountant/profile', {
    'officeName': officeName.trim(),
  });
  return jStr(j['officeName']) ?? officeName.trim();
}

class AccessRequestSent {
  const AccessRequestSent({
    required this.id,
    required this.link,
    required this.whatsappText,
    required this.emailed,
  });

  factory AccessRequestSent.fromJson(Map<String, dynamic> j) =>
      AccessRequestSent(
        id: jStr(j['id']) ?? '',
        link: jStr(j['link']) ?? '',
        whatsappText: jStr(j['whatsappText']) ?? '',
        emailed: j['emailed'] == true,
      );

  final String id;
  final String link;
  final String whatsappText;
  final bool emailed;
}

Future<AccessRequestSent> createAccessRequest({
  required String contact,
  required String role,
}) async => AccessRequestSent.fromJson(
  await _api.post('/mobile/accountant/access-requests', {
    'contact': contact.trim(),
    'role': role,
  }),
);

Future<AccessRequestSent> resendAccessRequest(String id) async =>
    AccessRequestSent.fromJson(
      await _api.post('/mobile/accountant/access-requests/$id/resend'),
    );

Future<void> cancelAccessRequest(String id) =>
    _api.delete('/mobile/accountant/access-requests/$id');

/// What the owner sees when opening /m/access/:token.
class AccessRequestPreview {
  const AccessRequestPreview({
    required this.id,
    required this.accountantName,
    required this.accountantEmail,
    required this.role,
    this.officeName,
    this.expiresAt,
    this.businesses = const [],
  });

  factory AccessRequestPreview.fromJson(Map<String, dynamic> j) {
    final a = jMap(j['accountant']);
    return AccessRequestPreview(
      id: jStr(j['id']) ?? '',
      accountantName: jStr(a['name']) ?? '',
      accountantEmail: jStr(a['email']) ?? '',
      officeName: jStr(a['officeName']),
      role: jStr(j['role']) ?? 'ACCOUNTANT_REP',
      expiresAt: DateTime.tryParse(jStr(j['expiresAt']) ?? ''),
      businesses: [
        for (final b
            in (j['businesses'] is List ? j['businesses'] as List : const []))
          if (b is Map<String, dynamic>)
            (id: jStr(b['businessId']) ?? '', name: jStr(b['legalName']) ?? ''),
      ],
    );
  }

  final String id;
  final String accountantName;
  final String accountantEmail;
  final String? officeName;
  final String role;
  final DateTime? expiresAt;

  /// Businesses where the caller has membership:manage.
  final List<({String id, String name})> businesses;
}

Future<AccessRequestPreview> fetchAccessRequest(String token) async =>
    AccessRequestPreview.fromJson(
      await _api.get('/mobile/access-requests/$token'),
    );

/// APPROVE needs [businessId]; [role] overrides the requested one.
Future<String> decideAccessRequest(
  String token, {
  required bool approve,
  String? businessId,
  String? role,
}) async {
  final j = await _api.post('/mobile/access-requests/$token/decide', {
    'decision': approve ? 'APPROVE' : 'DECLINE',
    'businessId': ?(approve ? businessId : null),
    'role': ?(approve ? role : null),
  });
  return jStr(j['status']) ?? (approve ? 'APPROVED' : 'DECLINED');
}

Future<void> leaveClient(String businessId) =>
    _api.post('/mobile/accountant/clients/$businessId/leave');

class PeriodReview {
  const PeriodReview({required this.period, this.reviewedAt, this.reviewedBy});

  factory PeriodReview.fromJson(Map<String, dynamic> j) => PeriodReview(
    period: jStr(j['period']) ?? '',
    reviewedAt: DateTime.tryParse(jStr(j['reviewedAt']) ?? ''),
    reviewedBy: jStr(j['reviewedBy']),
  );

  final String period;
  final DateTime? reviewedAt;
  final String? reviewedBy;
}

/// The selected business's reviewed periods; null = not served (404 / 403).
Future<List<PeriodReview>?> fetchPeriodReviews() async {
  try {
    final j = await _api.get('/reports/period-review');
    final list = j['reviews'];
    if (list is! List) return null;
    return [
      for (final r in list)
        if (r is Map<String, dynamic>) PeriodReview.fromJson(r),
    ];
  } on ApiException catch (e) {
    if (e.status == 404 || e.status == 403) return null;
    rethrow;
  }
}

Future<PeriodReview> markPeriodReviewed(String period) async =>
    PeriodReview.fromJson(
      await _api.post('/reports/period-review', {'period': period}),
    );

Future<void> unmarkPeriodReviewed(String period) => _api.delete(
  '/reports/period-review?period=${Uri.encodeQueryComponent(period)}',
);

/// 'YYYY-MM' of [month].
String periodKeyOf(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

/// True when the period before the current one is marked reviewed. The list
/// does not know each business's VAT cadence, so the earlier (bi-monthly)
/// start counts: a review of that month or later.
bool previousPeriodReviewed(String? lastReviewed, {DateTime? now}) {
  if (lastReviewed == null ||
      !RegExp(r'^\d{4}-\d{2}$').hasMatch(lastReviewed)) {
    return false;
  }
  final n = now ?? DateTime.now();
  var start = ((n.month - 1) ~/ 2) * 2 + 1 - 2;
  var year = n.year;
  if (start < 1) {
    start += 12;
    year -= 1;
  }
  return lastReviewed.compareTo(periodKeyOf(DateTime(year, start))) >= 0;
}

/// Contact validation for "הוספת לקוח": e-mail or Israeli mobile.
bool isValidAccessContact(String raw) {
  final v = raw.trim();
  if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) return true;
  final digits = v.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^(05\d{8}|\+9725\d{8})$').hasMatch(digits);
}
