// Fakes owned by squad E (SPEC-v2 §18.1). Register this domain's endpoints on
// a [FakeBackend] with sensible defaults; tests override single routes after.
// Endpoints: /business/members*, /business/invitations/*, /settings/approval,
// /settings/branding, /settings/signing, /shaam/status, /sequences*,
// /mobile/web-handoff, /mobile/logout-all, /exports/*, /dashboard, /reports/*,
// /auth/invite/:token*.

import 'fake_backend.dart';

/// GET /business/members row.
Map<String, dynamic> memberJson(
  String id,
  String role, {
  List<String> permissions = const [],
  bool self = false,
  String? name,
  String? email,
}) => {
  'userId': id,
  'email': email ?? '$id@tevel.test',
  'displayName': name,
  'role': role,
  'permissions': permissions,
  'revokedAt': null,
  'lastLoginAt': null,
  'isSelf': self,
};

/// GET /business/members invitation row.
Map<String, dynamic> invitationJson(
  String id,
  String email,
  String role, {
  List<String> permissions = const [],
  DateTime? expiresAt,
}) => {
  'id': id,
  'email': email,
  'role': role,
  'permissions': permissions,
  'invitedBy': 'דנה',
  'expiresAt': (expiresAt ?? DateTime.now().add(const Duration(days: 5))).toUtc().toIso8601String(),
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

/// The default team: me (owner) + a partner + an employee + one pending invite.
Map<String, dynamic> teamJson({
  List<Map<String, dynamic>>? members,
  List<Map<String, dynamic>>? invitations,
  List<Map<String, dynamic>>? expired,
}) => {
  'members':
      members ??
      [
        memberJson('u-me', 'OWNER', self: true, name: 'דנה'),
        memberJson('u-partner', 'ADMIN', name: 'יוסי'),
        memberJson('u-emp', 'EMPLOYEE', name: 'רון'),
      ],
  'invitations': invitations ?? [invitationJson('i1', 'new@tevel.test', 'EMPLOYEE')],
  'expiredInvitations': expired ?? const [],
  'grantablePermissions': [
    'document:read',
    'document:draft:write',
    'document:finalize',
    'document:send',
    'payment:record',
    'expense:record',
    'expense:approve',
  ],
};

void installBusinessFakes(FakeBackend backend) {
  backend
    ..json('GET', '/business/members', teamJson())
    ..on(
      'POST',
      '/business/members/invite',
      (r) => r.body['role'] == 'ACCOUNTANT_REP'
          // Pre-BE-04 server (today): unknown role → 400 VALIDATION.
          ? FakeResponse.error(400, 'VALIDATION', 'role')
          : FakeResponse(201, {
              'invitationId': 'i-new',
              'link': 'https://app.test/#/invite?token=t',
              'inviteUrl': 'https://app.test/m/invite/tok',
              'expiresAt': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
              'role': r.body['role'],
              'permissions': r.body['permissions'] ?? const [],
            }),
    )
    ..on(
      'POST',
      '/business/invitations/:id/resend',
      (r) => FakeResponse(200, {
        'invitationId': r.params['id'],
        'inviteUrl': 'https://app.test/m/invite/tok2',
        'permissions': const [],
      }),
    )
    ..json('POST', '/business/invitations/:id/revoke', {'status': 'ok'})
    ..on(
      'PUT',
      '/business/members/:userId/role',
      (r) => r.body['role'] == 'ACCOUNTANT_REP'
          ? FakeResponse.error(400, 'VALIDATION', 'role')
          : const FakeResponse(200, {'status': 'ok'}),
    )
    ..on(
      'PUT',
      '/business/members/:userId/permissions',
      (r) => FakeResponse(200, {'permissions': r.body['permissions']}),
    )
    ..json('POST', '/business/members/:userId/revoke', {'status': 'ok'})
    ..on('PUT', '/settings/approval', (r) => FakeResponse(200, {'mode': r.body['mode']}))
    ..json('GET', '/settings/branding', {
      'branding': {
        'template': 'modern',
        'fontFamily': 'sans',
        'logoDataUri': null,
        'logoSize': 'medium',
        'accentColor': null,
        'accentTableHeader': false,
        'headerNote': 'כותרת',
        'footerNote': null,
      },
      'canConfigure': true,
    })
    ..on('PUT', '/settings/branding', (r) => FakeResponse(200, {'branding': r.body, 'canConfigure': true}))
    ..json('GET', '/settings/signing', {
      'available': true,
      'identity': {'id': 'sig1'},
      'session': {'unlocked': false, 'expiresAt': null},
    })
    ..json('GET', '/shaam/status', {
      'environment': 'sandbox',
      'status': 'CONNECTED',
      'refreshTokenExpiresAt': '2027-01-10T00:00:00Z',
      'lastVerifiedAt': '2026-10-01T00:00:00Z',
      'manualEntryEnabled': false,
      'canConfigure': true,
    })
    ..json('GET', '/sequences', {
      'sequences': [
        {'numbering_scope_key': 'default', 'numbering_policy_version': 1, 'next_number': '1'},
      ],
    })
    ..on(
      'PUT',
      '/sequences/:scopeKey/start',
      (r) => FakeResponse(200, {'scopeKey': r.params['scopeKey'], 'nextNumber': r.body['nextNumber']}),
    )
    ..on(
      'POST',
      '/mobile/web-handoff',
      (r) => FakeResponse(202, {'status': 'SENT', 'topic': r.body['topic']}),
    )
    ..json('POST', '/mobile/logout-all', {'status': 'ok', 'revoked': 2})
    ..json('POST', '/mobile/logout', {'status': 'ok'})
    ..json('GET', '/dashboard', {
      'summary': {
        'month_income': '472000',
        'unpaid_total': '354000',
        'unpaid_balance': '354000',
        'overdue_total': '118000',
        'overdue_count': 1,
      },
      'recent': const [],
    })
    ..on(
      'POST',
      '/exports/:kind',
      (r) => FakeResponse(201, {'exportId': 'x1', 'storageKey': 'exports/b1/${r.params['kind']}-2026.zip'}),
    )
    ..on('GET', '/exports/download', (_) => const FakeResponse(200, <int>[80, 75, 3, 4]))
    // BE-13 (SRV-2, live): copy of every document e-mail to the owner.
    ..json('GET', '/settings/document-email', {'ccOwnerEmail': false})
    ..on(
      'PUT',
      '/settings/document-email',
      (r) => FakeResponse(200, {'ccOwnerEmail': r.body['ccOwnerEmail']}),
    )
    // BE-11 (SRV-2, live): payments ledger.
    ..json('GET', '/payments', paymentsJson())
    // BE-24 (SRV-3, live): business list with search.
    ..on('GET', '/mobile/businesses', (r) {
      final q = r.raw.url.queryParameters['q'] ?? '';
      final all = [
        for (var i = 1; i <= 30; i++)
          {'businessId': 'srv-$i', 'legalName': 'לקוח שרת $i', 'role': 'ACCOUNTANT'},
      ].where((b) => (b['legalName'] as String).contains(q)).toList();
      final offset = int.parse(r.raw.url.queryParameters['offset'] ?? '0');
      final limit = int.parse(r.raw.url.queryParameters['limit'] ?? '50');
      return FakeResponse(200, {
        'total': all.length,
        'offset': offset,
        'limit': limit,
        'businesses': all.skip(offset).take(limit).toList(),
      });
    })
    // P2 routes not on the server yet → router 404 NOT_FOUND (rows hidden):
    // /settings/reminders, /settings/accountant-automation, /businesses,
    // /business/type-change, /business/ownership/transfer, /reports/:kind/send.
    // BE-18 is not on the server yet: 404 (cards hidden). Tests override.
    ..error('GET', '/reports/:kind', 404, 'NOT_FOUND')
    ..json('GET', '/auth/invite/:token', {
      'email': 'new@tevel.test',
      'role': 'EMPLOYEE',
      'roleLabel': 'עובד',
      'permissions': const [],
      'businessName': 'סטודיו תבל',
      'inviterName': 'דנה',
      'expiresAt': DateTime.now().add(const Duration(days: 5)).toUtc().toIso8601String(),
      'accountExists': true,
      'accountHasPassword': true,
    })
    ..json('POST', '/auth/invite/:token/accept', {
      'status': 'ok',
      'businessId': 'b1',
      'role': 'EMPLOYEE',
      'csrfToken': 'c',
    });
}

/// BE-18 report answer for R2 tests.
Map<String, dynamic> reportJson({int rows = 3}) => {
  'kpis': [
    {'label': 'הכנסות', 'valueMinor': '472000'},
    {'label': 'מסמכים', 'value': '$rows'},
  ],
  'columns': [
    {'key': 'customer', 'label': 'לקוח'},
    {'key': 'total', 'label': 'סכום', 'type': 'money'},
  ],
  'rows': [
    for (var i = 1; i <= rows; i++) {'customer': 'לקוח $i', 'total': '${i * 10000}'},
  ],
};

/// GET /payments (BE-11) answer: [n] payments of 100 ₪ each.
Map<String, dynamic> paymentsJson({int n = 2, int? total}) => {
  'total': total ?? n,
  'offset': 0,
  'limit': 500,
  'payments': [
    for (var i = 1; i <= n; i++)
      {
        'id': 'p$i',
        'method': i.isEven ? 'CASH' : 'BANK_TRANSFER',
        'amountMinor': '10000',
        'currency': 'ILS',
        'paymentDate': '2026-10-0$i',
        'reference': null,
        'customerId': 'c$i',
        'customerName': 'לקוח $i',
        'allocations': const [],
        'receiptDocumentId': 'r$i',
        'receiptDocumentNumber': '100$i',
        'recordedBy': 'u-me',
        'recordedAt': '2026-10-0${i}T10:00:00Z',
        'voidedAt': null,
        'voidReason': null,
      },
  ],
};
