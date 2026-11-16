// SA2 (QA 2026-11-16, persona 02 pain 2): the money of a paid issue that
// stops at WAITING_FOR_ALLOCATION is handed to the server, never kept only on
// the phone; an older version's local copy is uploaded once on startup.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/issue_api.dart';
import 'package:invoice/state/cache.dart';

/// The document routes of an SA2 server: finalize stores `pendingPayments`
/// when the document waits; POST pending-payments is idempotent per key and
/// records at once on an issued document.
class Sa2Server {
  final List<http.Request> requests = [];
  final Set<String> loseResponseOnce = {};
  String status = 'NONE';

  /// false = an older SA2 server that stores but does not echo.
  bool echoPending = true;

  /// false = a server without SA2 (no pending-payments route).
  bool hasPendingRoute = true;
  final Map<String, Map<String, dynamic>> pending = {}; // key → row
  int recordedPayments = 0;
  String? finalizeKey;

  http.Response _json(int code, Object body) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json'},
  );

  Map<String, dynamic> _row(String key, Map<String, dynamic> body) =>
      pending.putIfAbsent(key, () {
        final issued = status != 'WAITING_FOR_ALLOCATION';
        if (issued) recordedPayments++;
        return {
          'id': 'pp-${pending.length + 1}',
          'method': body['method'],
          'amountMinor': '118000',
          'status': issued ? 'RECORDED' : 'PENDING',
        };
      });

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final key = '${r.method} ${r.url.path}';
    final res = _route(r, key);
    if (loseResponseOnce.remove(key)) throw const SocketException('lost');
    return res;
  }

  http.Response _route(http.Request r, String key) {
    switch (key) {
      case 'POST /documents':
        status = 'DRAFT';
        return _json(201, {'id': 'd1', 'status': 'DRAFT'});
      case 'GET /sequences':
        return _json(200, {
          'sequences': [
            {'numbering_scope_key': 'default'},
          ],
        });
      case 'POST /documents/d1/allocation/evaluate':
        return _json(200, {'state': 'REQUIRED'});
      case 'GET /documents/d1/allocation':
        return _json(200, {'state': 'REQUESTED'});
      case 'POST /documents/d1/finalize':
        final k = r.headers['Idempotency-Key']!;
        finalizeKey ??= k;
        status = 'WAITING_FOR_ALLOCATION';
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final list = body['pendingPayments'] as List? ?? const [];
        if (hasPendingRoute) {
          for (var i = 0; i < list.length; i++) {
            _row('$k:pending:$i', Map<String, dynamic>.from(list[i] as Map));
          }
        }
        return _json(200, {
          'status': 'WAITING_FOR_ALLOCATION',
          'documentNumber': null,
          'reused': false,
          if (echoPending && hasPendingRoute)
            'pendingPayments': [
              for (final row in pending.values)
                if (row['status'] == 'PENDING') row,
            ],
        });
      case 'POST /documents/d1/pending-payments':
        if (!hasPendingRoute) return _json(404, {'error': 'NOT_FOUND'});
        final row = _row(
          r.headers['Idempotency-Key']!,
          jsonDecode(r.body) as Map<String, dynamic>,
        );
        return _json(201, {'pendingPayment': row, 'reused': false});
      case 'POST /documents/d1/artifact':
        status = 'ARCHIVED';
        return _json(201, {'signing': 'NOT_APPLICABLE'});
      case 'POST /payments':
        return _json(201, {'paymentId': 'p1'});
      case 'POST /documents/d1/payments':
        recordedPayments++;
        return _json(200, {'allocated': true});
      case 'GET /documents/d1':
        return _json(200, {
          'document': {
            'id': 'd1',
            'document_type': 'TAX_INVOICE_RECEIPT',
            'status': status,
            'currency': 'ILS',
            'total_minor': '118000',
            'paid_total_minor': recordedPayments > 0 ? '118000' : '0',
            'balance_minor': recordedPayments > 0 ? '0' : '118000',
            'pendingPayments': [
              for (final row in pending.values)
                if (row['status'] == 'PENDING') row,
            ],
          },
          'lines': [],
        });
    }
    return _json(404, {'error': 'NOT_FOUND'});
  }

  int count(String key) =>
      requests.where((r) => '${r.method} ${r.url.path}' == key).length;
}

PendingIssue paidIssue() => PendingIssue(
  businessId: 'b1',
  body: {
    'documentType': 'TAX_INVOICE_RECEIPT',
    'customerId': 'c1',
    'lines': const [],
  },
  form: const {'amountText': '1180'},
  payment: const PaymentInput(method: 'BANK_TRANSFER'),
  totalMinor: BigInt.from(118000),
  needsApproval: false,
);

