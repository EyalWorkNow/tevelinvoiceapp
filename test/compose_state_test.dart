// ComposeState: request lines = what the server computes (§6.C, §8).

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/util/composer_config.dart';

ComposeState st(DocKind k, {String type = 'OSEK_MURSHE'}) =>
    ComposeState(kind: k, businessType: type, vatBasisPoints: 1800)
      ..customer = const Customer(id: 'c1', name: 'דנה', phone: '0501234567')
      ..description = 'תיקון דוד';

void main() {
  test('1,180 including VAT → net 1,000 + 180 (default inclusive)', () {
    final s = st(DocKind.taxInvoiceReceipt)..amountText = '1180';
    expect(s.requestLines.single['unitPriceMinor'], '100000');
    expect(s.requestLines.single['taxRateBasisPoints'], 1800);
    expect(s.totals.taxMinor, BigInt.from(18000));
    expect(s.totalMinor, BigInt.from(118000));
    expect(s.ready, isTrue);
  });

  test('tap on the VAT line → before VAT: 1,000 + 180 = 1,180', () {
    final s = st(DocKind.taxInvoice)
      ..amountText = '1000'
      ..inclusive = false;
    expect(s.totalMinor, BigInt.from(118000));
  });

  test('exempt business: no VAT anywhere, 300 at 0%', () {
    final s = st(DocKind.transactionInvoice, type: 'OSEK_PATUR')
      ..amountText = '500';
    expect(s.showVat, isFalse);
    expect(s.requestLines.single['taxRateBasisPoints'], 0);
    expect(s.totalMinor, BigInt.from(50000));
  });

  test('S3: extra line, discount on the main line, VAT "ללא"', () {
    final s = st(DocKind.taxInvoice)
      ..inclusive = false
      ..amountText = '1000'
      ..discountText = '100'
      ..extraLines.add(
        ComposeLine(description: 'חלקים', quantityText: '2', priceText: '50'),
      );
    expect(s.requestLines, hasLength(2));
    expect(s.requestLines.first['discountMinor'], '10000');
    expect(s.totals.subtotalMinor, BigInt.from(100000));
    s.vatNone = true;
    expect(s.totalMinor, BigInt.from(100000));
  });

  test('amount 0 → not ready (no button); CHECK needs its four fields', () {
    final s = st(DocKind.taxInvoiceReceipt);
    expect(s.ready, isFalse);
    s
      ..amountText = '100'
      ..method = 'CHECK';
    expect(s.ready, isFalse);
    s
      ..bankNumber = '12'
      ..branchNumber = '345'
      ..accountNumber = '678'
      ..checkNumber = '1001';
    expect(s.ready, isTrue);
    expect(
      s.payment!.requestBody(BigInt.one, '2026-10-30')['reference'],
      '1001',
    );
  });

  test('405 needs the donor ID when the customer has none', () {
    final s = st(DocKind.donationReceipt, type: 'NONPROFIT')
      ..amountText = '100';
    expect(s.ready, isFalse);
    s.donorTaxId = '123456782';
    expect(s.ready, isTrue);
  });

  test('requestBody: issueDate today, customerId; 500 → supplierId', () {
    final s = st(DocKind.taxInvoice)..amountText = '100';
    final b = s.requestBody();
    expect(b['documentType'], 'TAX_INVOICE');
    expect(b['customerId'], 'c1');
    expect(b['issueDate'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    s.setKind(DocKind.purchaseOrder);
    expect(s.requestBody()['supplierId'], 'c1');
  });

  test('loadLines (duplicate / convert): net prices, extra lines kept', () {
    final s = st(DocKind.taxInvoice)
      ..loadLines([
        DocumentLine(
          position: 1,
          description: 'עיצוב',
          quantityMicros: BigInt.from(1000000),
          unitPriceMinor: BigInt.from(100000),
          discountMinor: BigInt.zero,
          subtotalMinor: BigInt.from(100000),
          taxRateBasisPoints: 1800,
          taxAmountMinor: BigInt.from(18000),
          totalMinor: BigInt.from(118000),
        ),
        DocumentLine(
          position: 2,
          description: 'הדפסה',
          quantityMicros: BigInt.from(3000000),
          unitPriceMinor: BigInt.from(1000),
          discountMinor: BigInt.zero,
          subtotalMinor: BigInt.from(3000),
          taxRateBasisPoints: 1800,
          taxAmountMinor: BigInt.from(540),
          totalMinor: BigInt.from(3540),
        ),
      ]);
    expect(s.inclusive, isFalse);
    expect(s.description, 'עיצוב');
    expect(s.extraLines.single.quantityText, '3');
    expect(s.totalMinor, BigInt.from(121540));
  });

  test('toJson / restore round trip (local draft)', () {
    final a = st(DocKind.taxInvoiceReceipt)
      ..amountText = '250'
      ..method = 'BANK_TRANSFER';
    final b = ComposeState(
      kind: DocKind.taxInvoice,
      businessType: 'OSEK_MURSHE',
      vatBasisPoints: 1800,
    )..restore(a.toJson());
    expect(b.kind, DocKind.taxInvoiceReceipt);
    expect(b.totalMinor, a.totalMinor);
    expect(b.method, 'BANK_TRANSFER');
    expect(b.customer!.id, 'c1');
  });

  group('P1', () {
    test(
      'BE-07: 305 sends notes + due date from the customer terms; a picked date wins',
      () {
        final s = st(DocKind.taxInvoice)
          ..amountText = '100'
          ..notes = '  לפי הזמנה 17  '
          ..customerTerms = 'EOM';
        final now = DateTime.now();
        final b = s.requestBody();
        expect(b['notes'], 'לפי הזמנה 17');
        expect(b['dueDate'], dueDateForTerms('EOM', now));
        s.pickedDueDate = '2027-01-15';
        expect(s.requestBody()['dueDate'], '2027-01-15');
        s.notes = '';
        expect(s.requestBody().containsKey('notes'), isTrue);
        expect(
          s.requestBody()['notes'],
          isNull,
          reason: 'null clears a stored note',
        );
      },
    );

    test(
      'BE-07: 320 (paid) has a note but no due date; receipts have neither',
      () {
        final paid = st(DocKind.taxInvoiceReceipt)..amountText = '100';
        expect(paid.hasNotes, isTrue);
        expect(paid.hasDueDate, isFalse);
        expect(paid.requestBody().containsKey('dueDate'), isFalse);
        final receipt = st(DocKind.receipt, type: 'OSEK_PATUR');
        expect((receipt.hasNotes, receipt.hasDueDate), (false, false));
        expect(
          st(DocKind.transactionInvoice, type: 'OSEK_PATUR').hasDueDate,
          isTrue,
        );
      },
    );

    test(
      'S3 "לפי שורה": a line marked "ללא מע״מ" goes at 0%, the others at the business rate',
      () {
        final s = st(DocKind.taxInvoice)
          ..amountText = '1180'
          ..vatPerLine = true
          ..extraLines.add(
            ComposeLine(
              description: 'אגרה',
              priceText: '50',
              vatNone: true,
              itemId: 'i9',
            ),
          );
        final lines = s.requestLines;
        expect(lines[0]['taxRateBasisPoints'], 1800);
        expect(
          lines[0]['unitPriceMinor'],
          '100000',
          reason: 'gross 1,180 → net 1,000',
        );
        expect(lines[1]['taxRateBasisPoints'], 0);
        expect(
          lines[1]['unitPriceMinor'],
          '5000',
          reason: 'no VAT to take out',
        );
        expect(lines[1]['itemId'], 'i9');
        expect(s.totalMinor, BigInt.from(123000));
        expect(s.quoteLines[1].itemId, 'i9');
        s.vatPerLine = false;
        expect(
          s.requestLines[1]['taxRateBasisPoints'],
          1800,
          reason: 'the flag counts only in per-line mode',
        );
      },
    );

    test(
      'loadLines with mixed rates → per-line mode; itemId kept; round trip',
      () {
        DocumentLine line(int pos, int rate, {String? item}) => DocumentLine(
          position: pos,
          itemId: item,
          description: 'שורה $pos',
          quantityMicros: BigInt.from(1000000),
          unitPriceMinor: BigInt.from(10000),
          discountMinor: BigInt.zero,
          subtotalMinor: BigInt.zero,
          taxRateBasisPoints: rate,
          taxAmountMinor: BigInt.zero,
          totalMinor: BigInt.zero,
        );
        final s = st(DocKind.taxInvoice)
          ..loadLines([line(1, 1800), line(2, 0, item: 'i1')]);
        expect(s.vatPerLine, isTrue);
        expect(s.extraLines.single.vatNone, isTrue);
        expect(s.extraLines.single.itemId, 'i1');
        final r =
            ComposeState(
              kind: DocKind.taxInvoice,
              businessType: 'OSEK_MURSHE',
              vatBasisPoints: 1800,
            )..restore(
              (s
                    ..notes = 'n'
                    ..customerTerms = 'EOM_60'
                    ..pickedDueDate = '2027-02-01')
                  .toJson(),
            );
        expect(
          (
            r.vatPerLine,
            r.notes,
            r.customerTerms,
            r.pickedDueDate,
            r.extraLines.single.itemId,
          ),
          (true, 'n', 'EOM_60', '2027-02-01', 'i1'),
        );
      },
    );

    test(
      'BE-06 quote lines (null rate = the business rate) prefill like a document',
      () {
        final s =
            ComposeState(
              kind: DocKind.quote,
              businessType: 'OSEK_MURSHE',
              vatBasisPoints: 1800,
            )..loadQuoteLines([
              QuoteLine(
                description: 'עיצוב',
                quantityMicros: BigInt.from(1000000),
                unitPriceMinor: BigInt.from(100000),
              ),
              QuoteLine(
                description: 'הדפסה',
                quantityMicros: BigInt.from(2000000),
                unitPriceMinor: BigInt.from(5000),
                taxRateBasisPoints: 1800,
                itemId: 'i2',
              ),
            ]);
        expect(s.amountText, '1000');
        expect(s.extraLines.single.itemId, 'i2');
        expect(s.quoteLines.map((l) => l.taxRateBasisPoints), [1800, 1800]);
        expect(s.totalMinor, BigInt.from(129800));
      },
    );
  });
}
