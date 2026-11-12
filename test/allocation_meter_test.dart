// R7 · allocation meter: the threshold function (boundaries, before-VAT,
// effective dates, עוסק פטור customer), the Composer hint, the document-screen
// words and the scan's candidate filter. Values mirror the server's
// packages/shaam/src/rules.ts (R-THRESH-2026-01 / -06, strict "עולה על").

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/allocation_scan_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/screens/compose/fields/allocation_hint_line.dart';
import 'package:invoice/util/allocation_meter.dart';
import 'package:invoice/util/composer_config.dart';

bool req({
  String type = 'TAX_INVOICE',
  String? dealer = 'AUTHORIZED_DEALER',
  required int beforeVat,
  int? vat,
  String date = '2026-11-12',
}) => allocationRequired(
  documentType: type,
  customerVatDealerStatus: dealer,
  amountBeforeVatMinor: BigInt.from(beforeVat),
  vatMinor: BigInt.from(vat ?? beforeVat * 18 ~/ 100),
  issueDate: date,
);

ComposeState compose(
  String amountText, {
  DocKind kind = DocKind.taxInvoice,
  String? dealer = 'AUTHORIZED_DEALER',
  bool inclusive = true,
  String businessType = 'OSEK_MURSHE',
}) => ComposeState(kind: kind, businessType: businessType, vatBasisPoints: 1800)
  ..customer = Customer(id: 'c1', name: 'לקוח', vatDealerStatus: dealer)
  ..inclusive = inclusive
  ..amountText = amountText;

