// Squad D widget tests: P (people list), P2 (customer / supplier card), S2
// (customer pick + new-customer page). SPEC-v2 §6.P, §6.P2, S2, §4.4, §7.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/customers_api.dart' show resetStatementProbe;
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart' show pdfSharer;
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/people/sheets/s2_customer.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/people_he.dart';

import 'fakes/fake_api.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

void main() {
  late FakeBackend backend;
  late Directory tmp;
  late FakeLauncher launcher;
  var taps = 0;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('people_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    resetSession();
    await AppCache.clearAll();
    backend = FakeBackend()..install();
    launcher = FakeLauncher()..install();
    taps = 0;
    pickContact = () async => null;
    resetStatementProbe();
  });

  tearDown(FakeLauncher.uninstall);

  Future<void> flush(WidgetTester tester, [int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    taps++;
    await tester.ensureVisible(f);
    await tester.tap(f);
    await flush(tester);
  }

  Future<void> pump(WidgetTester tester, Widget home,
      {Preset preset = Preset.owner, bool readGating = false}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await signInAs(backend, preset);
      if (readGating) {
        backend.json('GET', '/me', meJson(preset, readGating: true));
        await session.refreshBusiness();
      }
    });
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      home: home,
    ));
    await flush(tester);
  }

  List<Map<String, dynamic>> docs() => [
        {'id': 'd1', 'documentType': 'TAX_INVOICE', 'status': 'SENT', 'customerId': 'c1',
          'customerName': 'דנה', 'documentNumber': '7', 'issueDate': '2026-10-20',
          'totalMinor': '599000', 'balanceMinor': '599000', 'openMinor': '599000'},
      ];

  group('P · לקוחות', () {
    testWidgets('owner: chips הכל·חייבים·ספקים, "חייב לך", archived only in search', (tester) async {
      installPeopleFakes(backend,
          customers: [
            customerJson('c1', 'דנה', phone: '0501234567'),
            customerJson('c2', 'אבי'),
            customerJson('c3', 'ישן', archived: true),
          ],
          suppliers: [
            {'id': 's1', 'name': 'חשמל', 'tax_id': null, 'email': null, 'phone': null, 'archived_at': null}
          ],
          documents: docs());
      await pump(tester, const PeopleScreen());

      expect(find.text(PeopleHe.chipAll), findsOneWidget);
      expect(find.text(PeopleHe.chipDebtors), findsOneWidget);
      expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
      expect(find.byKey(const Key('person-c1')), findsOneWidget);
      expect(find.byKey(const Key('person-c3')), findsNothing, reason: 'archived: search only');
      expect(find.text(PeopleHe.owesYou), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing, reason: 'list screen: 0 primary');

      await tester.enterText(find.byKey(const Key('people-search')), 'ישן');
      await flush(tester);
      expect(find.byKey(const Key('person-c3')), findsOneWidget);
      expect(find.text(PeopleHe.archivedBadge), findsOneWidget);

      await tester.enterText(find.byKey(const Key('people-search')), '');
      await tap(tester, find.text(PeopleHe.chipDebtors));
      expect(find.byKey(const Key('person-c1')), findsOneWidget);
      expect(find.byKey(const Key('person-c2')), findsNothing);

      await tap(tester, find.text(PeopleHe.chipSuppliers));
      expect(find.byKey(const Key('supplier-s1')), findsOneWidget);
      expect(find.text(PeopleHe.addSupplier), findsOneWidget);
    });

    testWidgets('employee: no balances, no debtors chip; viewer: no "+ לקוח", no chips', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')], documents: docs());
      await pump(tester, const PeopleScreen(), preset: Preset.employee);
      expect(find.text(PeopleHe.owesYou), findsNothing);
      expect(find.text(PeopleHe.chipDebtors), findsNothing);
      expect(find.text(PeopleHe.chipSuppliers), findsOneWidget, reason: 'P0: expense:record');
      expect(find.text(PeopleHe.addCustomer), findsOneWidget);
      expect(backend.calls('GET', '/documents'), isEmpty, reason: 'no money call without money.view');
    });

    testWidgets('viewer (§4.4): balances yes, suppliers and "+ לקוח" no', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')], documents: docs());
      await pump(tester, const PeopleScreen(), preset: Preset.viewer);
      expect(find.text(PeopleHe.addCustomer), findsNothing);
      expect(find.text(PeopleHe.chipSuppliers), findsNothing);
      expect(find.text(PeopleHe.owesYou), findsOneWidget);
      expect(backend.calls('GET', '/suppliers'), isEmpty);
    });

    for (final preset in [Preset.employee, Preset.accountantRep]) {
      testWidgets('§4.4 read gating ($preset): suppliers chip + list; "+ ספק" stays supplier.manage',
          (tester) async {
        installPeopleFakes(backend,
            customers: [customerJson('c1', 'דנה')],
            suppliers: [
              {'id': 's1', 'name': 'חשמל', 'tax_id': null, 'email': null, 'phone': null, 'archived_at': null}
            ]);
        await pump(tester, const PeopleScreen(), preset: preset, readGating: true);
        expect(businessContext.can(Cap.supplierManage), isFalse, reason: 'gated: no supplier:manage');
        expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
        await tap(tester, find.text(PeopleHe.chipSuppliers));
        expect(find.byKey(const Key('supplier-s1')), findsOneWidget);
        expect(find.text(PeopleHe.addSupplier), findsNothing);
      });
    }

    testWidgets('capped open documents hide balances; 500 customers → "המשך במחשב" line', (tester) async {
      installPeopleFakes(backend,
          customers: [for (var i = 0; i < 500; i++) customerJson('c$i', 'לקוח $i')]);
      backend.json('GET', '/documents', {
        'total': 900,
        'documents': [
          {'id': 'x', 'documentType': 'TAX_INVOICE', 'status': 'SENT', 'customerId': 'c1',
            'totalMinor': '100', 'balanceMinor': '100'}
        ]
      });
      await pump(tester, const PeopleScreen());
      expect(find.text(PeopleHe.owesYou), findsNothing);
      expect(find.text(PeopleHe.chipDebtors), findsNothing);
      await tester.scrollUntilVisible(find.text(PeopleHe.capped500), 2000,
          scrollable: find.descendant(of: find.byKey(const Key('people-list')), matching: find.byType(Scrollable)));
      expect(find.text(PeopleHe.capped500), findsOneWidget);
    });

    testWidgets('empty → teaching sentence + "הוסף מאנשי הקשר" opens S2 page 2 with the picker',
        (tester) async {
      installPeopleFakes(backend);
      var picked = 0;
      pickContact = () async {
        picked++;
        return null;
      };
      await pump(tester, const PeopleScreen());
      expect(find.text(PeopleHe.emptyCustomers), findsOneWidget);
      await tap(tester, find.text(PeopleHe.emptyCustomersAction));
      // Under load the sheet + S2 page 2 + picker can need more frames.
      for (var i = 0; i < 20 && picked == 0; i++) {
        await flush(tester, 3);
      }
      expect(picked, 1);
      expect(find.text(PeopleHe.newCustomerTitle), findsOneWidget);
    });

    testWidgets('error → Hebrew message + נסה שוב; retry loads', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      backend.error('GET', '/customers', 500, 'INTERNAL');
      await pump(tester, const PeopleScreen());
      expect(find.text('נסה שוב'), findsOneWidget);
      backend.json('GET', '/customers', {'customers': [customerJson('c1', 'דנה')]});
      await tap(tester, find.text('נסה שוב'));
      expect(find.byKey(const Key('person-c1')), findsOneWidget);
    });
  });

  group('P2 · כרטיס', () {
    testWidgets('balance > 0 → ONE primary "בקש תשלום"; contact circles via wa.me / tel / mailto',
        (tester) async {
      installPeopleFakes(backend,
          customers: [customerJson('c1', 'דנה', phone: '050-1234567', email: 'd@x.co')], documents: docs());
      await pump(tester, const PersonScreen(id: 'c1'));
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.text('בקש תשלום'), findsOneWidget);
      expect(find.byKey(const Key('person-owes')), findsOneWidget);
      expect(find.byKey(const Key('person-doc-d1')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('person-doc-d1')), matching: find.textContaining('7')),
          findsWidgets, reason: 'title = type · number, not the date');

      await tap(tester, find.byKey(const Key('person-whatsapp')));
      expect(launcher.last.toString(), 'https://wa.me/972501234567');
      await tap(tester, find.byKey(const Key('person-call')));
      expect(launcher.last!.scheme, 'tel');
      await tap(tester, find.byKey(const Key('person-mail')));
      expect(launcher.last.toString(), 'mailto:d@x.co');

      await tap(tester, find.text('בקש תשלום'));
      final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
      expect(c.intent, 'REQUEST');
      expect(c.customerId, 'c1');
    });

    testWidgets('no balance → "מסמך חדש ל-X"; no phone → no call/WhatsApp circles', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(tester, const PersonScreen(id: 'c1'));
      expect(find.text(PeopleHe.newDocFor('דנה')), findsOneWidget);
      expect(find.byKey(const Key('person-whatsapp')), findsNothing);
      expect(find.byKey(const Key('person-call')), findsNothing);
      expect(find.text(PeopleHe.noDocuments), findsOneWidget);
    });

    testWidgets('⋯ "ארכב" with an open balance asks first, then archives', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')], documents: docs());
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(openPerson(navigatorKey.currentContext!, 'c1'));
      await flush(tester);
      await tap(tester, find.byIcon(Iconsax.more));
      await tap(tester, find.text(PeopleHe.archive));
      expect(find.textContaining('ללקוח יש'), findsOneWidget);
      expect(find.textContaining('5,990 פתוח'), findsNothing, reason: 'amount is an LTR isolate');
      expect(find.textContaining('₪5,990\u2069 פתוח'), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, PeopleHe.archive));
      expect(backend.calls('POST', '/customers/:id/archive'), hasLength(1));
      expect(find.text('root'), findsOneWidget, reason: 'card closes');
    });

    testWidgets('employee: no ⋯, no "פרטים ועריכה", no balance', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')], documents: docs());
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.employee);
      expect(find.byIcon(Iconsax.more), findsNothing);
      expect(find.byKey(const Key('person-edit')), findsNothing);
      expect(find.byKey(const Key('person-owes')), findsNothing);
      expect(find.text(PeopleHe.newDocFor('דנה')), findsOneWidget);
    });

    testWidgets('viewer: no primary button at all (hidden, not disabled)', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.viewer);
      expect(find.byType(PrimaryButton), findsNothing);
    });

    testWidgets('"פרטים ועריכה" (BE-09): S2 edit form PATCHes only changes incl. payment terms',
        (tester) async {
      installPeopleFakes(backend,
          customers: [customerJson('c1', 'דנה', phone: '0501234567', be09: true)], be09: true);
      await pump(tester, const PersonScreen(id: 'c1'));
      await tap(tester, find.byKey(const Key('person-edit')));
      expect(find.text(PeopleHe.editTitle), findsWidgets);
      await tester.enterText(find.byKey(const Key('s2-email')), 'dana@x.co');
      await tap(tester, find.text('שוטף+60'));
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(backend.last('PATCH', '/customers/:id')!.body,
          {'email': 'dana@x.co', 'paymentTerms': 'EOM_60'});
    });

    testWidgets('supplier card: badge "ספק", primary "הוצאה חדשה מ-X"', (tester) async {
      installPeopleFakes(backend, suppliers: [
        {'id': 's1', 'name': 'חשמל', 'tax_id': null, 'email': null, 'phone': '036000000', 'archived_at': null}
      ]);
      await pump(tester, const PersonScreen(id: 's1', isSupplier: true));
      expect(find.text(PeopleHe.supplierBadge), findsOneWidget);
      expect(find.text(PeopleHe.newExpenseFrom('חשמל')), findsOneWidget);
      expect(find.byKey(const Key('person-call')), findsOneWidget);
      expect(find.byKey(const Key('person-edit')), findsNothing, reason: 'no BE-16: read-only card');
      expect(find.byIcon(Iconsax.more), findsNothing);
    });

    testWidgets('J11 (AT-28, BE-17): לקוחות → לקוח → "שלח כרטסת" = 3 taps; e-mailed for this year',
        (tester) async {
      installPeopleFakes(backend,
          customers: [customerJson('c1', 'דנה', email: 'd@x.co')], documents: docs(), be17: true);
      await pump(tester, const PeopleScreen());
      taps = 1; // (1) the "לקוחות" tab
      await tap(tester, find.byKey(const Key('person-c1')));
      expect(find.byKey(const Key('person-statement')), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget, reason: 'statement is a row, not a 2nd primary');
      await tap(tester, find.byKey(const Key('person-statement')));
      expect(taps, lessThanOrEqualTo(3));
      final body = backend.last('POST', '/customers/:id/statement/send')!.body;
      expect(body['channel'], 'EMAIL');
      expect(body['from'], '${DateTime.now().year}-01-01');
      expect(find.text(PeopleHe.statementSent('d@x.co')), findsOneWidget);
    });

    testWidgets('BE-17: no e-mail or accountant (no send) → statement PDF to the share sheet; '
        'no BE-17 → no row', (tester) async {
      String? shared;
      final old = pdfSharer;
      pdfSharer = (bytes, name, {text}) async => shared = name;
      addTearDown(() => pdfSharer = old);

      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה', email: 'd@x.co')], be17: true);
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.accountantRep);
      expect(find.byKey(const Key('person-edit')), findsNothing, reason: 'rep: statement only (§4.4)');
      await tap(tester, find.byKey(const Key('person-statement')));
      expect(backend.calls('POST', '/customers/:id/statement/send'), isEmpty);
      expect(shared, 'כרטסת דנה.pdf');
    });

    testWidgets('no BE-17 on the server → "שלח כרטסת" hidden (F5); employee never sees it', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה', email: 'd@x.co')]);
      await pump(tester, const PersonScreen(id: 'c1'));
      expect(find.byKey(const Key('person-edit')), findsOneWidget);
      expect(find.byKey(const Key('person-statement')), findsNothing);
    });

    testWidgets('BE-09 edit: address (city required), consent switch while not given', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה', be09: true)], be09: true);
      await pump(tester, const PersonScreen(id: 'c1'));
      await tap(tester, find.byKey(const Key('person-edit')));
      expect(find.byKey(const Key('s2-accountkey')), findsNothing, reason: 'BE-04 cap only');
      await tester.enterText(find.byKey(const Key('s2-street')), 'הרצל');
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(find.text(PeopleHe.cityRequired), findsOneWidget);
      expect(backend.calls('PATCH', '/customers/:id'), isEmpty);

      await tester.enterText(find.byKey(const Key('s2-house')), '5');
      await tester.enterText(find.byKey(const Key('s2-city')), 'תל אביב');
      await tap(tester, find.byKey(const Key('s2-consent')));
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(backend.last('PATCH', '/customers/:id')!.body, {
        'address': {'street': 'הרצל', 'number': '5', 'city': 'תל אביב', 'postalCode': null},
      });
      expect(backend.calls('POST', '/customers/:id/consent'), hasLength(1));
    });

    testWidgets('supplier card with BE-16: "פרטים ועריכה" PATCHes the change; ⋯ "ארכב"', (tester) async {
      installPeopleFakes(backend, be16: true, suppliers: [
        {'id': 's1', 'name': 'חשמל', 'tax_id': null, 'email': null, 'phone': null, 'archived_at': null}
      ]);
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(openPerson(navigatorKey.currentContext!, 's1', supplier: true));
      await flush(tester);
      await tap(tester, find.byKey(const Key('person-edit')));
      expect(find.byKey(const Key('s2-consent')), findsNothing);
      await tester.enterText(find.byKey(const Key('s2-phone')), '03-6000000');
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(backend.last('PATCH', '/suppliers/:id')!.body, {'phone': '036000000'});

      await tap(tester, find.byIcon(Iconsax.more));
      await tap(tester, find.text(PeopleHe.archive));
      expect(find.text(PeopleHe.supplierArchiveConfirm), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, PeopleHe.archive));
      expect(backend.calls('POST', '/suppliers/:id/archive'), hasLength(1));
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('unknown customer → error + retry', (tester) async {
      installPeopleFakes(backend);
      await pump(tester, const PersonScreen(id: 'zz'));
      expect(find.text('נסה שוב'), findsOneWidget);
    });
  });

  group('S2 · לקוח', () {
    testWidgets('pick: a tap returns the customer at once (auto-advance)', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה'), customerJson('c2', 'אבי')]);
      Customer? picked;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!).then((c) => picked = c));
      await flush(tester);
      expect(find.text(PeopleHe.walkIn), findsOneWidget);
      expect(find.text(PeopleHe.walkInHint), findsOneWidget);
      await tap(tester, find.byKey(const Key('s2-row-c1')));
      expect(picked?.id, 'c1');
      expect(taps, 1);
    });

    testWidgets('J1-new inside S2: "+ לקוח חדש" → contact → "שמור" = 3 taps; consent switch → consent call',
        (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'אבי')]);
      pickContact = () async {
        taps++; // the contact row tapped in the system picker counts (F3.1)
        return const PickedContact(name: 'דנה לוי', phones: ['03-5551234', '052-111-2222']);
      };
      Customer? created;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!).then((c) => created = c));
      await flush(tester);
      await tap(tester, find.byKey(const Key('s2-new')));
      expect(find.text('דנה לוי'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(taps, 3);
      expect(created?.name, 'דנה לוי');
      final body = backend.last('POST', '/customers')!.body;
      expect(body['phone'], '0521112222');
      expect(body['customerType'], 'INDIVIDUAL');
      expect(body.containsKey('vatDealerStatus'), isFalse);
      expect(backend.calls('POST', '/customers/:id/consent'), isEmpty, reason: 'switch off by default');
    });

    testWidgets('consent switch on → POST consent; tax id → BUSINESS', (tester) async {
      installPeopleFakes(backend);
      Customer? created;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!, startOnNew: true).then((c) => created = c));
      await flush(tester);
      await tester.enterText(find.byKey(const Key('s2-name')), 'מוסך');
      await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
      await tap(tester, find.byKey(const Key('s2-consent')));
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(backend.last('POST', '/customers')!.body['customerType'], 'BUSINESS');
      expect(backend.calls('POST', '/customers/:id/consent'), hasLength(1));
      expect(created?.consentGranted, isTrue);
    });

    testWidgets('validation: no name → "צריך שם"; bad tax id → check digit message; nothing sent',
        (tester) async {
      installPeopleFakes(backend);
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!, startOnNew: true));
      await flush(tester);
      await tester.enterText(find.byKey(const Key('s2-taxid')), '123');
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(find.text(PeopleHe.nameRequired), findsOneWidget);
      expect(find.text(PeopleHe.taxIdInvalid), findsOneWidget);
      expect(backend.calls('POST', '/customers'), isEmpty);
    });

    testWidgets('duplicate phone → "כבר קיים: X · השתמש בו" returns the existing one', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה', phone: '0521112222')]);
      pickContact = () async => const PickedContact(name: 'דנה ל.', phones: ['+972 52-111-2222']);
      Customer? result;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!).then((c) => result = c));
      await flush(tester);
      await tap(tester, find.byKey(const Key('s2-new')));
      expect(find.byKey(const Key('s2-duplicate')), findsOneWidget);
      expect(find.text(PeopleHe.alreadyExists('דנה')), findsOneWidget);
      await tap(tester, find.text(PeopleHe.useExisting));
      expect(result?.id, 'c1');
      expect(backend.calls('POST', '/customers'), isEmpty);
    });

    testWidgets('"לקוח מזדמן" creates one INDIVIDUAL record and returns it', (tester) async {
      installPeopleFakes(backend);
      Customer? result;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showCustomerSheet(navigatorKey.currentContext!).then((c) => result = c));
      await flush(tester);
      await tap(tester, find.byKey(const Key('s2-walkin')));
      expect(result?.name, PeopleHe.walkIn);
      expect(backend.last('POST', '/customers')!.body['customerType'], 'INDIVIDUAL');
    });

    testWidgets('supplier mode: lists suppliers, new supplier → POST /suppliers, no consent switch',
        (tester) async {
      installPeopleFakes(backend, suppliers: [
        {'id': 's1', 'name': 'חשמל', 'tax_id': null, 'email': null, 'phone': null, 'archived_at': null}
      ]);
      Supplier? result;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(showSupplierSheet(navigatorKey.currentContext!).then((s) => result = s));
      await flush(tester);
      expect(find.byKey(const Key('s2-row-s1')), findsOneWidget);
      expect(find.text(PeopleHe.walkIn), findsNothing);
      await tap(tester, find.byKey(const Key('s2-new')));
      expect(find.byKey(const Key('s2-consent')), findsNothing);
      await tester.enterText(find.byKey(const Key('s2-name')), 'דלק');
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(result?.name, 'דלק');
      expect(backend.calls('POST', '/suppliers'), hasLength(1));
    });

    testWidgets('viewer: no "+ לקוח חדש" and no walk-in', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(tester, const Scaffold(body: Text('root')), preset: Preset.viewer);
      unawaited(showCustomerSheet(navigatorKey.currentContext!));
      await flush(tester);
      expect(find.byKey(const Key('s2-new')), findsNothing);
      expect(find.byKey(const Key('s2-walkin')), findsNothing);
      expect(find.byKey(const Key('s2-row-c1')), findsOneWidget);
    });

  });
}

