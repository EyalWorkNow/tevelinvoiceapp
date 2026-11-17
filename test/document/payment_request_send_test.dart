// בקשת תשלום (owner 2026-11-17): the payment link a sent 300 / 305 carries,
// and the WhatsApp text that carries it.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/compose_he.dart' show issueWhatsAppText;

import '../fakes/fake_api.dart';

DocumentDetail detail({
  String type = 'TRANSACTION_INVOICE',
  int paid = 0,
  String? voidedAt,
}) => DocumentDetail.fromJson(
  docDetailJson(id: 'pr-1', type: type, paid: paid, voidedAt: voidedAt),
);

void main() {
  late FakeBackend backend;
  late bool connected;
  late List<String> checkouts;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    connected = false;
    checkouts = [];
    merchantConnected = () async => connected;
    customerPaymentLink = (id) async {
      checkouts.add(id);
      return 'https://secure.cardcom.solutions/p/$id';
    };
  });

  group('paymentUrlForSend', () {
    test('open 300 → the business payment page', () async {
      await signInAs(backend, Preset.owner);
      expect(await paymentUrlForSend(detail()), 'https://pay.example/tevel');
      expect(checkouts, isEmpty);
    });

    test(
      'no own page + Cardcom connected → a checkout for the document',
      () async {
        await signInAs(
          backend,
          Preset.owner,
          profile: profileJson(paymentLinkUrl: null),
        );
        connected = true;
        expect(
          await paymentUrlForSend(detail()),
          'https://secure.cardcom.solutions/p/pr-1',
        );
        expect(checkouts, ['pr-1']);
      },
    );

    test('no page and no terminal → none (the text goes without)', () async {
      await signInAs(
        backend,
        Preset.owner,
        profile: profileJson(paymentLinkUrl: null),
      );
      expect(await paymentUrlForSend(detail()), isNull);
    });

    test('a gateway error never blocks the send', () async {
      await signInAs(
        backend,
        Preset.owner,
        profile: profileJson(paymentLinkUrl: null),
      );
      connected = true;
      customerPaymentLink = (_) async => throw StateError('down');
      expect(await paymentUrlForSend(detail()), isNull);
    });

    test(
      'nothing owed / not a demand for payment / cancelled → none',
      () async {
        await signInAs(backend, Preset.owner);
        expect(await paymentUrlForSend(detail(paid: 118000)), isNull);
        expect(await paymentUrlForSend(detail(type: 'RECEIPT')), isNull);
        expect(
          await paymentUrlForSend(detail(type: 'TAX_INVOICE_RECEIPT')),
          isNull,
        );
        expect(
          await paymentUrlForSend(detail(type: 'CREDIT_DOCUMENT')),
          isNull,
        );
        expect(
          await paymentUrlForSend(detail(voidedAt: '2026-11-17T00:00:00Z')),
          isNull,
        );
        // A 305 that is still open carries it too.
        expect(
          await paymentUrlForSend(detail(type: 'TAX_INVOICE')),
          'https://pay.example/tevel',
        );
      },
    );

    test('a viewer without payment.record never creates a checkout', () async {
      await signInAs(
        backend,
        Preset.viewer,
        profile: profileJson(paymentLinkUrl: null),
      );
      connected = true;
      expect(await paymentUrlForSend(detail()), isNull);
      expect(checkouts, isEmpty);
    });
  });

  test('after-issue WhatsApp text: "לתשלום" on its own line', () {
    final text = issueWhatsAppText(
      customerName: 'דנה',
      documentType: 'TRANSACTION_INVOICE',
      number: '12',
      totalMinor: BigInt.from(59000),
      link: 'https://invoice.test/d/t',
      businessName: 'סטודיו',
      paymentUrl: 'https://pay.example/tevel',
    );
    expect(text, contains('https://invoice.test/d/t'));
    expect(text, endsWith('\nלתשלום: https://pay.example/tevel'));
    expect(
      issueWhatsAppText(
        customerName: 'דנה',
        documentType: 'RECEIPT',
        number: '3',
        totalMinor: BigInt.from(59000),
        link: 'https://invoice.test/d/t',
        businessName: 'סטודיו',
      ),
      isNot(contains('לתשלום:')),
    );
  });

  test('S6 WhatsApp of an open 300 carries the payment page', () async {
    await signInAs(backend, Preset.owner);
    installActionsFakes(backend);
    final launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
    await sendDocumentWhatsApp(
      detail(),
      const Customer(id: 'cus-1', name: 'דנה', phone: '050-1234567'),
    );
    final text = launcher.last!.queryParameters['text']!;
    expect(text, contains('https://invoice.test/d/tok123'));
    expect(text, contains('לתשלום: https://pay.example/tevel'));
  });
}
