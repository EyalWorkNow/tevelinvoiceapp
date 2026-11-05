// Squad C API layer against the fakes: payments_api (S5, multiple payments,
// resume), actions_api (approve/reject, credit/void, allocation, quotes,
// duplicate, share/copy PDF, §13.5 text), signing_api (release in the flow).

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/actions_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/payments_api.dart';
import 'package:invoice/api/signing_api.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/fake_api.dart';

DocumentDetail detail(Map<String, dynamic> json) => DocumentDetail.fromJson(json);

void main() {
  late FakeBackend backend;
  late Directory tmp;
  var prompts = 0;
  var biometrics = 0;

  Future<PassphraseAnswer?> answer() async {
    prompts++;
    return (passphrase: 'secret-pass', remember: true);
  }

  Future<PassphraseAnswer?> cancel() async {
    prompts++;
    return null;
  }

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('money_api_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    installActionsFakes(backend);
    await signInAs(backend, Preset.owner);
    await AppCache.clearAll();
    prompts = 0;
    biometrics = 0;
    signingBiometric = (_) async {
      biometrics++;
      return true;
    };
  });

  group('S5 payments', () {
    final cash = PaymentEntry(method: 'CASH', amountMinor: BigInt.from(18000), paymentDate: '2026-10-30');
    final check = PaymentEntry(
      method: 'CHECK',
      amountMinor: BigInt.from(100000),
      paymentDate: '2026-11-30',
      reference: '0042',
      bankNumber: '12',
      branchNumber: '600',
      accountNumber: '123456',
    );

    test('305: two payments → two allocations → ONE receipt for both → receipt artifact', () async {
      final out = await recordPayments(detail(docDetailJson()), [cash, check], askPassphrase: answer);
      final pays = backend.calls('POST', '/payments');
      expect(pays, hasLength(2));
      expect(pays[0].idempotencyKey, isNot(pays[1].idempotencyKey));
      expect(pays[0].body, {'method': 'CASH', 'amountMinor': '18000', 'currency': 'ILS', 'paymentDate': '2026-10-30'});
      expect(pays[1].body['reference'], '0042');
      expect(pays[1].body['bankNumber'], '12');
      final allocs = backend.calls('POST', '/documents/:id/payments');
      expect([for (final a in allocs) a.body['amountMinor']], ['18000', '100000']);
      final receipt = backend.last('POST', '/receipts')!;
      expect(receipt.body['paymentIds'], hasLength(2));
      expect(receipt.body['forDocumentId'], 'doc-1');
      expect(receipt.body['customerId'], 'cus-1');
      expect(receipt.body['scopeKey'], 'default');
      expect(receipt.idempotencyKey, isNotNull);
      expect(backend.last('POST', '/documents/:id/artifact')!.params['id'], 'rcp-1');
      expect(out.receiptId, 'rcp-1');
      expect(out.receiptNumber, '77');
      expect(out.signingPending, isFalse);
      expect(await hasPendingPayments('doc-1'), isFalse);
    });

    test('"העברה / ביט" writes no reference (§9.1)', () async {
      final bit = PaymentEntry(
          method: 'BANK_TRANSFER', amountMinor: BigInt.from(118000), paymentDate: '2026-10-30', reference: 'x');
      expect(bit.toJson().containsKey('reference'), isFalse);
    });

    test('320: payments are only allocated, no receipt', () async {
      await recordPayments(detail(docDetailJson(type: 'TAX_INVOICE_RECEIPT')), [cash]);
      expect(backend.calls('POST', '/receipts'), isEmpty);
      expect(backend.calls('POST', '/documents/:id/payments'), hasLength(1));
    });

    test('a failure at the receipt → retry re-sends the SAME keys and skips done steps', () async {
      backend.error('POST', '/receipts', 503, 'SERVICE_UNAVAILABLE');
      final doc = detail(docDetailJson());
      await expectLater(recordPayments(doc, [cash, check]), throwsA(isA<ApiException>()));
      expect(await hasPendingPayments('doc-1'), isTrue);
      final firstKey = backend.last('POST', '/receipts')!.idempotencyKey;
      installActionsFakes(backend);
      // the user even changed the amount: the recorded payments win
      await recordPayments(doc, [cash.copyWith(amountMinor: BigInt.from(1)), check]);
      expect(backend.calls('POST', '/payments'), hasLength(2));
      expect(backend.calls('POST', '/documents/:id/payments'), hasLength(2));
      expect(backend.last('POST', '/receipts')!.idempotencyKey, firstKey);
    });

    test('lost allocation response: PAYMENT_OVERALLOCATED + paid went up → continue', () async {
      backend
        ..error('POST', '/documents/:id/payments', 409, 'PAYMENT_OVERALLOCATED')
        ..json('GET', '/documents/:id', docDetailJson(paid: 18000));
      final out = await recordPayments(detail(docDetailJson()), [cash]);
      expect(out.receiptId, 'rcp-1');
    });

    test('PAYMENT_OVERALLOCATED without the paid total going up is an error', () async {
      backend.error('POST', '/documents/:id/payments', 409, 'PAYMENT_OVERALLOCATED');
      await expectLater(recordPayments(detail(docDetailJson()), [cash]),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', 'PAYMENT_OVERALLOCATED')));
    });

    test('receipt signing LOCKED → passphrase dialog → unlock → /sign; cancelled → signingPending', () async {
      backend.json('POST', '/documents/:id/artifact', {'signing': 'LOCKED'}, status: 201);
      backend.error('POST', '/documents/:id/sign', 409, 'SIGNING_LOCKED');
      var signCalls = 0;
      backend.on('POST', '/settings/signing/unlock', (r) {
        backend.on('POST', '/documents/:id/sign', (_) {
          signCalls++;
          return const FakeResponse(200, {'signing': 'SIGNED'});
        });
        return const FakeResponse(200, {'session': {'unlocked': true}});
      });
      final out = await recordPayments(detail(docDetailJson()), [cash], askPassphrase: answer);
      expect(prompts, 1);
      expect(backend.last('POST', '/settings/signing/unlock')!.body, {'passphrase': 'secret-pass'});
      expect(signCalls, 1);
      expect(out.signingPending, isFalse);
      expect(biometrics, 1, reason: '"שמור עם Face ID" confirms before saving');
      expect(await hasSavedSigningPassphrase(), isTrue);

      installActionsFakes(backend);
      backend
        ..json('POST', '/documents/:id/artifact', {'signing': 'LOCKED'}, status: 201)
        ..error('POST', '/documents/:id/sign', 409, 'SIGNING_LOCKED');
      await forgetSigningPassphrase();
      final out2 = await recordPayments(detail(docDetailJson(id: 'doc-2')), [cash], askPassphrase: cancel);
      expect(out2.signingPending, isTrue);
    });

    test('"+ צ\'ק נוסף": number + 1, a month later (31 Jan → 28 Feb), same bank', () {
      final c = check.copyWith(paymentDate: '2027-01-31', reference: '0099');
      final n = c.nextCheck();
      expect(n.reference, '0100');
      expect(n.paymentDate, '2027-02-28');
      expect((n.bankNumber, n.branchNumber, n.accountNumber), ('12', '600', '123456'));
    });
  });

  group('approvals', () {
    test('approve: Idempotency-Key + scopeKey → original; saved passphrase → no dialog', () async {
      FlutterSecureStorage.setMockInitialValues({'signing_passphrase_b1': 'saved-pass'});
      backend
        ..json('POST', '/documents/:id/artifact', {'signing': 'LOCKED'}, status: 201)
        ..error('POST', '/documents/:id/sign', 409, 'SIGNING_LOCKED')
        ..on('POST', '/settings/signing/unlock', (_) {
          backend.json('POST', '/documents/:id/sign', {'signing': 'SIGNED'});
          return const FakeResponse(200, {});
        });
      final out = await approveDocument(detail(docDetailJson(status: 'PENDING_APPROVAL')), askPassphrase: answer);
      final req = backend.last('POST', '/documents/:id/approve')!;
      expect(req.idempotencyKey, isNotNull);
      expect(req.body['scopeKey'], 'default');
      expect(out.status, 'FINALIZED');
      expect(prompts, 0);
      expect(backend.last('POST', '/settings/signing/unlock')!.body['passphrase'], 'saved-pass');
    });

    test('a wrong saved passphrase is forgotten and asked again', () async {
      FlutterSecureStorage.setMockInitialValues({'signing_passphrase_b1': 'old'});
      backend.on('POST', '/settings/signing/unlock', (r) => r.body['passphrase'] == 'old'
          ? FakeResponse.error(422, 'SIGNING_ACTIVATION_INVALID')
          : const FakeResponse(200, {}));
      expect(await unlockSigning(askPassphrase: answer), isTrue);
      expect(prompts, 1);
    });

    test('approve → WAITING_FOR_ALLOCATION: no artifact yet', () async {
      backend.json('POST', '/documents/:id/approve', {'status': 'WAITING_FOR_ALLOCATION'});
      final out = await approveDocument(detail(docDetailJson(status: 'PENDING_APPROVAL')), askPassphrase: answer);
      expect(out.status, 'WAITING_FOR_ALLOCATION');
      expect(backend.calls('POST', '/documents/:id/artifact'), isEmpty);
    });

    test('reject sends the reason; an empty reason never reaches the server', () async {
      await rejectDocument('doc-1', '  חסר פירוט ');
      expect(backend.last('POST', '/documents/:id/reject')!.body, {'reason': 'חסר פירוט'});
      expect(() => rejectDocument('doc-1', ' '), throwsArgumentError);
    });
  });

  group('credit / void', () {
    test('AT-21 partial ₪200: one 18% line of 169.49, Idempotency-Key, then the credit\'s original', () async {
      final out = await creditDocument(detail(docDetailJson()), amountMinor: BigInt.from(20000), askPassphrase: answer);
      final req = backend.last('POST', '/documents/:id/credit')!;
      expect(req.idempotencyKey, isNotNull);
      expect(req.body['scopeKey'], 'default');
      final lines = req.body['lines'] as List;
      expect(lines.single['unitPriceMinor'], '16949');
      expect(lines.single['description'], 'זיכוי חלקי לחשבונית 1042');
      expect(backend.last('POST', '/documents/:id/artifact')!.params['id'], 'cr-1');
      expect(out.creditId, 'cr-1');
    });

    test('CREDIT_LIMIT_EXCEEDED → the maximum re-read from the server (₪980)', () async {
      backend
        ..error('POST', '/documents/:id/credit', 409, 'CREDIT_LIMIT_EXCEEDED')
        ..json('GET', '/documents/:id', docDetailJson(credited: 20000));
      await expectLater(
          creditDocument(detail(docDetailJson()), amountMinor: BigInt.from(100000), askPassphrase: answer),
          throwsA(isA<CreditLimitExceeded>().having((e) => e.maxMinor, 'max', BigInt.from(98000))));
    });

    test('a network failure keeps the key for the retry with the same amount', () async {
      backend.error('POST', '/documents/:id/credit', 503, 'SERVICE_UNAVAILABLE');
      final doc = detail(docDetailJson());
      await expectLater(creditDocument(doc, amountMinor: BigInt.from(118000), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      final key = backend.last('POST', '/documents/:id/credit')!.idempotencyKey;
      await expectLater(creditDocument(doc, amountMinor: BigInt.from(118000), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      expect(backend.last('POST', '/documents/:id/credit')!.idempotencyKey, key);
    });

    test('lost response, then ANOTHER amount → the SAME key (never a second credit)', () async {
      backend.error('POST', '/documents/:id/credit', 503, 'SERVICE_UNAVAILABLE');
      final doc = detail(docDetailJson());
      await expectLater(creditDocument(doc, amountMinor: BigInt.from(50000), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      final key = backend.last('POST', '/documents/:id/credit')!.idempotencyKey;
      // The first one had landed: the server refuses the reused key.
      backend.error('POST', '/documents/:id/credit', 409, 'IDEMPOTENCY_CONFLICT');
      final out = await creditDocument(doc, amountMinor: BigInt.from(40000), askPassphrase: answer);
      expect(backend.last('POST', '/documents/:id/credit')!.idempotencyKey, key);
      expect(out.creditId, isNull); // landed earlier; D reloads and lists it
      expect(await AppCache.hasPending(), isFalse);
    });

    test('a permanent refusal drops the pending credit / approve key', () async {
      backend.error('POST', '/documents/:id/credit', 403, 'DOCUMENT_ACTION_FORBIDDEN');
      await expectLater(creditDocument(detail(docDetailJson()), amountMinor: BigInt.from(10000), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      expect(await AppCache.hasPending(), isFalse);
      backend.error('POST', '/documents/:id/approve', 409, 'DOCUMENT_INVALID_TRANSITION');
      await expectLater(approveDocument(detail(docDetailJson(status: 'PENDING_APPROVAL')), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      expect(await AppCache.hasPending(), isFalse);
      // offline keeps it
      backend.error('POST', '/documents/:id/approve', 503, 'SERVICE_UNAVAILABLE');
      await expectLater(approveDocument(detail(docDetailJson(status: 'PENDING_APPROVAL')), askPassphrase: answer),
          throwsA(isA<ApiException>()));
      expect(await AppCache.hasPending(), isTrue);
    });

    test('void (BE-36) sends the reason', () async {
      await voidDocument('doc-1', ' לא רלוונטי ');
      expect(backend.last('POST', '/documents/:id/void')!.body, {'reason': 'לא רלוונטי'});
    });
  });

  group('allocation (row 4)', () {
    test('"נסה שוב": request when failed, reconcile when in flight', () async {
      await retryAllocation('doc-1');
      expect(backend.calls('POST', '/documents/:id/allocation/request'), hasLength(1));
      backend.json('GET', '/documents/:id/allocation', {'state': 'OUTCOME_UNKNOWN'});
      await retryAllocation('doc-1');
      expect(backend.calls('POST', '/documents/:id/allocation/reconcile'), hasLength(1));
    });

    test('manual / continue / cancel bodies', () async {
      await attachManualAllocation('doc-1', ' 123456789 ');
      expect(backend.last('POST', '/documents/:id/allocation/manual')!.body, {'allocationNumber': '123456789'});
      await continueWithoutAllocation('doc-1');
      expect(backend.last('POST', '/documents/:id/allocation/decision')!.body, {'decision': 'CONTINUE'});
      await cancelAllocationRequest('doc-1');
      expect(backend.calls('POST', '/documents/:id/allocation/cancel'), hasLength(1));
    });

    test('decisionAllowed only for USER_ACTION_REQUIRED / HEARING_PENDING (AT-62)', () {
      expect(AllocationState.fromJson({'state': 'USER_ACTION_REQUIRED'}).decisionAllowed, isTrue);
      expect(AllocationState.fromJson({'state': 'RETRYABLE_FAILURE'}).decisionAllowed, isFalse);
    });
  });

  group('quotes on D', () {
    test('AT-20: SENT → status ACCEPTED (`to`) → convert {TAX_INVOICE, 1800}', () async {
      final q = (await fetchQuote('q-1'))!;
      final id = await quoteToInvoice(q, vatExempt: false, vatRateBasisPoints: 1800);
      expect(id, 'doc-new');
      expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'ACCEPTED'});
      expect(backend.last('POST', '/quotes/:id/convert')!.body,
          {'documentType': 'TAX_INVOICE', 'taxRateBasisPoints': 1800});
      final order = [for (final r in backend.requests) if (r.method == 'POST') r.pattern];
      expect(order.indexOf('/quotes/:id/status'), lessThan(order.indexOf('/quotes/:id/convert')));
    });

    test('AT-20b: DRAFT → convert directly; exempt → TRANSACTION_INVOICE at 0', () async {
      backend.json('GET', '/quotes', {'quotes': [quoteRowJson(status: 'DRAFT')]});
      final q = (await fetchQuote('q-1'))!;
      await quoteToInvoice(q, vatExempt: true, vatRateBasisPoints: 1800);
      expect(backend.calls('POST', '/quotes/:id/status'), isEmpty);
      expect(backend.last('POST', '/quotes/:id/convert')!.body,
          {'documentType': 'TRANSACTION_INVOICE', 'taxRateBasisPoints': 0});
    });
  });

  group('duplicate, share, text', () {
    test('BE-08 clone when present; before BE-08 a new draft with the same lines and no date', () async {
      expect(await duplicateDocument(detail(docDetailJson())), 'doc-dup');
      backend
        ..off('POST', '/documents/:id/clone')
        ..json('POST', '/documents', {'id': 'doc-p0', 'status': 'DRAFT'}, status: 201);
      expect(await duplicateDocument(detail(docDetailJson())), 'doc-p0');
      final body = backend.last('POST', '/documents')!.body;
      expect(body['documentType'], 'TAX_INVOICE');
      expect(body['customerId'], 'cus-1');
      expect(body.containsKey('issueDate'), isFalse); // today (no BACKDATING_OWNER_ONLY)
      expect((body['lines'] as List).single['description'], 'תיקון דוד');
    });

    test('PDF copy: 404 → POST /artifact?type=COPY → read again', () async {
      var reads = 0;
      backend.on('GET', '/documents/:id/pdf', (r) {
        reads++;
        return r.query['type'] == 'COPY' && reads == 1
            ? FakeResponse.error(404, 'ARTIFACT_NOT_FOUND')
            : const FakeResponse(200, samplePdfBytes);
      });
      final bytes = await fetchCopyPdf('doc-1');
      expect(bytes, samplePdfBytes);
      expect(backend.last('POST', '/documents/:id/artifact')!.query['type'], 'COPY');
    });

    test('share link on a FINALIZED document creates the original first', () async {
      final url = await createShareLink(detail(docDetailJson(status: 'FINALIZED')));
      expect(url, 'https://invoice.test/d/tok123');
      final order = [for (final r in backend.requests) if (r.method == 'POST') r.pattern];
      expect(order, ['/documents/:id/artifact', '/documents/:id/share-link']);
    });

    test('§13.5 fixed WhatsApp text', () {
      expect(
        whatsAppMessage(
            customerName: 'דנה',
            documentType: 'TAX_INVOICE',
            documentNumber: '1042',
            totalMinor: BigInt.from(118000),
            businessName: 'סטודיו תבל',
            link: 'https://invoice.test/d/t'),
        "שלום דנה, מצורפת חשבונית מס מס' 1042 על סך ₪1,180. לצפייה ולתשלום: https://invoice.test/d/t. תודה, סטודיו תבל",
      );
    });

    test('BE-11: void payment + list', () async {
      backend
        ..json('POST', '/payments/:id/void', {'voided': true})
        ..json('GET', '/payments', {
          'total': 1,
          'payments': [
            {'id': 'p1', 'method': 'CASH', 'amountMinor': '500', 'paymentDate': '2026-10-30'}
          ]
        });
      await voidPayment('p1', 'טעות');
      expect(backend.last('POST', '/payments/:id/void')!.body, {'reason': 'טעות'});
      final rows = await fetchPayments();
      expect(rows.single.amountMinor, BigInt.from(500));
    });
  });

  group('P1 (SRV-2): quotes BE-06, clone BE-08, void BE-36, allocation BE-26, BE-11, BE-12', () {
    test('BE-06: GET /quotes/:id with lines; PDF, share link and clone', () async {
      installQuoteDetail(backend);
      final q = (await fetchQuote('q-1'))!;
      expect(quoteHasLines(q), isTrue);
      expect(q.totalMinor, BigInt.from(118000));
      expect(backend.calls('GET', '/quotes'), isEmpty, reason: 'no list fallback with BE-06');
      expect(await quotePdfBytes('q-1'), samplePdfBytes);
      expect(await quoteShareUrl('q-1'), 'https://invoice.test/q/qtok');
      expect(await duplicateQuote('q-1'), 'q-2');
    });

    test('quote text with the BE-06 link; P0 text without one', () {
      final p1 = quoteWhatsAppMessage(
          customerName: 'דנה',
          totalMinor: BigInt.from(118000),
          validUntil: '2026-11-13',
          businessName: 'סטודיו תבל',
          link: 'https://invoice.test/d/qtok');
      expect(p1, contains('לצפייה: https://invoice.test/d/qtok'));
      final p0 = quoteWhatsAppMessage(customerName: 'דנה', totalMinor: BigInt.from(118000), businessName: 'ס');
      expect(p0, isNot(contains('http')));
    });

    test('BE-08: "הפק חשבונית מס" = linked clone to TAX_INVOICE', () async {
      expect(await issueTaxInvoiceFrom('doc-300'), 'doc-dup');
      expect(backend.last('POST', '/documents/:id/clone')!.body, {'documentType': 'TAX_INVOICE', 'link': true});
    });

    test('BE-36 void: body {reason}; DOCUMENT_HAS_PAYMENTS in Hebrew; ALREADY_VOIDED = done', () async {
      await voidDocument('doc-1', ' כפול ');
      expect(backend.last('POST', '/documents/:id/void')!.body, {'reason': 'כפול'});
      backend.error('POST', '/documents/:id/void', 409, 'DOCUMENT_HAS_PAYMENTS');
      await expectLater(
          voidDocument('doc-1', 'x'),
          throwsA(isA<ApiException>()
              .having((e) => e.messageHe, 'he', 'יש תשלום. בטל קודם את הקבלה במחשב')));
      backend.error('POST', '/documents/:id/void', 409, 'DOCUMENT_ALREADY_VOIDED');
      await voidDocument('doc-1', 'x'); // a lost first response
    });

    test('BE-26: ALLOCATION_NUMBER_RESERVED → Hebrew explanation', () async {
      backend.error('POST', '/documents/:id/allocation/cancel', 409, 'ALLOCATION_NUMBER_RESERVED');
      await expectLater(
          cancelAllocationRequest('doc-1'),
          throwsA(isA<ApiException>().having((e) => e.messageHe, 'he', contains('המשך בלי מספר'))));
    });

    test('BE-11 ledger page: paging fields, includeVoided, mayVoid', () async {
      final page = await fetchPaymentsPage(from: '2026-10-01', to: '2026-10-31', includeVoided: true);
      final q = backend.last('GET', '/payments')!.query;
      expect(q['from'], '2026-10-01');
      expect(q['includeVoided'], '1');
      expect(q['limit'], '50');
      expect(page.total, 2);
      expect(page.hasMore, isFalse);
      expect(page.rows.first.mayVoid, isTrue);
      expect(page.rows.last.mayVoid, isFalse, reason: 'in a receipt');
      expect(page.rows.last.receiptDocumentNumber, '9');
    });

    test('BE-11 void of a locked payment → Hebrew PAYMENT_LOCKED_IN_DOCUMENT', () async {
      backend.error('POST', '/payments/:id/void', 409, 'PAYMENT_LOCKED_IN_DOCUMENT');
      await expectLater(voidPayment('p1', 'טעות'),
          throwsA(isA<ApiException>().having((e) => e.messageHe, 'he', contains('הפק זיכוי'))));
    });

    test('BE-14 gate: a refused extended method reads in Hebrew', () async {
      backend.error('POST', '/payments', 422, 'PAYMENT_METHOD_NOT_ENABLED');
      final doc = detail(docDetailJson());
      await expectLater(
          recordPayments(doc, [PaymentEntry(method: 'BIT', amountMinor: BigInt.from(100), paymentDate: '2026-10-30')]),
          throwsA(isA<ApiException>().having((e) => e.messageHe, 'he', contains('העברה בנקאית'))));
    });

    test('BE-11/12 detail extras: payments, links, timeline → sent / viewed / live link', () {
      final x = DocumentExtras.fromJson(docDetailJson(
        timeline: [
          timelineJson('document.finalized'),
          timelineJson('document.shared', at: '2026-10-30T09:00:00.000Z'),
          timelineJson('document.share_downloaded', at: '2026-10-30T10:00:00.000Z'),
          timelineJson('document.share_revoked', at: '2026-10-30T11:00:00.000Z'),
        ],
        payments: [
          {'id': 'p1', 'method': 'CASH', 'amountMinor': '50000', 'allocatedMinor': '50000', 'paymentDate': '2026-10-30',
            'reference': null, 'receiptDocumentId': 'rcp-1', 'voidedAt': null},
        ],
        linked: [
          {'id': 'rcp-1', 'type': 'RECEIPT', 'number': '77', 'status': 'ARCHIVED', 'totalMinor': '50000', 'relation': 'RECEIPT'},
          {'id': 'd305', 'type': 'TAX_INVOICE', 'number': '12', 'status': 'ARCHIVED', 'totalMinor': '118000', 'relation': 'CONVERTED_TO'},
        ],
        notes: 'תודה',
      ));
      expect(x.hasTimeline, isTrue);
      expect(x.sentAt, '2026-10-30T09:00:00.000Z');
      expect(x.viewedAt, '2026-10-30T10:00:00.000Z');
      expect(x.hasLiveShareLink, isFalse);
      expect(x.payments.single.allocatedMinor, BigInt.from(50000));
      expect(x.convertedTo?.id, 'd305');
      expect(x.notes, 'תודה');
      expect(DocumentExtras.fromJson(docDetailJson()).hasTimeline, isFalse, reason: 'older server');
    });
  });
}