void main() {
  final api = ApiClient.instance;
  late Sa2Server server;
  late Directory tmp;

  setUp(() {
    resetScopeKeyCache();
    resetPendingPaymentUploads();
    tmp = Directory.systemTemp.createTempSync('pending_payment_test');
    AppCache.directoryProvider = () async => tmp;
    server = Sa2Server();
    api
      ..clearCredentials()
      ..deviceToken = 'inv_t'
      ..businessId = 'b1'
      ..httpClient = MockClient(server.handle);
  });

  tearDown(() async {
    await AppCache.clearAll();
  });

  test('finalize carries the payment; the phone keeps no copy', () async {
    final r = await runIssue(paidIssue());
    expect(r.outcome, IssueOutcome.waitingForAllocation);
    final finalize = server.requests.firstWhere(
      (q) => q.url.path.endsWith('/finalize'),
    );
    expect(jsonDecode(finalize.body)['pendingPayments'], [
      {'method': 'BANK_TRANSFER', 'currency': 'ILS', 'paymentDate': todayIso()},
    ]);
    expect(server.pending, hasLength(1));
    final saved = (await loadPendingIssue())!;
    expect(saved.payment, isNull, reason: 'the server owns it now');
    expect(saved.paymentViaServer, isTrue);
    expect(server.count('POST /documents/d1/pending-payments'), 0);

    // A second issue overwrites the local slot: the money is safe on the server.
    await clearPendingIssue('b1');
    expect(server.pending.values.single['status'], 'PENDING');
  });

  test(
    'after the number arrives the resume never records the payment itself',
    () async {
      await runIssue(paidIssue());
      server.status = 'FINALIZED'; // the server recorded it on completion
      final done = await resumeAfterAllocation('d1');
      expect(done!.outcome, IssueOutcome.issued);
      expect(server.count('POST /payments'), 0);
      expect(server.count('POST /documents/d1/payments'), 0);
    },
  );

  test('no echo → uploaded right after with the derived key', () async {
    server.echoPending = false;
    await runIssue(paidIssue());
    final upload = server.requests.lastWhere(
      (q) => q.url.path.endsWith('/pending-payments'),
    );
    expect(
      upload.headers['Idempotency-Key'],
      pendingPaymentKey(server.finalizeKey!),
    );
    expect(server.pending, hasLength(1), reason: 'same key → same row');
    expect((await loadPendingIssue())!.payment, isNull);
  });

  test(
    'offline upload: the local copy stays; startup uploads it once',
    () async {
      server.echoPending = false;
      server.loseResponseOnce.add('POST /documents/d1/pending-payments');
      final r = await runIssue(paidIssue());
      expect(r.outcome, IssueOutcome.waitingForAllocation);
      expect((await loadPendingIssue())!.payment, isNotNull);

      await uploadLocalPendingPayment();
      await uploadLocalPendingPayment(); // once per business per run
      expect(server.pending, hasLength(1), reason: 'the lost try is reused');
      expect((await loadPendingIssue())!.payment, isNull);
      expect(server.count('POST /documents/d1/pending-payments'), 2);
    },
  );

  test(
    "migration: an older version's waiting journal is uploaded; issued doc records it",
    () async {
      server.status = 'FINALIZED'; // the number already arrived
      final old = paidIssue()
        ..draftId = 'd1'
        ..stage = IssueStage.waitingAllocation
        ..finalizeKey = 'fin-old-1'
        ..paymentDate = '2026-11-10';
      await savePendingIssue(old);
      await uploadLocalPendingPayment();
      final upload = server.requests.single;
      expect(upload.url.path, '/documents/d1/pending-payments');
      expect(upload.headers['Idempotency-Key'], 'fin-old-1:pending:0');
      expect(jsonDecode(upload.body)['paymentDate'], '2026-11-10');
      expect(server.recordedPayments, 1);
      final saved = (await loadPendingIssue())!;
      expect(saved.payment, isNull);

      // Resuming that journal now finishes without a second payment.
      await resumeIssueFor('d1');
      expect(server.count('POST /payments'), 0);
      expect(server.recordedPayments, 1);
    },
  );

  test('a server without SA2 keeps the old local flow', () async {
    server.hasPendingRoute = false;
    await runIssue(paidIssue());
    expect((await loadPendingIssue())!.payment, isNotNull);
    server.status = 'FINALIZED';
    await resumeAfterAllocation('d1');
    expect(server.count('POST /payments'), 1);
    expect(server.recordedPayments, 1);
  });

  test('migration ignores journals that never waited', () async {
    await savePendingIssue(
      paidIssue()
        ..draftId = 'd1'
        ..stage = IssueStage.draft,
    );
    await uploadLocalPendingPayment();
    expect(server.requests, isEmpty);
  });

  test('pendingPaymentsOf reads document.pendingPayments', () {
    final list = pendingPaymentsOf({
      'document': {
        'pendingPayments': [
          {'id': 'pp-1', 'method': 'CHECK', 'amountMinor': '50000'},
          {'method': 'CASH'}, // no id → skipped
        ],
      },
    });
    expect(list, hasLength(1));
    expect(list.single.amountMinor, BigInt.from(50000));
    expect(pendingPaymentsOf({'document': {}}), isEmpty);
  });

  test('PaymentInput.pendingBody carries the cheque, never an amount', () {
    const pay = PaymentInput(
      method: 'CHECK',
      bankNumber: '12',
      branchNumber: '345',
      accountNumber: '678901',
      checkNumber: '1001',
    );
    expect(pay.pendingBody('2026-11-16'), {
      'method': 'CHECK',
      'currency': 'ILS',
      'paymentDate': '2026-11-16',
      'bankNumber': '12',
      'branchNumber': '345',
      'accountNumber': '678901',
      'reference': '1001',
    });
  });
}
