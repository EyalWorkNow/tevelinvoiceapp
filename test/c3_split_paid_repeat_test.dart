// C3 (QA 2026-11-16, personas 02 + 04): split payment in the Composer, quote
// → 320 "שילם עכשיו", and "כמו בפעם הקודמת". Unit level: the state rules,
// the issue sequence against a fake server, and the repeat template.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/issue_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/compose/compose_repeat.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/screens/compose/compose_submit.dart'
    show quoteTargetType;
import 'package:invoice/state/cache.dart';
import 'package:invoice/util/composer_config.dart';

ComposeState paid({
  String amount = '1180',
  DocKind kind = DocKind.taxInvoiceReceipt,
}) =>
    ComposeState(kind: kind, businessType: 'OSEK_MURSHE', vatBasisPoints: 1800)
      ..customer = const Customer(id: 'c1', name: 'קבלן')
      ..description = 'עבודת חשמל'
      ..amountText = amount;

/// A server with C3 (finalize records a split when asked) or without it.
class SplitServer {
  SplitServer({this.recordsWithFinalize = true});

  final bool recordsWithFinalize;
  final List<http.Request> requests = [];
  final Map<String, Map<String, dynamic>> pending = {}; // key → body
  int payments = 0;

  http.Response _json(int code, Object body) => http.Response(
    jsonEncode(body),
    code,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final body = r.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(r.body) as Map<String, dynamic>;
    switch ('${r.method} ${r.url.path}') {
      case 'POST /documents':
        return _json(201, {'id': 'd1', 'status': 'DRAFT'});
      case 'GET /sequences':
        return _json(200, {
          'sequences': [
            {'numbering_scope_key': 'default'},
          ],
        });
      case 'POST /documents/d1/allocation/evaluate':
        return _json(200, {'state': 'NOT_REQUIRED'});
      case 'POST /documents/d1/finalize':
        final record =
            recordsWithFinalize && body['recordPendingPayments'] == true;
        if (record) {
          final list = body['pendingPayments'] as List;
          for (var i = 0; i < list.length; i++) {
            pending.putIfAbsent(
              '${r.headers['Idempotency-Key']}:pending:$i',
              () => Map<String, dynamic>.from(list[i] as Map),
            );
          }
        }
        return _json(200, {
          'status': 'FINALIZED',
          'documentNumber': '7',
          if (record) 'paymentRecorded': true,
        });
      case 'POST /documents/d1/pending-payments':
        pending.putIfAbsent(r.headers['Idempotency-Key']!, () => body);
        return _json(201, {
          'pendingPayment': {'id': 'pp', 'status': 'RECORDED'},
          'reused': false,
        });
      case 'POST /documents/d1/artifact' || 'POST /documents/r1/artifact':
        return _json(201, {'signing': 'NOT_APPLICABLE'});
      case 'POST /payments':
        payments++;
        return _json(201, {'paymentId': 'p-${r.headers['Idempotency-Key']}'});
      case 'POST /receipts':
        return _json(201, {
          'receiptDocumentId': 'r1',
          'outcome': {'status': 'FINALIZED', 'documentNumber': '9'},
        });
      case 'GET /documents/d1' || 'GET /documents/r1':
        return _json(200, {
          'document': {
            'id': r.url.pathSegments.last,
            'document_type': 'TAX_INVOICE_RECEIPT',
            'status': 'ARCHIVED',
            'currency': 'ILS',
            'total_minor': '118000',
            'paid_total_minor': '118000',
            'balance_minor': '0',
          },
          'lines': [],
        });
    }
    return _json(404, {'error': 'NOT_FOUND'});
  }

  List<http.Request> calls(String key) => [
    for (final r in requests)
      if ('${r.method} ${r.url.path}' == key) r,
  ];
}

PendingIssue issueOf(ComposeState s) => PendingIssue(
  businessId: 'b1',
  body: s.config.receiptOnly
      ? {'documentType': s.config.serverType, 'customerId': 'c1'}
      : s.requestBody(),
  form: s.toJson(),
  payment: s.payment,
  splitPayments: s.splitPayments,
  totalMinor: s.totalMinor,
  needsApproval: false,
  receiptOnly: s.config.receiptOnly,
);

