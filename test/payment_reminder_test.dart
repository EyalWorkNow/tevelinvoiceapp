// R1 one-tap WhatsApp payment reminder: message builder (RTL/LTR isolation,
// phone → wa.me 972…), button visibility per status + caps, the no-phone
// fallback and the device-local "last reminded" hint.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/screens/home/inbox_cards.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/labels/reminder_he.dart';
import 'package:invoice/util/payment_reminder.dart';
import 'package:invoice/util/status_map.dart';

import 'fakes/fake_api.dart';

const lri = '\u2066', fsi = '\u2068', pdi = '\u2069';

Caps capsOf(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));

DocumentSummary row(
  String id, {
  String type = 'TAX_INVOICE',
  String status = 'ARCHIVED',
  int? open = 118000,
  String? voidedAt,
}) => DocumentSummary.fromJson(
  docJson(
    id,
    type: type,
    status: status,
    open: open,
    number: '10$id',
    voidedAt: voidedAt,
    issueDate: '2026-09-01',
  ),
);

bool gate(DocumentSummary d, Caps caps) => mayRemindOnWhatsApp(
  documentType: d.documentType,
  status: d.status,
  totalMinor: d.totalMinor,
  openMinor: d.openMinor,
  creditedMinor: d.creditedMinor,
  voidedAt: d.voidedAt,
  amountHidden: d.amountHidden,
  caps: caps,
);

