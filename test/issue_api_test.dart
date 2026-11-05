import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/issue_api.dart';
import 'package:invoice/state/cache.dart';

/// Tiny in-memory stand-in for the document routes, with switches to lose a
/// response AFTER the server already did the work (the dangerous case).
class FakeServer {
  final List<http.Request> requests = [];
  final Set<String> loseResponseOnce = {};
  String status = 'NONE';
  BigInt paid = BigInt.zero;
  int drafts = 0;
  String draftType = '';
  int numbers = 0;
  bool artifact = false;
  final Map<String, String> finalizeKeys = {};
  final Map<String, String> paymentKeys = {};
  bool approvalPolicy = false;
  String finalizeOutcome = 'FINALIZED';

  http.Response _json(int code, Object body) =>
      http.Response(jsonEncode(body), code, headers: {'content-type': 'application/json'});

  Map<String, dynamic> _doc() => {
        'document': {
          'id': 'd1',
          'document_type': 'TAX_INVOICE_RECEIPT',
          'status': status,
          'document_number': numbers == 0 ? null : '$numbers',
          'currency': 'ILS',
          'subtotal_minor': '100000',
          'tax_total_minor': '18000',
          'total_minor': '118000',
          'paid_total_minor': '$paid',
          'balance_minor': '${BigInt.from(118000) - paid}',
        },
        'lines': [],
      };

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
        drafts++;
        status = 'DRAFT';
        draftType = (jsonDecode(r.body) as Map)['documentType'] as String;
        return _json(201, {'id': 'd1', 'status': 'DRAFT'});
      case 'GET /documents':
        final q = r.url.queryParameters;
        return _json(200, {
          'documents': [
            if (status == 'DRAFT' && q['status'] == 'DRAFT' && q['documentType'] == draftType)
              {'id': 'd1', 'documentType': draftType, 'status': 'DRAFT', 'customerId': 'c1', 'totalMinor': '118000'}
          ]
        });
      case 'DELETE /documents/d1':
        if (status != 'DRAFT') return _json(403, {'error': 'DOCUMENT_ACTION_FORBIDDEN'});
        status = 'NONE';
        return _json(200, {'status': 'deleted'});
      case 'PUT /documents/d1':
        if (status != 'DRAFT') return _json(409, {'error': 'DOCUMENT_ALREADY_FINALIZED'});
        return _json(200, {'id': 'd1'});
      case 'GET /sequences':
        return _json(200, {
          'sequences': [
            {'numbering_scope_key': 'default', 'numbering_policy_version': 'v1', 'next_number': '1'}
          ]
        });
      case 'POST /documents/d1/finalize':
        final k = r.headers['Idempotency-Key']!;
        if (approvalPolicy) return _json(409, {'error': 'APPROVAL_REQUIRED'});
        if (status != 'DRAFT') {
          if (finalizeKeys['d1'] == k) {
            return _json(200, {'status': 'FINALIZED', 'documentNumber': '$numbers', 'reused': true});
          }
          return _json(409, {'error': 'DOCUMENT_ALREADY_FINALIZED'});
        }
        finalizeKeys['d1'] = k;
        numbers++;
        status = finalizeOutcome;
        return _json(200, {'status': finalizeOutcome, 'documentNumber': '$numbers', 'reused': false});
      case 'POST /documents/d1/submit':
        status = 'PENDING_APPROVAL';
        return _json(200, {'status': 'PENDING_APPROVAL'});
      case 'POST /documents/d1/artifact':
        if (artifact) return _json(409, {'error': 'ORIGINAL_ARTIFACT_REGENERATION_FORBIDDEN'});
        artifact = true;
        status = 'ARCHIVED';
        return _json(201, {'artifactId': 'a1'});
      case 'POST /payments':
        final k = r.headers['Idempotency-Key']!;
        final id = paymentKeys.putIfAbsent(k, () => 'p${paymentKeys.length + 1}');
        return _json(201, {'paymentId': id, 'reused': paymentKeys.length > 1});
      case 'POST /documents/d1/payments':
        final amount = BigInt.parse((jsonDecode(r.body) as Map)['amountMinor'] as String);
        if (paid + amount > BigInt.from(118000)) return _json(409, {'error': 'PAYMENT_OVERALLOCATED'});
        paid += amount;
        return _json(200, {'allocated': true});
      case 'GET /documents/d1':
        return _json(200, _doc());
    }
    return _json(404, {'error': 'NOT_FOUND'});
  }

  int count(String key) => requests.where((r) => '${r.method} ${r.url.path}' == key).length;
}