void main() {
  group('split validation (ComposeState)', () {
    test('one method stays the default; split is opt-in', () {
      final s = paid();
      expect(s.split, isFalse);
      expect(s.ready, isTrue);
      expect(s.payment!.method, 'CASH');
      expect(s.splitPayments, isEmpty);
    });

    test('"פיצול תשלום" → line 1 = the whole total; + adds the rest', () {
      final s = paid()..method = 'BANK_TRANSFER';
      s.startSplit();
      expect(s.splits.single.method, 'BANK_TRANSFER');
      expect(s.splits.single.amountMinor, BigInt.from(118000));
      expect(s.ready, isFalse, reason: 'a split has at least two lines');
      s.splits.first.amountText = '600';
      expect(s.splitRemainingMinor, BigInt.from(58000));
      s.addSplitLine();
      expect(s.splits.last.amountMinor, BigInt.from(58000));
      expect(s.splitRemainingMinor, BigInt.zero);
      expect(s.ready, isTrue);
      expect(s.payment, isNull, reason: 'the split replaces the one method');
      expect(s.splitPayments.map((p) => p.amountMinor), [
        BigInt.from(60000),
        BigInt.from(58000),
      ]);
    });

    test('the issue is blocked until the lines add up to the total', () {
      final s = paid()..startSplit();
      s.splits.first.amountText = '500';
      s.addSplitLine();
      s.splits.last.amountText = '600'; // 1100 of 1180
      expect(s.splitRemainingMinor, BigInt.from(8000));
      expect(s.ready, isFalse);
      s.splits.last.amountText = '700'; // 1200 of 1180
      expect(s.splitRemainingMinor, BigInt.from(-2000));
      expect(s.ready, isFalse);
      s.splits.last.amountText = '680';
      expect(s.ready, isTrue);
    });

    test('a cheque line needs its four details (digits); "+ צ\'ק נוסף"', () {
      final s = paid(amount: '3000')..startSplit();
      s.splits.first
        ..method = 'CHECK'
        ..amountText = '1000'
        ..bankNumber = '12'
        ..branchNumber = '600'
        ..accountNumber = '123456'
        ..checkNumber = '0041'
        ..date = '2026-11-16';
      s.addSplitLine();
      final next = s.splits.last;
      expect(next.method, 'CHECK');
      expect(next.checkNumber, '0042');
      expect(next.date, '2026-12-16');
      expect(next.bankNumber, '12');
      expect(next.amountText, '1000', reason: 'same amount while it fits');
      s.addSplitLine();
      expect(s.splitRemainingMinor, BigInt.zero);
      expect(s.ready, isTrue);
      s.splits.last.checkNumber = '';
      expect(s.ready, isFalse);
      s.splits.last.checkNumber = '00a3';
      expect(s.ready, isFalse);
    });

    test('removing down to one line goes back to one method', () {
      final s = paid()..startSplit();
      s.splits.first.method = 'CREDIT_CARD';
      s.addSplitLine();
      s.removeSplitLine(1);
      expect(s.split, isFalse);
      expect(s.method, 'CREDIT_CARD');
      expect(s.payment, isNotNull);
    });

    test('the split survives the local draft (toJson / restore)', () {
      final s = paid()..startSplit();
      s.splits.first.amountText = '180';
      s.addSplitLine();
      final back = paid()..restore(s.toJson());
      expect(back.split, isTrue);
      expect(back.splits.map((l) => l.amountText), ['180', '1000']);
    });
  });

  group('issue sequence', () {
    final api = ApiClient.instance;
    late Directory tmp;

    setUp(() {
      resetScopeKeyCache();
      tmp = Directory.systemTemp.createTempSync('c3_split_test');
      AppCache.directoryProvider = () async => tmp;
      api
        ..clearCredentials()
        ..deviceToken = 'inv_t'
        ..businessId = 'b1';
    });

    tearDown(() async => AppCache.clearAll());

    ComposeState split320() {
      final s = paid()..startSplit();
      s.splits.first
        ..method = 'BANK_TRANSFER'
        ..amountText = '590';
      s.addSplitLine();
      s.splits.last
        ..method = 'CHECK'
        ..bankNumber = '12'
        ..branchNumber = '600'
        ..accountNumber = '123456'
        ..checkNumber = '1001'
        ..date = '2026-12-16';
      expect(s.ready, isTrue);
      return s;
    }

    test(
      '320: finalize carries every line and records them atomically',
      () async {
        final server = SplitServer();
        api.httpClient = MockClient(server.handle);
        final r = await runIssue(issueOf(split320()));
        expect(r.outcome, IssueOutcome.issued);
        final body =
            jsonDecode(server.calls('POST /documents/d1/finalize').single.body)
                as Map<String, dynamic>;
        expect(body['recordPendingPayments'], isTrue);
        final list = body['pendingPayments'] as List;
        expect(list, hasLength(2));
        expect(list[0]['method'], 'BANK_TRANSFER');
        expect(list[0]['amountMinor'], '59000');
        expect(list[1]['method'], 'CHECK');
        expect(
          (list[1] as Map).containsKey('amountMinor'),
          isFalse,
          reason: 'the last line takes what the server still has open',
        );
        expect(list[1]['paymentDate'], '2026-12-16');
        expect(list[1]['reference'], '1001');
        expect(server.pending, hasLength(2));
        expect(server.calls('POST /payments'), isEmpty);
        expect(server.calls('POST /documents/d1/pending-payments'), isEmpty);
        expect(await loadPendingIssue(), isNull);
      },
    );

    test(
      '320 on a server before C3: each line after the issue, same keys',
      () async {
        final server = SplitServer(recordsWithFinalize: false);
        api.httpClient = MockClient(server.handle);
        await runIssue(issueOf(split320()));
        final fin = server.calls('POST /documents/d1/finalize').single;
        final uploads = server.calls('POST /documents/d1/pending-payments');
        expect(uploads.map((u) => u.headers['Idempotency-Key']), [
          pendingPaymentKey(fin.headers['Idempotency-Key']!),
          pendingPaymentKey(fin.headers['Idempotency-Key']!, 1),
        ]);
        expect(server.calls('POST /payments'), isEmpty);
      },
    );

    test(
      'receipt (400): one POST /payments per line, one receipt for all',
      () async {
        final server = SplitServer();
        api.httpClient = MockClient(server.handle);
        final s =
            ComposeState(
                kind: DocKind.receipt,
                businessType: 'OSEK_PATUR',
                vatBasisPoints: 1800,
              )
              ..customer = const Customer(id: 'c1', name: 'סיגל')
              ..description = 'שירותים'
              ..amountText = '440'
              ..startSplit();
        s.splits.first
          ..method = 'CASH'
          ..amountText = '350';
        s.addSplitLine();
        s.splits.last.method = 'BANK_TRANSFER';
        expect(s.ready, isTrue);
        await runIssue(issueOf(s));
        final pays = server.calls('POST /payments');
        expect(pays.map((p) => jsonDecode(p.body)['amountMinor']), [
          '35000',
          '9000',
        ]);
        final keys = [for (final p in pays) p.headers['Idempotency-Key']!];
        expect(keys[0].endsWith(':0') && keys[1].endsWith(':1'), isTrue);
        final receipt =
            jsonDecode(server.calls('POST /receipts').single.body) as Map;
        expect(receipt['paymentIds'], [
          {'id': 'p-${keys[0]}'},
          {'id': 'p-${keys[1]}'},
        ]);
      },
    );
  });

  group('quote → "שילם עכשיו"', () {
    test('the convert type follows the kind (פטור: 300)', () {
      expect(
        quoteTargetType(DocKind.taxInvoiceReceipt, exempt: false),
        'TAX_INVOICE_RECEIPT',
      );
      expect(quoteTargetType(DocKind.taxInvoice, exempt: false), 'TAX_INVOICE');
      expect(
        quoteTargetType(DocKind.taxInvoiceReceipt, exempt: true),
        'TRANSACTION_INVOICE',
      );
    });
  });

  group('"כמו בפעם הקודמת"', () {
    late Directory tmp;
    final api = ApiClient.instance;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('c3_repeat_test');
      AppCache.directoryProvider = () async => tmp;
      api
        ..clearCredentials()
        ..deviceToken = 'inv_t'
        ..businessId = 'b1';
    });

    tearDown(() async => AppCache.clearAll());

    test(
      'device memory: lines, amount and method; never the cheque number',
      () async {
        api.httpClient = MockClient((_) async => throw StateError('no server'));
        final last = paid(kind: DocKind.receipt, amount: '350')
          ..method = 'CHECK'
          ..bankNumber = '12'
          ..branchNumber = '600'
          ..accountNumber = '1'
          ..checkNumber = '77';
        await rememberRepeat(last);
        final t = await findRepeat(
          'c1',
          businessType: 'OSEK_MURSHE',
          vatBasisPoints: 1800,
        );
        expect(t!.kind, DocKind.receipt);
        expect(t.totalMinor, BigInt.from(35000));
        final next = paid(kind: DocKind.receipt, amount: '');
        applyRepeat(next, t);
        expect(next.amountText, '350');
        expect(next.method, 'CHECK');
        expect(next.bankNumber, '12');
        expect(next.checkNumber, isEmpty);
        expect(next.ready, isFalse, reason: 'the new cheque number is typed');
        next.checkNumber = '78';
        expect(next.ready, isTrue);
      },
    );

    test(
      'server fallback: the newest issued document, its lines and method',
      () async {
        api.httpClient = MockClient((r) async {
          final path = r.url.path;
          Map<String, dynamic> body;
          if (path == '/documents') {
            expect(r.url.queryParameters['customerId'], 'c9');
            body = {
              'documents': [
                {
                  'id': 'old',
                  'document_type': 'TAX_INVOICE_RECEIPT',
                  'status': 'ARCHIVED',
                  'document_number': '3',
                  'issue_date': '2026-10-01',
                  'total_minor': '11800',
                  'currency': 'ILS',
                },
                {
                  'id': 'new',
                  'document_type': 'TAX_INVOICE_RECEIPT',
                  'status': 'ARCHIVED',
                  'document_number': '8',
                  'issue_date': '2026-11-10',
                  'total_minor': '51920',
                  'currency': 'ILS',
                },
                {
                  'id': 'draft',
                  'document_type': 'TAX_INVOICE_RECEIPT',
                  'status': 'DRAFT',
                  'issue_date': '2026-11-15',
                  'total_minor': '100',
                  'currency': 'ILS',
                },
              ],
            };
          } else {
            expect(path, '/documents/new');
            body = {
              'document': {
                'id': 'new',
                'document_type': 'TAX_INVOICE_RECEIPT',
                'status': 'ARCHIVED',
                'document_number': '8',
                'currency': 'ILS',
                'total_minor': '51920',
                'payments': [
                  {'id': 'p', 'method': 'CREDIT_CARD', 'amountMinor': '51920'},
                ],
              },
              'lines': [
                {
                  'position': 1,
                  'description': 'תספורת + צבע',
                  'quantity_micros': '1000000',
                  'unit_price_minor': '35000',
                  'discount_minor': '0',
                  'subtotal_minor': '35000',
                  'tax_rate_basis_points': 1800,
                  'tax_amount_minor': '6300',
                  'total_minor': '41300',
                },
                {
                  'position': 2,
                  'description': 'קרם',
                  'quantity_micros': '1000000',
                  'unit_price_minor': '9000',
                  'discount_minor': '0',
                  'subtotal_minor': '9000',
                  'tax_rate_basis_points': 1800,
                  'tax_amount_minor': '1620',
                  'total_minor': '10620',
                },
              ],
            };
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final t = await findRepeat(
          'c9',
          businessType: 'OSEK_MURSHE',
          vatBasisPoints: 1800,
        );
        expect(t!.kind, DocKind.taxInvoiceReceipt);
        expect(t.totalMinor, BigInt.from(51920));
        final s = paid(amount: '')..method = 'CASH';
        applyRepeat(s, t);
        expect(s.description, 'תספורת + צבע');
        expect(s.extraLines.single.description, 'קרם');
        expect(s.method, 'CREDIT_CARD');
        expect(s.totalMinor, BigInt.from(51920));
        expect(s.ready, isTrue);
      },
    );

    test('nothing issued for the customer → no template', () async {
      api.httpClient = MockClient(
        (_) async => http.Response(
          jsonEncode({'documents': []}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(
        await findRepeat(
          'c1',
          businessType: 'OSEK_MURSHE',
          vatBasisPoints: 1800,
        ),
        isNull,
      );
    });
  });
}