void main() {
  late Directory tmp;
  late FakeBackend backend;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('payment_reminder_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    await AppCache.clearAll();
  });

  group('message builder', () {
    final text = ReminderHe.message(
      customerName: 'Dana Ltd',
      documentType: 'TAX_INVOICE',
      documentNumber: '1024',
      amountMinor: BigInt.from(118000),
      dueDate: '2026-11-12',
      business: 'סטודיו תבל',
      link: 'https://invoice.test/d/tok',
    );

    test('business, type + number, amount, due date and link', () {
      expect(text, contains('סטודיו תבל'));
      expect(text, contains('חשבונית מס'));
      expect(text, contains('1024'));
      expect(text, contains('₪1,180'));
      expect(text, contains('12.11.2026'));
      expect(text, contains('https://invoice.test/d/tok'));
    });

    test('numbers, amount and date are LTR-isolated; names first-strong', () {
      expect(text, contains("מס׳ ${lri}1024$pdi"));
      expect(text, contains('$lri₪1,180$pdi'));
      expect(text, contains('${lri}12.11.2026$pdi'));
      expect(text, contains('${fsi}Dana Ltd$pdi'));
      expect(text, contains('$fsiסטודיו תבל$pdi'));
    });

    test('the link stands alone on its own line, never isolated', () {
      expect(text.split('\n'), contains('https://invoice.test/d/tok'));
    });

    test('no number / due date / name → no empty fragments', () {
      final t = ReminderHe.message(
        documentType: 'TRANSACTION_INVOICE',
        amountMinor: BigInt.from(5050),
        business: 'B',
        link: 'L',
      );
      expect(t, startsWith('שלום,'));
      expect(t, isNot(contains('מס׳')));
      expect(t, isNot(contains('לתשלום עד')));
      expect(t, contains('$lri₪50.50$pdi'));
    });

    test('short text (share sheet) keeps type, number, amount and link', () {
      final t = ReminderHe.short(
        documentType: 'TAX_INVOICE',
        documentNumber: '7',
        amountMinor: BigInt.from(30000),
        business: 'B',
        link: 'https://x/d/1',
      );
      expect(t, contains('${lri}7$pdi'));
      expect(t, contains('$lri₪300$pdi'));
      expect(t, endsWith('\nhttps://x/d/1'));
      expect(t.length, lessThan(120));
    });

    test('last reminded: today / yesterday / N days', () {
      expect(ReminderHe.lastReminded(0), 'נשלחה תזכורת היום');
      expect(ReminderHe.lastReminded(1), 'נשלחה תזכורת אתמול');
      expect(ReminderHe.lastReminded(4), 'נשלחה תזכורת לפני 4 ימים');
      expect(
        daysSince(DateTime(2026, 11, 8, 23, 50), DateTime(2026, 11, 12, 0, 5)),
        4,
      );
    });

    test('due date: dueDate, else issue + 30 calendar days', () {
      expect(
        effectiveDueDate(dueDate: '2026-12-01', issueDate: '2026-01-01'),
        '2026-12-01',
      );
      expect(effectiveDueDate(issueDate: '2026-10-20'), '2026-11-19');
      expect(effectiveDueDate(), isNull);
    });
  });

  group('button visibility (status + caps)', () {
    final owner = capsOf(Preset.owner);
    final viewer = capsOf(Preset.viewer);

    test('precondition: owner may send, viewer may not', () {
      expect(owner.can(Cap.docSend), isTrue);
      expect(viewer.can(Cap.docSend), isFalse);
    });

    test('only unpaid issued invoices', () {
      expect(gate(row('a'), owner), isTrue);
      expect(gate(row('b', type: 'TRANSACTION_INVOICE'), owner), isTrue);
      expect(gate(row('c', open: 0), owner), isFalse, reason: 'paid');
      expect(gate(row('d', status: 'DRAFT'), owner), isFalse);
      expect(gate(row('e', type: 'RECEIPT'), owner), isFalse);
      expect(gate(row('f', type: 'TAX_INVOICE_RECEIPT'), owner), isFalse);
      expect(
        gate(row('g', voidedAt: '2026-11-01T00:00:00Z'), owner),
        isFalse,
        reason: 'voided',
      );
      expect(gate(row('h', status: 'PENDING_APPROVAL'), owner), isFalse);
    });

    test('gated by doc.send', () {
      expect(gate(row('a'), viewer), isFalse);
      expect(gate(row('a'), capsOf(Preset.accountantRep)), isFalse);
    });
  });

  group('send flow (user tap only)', () {
    late FakeLauncher launcher;
    late List<String> shared;

    setUp(() {
      launcher = FakeLauncher()..install();
      shared = [];
      textSharer = (t) async => shared.add(t);
    });
    tearDown(FakeLauncher.uninstall);

    Future<void> send(String? phone) => sendPaymentReminder(
      documentId: 'd1',
      documentType: 'TAX_INVOICE',
      documentNumber: '1024',
      openMinor: BigInt.from(118000),
      dueDate: '2026-11-12',
      customerName: 'דנה',
      phone: phone,
      link: () async => 'https://invoice.test/d/tok',
      now: DateTime(2026, 11, 12, 9),
    );

    for (final (raw, wa) in [
      ('050-123-4567', '972501234567'),
      ('+972 50 1234567', '972501234567'),
      ('00972-50-123-4567', '972501234567'),
      ('+972 (0)50 1234567', '972501234567'),
      ('03-5551234', '97235551234'),
    ]) {
      test('phone "$raw" → wa.me/$wa with the full text', () async {
        await send(raw);
        final url = launcher.last.toString();
        expect(url, startsWith('https://wa.me/$wa?text='));
        final text = Uri.parse(url).queryParameters['text']!;
        expect(text, contains('https://invoice.test/d/tok'));
        expect(text, contains('${lri}12.11.2026$pdi'));
        expect(shared, isEmpty);
      });
    }

    test('no / unusable phone → share sheet with the short text', () async {
      await send(null);
      await send('12');
      expect(launcher.opened, isEmpty);
      expect(shared, hasLength(2));
      expect(shared.first, contains('https://invoice.test/d/tok'));
    });

    test('WhatsApp did not open → share sheet', () async {
      launcher.result = false;
      await send('0501234567');
      expect(launcher.opened, hasLength(1));
      expect(shared, hasLength(1));
    });

    test('records "last reminded" on this device', () async {
      expect(await ReminderLog.lastFor('d1'), isNull);
      await send('0501234567');
      expect(await ReminderLog.lastFor('d1'), DateTime(2026, 11, 12, 9));
      expect((await ReminderLog.all()).keys, ['d1']);
    });
  });

  group('overdue list', () {
    Future<void> pumpPreview(
      WidgetTester tester,
      Preset preset,
      List<DocumentSummary> docs, {
      Map<String, DateTime> reminded = const {},
    }) async {
      await tester.runAsync(() => signInAs(backend, preset));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showReminderPreview(
                context,
                docs,
                reminded: Future.value(reminded),
                now: DateTime(2026, 11, 12, 12),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a WhatsApp button on each row the owner may remind', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        Preset.owner,
        [row('1'), row('2')],
        reminded: {'2': DateTime(2026, 11, 9, 10)},
      );
      expect(find.byKey(const Key('reminder-wa-1')), findsOneWidget);
      expect(find.byKey(const Key('reminder-wa-2')), findsOneWidget);
      expect(find.textContaining('נשלחה תזכורת לפני 3 ימים'), findsOneWidget);
    });

    testWidgets('no WhatsApp button without doc.send', (tester) async {
      await pumpPreview(tester, Preset.viewer, [row('1')]);
      expect(find.byKey(const Key('reminder-1')), findsOneWidget);
      expect(find.byKey(const Key('reminder-wa-1')), findsNothing);
    });

    testWidgets('tap → wa.me for that row, then the hint shows', (
      tester,
    ) async {
      final launcher = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      backend
        ..json('GET', '/customers', {
          'customers': [
            {'id': 'c1', 'name': 'דנה כהן', 'phone': '0501234567'},
          ],
        })
        ..json('GET', '/customers/:id', {
          'customer': {'id': 'c1', 'name': 'דנה כהן', 'phone': '0501234567'},
        })
        ..json('POST', '/documents/:id/share-link', {
          'url': 'https://invoice.test/d/tok',
        });
      await pumpPreview(tester, Preset.owner, [row('1')]);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('reminder-wa-1')));
        for (var i = 0; i < 40 && launcher.opened.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        launcher.last.toString(),
        startsWith('https://wa.me/972501234567'),
      );
      expect(find.textContaining('נשלחה תזכורת היום'), findsOneWidget);
    });
  });
}