PendingIssue newIssue({bool paid = true, bool approval = false}) => PendingIssue(
      businessId: 'b1',
      body: {
        'documentType': 'TAX_INVOICE_RECEIPT',
        'customerId': 'c1',
        'currency': 'ILS',
        'fiscalContext': 'default',
        'lines': [
          {'description': 'x', 'quantityMicros': '1000000', 'unitPriceMinor': '100000', 'taxRateBasisPoints': 1800}
        ],
      },
      form: const {'amountText': '1180'},
      payment: paid ? const PaymentInput(method: 'CASH') : null,
      totalMinor: BigInt.from(118000),
      needsApproval: approval,
    );

void main() {
  final api = ApiClient.instance;
  late FakeServer server;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('issue_api_test');
    AppCache.directoryProvider = () async => tmp;
    server = FakeServer();
    api
      ..clearCredentials()
      ..deviceToken = 'inv_t'
      ..businessId = 'b1'
      ..httpClient = MockClient(server.handle);
  });

  tearDown(() async {
    await AppCache.clearAll();
  });

  test('happy path: draft → finalize (key) → artifact → payment (key) → allocation', () async {
    final stages = <IssueStage>[];
    final r = await runIssue(newIssue(), onStage: stages.add);
    expect(r.outcome, IssueOutcome.issued);
    expect(r.document.balanceMinor, BigInt.zero);
    expect(server.drafts, 1);
    expect(server.count('POST /payments'), 1);
    expect(stages.last, IssueStage.done);
    final finalize = server.requests.firstWhere((q) => q.url.path.endsWith('/finalize'));
    expect(finalize.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(finalize.body), {'scopeKey': 'default'});
    final pay = server.requests.firstWhere((q) => q.url.path == '/payments');
    expect(jsonDecode(pay.body)['amountMinor'], '118000');
    expect(jsonDecode(pay.body)['method'], 'CASH');
    expect(await loadPendingIssue(), isNull, reason: 'cleared when done');
  });

  test('finalize response lost → retry reuses the SAME key; one draft, one number', () async {
    server.loseResponseOnce.add('POST /documents/d1/finalize');
    final p = newIssue();
    await expectLater(runIssue(p), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', true)));
    final saved = (await loadPendingIssue())!;
    expect(saved.draftId, 'd1');
    expect(saved.finalizeKey, isNotNull);

    final r = await runIssue(saved);
    expect(r.outcome, IssueOutcome.issued);
    expect(server.drafts, 1);
    expect(server.numbers, 1);
    final keys = server.requests
        .where((q) => q.url.path.endsWith('/finalize'))
        .map((q) => q.headers['Idempotency-Key'])
        .toSet();
    expect(keys.length, 1);
  });

  test('artifact + allocation responses lost → retry treats 409s as done; paid once', () async {
    server.loseResponseOnce
      ..add('POST /documents/d1/artifact')
      ..add('POST /documents/d1/payments');
    final p = newIssue();
    await expectLater(runIssue(p), throwsA(isA<ApiException>()));
    await expectLater(runIssue((await loadPendingIssue())!), throwsA(isA<ApiException>()));
    final r = await runIssue((await loadPendingIssue())!);
    expect(r.outcome, IssueOutcome.issued);
    expect(server.paid, BigInt.from(118000));
    expect(server.paymentKeys.length, 1, reason: 'same payment idempotency key every time');
    expect(server.drafts, 1);
  });

  test('content changed after a failed finalize → PUT + new finalize key', () async {
    server.loseResponseOnce.add('GET /sequences');
    final p = newIssue();
    await expectLater(runIssue(p), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!;
    expect(saved.editable, isTrue);
    saved.body = {...saved.body, 'customerId': 'c2'};
    await runIssue(saved);
    expect(server.count('PUT /documents/d1'), 1);
    expect(server.drafts, 1);
  });

  test('POST /documents response lost → retry adopts that draft, never a second one', () async {
    server.loseResponseOnce.add('POST /documents');
    await expectLater(runIssue(newIssue()), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!;
    expect(saved.draftId, isNull);
    expect(saved.createAttemptTotal, '118000');
    final r = await runIssue(saved);
    expect(r.outcome, IssueOutcome.issued);
    expect(server.drafts, 1);
    expect(server.count('PUT /documents/d1'), 1, reason: 'current body written onto the adopted draft');
    expect(server.numbers, 1);
  });

  test('type changed after a failure (paid toggled) → draft replaced, not PUT with the old type', () async {
    server.loseResponseOnce.add('GET /sequences');
    final p = newIssue(paid: false)..body = {...newIssue().body, 'documentType': 'TAX_INVOICE'};
    await expectLater(runIssue(p), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!;
    expect(saved.draftType, 'TAX_INVOICE');
    saved
      ..body = {...saved.body, 'documentType': 'TAX_INVOICE_RECEIPT'}
      ..payment = const PaymentInput(method: 'CASH');
    final r = await runIssue(saved);
    expect(r.outcome, IssueOutcome.issued);
    expect(server.count('DELETE /documents/d1'), 1);
    expect(server.count('PUT /documents/d1'), 0);
    expect(server.drafts, 2);
    expect(server.draftType, 'TAX_INVOICE_RECEIPT');
    expect(server.paid, BigInt.from(118000));
  });

  test('type changed but the lost finalize already numbered it → finish as issued, no payment on an unpaid type',
      () async {
    server.loseResponseOnce.add('POST /documents/d1/finalize');
    final p = newIssue(paid: false)..body = {...newIssue().body, 'documentType': 'TAX_INVOICE'};
    await expectLater(runIssue(p), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!
      ..body = {...newIssue().body, 'documentType': 'TAX_INVOICE_RECEIPT'}
      ..payment = const PaymentInput(method: 'CASH');
    final r = await runIssue(saved);
    expect(r.outcome, IssueOutcome.issued);
    expect(server.drafts, 1);
    expect(server.numbers, 1);
    expect(server.count('POST /payments'), 0, reason: 'a TAX_INVOICE gets no receipt payment');
  });

  test('payment response lost → retry sends the SAME paymentDate (part of the idempotency hash)', () async {
    server.loseResponseOnce.add('POST /payments');
    await expectLater(runIssue(newIssue()), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!;
    expect(saved.paymentDate, isNotNull);
    saved.paymentDate = '2026-10-29'; // as if computed before midnight
    await savePendingIssue(saved);
    await runIssue((await loadPendingIssue())!);
    final dates = server.requests
        .where((q) => q.url.path == '/payments')
        .map((q) => (jsonDecode(q.body) as Map)['paymentDate'])
        .toList();
    expect(dates.last, '2026-10-29');
    expect(server.paymentKeys.length, 1);
  });

  test('unpaid: no payment calls', () async {
    final r = await runIssue(newIssue(paid: false));
    expect(r.outcome, IssueOutcome.issued);
    expect(server.count('POST /payments'), 0);
    expect(server.count('POST /documents/d1/payments'), 0);
  });

  test('approval policy: submit instead of finalize', () async {
    final r = await runIssue(newIssue(approval: true));
    expect(r.outcome, IssueOutcome.submittedForApproval);
    expect(server.count('POST /documents/d1/finalize'), 0);
    expect(server.count('POST /documents/d1/submit'), 1);
    expect(await loadPendingIssue(), isNull);
  });

  test('server says APPROVAL_REQUIRED on finalize → submitted', () async {
    server.approvalPolicy = true;
    final r = await runIssue(newIssue());
    expect(r.outcome, IssueOutcome.submittedForApproval);
    expect(server.count('POST /documents/d1/submit'), 1);
  });

  test('WAITING_FOR_ALLOCATION stops before artifact/payment; resumes after', () async {
    server.finalizeOutcome = 'WAITING_FOR_ALLOCATION';
    final r = await runIssue(newIssue());
    expect(r.outcome, IssueOutcome.waitingForAllocation);
    expect(server.count('POST /documents/d1/artifact'), 0);
    expect((await loadPendingIssue())!.stage, IssueStage.waitingAllocation);

    server.status = 'FINALIZED'; // the authority answered
    final done = await resumeAfterAllocation('d1');
    expect(done!.outcome, IssueOutcome.issued);
    expect(server.paid, BigInt.from(118000));
    expect(server.count('POST /documents/d1/finalize'), 1, reason: 'never finalized twice');
  });

  test('discard deletes only an unnumbered draft', () async {
    server.loseResponseOnce.add('GET /sequences');
    await expectLater(runIssue(newIssue()), throwsA(isA<ApiException>()));
    final saved = (await loadPendingIssue())!;
    await discardPendingIssue(saved);
    expect(server.count('DELETE /documents/d1'), 1);
    expect(await loadPendingIssue(), isNull);
  });

  test('PaymentInput CHECK body carries bank/branch/account + reference', () {
    const pay = PaymentInput(
        method: 'CHECK', bankNumber: '12', branchNumber: '345', accountNumber: '678901', checkNumber: '1001');
    expect(pay.requestBody(BigInt.from(500), '2026-10-30'), {
      'method': 'CHECK',
      'amountMinor': '500',
      'currency': 'ILS',
      'paymentDate': '2026-10-30',
      'bankNumber': '12',
      'branchNumber': '345',
      'accountNumber': '678901',
      'reference': '1001',
    });
    expect(const PaymentInput(method: 'CASH').requestBody(BigInt.one, '2026-10-30').containsKey('reference'),
        isFalse);
  });
}
