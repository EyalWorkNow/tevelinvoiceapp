// Fakes owned by squad A (SPEC-v2 §18.1). Register this domain's endpoints on
// a [FakeBackend] with sensible defaults; tests override single routes after.
// Endpoints: GET /dashboard, GET /documents (limit / offset / status / unpaid /
// q / minTotal+maxTotal / customerId),
// GET /approvals, GET /expenses/inbox, GET /quotes, GET /settings/branding,
// reminders (POST /documents/:id/send, /deliveries/:id/process,
// /documents/:id/share-link, /artifact), POST /documents/:id/allocation;
// BE-05 GET /mobile/inbox only when [mobileInbox] is given (else 404 → P0).

import 'fake_backend.dart';

/// A GET /documents row (BE-10a camelCase).
Map<String, dynamic> docJson(
  String id, {
  String type = 'TAX_INVOICE',
  String status = 'ARCHIVED',
  String? number,
  String? customerId = 'c1',
  String? customerName = 'דנה כהן',
  int total = 118000,
  int? open,
  int credited = 0,
  String? issueDate = '2026-10-20',
  String? dueDate,
  String? createdBy = 'u-me',
  String? submittedBy,
  String? sentAt,
  String? voidedAt,
  Map<String, dynamic>? rejection,
}) =>
    {
      'id': id,
      'documentType': type,
      'status': status,
      'documentNumber': number,
      'customerId': customerId,
      'customerName': customerName,
      'issueDate': issueDate,
      'dueDate': dueDate,
      'currency': 'ILS',
      'totalMinor': '$total',
      'balanceMinor': '${open ?? 0}',
      'creditedMinor': '$credited',
      'openMinor': '${open ?? 0}',
      'createdBy': createdBy,
      'submittedBy': submittedBy,
      'sentAt': sentAt,
      'voidedAt': voidedAt,
      'rejection': rejection,
    };

/// One BE-05 card exactly as SRV-3 sends it ({kind, priority, count,
/// amountMinor, documentIds, action, detail}).
Map<String, dynamic> inboxCardJson(
  String kind, {
  int count = 1,
  String? amount,
  List<String> documentIds = const [],
  List<String>? expenseIds,
  String action = 'OPEN',
  Map<String, dynamic>? detail,
}) =>
    {
      'kind': kind,
      'priority': 0,
      'count': count,
      'amountMinor': amount,
      'documentIds': documentIds,
      'expenseIds': ?expenseIds,
      'action': action,
      'detail': detail,
    };

/// GET /mobile/inbox body (BE-05). [recent] rows use the BE-05 projection.
Map<String, dynamic> mobileInboxJson({
  int? open,
  int overdue = 0,
  List<Map<String, dynamic>> cards = const [],
  List<Map<String, dynamic>> recent = const [],
}) =>
    {
      'generatedAt': '2026-10-30T08:00:00Z',
      'money': open == null ? null : {'openMinor': '$open', 'overdueMinor': '$overdue'},
      'cards': cards,
      'recent': recent,
    };

/// A BE-05 `recent[]` row.
Map<String, dynamic> recentJson(String id,
        {String type = 'TAX_INVOICE', String status = 'ARCHIVED', String? number, String? customerName = 'דנה כהן',
        int total = 118000, int open = 0, String? issueDate = '2026-10-20', bool cancelled = false}) =>
    {
      'id': id,
      'documentType': type,
      'status': status,
      'documentNumber': number,
      'customerName': customerName,
      'totalMinor': '$total',
      'openMinor': '$open',
      'issueDate': issueDate,
      'cancelled': cancelled,
    };

/// /dashboard body (BE-01 shape).
Map<String, dynamic> dashboardJson({int unpaid = 0, int overdue = 0, int overdueCount = 0}) => {
      'summary': {
        'month_income': '0', 'month_income_count': 0, 'month_expenses': '0',
        'unpaid_count': unpaid == 0 ? 0 : 1, 'unpaid_balance': '$unpaid', 'unpaid_total': '$unpaid',
        'overdue_total': '$overdue', 'overdue_count': overdueCount, 'review_count': 0,
        'open_quotes': 0, 'pending_approval': 0,
      },
      'recent': [],
    };

void installInboxFakes(
  FakeBackend backend, {
  List<Map<String, dynamic>> documents = const [],
  Map<String, dynamic>? dashboard,
  List<Map<String, dynamic>> approvals = const [],
  List<Map<String, dynamic>> expenses = const [],
  List<Map<String, dynamic>> quotes = const [],
  String? logoDataUri = 'data:image/png;base64,AAAA',
  Map<String, dynamic>? mobileInbox,
  bool be10 = false,
}) {
  backend
    ..json('GET', '/dashboard', dashboard ?? dashboardJson())
    ..on('GET', '/documents', (r) {
      final q = r.query;
      var rows = [
        for (final d in documents)
          if ((q['status'] == null || d['status'] == q['status']) &&
              (q['unpaid'] != '1' ||
                  ((d['documentType'] == 'TAX_INVOICE' || d['documentType'] == 'TRANSACTION_INVOICE') &&
                      int.parse('${d['openMinor']}') > 0)) &&
              (q['q'] == null || '${d['customerName']}'.contains(q['q']!) || d['documentNumber'] == q['q']) &&
              (q['minTotal'] == null || int.parse('${d['totalMinor']}') >= int.parse(q['minTotal']!)) &&
              (q['maxTotal'] == null || int.parse('${d['totalMinor']}') <= int.parse(q['maxTotal']!)) &&
              (q['customerId'] == null || d['customerId'] == q['customerId']))
            d
      ];
      final total = rows.length;
      final limit = int.tryParse(q['limit'] ?? '') ?? 100;
      final offset = int.tryParse(q['offset'] ?? '') ?? 0;
      rows = rows.skip(offset).take(limit).toList();
      return FakeResponse(200, {
        'total': total,
        'limit': limit,
        if (be10) 'offset': offset,
        'documents': rows,
      });
    })
    ..json('GET', '/approvals', {'approvals': approvals})
    ..json('GET', '/expenses/inbox', {'expenses': expenses})
    ..json('GET', '/quotes', {'quotes': quotes})
    ..json('GET', '/settings/branding', {
      'branding': {'logoDataUri': logoDataUri},
      'canConfigure': true,
    })
    ..on('POST', '/documents/:id/send', (r) => FakeResponse(202, {'deliveryId': 'dl-${r.params['id']}'}))
    ..json('POST', '/deliveries/:id/process', {'status': 'SENT', 'attemptCount': 1})
    ..on('POST', '/documents/:id/share-link',
        (r) => FakeResponse(201, {'url': 'https://invoice.test/d/tok-${r.params['id']}'}))
    ..json('POST', '/documents/:id/artifact', {'artifactId': 'a1'}, status: 201)
    ..on('GET', '/documents/:id', (r) => FakeResponse(200, {
          'document': {'id': r.params['id'], 'numbering_scope_key': 'default'},
          'lines': [],
        }))
    ..json('POST', '/documents/:id/allocation', {'status': 'PENDING'});
  if (mobileInbox != null) backend.json('GET', '/mobile/inbox', mobileInbox);
}