void main() {
  group('effective dates (server ISRAEL_INVOICE_RULES)', () {
    test('no verified rule before 2026 → null', () {
      expect(thresholdOn('2025-12-31'), isNull);
      expect(req(beforeVat: 5000000, date: '2025-12-31'), isFalse);
    });
    test('2026-01-01 … 2026-05-31: ₪10,000', () {
      expect(thresholdOn('2026-01-01')!.thresholdMinor, 1000000);
      expect(thresholdOn('2026-05-31')!.ruleId, 'R-THRESH-2026-01');
    });
    test('from 2026-06-01 (open-ended): ₪5,000', () {
      expect(thresholdOn('2026-06-01')!.thresholdMinor, 500000);
      expect(thresholdOn('2030-01-01')!.ruleId, 'R-THRESH-2026-06');
    });
    test('a malformed date has no rule', () {
      expect(thresholdOn('12/11/2026'), isNull);
      expect(thresholdOn(''), isNull);
    });
    test('the same ₪8,000 is mandatory in June, not in May', () {
      expect(req(beforeVat: 800000, date: '2026-05-31'), isFalse);
      expect(req(beforeVat: 800000, date: '2026-06-01'), isTrue);
    });
    test('lowest threshold over a 12-month window', () {
      expect(lowestThresholdSince('2025-11-12'), 500000);
      expect(lowestThresholdSince('2026-07-01'), 500000);
      expect(
        lowestThresholdSince('2026-07-01', const [
          AllocationThreshold(
            ruleId: 'old',
            effectiveFrom: '2026-01-01',
            effectiveUntil: '2026-05-31',
            thresholdMinor: 1,
          ),
        ]),
        isNull,
      );
    });
  });

  group('boundaries ("עולה על" = strictly greater)', () {
    test('exactly ₪5,000.00 before VAT → not required', () {
      expect(req(beforeVat: 500000), isFalse);
    });
    test('₪5,000.01 → required', () {
      expect(req(beforeVat: 500001), isTrue);
    });
    test('exactly ₪10,000.00 in May → not required; +1 agora → required', () {
      expect(req(beforeVat: 1000000, date: '2026-05-15'), isFalse);
      expect(req(beforeVat: 1000001, date: '2026-05-15'), isTrue);
    });
    test('zero VAT component → not required', () {
      expect(req(beforeVat: 900000, vat: 0), isFalse);
    });
  });

  group('customer and document type', () {
    test('עוסק פטור customer → never required', () {
      expect(req(beforeVat: 9000000, dealer: 'EXEMPT_DEALER'), isFalse);
    });
    test('private / unknown / missing status → not required', () {
      expect(req(beforeVat: 900000, dealer: 'PRIVATE'), isFalse);
      expect(req(beforeVat: 900000, dealer: 'UNKNOWN'), isFalse);
      expect(req(beforeVat: 900000, dealer: null), isFalse);
    });
    test('305 and 320 only', () {
      expect(req(beforeVat: 900000, type: 'TAX_INVOICE_RECEIPT'), isTrue);
      expect(req(beforeVat: 900000, type: 'TRANSACTION_INVOICE'), isFalse);
      expect(req(beforeVat: 900000, type: 'CREDIT_DOCUMENT'), isFalse);
      expect(req(beforeVat: 900000, type: 'RECEIPT'), isFalse);
    });
  });

  group('Composer: before-VAT is computed from the typed amount', () {
    const june = '2026-07-01';
    test('₪5,900 incl. 18% = ₪5,000 net → nothing', () {
      expect(
        composeAllocationHint(compose('5900'), issueDate: june),
        AllocationHint.none,
      );
    });
    test('₪5,901.18 incl. VAT = ₪5,001 net → "יקבל מספר הקצאה"', () {
      expect(
        composeAllocationHint(compose('5901.18'), issueDate: june),
        AllocationHint.willAllocate,
      );
    });
    test('₪5,000.01 typed before VAT → hint', () {
      expect(
        composeAllocationHint(
          compose('5000.01', inclusive: false),
          issueDate: june,
        ),
        AllocationHint.willAllocate,
      );
    });
    test('320 counts; a receipt never does', () {
      expect(
        composeAllocationHint(
          compose('9000', kind: DocKind.taxInvoiceReceipt),
          issueDate: june,
        ),
        AllocationHint.willAllocate,
      );
      expect(
        composeAllocationHint(
          compose('9000', kind: DocKind.receipt),
          issueDate: june,
        ),
        AllocationHint.none,
      );
    });
    test('עוסק פטור customer → nothing', () {
      expect(
        composeAllocationHint(
          compose('90000', dealer: 'EXEMPT_DEALER'),
          issueDate: june,
        ),
        AllocationHint.none,
      );
    });
    test('not connected to SHAAM → "נדרש חיבור לרשות המסים"', () {
      for (final status in ['NOT_CONNECTED', 'EXPIRED', 'DISABLED']) {
        expect(
          composeAllocationHint(
            compose('9000'),
            issueDate: june,
            shaamStatus: status,
          ),
          AllocationHint.needsConnection,
        );
      }
      expect(
        composeAllocationHint(
          compose('9000'),
          issueDate: june,
          shaamStatus: 'CONNECTED',
        ),
        AllocationHint.willAllocate,
      );
    });
    test('below the threshold the connection does not matter', () {
      expect(
        allocationHint(required: false, shaamStatus: 'EXPIRED'),
        AllocationHint.none,
      );
    });
  });

  group('document screen words', () {
    test('a number wins over any state', () {
      final s = allocationStatusHe('NOT_EVALUATED', '123456789')!;
      expect(s.$1, contains('123456789'));
      expect(s.$2, AllocationTone.ok);
    });
    test('waiting / failed / not required / unknown', () {
      expect(allocationStatusHe('REQUESTING', null)!.$1, AllocationHe.waiting);
      expect(allocationStatusHe('REQUIRED', null)!.$2, AllocationTone.waiting);
      expect(
        allocationStatusHe('RETRYABLE_FAILURE', null)!.$1,
        AllocationHe.failed,
      );
      expect(allocationStatusHe('NOT_APPROVED', null)!.$1, AllocationHe.failed);
      expect(
        allocationStatusHe('AUTHORIZATION_REQUIRED', null)!.$1,
        AllocationHe.needsConnection,
      );
      expect(
        allocationStatusHe('OPTIONAL', null)!.$1,
        AllocationHe.notRequired,
      );
      expect(
        allocationStatusHe('CONTINUED_WITHOUT_ALLOCATION', null)!.$1,
        AllocationHe.continuedWithout,
      );
      expect(allocationStatusHe('NOT_EVALUATED', null), isNull);
      expect(allocationStatusHe('REGULATORY_RULE_UNKNOWN', null), isNull);
    });
    test('retry only where the server accepts request/reconcile', () {
      expect(allocationRetryable('TECHNICAL_FAILURE', null), isTrue);
      expect(allocationRetryable('OUTCOME_UNKNOWN', null), isTrue);
      expect(allocationRetryable('CONTINUED_WITHOUT_ALLOCATION', null), isTrue);
      expect(allocationRetryable('NOT_APPROVED', null), isFalse); // decision
      expect(allocationRetryable('OPTIONAL', null), isFalse);
      expect(allocationRetryable('RETRYABLE_FAILURE', '1'), isFalse);
    });
    test('missing = required state without a number', () {
      expect(allocationMissing('REQUIRED', null), isTrue);
      expect(allocationMissing('TECHNICAL_FAILURE', ''), isTrue);
      expect(allocationMissing('APPROVED', '123'), isFalse);
      expect(allocationMissing('OPTIONAL', null), isFalse);
      expect(allocationMissing('NOT_EVALUATED', null), isFalse);
    });
  });

  group('scan candidates', () {
    DocumentSummary row(
      String id, {
      String type = 'TAX_INVOICE',
      String status = 'ARCHIVED',
      int total = 700000,
      String date = '2026-08-01',
      String customer = 'c1',
      String? voidedAt,
    }) => DocumentSummary.fromJson({
      'id': id,
      'documentType': type,
      'status': status,
      'customerId': customer,
      'issueDate': date,
      'totalMinor': '$total',
      'voidedAt': voidedAt,
    });

    test('issued, above threshold, not a known non-dealer', () {
      final out = allocationCandidates(
        [
          row('ok'),
          row('320', type: 'TAX_INVOICE_RECEIPT'),
          row('draft', status: 'DRAFT'),
          row('waiting', status: 'WAITING_FOR_ALLOCATION'),
          row('void', voidedAt: '2026-08-02T00:00:00Z'),
          row('small', total: 500000),
          row('may', total: 900000, date: '2026-05-10'), // ₪10k then
          row('2025', date: '2025-12-20'),
          row('exempt', customer: 'c2'),
          row('300', type: 'TRANSACTION_INVOICE'),
        ],
        {'c1': 'AUTHORIZED_DEALER', 'c2': 'EXEMPT_DEALER'},
      );
      expect([for (final d in out) d.id], ['ok', '320', 'waiting']);
    });
    test('12-month window start', () {
      expect(scanFromIso(DateTime(2026, 11, 12)), '2025-11-12');
    });
  });
}
