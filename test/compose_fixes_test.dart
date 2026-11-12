// QA 2026-11-12 (A1): Composer fixes that need no full flow – the decimal
// key and the fake phone in the (fixed) dark theme, the VAT line order,
// /tax-rates cache-first.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/compose/compose_memory.dart';
import 'package:invoice/screens/compose/fields/customer_chip.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/labels.dart';

import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;

  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('compose_fixes_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    resetSession();
    backend = FakeBackend()..install();
    await AppCache.clearAll();
  });

  Future<void> dark(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('dark theme (the app default): the keypad has a decimal point', (
    tester,
  ) async {
    final keys = <String>[];
    await dark(tester, Keypad(onKey: keys.add));
    await tester.tap(find.text('.'));
    expect(keys, ['.'], reason: '₪99.90 must be typeable');
  });

  testWidgets('dark theme: a customer without a phone shows no made-up phone', (
    tester,
  ) async {
    await dark(
      tester,
      CustomerChip(
        customer: const Customer(id: 'c1', name: 'דנה'),
        onTap: () {},
      ),
    );
    expect(find.text('דנה'), findsOneWidget);
    expect(find.textContaining('052'), findsNothing);
  });

  test('VAT line: "net + vat מע״מ = total", the Hebrew word isolated', () {
    final line = vatBreakdown(
      BigInt.from(1271),
      BigInt.from(229),
      BigInt.from(1500),
    );
    // Bare, "מע״מ" pulled "₪2.29 = ₪15" into its RTL run: ₪12.71 + ₪15 = ₪2.29 מע״מ.
    expect(line, '₪12.71 + ₪2.29 \u2067מע״מ\u2069 = ₪15');
  });

  test(
    '/tax-rates is cache-first: a slow server does not hold the Composer',
    () async {
      await signInAs(backend, Preset.owner);
      backend.json('GET', '/tax-rates', {
        'rates': [
          {'tax_code': 'VAT', 'rate_basis_points': 1700},
        ],
      });
      expect(await fetchVatRate(), 1700, reason: 'nothing cached: the server');

      final never = Completer<FakeResponse>();
      backend.on('GET', '/tax-rates', (_) => never.future);
      final rate = await fetchVatRate().timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
      expect(rate, 1700, reason: 'cached rate returned without waiting');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      never.complete(const FakeResponse(200, {'rates': []}));
      expect(
        backend.calls('GET', '/tax-rates'),
        hasLength(2),
        reason: 'refreshed in the background',
      );
    },
  );
}
