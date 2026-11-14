// §8.3 cancel table (one test per row) + §8.2.5 credit lines (AT-21 numbers).

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/cancel_policy.dart';

CancelFacts facts(
  String type, {
  String status = 'ARCHIVED',
  int total = 118000,
  int credited = 0,
  int paid = 0,
  String? voidedAt,
}) => CancelFacts(
  documentType: type,
  status: status,
  totalMinor: BigInt.from(total),
  creditedMinor: BigInt.from(credited),
  paidMinor: BigInt.from(paid),
  voidedAt: voidedAt,
);

bool shown(
  CancelFacts f, {
  bool canCancel = true,
  bool exempt = false,
  bool voidAvailable = true,
}) => showCancelItem(
  f,
  canCancel: canCancel,
  vatExempt: exempt,
  voidAvailable: voidAvailable,
);

void main() {
  group('§8.3 rows', () {
    test(
      '305 → credit (full/partial) while total − credited > 0; doc.cancel only',
      () {
        expect(
          cancelActionFor('TAX_INVOICE', vatExempt: false),
          CancelAction.credit,
        );
        expect(shown(facts('TAX_INVOICE')), isTrue);
        expect(shown(facts('TAX_INVOICE', credited: 118000)), isFalse);
        expect(
          facts('TAX_INVOICE', credited: 20000).creditableMinor,
          BigInt.from(98000),
        );
        expect(shown(facts('TAX_INVOICE'), canCancel: false), isFalse);
      },
    );

    test('320 → credit (the payment stays)', () {
      expect(
        cancelActionFor('TAX_INVOICE_RECEIPT', vatExempt: false),
        CancelAction.credit,
      );
      expect(shown(facts('TAX_INVOICE_RECEIPT', paid: 118000)), isTrue);
    });

    test(
      '300 → void (BE-36) without payments; with payments S8 says "cancel the receipt on the computer"',
      () {
        expect(
          cancelActionFor('TRANSACTION_INVOICE', vatExempt: true),
          CancelAction.voidDocument,
        );
        expect(shown(facts('TRANSACTION_INVOICE')), isTrue);
        expect(
          voidBlockedByPayments(facts('TRANSACTION_INVOICE', paid: 1)),
          isTrue,
        );
        expect(voidBlockedByPayments(facts('TRANSACTION_INVOICE')), isFalse);
        expect(
          shown(facts('TRANSACTION_INVOICE', voidedAt: '2026-10-30')),
          isFalse,
        );
      },
    );

    test('100 / 500 → void, never blocked by payments', () {
      for (final t in ['SALES_ORDER', 'PURCHASE_ORDER']) {
        expect(cancelActionFor(t, vatExempt: false), CancelAction.voidDocument);
        expect(voidBlockedByPayments(facts(t, paid: 5)), isFalse);
      }
    });

    test('P0 without BE-36 void: only 305/320 show the item', () {
      expect(
        shown(facts('TRANSACTION_INVOICE'), voidAvailable: false),
        isFalse,
      );
      expect(shown(facts('TAX_INVOICE'), voidAvailable: false), isTrue);
    });

    test('400 / 405 / 330 / quote / 200 → not in the app', () {
      for (final t in [
        'RECEIPT',
        'DONATION_RECEIPT',
        'CREDIT_DOCUMENT',
        'QUOTE',
        'DELIVERY_NOTE',
      ]) {
        expect(
          cancelActionFor(t, vatExempt: false),
          CancelAction.none,
          reason: t,
        );
        expect(shown(facts(t)), isFalse, reason: t);
      }
    });

    test(
      'exempt dealer: no credit at all (CREDIT_SOURCE_TYPE_INVALID on the server)',
      () {
        expect(
          cancelActionFor('TAX_INVOICE', vatExempt: true),
          CancelAction.none,
        );
        expect(shown(facts('TAX_INVOICE'), exempt: true), isFalse);
      },
    );

    test('drafts and pending documents are not cancelled from S8', () {
      expect(shown(facts('TAX_INVOICE', status: 'DRAFT')), isFalse);
      expect(shown(facts('TAX_INVOICE', status: 'PENDING_APPROVAL')), isFalse);
    });
  });

  group('§8.2.5 credit lines', () {
    final source = [
      CreditSourceLine(
        description: 'תיקון דוד',
        quantityMicros: BigInt.from(1000000),
        unitPriceMinor: BigInt.from(100000),
        discountMinor: BigInt.zero,
        taxRateBasisPoints: 1800,
        totalMinor: BigInt.from(118000),
      ),
    ];

    test('full first credit = the source lines', () {
      final lines = creditLines(
        source: source,
        totalMinor: BigInt.from(118000),
        alreadyCreditedMinor: BigInt.zero,
        amountMinor: BigInt.from(118000),
        partialDescription: 'x',
      );
      expect(lines, [
        {
          'description': 'תיקון דוד',
          'quantityMicros': '1000000',
          'unitPriceMinor': '100000',
          'discountMinor': '0',
          'taxRateBasisPoints': 1800,
        },
      ]);
    });

    test(
      'AT-21: ₪200 of 1,000 + 18% → one line 169.49 + VAT 30.51 = 200.00',
      () {
        final lines = creditLines(
          source: source,
          totalMinor: BigInt.from(118000),
          alreadyCreditedMinor: BigInt.zero,
          amountMinor: BigInt.from(20000),
          partialDescription: 'זיכוי חלקי לחשבונית 1042',
        );
        expect(lines, hasLength(1));
        expect(lines.single['unitPriceMinor'], '16949');
        expect(lines.single['taxRateBasisPoints'], 1800);
        expect(lines.single['description'], 'זיכוי חלקי לחשבונית 1042');
        final net = BigInt.parse(lines.single['unitPriceMinor'] as String);
        expect(vatOn(net, 1800), BigInt.from(3051));
        expect(net + vatOn(net, 1800), BigInt.from(20000));
      },
    );

    test(
      'the rest after an earlier credit is split even when it equals the remaining total',
      () {
        final lines = creditLines(
          source: source,
          totalMinor: BigInt.from(118000),
          alreadyCreditedMinor: BigInt.from(20000),
          amountMinor: BigInt.from(98000),
          partialDescription: 'p',
        );
        expect(lines.single['description'], 'p');
      },
    );

    test('two VAT groups: proportional split, remainder to the larger group', () {
      final mixed = [
        source.first,
        CreditSourceLine(
          description: 'פטור',
          quantityMicros: BigInt.from(1000000),
          unitPriceMinor: BigInt.from(10001),
          discountMinor: BigInt.zero,
          taxRateBasisPoints: 0,
          totalMinor: BigInt.from(10001),
        ),
      ];
      final lines = creditLines(
        source: mixed,
        totalMinor: BigInt.from(128001),
        alreadyCreditedMinor: BigInt.zero,
        amountMinor: BigInt.from(10000),
        partialDescription: 'p',
      );
      expect(lines, hasLength(2));
      // 10000 × 118000/128001 = 9218.67 → 9218 (+1 remainder → 9219); 10000 × 10001/128001 = 781
      final gross18 =
          BigInt.parse(lines[0]['unitPriceMinor'] as String) +
          vatOn(BigInt.parse(lines[0]['unitPriceMinor'] as String), 1800);
      expect(gross18, BigInt.from(9219));
      expect(lines[1]['unitPriceMinor'], '781');
    });

    test('netOfVat rounds half up', () {
      expect(netOfVat(BigInt.from(118), 1800), BigInt.from(100));
      expect(netOfVat(BigInt.from(20000), 1800), BigInt.from(16949));
      expect(netOfVat(BigInt.from(500), 0), BigInt.from(500));
    });
  });
}
