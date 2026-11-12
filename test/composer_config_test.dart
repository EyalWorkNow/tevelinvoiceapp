// §8.1 Composer configuration: one test per table row + the S1/S3 type lists.

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/composer_config.dart';

import 'fakes/me_fixtures.dart';

Caps capsOf(Preset p, {String type = 'OSEK_MURSHE'}) =>
    Caps.fromMe(Me.fromJson(meJson(p, businessType: type)));

void main() {
  final owner = capsOf(Preset.owner);

  test(
    '320 חשבונית מס-קבלה: PAID, VAT, payment method, docIssue (else submit), VAT businesses',
    () {
      final c = configFor(DocKind.taxInvoiceReceipt);
      expect(
        (c.code, c.serverType, c.paid, c.vat, c.cap, c.after),
        (
          320,
          'TAX_INVOICE_RECEIPT',
          true,
          VatRule.always,
          Cap.docIssue,
          AfterIssue.share,
        ),
      );
      expect(c.receiptOnly, isFalse);
      expect(kindAllowedFor(DocKind.taxInvoiceReceipt, 'OSEK_PATUR'), isFalse);
      expect(kindAllowedFor(DocKind.taxInvoiceReceipt, 'COMPANY'), isTrue);
      // an employee without finalize still gets it: it ends in "שלח לאישור".
      expect(
        kindAllowedForCaps(DocKind.taxInvoiceReceipt, capsOf(Preset.employee)),
        isTrue,
      );
      expect(taxRateFor(DocKind.taxInvoiceReceipt, 'OSEK_MURSHE', 1800), 1800);
    },
  );

  test('305 חשבונית מס: REQUEST, VAT, collect afterwards', () {
    final c = configFor(DocKind.taxInvoice);
    expect(
      (c.code, c.serverType, c.paid, c.cap, c.after),
      (305, 'TAX_INVOICE', false, Cap.docDraft, AfterIssue.collect),
    );
    expect(kindAllowedFor(DocKind.taxInvoice, 'NONPROFIT'), isFalse);
    expect(kindHasVat(DocKind.taxInvoice, 'PARTNERSHIP'), isTrue);
  });

  test('300 חשבון עסקה: VAT only for VAT businesses', () {
    final c = configFor(DocKind.transactionInvoice);
    expect(
      (c.code, c.serverType, c.vat),
      (300, 'TRANSACTION_INVOICE', VatRule.byBusiness),
    );
    expect(kindHasVat(DocKind.transactionInvoice, 'OSEK_PATUR'), isFalse);
    expect(kindHasVat(DocKind.transactionInvoice, 'OSEK_MURSHE'), isTrue);
    expect(taxRateFor(DocKind.transactionInvoice, 'NONPROFIT', 1800), 0);
  });

  test(
    '400 קבלה: receipt only (no POST /documents), no VAT, payment.record',
    () {
      final c = configFor(DocKind.receipt);
      expect(
        (c.code, c.serverType, c.paid, c.vat, c.cap),
        (400, 'RECEIPT', true, VatRule.never, Cap.paymentRecord),
      );
      expect(c.receiptOnly, isTrue);
      expect(kindAllowedFor(DocKind.receipt, 'OSEK_PATUR'), isTrue);
      expect(
        kindAllowedForCaps(DocKind.receipt, capsOf(Preset.employee)),
        isFalse,
      );
      expect(
        kindAllowedForCaps(DocKind.receipt, capsOf(Preset.employeeIssuer)),
        isTrue,
      );
    },
  );

  test('405 קבלה על תרומה: nonprofit with a §46 approval only; donor ID', () {
    final c = configFor(DocKind.donationReceipt);
    expect(
      (c.code, c.counterparty, c.receiptOnly),
      (405, Counterparty.donor, true),
    );
    expect(kindAllowedFor(DocKind.donationReceipt, 'NONPROFIT'), isFalse);
    expect(
      kindAllowedFor(DocKind.donationReceipt, 'NONPROFIT', section46: true),
      isTrue,
    );
    expect(
      kindAllowedFor(DocKind.donationReceipt, 'OSEK_MURSHE', section46: true),
      isFalse,
    );
  });

  test(
    '330 זיכוי: S8 only, never the Composer; doc.cancel; VAT from the source',
    () {
      final c = configFor(DocKind.credit);
      expect(
        (c.code, c.viaComposer, c.cap, c.vat),
        (330, false, Cap.docCancel, VatRule.fromSource),
      );
      expect(kindForCode(330), DocKind.credit);
    },
  );

  test('QUOTE: business rate, valid until, no server type, quote flow', () {
    final c = configFor(DocKind.quote);
    expect(
      (c.code, c.serverType, c.validUntil, c.after),
      (null, null, true, AfterIssue.quote),
    );
    expect(kindHasVat(DocKind.quote, 'OSEK_PATUR'), isFalse);
    expect(kindHasVat(DocKind.quote, 'OSEK_MURSHE'), isTrue);
  });

  test('100 הזמנה: lines, docDraft', () {
    final c = configFor(DocKind.salesOrder);
    expect(
      (c.code, c.serverType, c.lines, c.cap),
      (100, 'SALES_ORDER', true, Cap.docDraft),
    );
  });

  test(
    '500 הזמנת רכש: supplier, needs supplier.manage AND a supplier picker',
    () {
      final c = configFor(DocKind.purchaseOrder);
      expect(
        (c.code, c.serverType, c.counterparty),
        (500, 'PURCHASE_ORDER', Counterparty.supplier),
      );
      expect(
        kindAllowedForCaps(DocKind.purchaseOrder, owner),
        isFalse,
      ); // no picker in P0
      expect(
        kindAllowedForCaps(DocKind.purchaseOrder, owner, supplierPicker: true),
        isTrue,
      );
    },
  );

  test(
    'not in the app (W): 200/210/310/340/345/205/410/420/600/610/700/710/800',
    () {
      for (final code in [
        200,
        210,
        310,
        340,
        345,
        205,
        410,
        420,
        600,
        610,
        700,
        710,
        800,
        910,
      ]) {
        expect(kindForCode(code), isNull, reason: '$code');
      }
    },
  );

  test('S1 "עוד סוגים" lists per business type (≤6, spec order)', () {
    expect(moreKinds('OSEK_MURSHE', owner), [
      DocKind.taxInvoice,
      DocKind.taxInvoiceReceipt,
      DocKind.transactionInvoice,
      DocKind.receipt,
      DocKind.salesOrder,
    ]);
    expect(moreKinds('OSEK_MURSHE', owner, supplierPicker: true), hasLength(6));
    final patur = capsOf(Preset.owner, type: 'OSEK_PATUR');
    expect(moreKinds('OSEK_PATUR', patur), [
      DocKind.transactionInvoice,
      DocKind.receipt,
      DocKind.salesOrder,
    ]);
    expect(moreKinds('NONPROFIT', patur, section46: true), [
      DocKind.transactionInvoice,
      DocKind.receipt,
      DocKind.donationReceipt,
      DocKind.salesOrder,
    ]);
    expect(moreKinds('OSEK_MURSHE', capsOf(Preset.viewer)), isEmpty);
    expect(
      moreKinds('OSEK_MURSHE', capsOf(Preset.employee)),
      isNot(contains(DocKind.receipt)),
      reason: 'no payment.record',
    );
  });

  test('isPaidServerType', () {
    expect(isPaidServerType('TAX_INVOICE_RECEIPT'), isTrue);
    expect(isPaidServerType('RECEIPT'), isTrue);
    expect(isPaidServerType('TAX_INVOICE'), isFalse);
  });

  test(
    'F8 / BE-07 due date from BE-09 payment terms (calendar days, DST-safe)',
    () {
      final oct = DateTime(2026, 10, 20); // DST ends in Israel on 2026-10-25
      expect(dueDateForTerms('IMMEDIATE', oct), '2026-10-20');
      expect(dueDateForTerms('EOM', oct), '2026-10-31');
      expect(dueDateForTerms('EOM_30', oct), '2026-11-30');
      expect(
        dueDateForTerms(null, oct),
        '2026-11-30',
        reason: '§7 default שוטף+30',
      );
      expect(dueDateForTerms('EOM_45', oct), '2026-12-15');
      expect(dueDateForTerms('EOM_60', DateTime(2026, 12, 3)), '2027-03-01');
      expect(dueDateForTerms('EOM_90', DateTime(2027, 2, 10)), '2027-05-29');
    },
  );
}
