// §4.7 / §6.C / §8.1: intent → kind per business type, and the primary action.

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/intent_resolver.dart';

void main() {
  test('PAID / REQUEST per business type (§4.7)', () {
    for (final t in ['OSEK_MURSHE', 'COMPANY', 'PARTNERSHIP']) {
      expect(resolveIntent('PAID', t), DocKind.taxInvoiceReceipt, reason: t);
      expect(resolveIntent('REQUEST', t), DocKind.taxInvoice, reason: t);
    }
    for (final t in ['OSEK_PATUR', 'NONPROFIT']) {
      expect(resolveIntent('PAID', t), DocKind.receipt, reason: t);
      expect(
        resolveIntent('REQUEST', t),
        DocKind.transactionInvoice,
        reason: t,
      );
    }
  });

  test(
    'exempt PAID without payment.record → 300 (submitted, approver records the payment)',
    () {
      expect(
        resolveIntent('PAID', 'OSEK_PATUR', canRecordPayment: false),
        DocKind.transactionInvoice,
      );
    },
  );

  test('QUOTE and TYPE:<code>', () {
    expect(resolveIntent('QUOTE', 'OSEK_PATUR'), DocKind.quote);
    expect(
      resolveIntent('TYPE:300', 'OSEK_MURSHE'),
      DocKind.transactionInvoice,
    );
    expect(resolveIntent('TYPE:100', 'OSEK_PATUR'), DocKind.salesOrder);
    expect(
      resolveIntent('TYPE:305', 'OSEK_PATUR'),
      isNull,
      reason: 'no VAT invoice for exempt',
    );
    expect(
      resolveIntent('TYPE:330', 'OSEK_MURSHE'),
      isNull,
      reason: 'credit = S8 only',
    );
    expect(resolveIntent('TYPE:405', 'NONPROFIT'), isNull, reason: 'needs §46');
    expect(
      resolveIntent('TYPE:405', 'NONPROFIT', section46: true),
      DocKind.donationReceipt,
    );
    expect(
      resolveIntent('TYPE:200', 'OSEK_MURSHE'),
      isNull,
      reason: 'AT-55: 200 never',
    );
    expect(
      resolveIntent('TYPE:600', 'OSEK_MURSHE'),
      isNull,
      reason: 'AT-63: 600 never',
    );
    expect(resolveIntent('BOGUS', 'OSEK_MURSHE'), isNull);
    expect(typeIntent(DocKind.taxInvoice), 'TYPE:305');
    expect(typeIntent(DocKind.quote), 'QUOTE');
  });

  test('primary action: first rule that holds (§6.C step 4)', () {
    ComposerAction a(
      DocKind k, {
      bool approval = false,
      bool phone = true,
      bool send = true,
    }) => resolveAction(
      kind: k,
      needsApproval: approval,
      hasPhone: phone,
      canSend: send,
    );
    expect(a(DocKind.taxInvoiceReceipt, approval: true), ComposerAction.submit);
    expect(a(DocKind.quote), ComposerAction.sendQuoteWhatsApp);
    expect(a(DocKind.quote, phone: false), ComposerAction.sendQuote);
    expect(a(DocKind.taxInvoiceReceipt), ComposerAction.issueAndWhatsApp);
    expect(a(DocKind.taxInvoice, phone: false), ComposerAction.issue);
    expect(
      a(DocKind.taxInvoice, send: false),
      ComposerAction.issue,
      reason: 'no doc.send',
    );
  });

  test(
    'receipts and quotes never go to approval (BE-37); others ask the caps rule',
    () {
      expect(kindNeedsApproval(DocKind.receipt, () => true), isFalse);
      expect(kindNeedsApproval(DocKind.donationReceipt, () => true), isFalse);
      expect(kindNeedsApproval(DocKind.quote, () => true), isFalse);
      expect(kindNeedsApproval(DocKind.taxInvoice, () => true), isTrue);
      expect(kindNeedsApproval(DocKind.taxInvoice, () => false), isFalse);
    },
  );
}
