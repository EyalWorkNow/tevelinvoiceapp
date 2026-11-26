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
import 'package:invoice/screens/compose/payment_request_screen.dart';
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
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    taps++;
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      await flush(tester, 3);
    }
    await tester.ensureVisible(f);
    await tester.tap(f);
    await flush(tester);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Preset preset = Preset.owner,
    bool readGating = false,
    Brightness brightness = Brightness.light,
  }) async {
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
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(brightness),
        home: home,
      ),
    );
    await flush(tester);
  }

  List<Map<String, dynamic>> docs() => [
    {
      'id': 'd1',
      'documentType': 'TAX_INVOICE',
      'status': 'SENT',
      'customerId': 'c1',
      'customerName': 'דנה',
      'documentNumber': '7',
      'issueDate': '2026-10-20',
      'totalMinor': '599000',
      'balanceMinor': '599000',
      'openMinor': '599000',
    },
  ];

  group('P · לקוחות', () {
    testWidgets(
      'owner: chips פעילים·לא פעילים·הכול·חייבים·ספקים, "חייב לך", inactive only in search',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [
            customerJson('c1', 'דנה', phone: '0501234567'),
            customerJson('c2', 'אבי'),
            customerJson('c3', 'ישן', archived: true),
          ],
          suppliers: [
            {
              'id': 's1',
              'name': 'חשמל',
              'tax_id': null,
              'email': null,
              'phone': null,
              'archived_at': null,
            },
          ],
          documents: docs(),
        );
        await pump(tester, const PeopleScreen());

        for (
          var i = 0;
          i < 20 &&
              (find.text(PeopleHe.chipDebtors).evaluate().isEmpty ||
                  find.text(PeopleHe.chipActive(2)).evaluate().isEmpty);
          i++
        ) {
          await flush(tester, 3);
        }
        expect(find.text(PeopleHe.chipActive(2)), findsOneWidget);
        expect(find.text(PeopleHe.chipInactive(1)), findsOneWidget);
        expect(find.text(PeopleHe.chipAllCustomers(3)), findsOneWidget);
        expect(find.text(PeopleHe.chipDebtors), findsOneWidget);
        expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
        expect(find.byKey(const Key('person-c1')), findsOneWidget);
        expect(
          find.byKey(const Key('person-c3')),
          findsNothing,
          reason: 'archived: search only',
        );
        expect(find.text(PeopleHe.owesYou), findsOneWidget);
        expect(
          find.byType(PrimaryButton),
          findsNothing,
          reason: 'list screen: 0 primary',
        );

        await tester.enterText(find.byKey(const Key('people-search')), 'ישן');
        await flush(tester);
        expect(find.byKey(const Key('person-c3')), findsOneWidget);
        expect(find.text(PeopleHe.inactiveBadge), findsOneWidget);

        await tester.enterText(find.byKey(const Key('people-search')), '');
        await tap(tester, find.text(PeopleHe.chipDebtors));
        expect(find.byKey(const Key('person-c1')), findsOneWidget);
        expect(find.byKey(const Key('person-c2')), findsNothing);

        await tap(tester, find.text(PeopleHe.chipSuppliers));
        expect(find.byKey(const Key('supplier-s1')), findsOneWidget);
        expect(find.text(PeopleHe.addSupplier), findsOneWidget);
      },
    );

    testWidgets('2611 §4: chips filter פעילים / לא פעילים / הכול with counts', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [
          customerJson('c1', 'דנה'),
          customerJson('c2', 'אבי'),
          customerJson('c3', 'ישן', archived: true),
        ],
      );
      await pump(tester, const PeopleScreen());
      expect(find.byKey(const Key('person-c3')), findsNothing);
      await tap(tester, find.text(PeopleHe.chipInactive(1)));
      expect(find.byKey(const Key('person-c3')), findsOneWidget);
      expect(find.byKey(const Key('person-c1')), findsNothing);
      await tap(tester, find.text(PeopleHe.chipAllCustomers(3)));
      for (final id in ['c1', 'c2', 'c3']) {
        expect(find.byKey(Key('person-$id')), findsOneWidget);
      }
      // The server's counts win (more than the 500 rows on the phone).
      backend.json('GET', '/customers', {
        'customers': [customerJson('c1', 'דנה')],
        'total': 1,
        'counts': {'active': 640, 'inactive': 12, 'all': 652},
      });
      await tester.pumpWidget(const SizedBox());
      await pump(tester, const PeopleScreen());
      for (
        var i = 0;
        i < 20 && find.text(PeopleHe.chipActive(640)).evaluate().isEmpty;
        i++
      ) {
        await flush(tester, 3);
      }
      expect(find.text(PeopleHe.chipActive(640)), findsOneWidget);
      expect(find.text(PeopleHe.chipInactive(12)), findsOneWidget);
    });

    testWidgets(
      'employee: no balances, no debtors chip; viewer: no "+ לקוח", no chips',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה')],
          documents: docs(),
        );
        await pump(tester, const PeopleScreen(), preset: Preset.employee);
        expect(find.text(PeopleHe.owesYou), findsNothing);
        expect(find.text(PeopleHe.chipDebtors), findsNothing);
        expect(
          find.text(PeopleHe.chipSuppliers),
          findsOneWidget,
          reason: 'P0: expense:record',
        );
        expect(find.text(PeopleHe.addCustomer), findsOneWidget);
        expect(
          backend.calls('GET', '/documents'),
          isEmpty,
          reason: 'no money call without money.view',
        );
      },
    );

    testWidgets('viewer (§4.4): balances yes, suppliers and "+ לקוח" no', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה')],
        documents: docs(),
      );
      await pump(tester, const PeopleScreen(), preset: Preset.viewer);
      expect(find.text(PeopleHe.addCustomer), findsNothing);
      expect(find.text(PeopleHe.chipSuppliers), findsNothing);
      expect(find.text(PeopleHe.owesYou), findsOneWidget);
      expect(backend.calls('GET', '/suppliers'), isEmpty);
    });

    for (final preset in [Preset.employee, Preset.accountantRep]) {
      testWidgets(
        '§4.4 read gating ($preset): suppliers chip + list; "+ ספק" stays supplier.manage',
        (tester) async {
          installPeopleFakes(
            backend,
            customers: [customerJson('c1', 'דנה')],
            suppliers: [
              {
                'id': 's1',
                'name': 'חשמל',
                'tax_id': null,
                'email': null,
                'phone': null,
                'archived_at': null,
              },
            ],
          );
          await pump(
            tester,
            const PeopleScreen(),
            preset: preset,
            readGating: true,
          );
          expect(
            businessContext.can(Cap.supplierManage),
            isFalse,
            reason: 'gated: no supplier:manage',
          );
          expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
          await tap(tester, find.text(PeopleHe.chipSuppliers));
          expect(find.byKey(const Key('supplier-s1')), findsOneWidget);
          expect(find.text(PeopleHe.addSupplier), findsNothing);
        },
      );
    }

    testWidgets(
      'capped open documents hide balances; 500 customers → "המשך במחשב" line',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [
            for (var i = 0; i < 500; i++) customerJson('c$i', 'לקוח $i'),
          ],
        );
        backend.json('GET', '/documents', {
          'total': 900,
          'documents': [
            {
              'id': 'x',
              'documentType': 'TAX_INVOICE',
              'status': 'SENT',
              'customerId': 'c1',
              'totalMinor': '100',
              'balanceMinor': '100',
            },
          ],
        });
        await pump(tester, const PeopleScreen());
        expect(find.text(PeopleHe.owesYou), findsNothing);
        expect(find.text(PeopleHe.chipDebtors), findsNothing);
        await tester.scrollUntilVisible(
          find.text(PeopleHe.capped500),
          2000,
          scrollable: find.descendant(
            of: find.byKey(const Key('people-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text(PeopleHe.capped500), findsOneWidget);
      },
    );

    testWidgets('empty → new customer form; contact import is explicit', (
      tester,
    ) async {
      installPeopleFakes(backend);
      var picked = 0;
      pickContact = () async {
        picked++;
        return null;
      };
      await pump(tester, const PeopleScreen());
      expect(find.text(PeopleHe.emptyCustomers), findsOneWidget);
      await tap(tester, find.text(PeopleHe.emptyCustomersAction));
      expect(picked, 0, reason: 'contact access is an explicit action');
      await tap(tester, find.byKey(const Key('s2-import-contact')));
      // Under load the sheet + S2 page 2 + picker can need more frames.
      for (var i = 0; i < 20 && picked == 0; i++) {
        await flush(tester, 3);
      }
      expect(picked, 1);
      expect(find.text(PeopleHe.newCustomerTitle), findsOneWidget);
    });

    testWidgets('error → Hebrew message + נסה שוב; retry loads', (
      tester,
    ) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      backend.error('GET', '/customers', 500, 'INTERNAL');
      await pump(tester, const PeopleScreen());
      expect(find.text('נסה שוב'), findsOneWidget);
      backend.json('GET', '/customers', {
        'customers': [customerJson('c1', 'דנה')],
      });
      await tap(tester, find.text('נסה שוב'));
      expect(find.byKey(const Key('person-c1')), findsOneWidget);
    });
  });

  group('P2 · כרטיס', () {
    /// The quick-action orbs, in order ('person-action-<id>' → id).
    List<String> orbs(WidgetTester tester) => [
      for (final w in tester.widgetList<ActionOrb>(find.byType(ActionOrb)))
        if ((w.key as ValueKey<String>?)?.value case final String k
            when k.startsWith('person-action-'))
          k.substring('person-action-'.length),
    ];

    Future<void> more(WidgetTester tester, String id) async {
      await tap(tester, find.byKey(const Key('person-action-more')));
      await tap(tester, find.byKey(Key('person-more-$id')));
    }

    Finder headerMenu() => find.descendant(
      of: find.byType(MoreMenu),
      matching: find.byType(IconButton),
    );

    /// "פרטים ועריכה" lives in the header ⋯ (2611 #11).
    Future<void> edit(WidgetTester tester) async {
      await tap(tester, headerMenu());
      await tap(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('פרטים ועריכה'),
        ),
      );
    }

    testWidgets(
      'balance > 0 → "בקשת תשלום" 3rd after call / WhatsApp; wa.me / tel / mailto',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [
            customerJson('c1', 'דנה', phone: '050-1234567', email: 'd@x.co'),
          ],
          documents: docs(),
        );
        await pump(tester, const PersonScreen(id: 'c1'));
        expect(find.byType(PrimaryButton), findsNothing, reason: 'no bar');
        expect(orbs(tester), [
          'call',
          'whatsapp',
          'payment-request',
          'book',
          'paid',
          'invoice',
          'more',
        ]);
        expect(find.byKey(const Key('person-owes')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('person-doc-d1')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(RefreshIndicator),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('person-doc-d1')),
            matching: find.textContaining('7'),
          ),
          findsWidgets,
          reason: 'title = type · number, not the date',
        );
        await tap(tester, find.byKey(const Key('person-action-whatsapp')));
        expect(launcher.last.toString(), 'https://wa.me/972501234567');
        await tap(tester, find.byKey(const Key('person-action-call')));
        expect(launcher.last!.scheme, 'tel');
        await more(tester, 'email');
        expect(launcher.last.toString(), 'mailto:d@x.co');

        // Owner 2026-11-18: the short payment-request form, for this customer.
        await tap(
          tester,
          find.byKey(const Key('person-action-payment-request')),
        );
        final c = tester.widget<PaymentRequestScreen>(
          find.byType(PaymentRequestScreen),
        );
        expect(c.customerId, 'c1');
      },
    );

    testWidgets(
      'no balance → "חשבונית" 3rd, "הצעת מחיר" 6th; no phone and no e-mail → '
      'one "הוספת טלפון" orb that opens the edit form',
      (tester) async {
        installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
        await pump(tester, const PersonScreen(id: 'c1'));
        expect(orbs(tester), [
          'add-phone',
          'invoice',
          'book',
          'paid',
          'quote',
          'more',
        ]);
        expect(find.text(PeopleHe.noDocuments), findsNothing);
        expect(find.text('עוד אין מסמכים'), findsWidgets);
        expect(find.byKey(const Key('person-first-invoice')), findsOneWidget);
        await tap(tester, find.byKey(const Key('person-action-add-phone')));
        expect(find.text(PeopleHe.editTitle), findsWidgets);
      },
    );

    testWidgets(
      '⋯ "סמן כלא פעיל" with an open balance asks first, then marks',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה')],
          documents: docs(),
        );
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(openPerson(navigatorKey.currentContext!, 'c1'));
        await flush(tester);
        await tap(tester, headerMenu());
        await tap(tester, find.text(PeopleHe.markInactive));
        expect(find.text(PeopleHe.markInactiveConfirm), findsOneWidget);
        expect(find.textContaining('ללקוח יתרה של'), findsOneWidget);
        expect(
          find.textContaining('₪5,990\u2069, התזכורות ימשיכו'),
          findsOneWidget,
          reason: 'amount is an LTR isolate',
        );
        await tap(
          tester,
          find.widgetWithText(TextButton, PeopleHe.markInactive),
        );
        expect(backend.calls('POST', '/customers/:id/archive'), hasLength(1));
        expect(find.text('root'), findsOneWidget, reason: 'card closes');
      },
    );

    testWidgets(
      '2611 §4: an inactive customer — grey strip "לקוח לא פעיל · החזר לפעיל"',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', archived: true, be09: true)],
          be09: true,
        );
        await pump(tester, const PersonScreen(id: 'c1'));
        expect(find.byKey(const Key('person-inactive-banner')), findsOneWidget);
        expect(find.text(PeopleHe.inactiveBanner), findsOneWidget);
        expect(find.text(PeopleHe.inactiveBadge), findsOneWidget);
        await tap(tester, find.byKey(const Key('person-restore')));
        expect(backend.calls('POST', '/customers/:id/restore'), hasLength(1));
        expect(find.text(PeopleHe.restored), findsOneWidget);
        expect(
          find.byKey(const Key('person-inactive-banner')),
          findsNothing,
          reason: 'reloaded: active again',
        );
      },
    );

    testWidgets('2611 §4: an employee sees the strip but cannot restore', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה', archived: true, be09: true)],
        be09: true,
      );
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.employee);
      expect(find.byKey(const Key('person-inactive-banner')), findsOneWidget);
      expect(find.byKey(const Key('person-restore')), findsNothing);
    });

    testWidgets('employee: no ⋯, no "פרטים ועריכה", no balance, no booking', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה', phone: '050-1234567')],
        documents: docs(),
      );
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.employee);
      expect(headerMenu(), findsNothing);
      expect(find.byKey(const Key('person-edit')), findsNothing);
      expect(find.byKey(const Key('person-owes')), findsNothing);
      final ids = orbs(tester);
      expect(ids.take(2), ['call', 'whatsapp']);
      expect(ids, isNot(contains('book')));
      expect(ids, isNot(contains('reminder')));
      expect(ids, isNot(contains('add-phone')));
    });

    testWidgets('viewer without contact details: no actions at all', (
      tester,
    ) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.viewer);
      expect(find.byType(PrimaryButton), findsNothing);
      expect(find.byType(ActionOrb), findsNothing);
    });

    testWidgets(
      '"פרטים ועריכה" (BE-09): S2 edit form PATCHes only changes; no terms '
      'picker of its own (terms live in "תנאי תשלום ותזכורות")',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [
            customerJson('c1', 'דנה', phone: '0501234567', be09: true),
          ],
          be09: true,
        );
        await pump(tester, const PersonScreen(id: 'c1'));
        await edit(tester);
        expect(find.text(PeopleHe.editTitle), findsWidgets);
        expect(find.text('שוטף+60'), findsNothing);
        expect(find.text(PeopleHe.paymentTerms), findsNothing);
        await tester.enterText(find.byKey(const Key('s2-email')), 'dana@x.co');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(backend.last('PATCH', '/customers/:id')!.body, {
          'email': 'dana@x.co',
        });
      },
    );

    testWidgets('supplier card: badge "ספק", orb "הוצאה חדשה"', (tester) async {
      installPeopleFakes(
        backend,
        suppliers: [
          {
            'id': 's1',
            'name': 'חשמל',
            'tax_id': null,
            'email': null,
            'phone': '036000000',
            'archived_at': null,
          },
        ],
      );
      await pump(tester, const PersonScreen(id: 's1', isSupplier: true));
      expect(find.text(PeopleHe.supplierBadge), findsOneWidget);
      expect(orbs(tester), ['call', 'whatsapp', 'expense']);
      final expense = tester.widget<ActionOrb>(
        find.byKey(const Key('person-action-expense')),
      );
      expect(expense.semanticsLabel, PeopleHe.newExpenseFrom('חשמל'));
      expect(
        find.byKey(const Key('person-edit')),
        findsNothing,
        reason: 'no BE-16: read-only card',
      );
      expect(headerMenu(), findsNothing);
    });

    testWidgets(
      'J11 (AT-28, BE-17): לקוחות → לקוח → עוד → "שליחת כרטסת" → אישור = 5 taps; e-mailed for this year',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', email: 'd@x.co')],
          documents: docs(),
          be17: true,
        );
        await pump(tester, const PeopleScreen());
        taps = 1; // (1) the "לקוחות" tab
        await tap(tester, find.byKey(const Key('person-c1')));
        await flush(tester);
        await more(tester, 'statement');
        // E-mailing the customer asks first (QA 2026-11-16 owner/114).
        expect(backend.calls('POST', '/customers/:id/statement/send'), isEmpty);
        expect(find.text(PeopleHe.statementConfirmTitle), findsOneWidget);
        await tap(tester, find.byKey(const Key('statement-confirm')));
        // 2611 #11: the statement is an action — in "עוד" only.
        expect(taps, lessThanOrEqualTo(5));
        final body = backend
            .last('POST', '/customers/:id/statement/send')!
            .body;
        expect(body['channel'], 'EMAIL');
        expect(body['from'], '${DateTime.now().year}-01-01');
        expect(find.text(PeopleHe.statementSent('d@x.co')), findsOneWidget);
      },
    );

    testWidgets(
      'BE-17: no e-mail or accountant (no send) → statement PDF to the share sheet; '
      'no BE-17 → no item',
      (tester) async {
        String? shared;
        final old = pdfSharer;
        pdfSharer = (bytes, name, {text}) async => shared = name;
        addTearDown(() => pdfSharer = old);

        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', email: 'd@x.co')],
          be17: true,
        );
        await pump(
          tester,
          const PersonScreen(id: 'c1'),
          preset: Preset.accountantRep,
        );
        expect(
          find.byKey(const Key('person-edit')),
          findsNothing,
          reason: 'rep: statement only (§4.4)',
        );
        await more(tester, 'statement');
        expect(backend.calls('POST', '/customers/:id/statement/send'), isEmpty);
        expect(shared, 'כרטסת דנה.pdf');
      },
    );

    testWidgets(
      'no BE-17 on the server → "שליחת כרטסת" hidden (F5) in ⋯ and in "עוד"',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', email: 'd@x.co')],
        );
        await pump(tester, const PersonScreen(id: 'c1'));
        await tap(tester, find.byKey(const Key('person-action-more')));
        expect(find.byKey(const Key('person-more-email')), findsOneWidget);
        expect(find.byKey(const Key('person-more-statement')), findsNothing);
        // Each action in one place: edit / archive are not in "עוד".
        expect(find.byKey(const Key('person-more-edit')), findsNothing);
        expect(find.byKey(const Key('person-more-archive')), findsNothing);
        expect(find.byKey(const Key('person-more-terms')), findsNothing);
      },
    );

    testWidgets(
      'BE-09 edit: address (city required), consent switch while not given',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', be09: true)],
          be09: true,
        );
        await pump(tester, const PersonScreen(id: 'c1'));
        await edit(tester);
        expect(
          find.byKey(const Key('s2-accountkey')),
          findsNothing,
          reason: 'BE-04 cap only',
        );
        // 2611 #2 #3: every field's name sits above it (never on the
        // border); street on its own line, number / postal wide enough.
        for (final label in [
          PeopleHe.name,
          PeopleHe.street,
          PeopleHe.city,
          PeopleHe.houseNumber,
          PeopleHe.postalCode,
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        final street = tester.getRect(find.byKey(const Key('s2-street')));
        final house = tester.getRect(find.byKey(const Key('s2-house')));
        final postal = tester.getRect(find.byKey(const Key('s2-postal')));
        expect(house.top, greaterThan(street.bottom));
        expect(house.width, greaterThanOrEqualTo(120));
        expect(postal.width, greaterThanOrEqualTo(street.width - 1));
        expect(
          tester.getRect(find.text(PeopleHe.street)).bottom,
          lessThanOrEqualTo(street.top),
        );
        await tester.enterText(find.byKey(const Key('s2-street')), 'הרצל');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(find.text(PeopleHe.cityRequired), findsOneWidget);
        expect(backend.calls('PATCH', '/customers/:id'), isEmpty);

        await tester.enterText(find.byKey(const Key('s2-house')), '5');
        await tester.enterText(find.byKey(const Key('s2-city')), 'תל אביב');
        await tap(tester, find.byKey(const Key('s2-consent')));
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(backend.last('PATCH', '/customers/:id')!.body, {
          'address': {
            'street': 'הרצל',
            'number': '5',
            'city': 'תל אביב',
            'postalCode': null,
          },
        });
        expect(backend.calls('POST', '/customers/:id/consent'), hasLength(1));
      },
    );

    testWidgets(
      'supplier card with BE-16: "פרטים ועריכה" PATCHes the change; ⋯ "ארכוב"',
      (tester) async {
        installPeopleFakes(
          backend,
          be16: true,
          suppliers: [
            {
              'id': 's1',
              'name': 'חשמל',
              'tax_id': null,
              'email': null,
              'phone': null,
              'archived_at': null,
            },
          ],
        );
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          openPerson(navigatorKey.currentContext!, 's1', supplier: true),
        );
        await flush(tester);
        await edit(tester);
        expect(find.byKey(const Key('s2-consent')), findsNothing);
        await tester.enterText(find.byKey(const Key('s2-phone')), '03-6000000');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(backend.last('PATCH', '/suppliers/:id')!.body, {
          'phone': '036000000',
        });

        await tap(tester, headerMenu());
        await tap(tester, find.text('ארכוב'));
        expect(find.text(PeopleHe.supplierArchiveConfirm), findsOneWidget);
        await tap(tester, find.widgetWithText(TextButton, PeopleHe.archive));
        expect(backend.calls('POST', '/suppliers/:id/archive'), hasLength(1));
        expect(find.text('root'), findsOneWidget);
      },
    );

    testWidgets('unknown customer → error + retry', (tester) async {
      installPeopleFakes(backend);
      await pump(tester, const PersonScreen(id: 'zz'));
      expect(find.text('נסה שוב'), findsOneWidget);
    });
  });

  group('S2 · לקוח', () {
    testWidgets('pick: a tap returns the customer at once (auto-advance)', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה'), customerJson('c2', 'אבי')],
      );
      Customer? picked;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(
        showCustomerSheet(navigatorKey.currentContext!).then((c) => picked = c),
      );
      await flush(tester);
      expect(find.text(PeopleHe.walkIn), findsOneWidget);
      expect(find.text(PeopleHe.walkInHint), findsOneWidget);
      await tap(tester, find.byKey(const Key('s2-row-c1')));
      expect(picked?.id, 'c1');
      expect(taps, 1);
    });

    testWidgets(
      'J1-new inside S2: explicit contact import → save in 4 taps; consent switch → consent call',
      (tester) async {
        installPeopleFakes(backend, customers: [customerJson('c1', 'אבי')]);
        pickContact = () async {
          taps++; // the contact row tapped in the system picker counts (F3.1)
          return const PickedContact(
            name: 'דנה לוי',
            phones: ['03-5551234', '052-111-2222'],
          );
        };
        Customer? created;
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(
            navigatorKey.currentContext!,
          ).then((c) => created = c),
        );
        await flush(tester);
        await tap(tester, find.byKey(const Key('s2-new')));
        await tap(tester, find.byKey(const Key('s2-import-contact')));
        expect(find.text('דנה לוי'), findsOneWidget);
        expect(find.byType(PrimaryButton), findsOneWidget);
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(taps, 4);
        expect(created?.name, 'דנה לוי');
        final body = backend.last('POST', '/customers')!.body;
        expect(body['phone'], '0521112222');
        expect(body['customerType'], 'INDIVIDUAL');
        expect(body.containsKey('vatDealerStatus'), isFalse);
        expect(
          backend.calls('POST', '/customers/:id/consent'),
          isEmpty,
          reason: 'switch off by default',
        );
      },
    );

    testWidgets('consent switch on → POST consent; tax id → BUSINESS', (
      tester,
    ) async {
      installPeopleFakes(backend);
      Customer? created;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(
        showCustomerSheet(
          navigatorKey.currentContext!,
          startOnNew: true,
        ).then((c) => created = c),
      );
      await flush(tester);
      await tester.enterText(find.byKey(const Key('s2-name')), 'מוסך');
      await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
      await tap(tester, find.byKey(const Key('s2-consent')));
      await tap(tester, find.byKey(const Key('s2-save')));
      expect(
        backend.last('POST', '/customers')!.body['customerType'],
        'BUSINESS',
      );
      expect(backend.calls('POST', '/customers/:id/consent'), hasLength(1));
      expect(created?.consentGranted, isTrue);
    });

    testWidgets(
      'validation: no name → "צריך שם"; bad tax id → check digit message; nothing sent',
      (tester) async {
        installPeopleFakes(backend);
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(navigatorKey.currentContext!, startOnNew: true),
        );
        await flush(tester);
        await tester.enterText(find.byKey(const Key('s2-taxid')), '123');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(find.text(PeopleHe.nameRequired), findsOneWidget);
        expect(find.text(PeopleHe.taxIdInvalid), findsOneWidget);
        expect(backend.calls('POST', '/customers'), isEmpty);
      },
    );

    testWidgets(
      'עוסק מורשה question: only with a tax id; "כן" → AUTHORIZED_DEALER on POST',
      (tester) async {
        installPeopleFakes(backend);
        Customer? created;
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(
            navigatorKey.currentContext!,
            startOnNew: true,
          ).then((c) => created = c),
        );
        await flush(tester);
        await tester.enterText(find.byKey(const Key('s2-name')), 'מוסך');
        await tester.pump();
        expect(find.text(PeopleHe.vatDealerQuestion), findsNothing);
        await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
        await tester.pump();
        expect(find.text(PeopleHe.vatDealerQuestion), findsOneWidget);
        await tester.ensureVisible(find.text(PeopleHe.vatDealerYes));
        await tester.tap(find.text(PeopleHe.vatDealerYes));
        await tester.pump();
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(
          backend.last('POST', '/customers')!.body['vatDealerStatus'],
          'AUTHORIZED_DEALER',
        );
        expect(created?.vatDealerStatus, 'AUTHORIZED_DEALER');
      },
    );

    testWidgets(
      'עוסק מורשה question: "לא" → EXEMPT_DEALER; "לא יודע" (default) sends nothing',
      (tester) async {
        installPeopleFakes(backend);
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(navigatorKey.currentContext!, startOnNew: true),
        );
        await flush(tester);
        await tester.enterText(find.byKey(const Key('s2-name')), 'סטודיו');
        await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
        await tester.pump();
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(
          backend
              .last('POST', '/customers')!
              .body
              .containsKey('vatDealerStatus'),
          isFalse,
        );
      },
    );

    test('vatDealerStatusFor: כן / לא / לא יודע and a known "לא" kept', () {
      expect(vatDealerStatusFor(dealerYes), 'AUTHORIZED_DEALER');
      expect(vatDealerStatusFor(dealerNo), 'EXEMPT_DEALER');
      expect(vatDealerStatusFor(dealerNo, old: 'NONPROFIT'), 'NONPROFIT');
      expect(vatDealerStatusFor(dealerUnknown), 'UNKNOWN');
      expect(dealerChipFor(null), dealerUnknown);
      expect(dealerChipFor('PRIVATE'), dealerNo);
      expect(dealerChipFor('AUTHORIZED_DEALER'), dealerYes);
    });

    testWidgets(
      'owner/032: a fixed phone / tax id loses its red error at once, before save',
      (tester) async {
        installPeopleFakes(backend);
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(navigatorKey.currentContext!, startOnNew: true),
        );
        await flush(tester);
        await tester.enterText(find.byKey(const Key('s2-name')), 'דנה');
        await tester.enterText(find.byKey(const Key('s2-phone')), '05012');
        await tester.enterText(find.byKey(const Key('s2-taxid')), '123456789');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(find.text(PeopleHe.phoneInvalid), findsOneWidget);
        expect(find.text(PeopleHe.taxIdInvalid), findsOneWidget);
        await tester.enterText(find.byKey(const Key('s2-phone')), '0501234567');
        await tester.pump();
        expect(find.text(PeopleHe.phoneInvalid), findsNothing);
        expect(find.text(PeopleHe.taxIdInvalid), findsOneWidget);
        await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
        await tester.pump();
        expect(find.text(PeopleHe.taxIdInvalid), findsNothing);
        expect(backend.calls('POST', '/customers'), isEmpty);
      },
    );

    testWidgets(
      'QA 3.1: 409 CUSTOMER_DUPLICATE → server text + "פתח לקוח קיים" opens P2; '
      'without customerId only the text',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c9', 'מוסך הצפון')],
        );
        var withId = true;
        backend.on(
          'POST',
          '/customers',
          (_) => FakeResponse(409, {
            'error': 'CUSTOMER_DUPLICATE',
            'message': 'לקוח עם אותו מספר ח.פ. / ת.ז. כבר קיים',
            if (withId) 'customerId': 'c9',
          }),
        );
        Future<void> submit() async {
          unawaited(
            showCustomerSheet(navigatorKey.currentContext!, startOnNew: true),
          );
          await flush(tester);
          await tester.enterText(find.byKey(const Key('s2-name')), 'מוסך');
          await tester.enterText(
            find.byKey(const Key('s2-taxid')),
            '514713288',
          );
          await tap(tester, find.byKey(const Key('s2-save')));
        }

        await pump(tester, const Scaffold(body: Text('root')));
        await submit();
        expect(find.byKey(const Key('s2-server-duplicate')), findsOneWidget);
        expect(
          find.text('לקוח עם אותו מספר ח.פ. / ת.ז. כבר קיים'),
          findsOneWidget,
        );
        await tap(tester, find.byKey(const Key('s2-open-existing')));
        await flush(tester);
        expect(find.byKey(const Key('s2-save')), findsNothing);
        expect(find.byType(PersonScreen), findsOneWidget);
        expect(tester.widget<PersonScreen>(find.byType(PersonScreen)).id, 'c9');

        withId = false;
        await pump(tester, const Scaffold(body: Text('root')));
        await submit();
        expect(find.byKey(const Key('s2-server-duplicate')), findsOneWidget);
        expect(find.byKey(const Key('s2-open-existing')), findsNothing);
      },
    );

    testWidgets(
      'QA 2026-11-15: from the Composer, "פתח לקוח קיים" returns the existing '
      'customer as the choice and opens no card (no blank Composer under P2)',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c9', 'מוסך הצפון')],
        );
        backend.on(
          'POST',
          '/customers',
          (_) => FakeResponse(409, {
            'error': 'CUSTOMER_DUPLICATE',
            'message': 'לקוח עם אותו מספר ח.פ. / ת.ז. כבר קיים',
            'customerId': 'c9',
          }),
        );
        await pump(tester, const Scaffold(body: Text('root')));
        Customer? chosen;
        var done = false;
        unawaited(
          showCustomerSheet(
            navigatorKey.currentContext!,
            openExistingCard: false,
          ).then((c) {
            chosen = c;
            done = true;
          }),
        );
        await flush(tester);
        await tap(tester, find.byKey(const Key('s2-new')));
        await tester.enterText(find.byKey(const Key('s2-name')), 'מוסך');
        await tester.enterText(find.byKey(const Key('s2-taxid')), '514713288');
        await tap(tester, find.byKey(const Key('s2-save')));
        await tap(tester, find.byKey(const Key('s2-open-existing')));
        await flush(tester);
        expect(done, isTrue);
        expect(chosen?.id, 'c9');
        expect(find.byType(PersonScreen), findsNothing);
        expect(find.text('root'), findsOneWidget);
      },
    );

    testWidgets(
      'QA 3.1: 422 VALIDATION in Hebrew lands on its field; editing it clears',
      (tester) async {
        installPeopleFakes(backend);
        backend.on(
          'POST',
          '/customers',
          (_) => FakeResponse.error(422, 'VALIDATION', 'מספר הטלפון לא תקין'),
        );
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(navigatorKey.currentContext!, startOnNew: true),
        );
        await flush(tester);
        await tester.enterText(find.byKey(const Key('s2-name')), 'דנה');
        await tester.enterText(find.byKey(const Key('s2-phone')), '0521112222');
        await tap(tester, find.byKey(const Key('s2-save')));
        final onPhone = find.descendant(
          of: find.byKey(const Key('s2-phone')),
          matching: find.text('מספר הטלפון לא תקין'),
        );
        expect(onPhone, findsOneWidget);
        expect(find.text('מספר הטלפון לא תקין'), findsOneWidget); // no snack
        await tester.enterText(find.byKey(const Key('s2-phone')), '0521112223');
        await flush(tester);
        expect(onPhone, findsNothing);
      },
    );

    test('customerFieldOfValidation maps server texts to S2 fields', () {
      expect(customerFieldOfValidation('מספר ח.פ. / ת.ז. לא תקין'), 'taxId');
      expect(customerFieldOfValidation('מספר הטלפון לא תקין'), 'phone');
      expect(
        customerFieldOfValidation('name must be 1-200 characters'),
        'name',
      );
      expect(
        customerFieldOfValidation('email must be at most 254 characters'),
        'email',
      );
      expect(customerFieldOfValidation('vatDealerStatus must be one of'), null);
    });

    testWidgets(
      'duplicate phone → "כבר קיים: X · השתמש בו" returns the existing one',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', phone: '0521112222')],
        );
        pickContact = () async =>
            const PickedContact(name: 'דנה ל.', phones: ['+972 52-111-2222']);
        Customer? result;
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showCustomerSheet(
            navigatorKey.currentContext!,
          ).then((c) => result = c),
        );
        await flush(tester);
        await tap(tester, find.byKey(const Key('s2-new')));
        await tap(tester, find.byKey(const Key('s2-import-contact')));
        expect(find.byKey(const Key('s2-duplicate')), findsOneWidget);
        expect(find.text(PeopleHe.alreadyExists('דנה')), findsOneWidget);
        await tap(tester, find.text(PeopleHe.useExisting));
        expect(result?.id, 'c1');
        expect(backend.calls('POST', '/customers'), isEmpty);
      },
    );

    testWidgets('"לקוח מזדמן" creates one INDIVIDUAL record and returns it', (
      tester,
    ) async {
      installPeopleFakes(backend);
      Customer? result;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(
        showCustomerSheet(navigatorKey.currentContext!).then((c) => result = c),
      );
      await flush(tester);
      await tap(tester, find.byKey(const Key('s2-walkin')));
      expect(result?.name, PeopleHe.walkIn);
      expect(
        backend.last('POST', '/customers')!.body['customerType'],
        'INDIVIDUAL',
      );
    });

    testWidgets(
      'supplier mode: lists suppliers, new supplier → POST /suppliers, no consent switch',
      (tester) async {
        installPeopleFakes(
          backend,
          suppliers: [
            {
              'id': 's1',
              'name': 'חשמל',
              'tax_id': null,
              'email': null,
              'phone': null,
              'archived_at': null,
            },
          ],
        );
        Supplier? result;
        await pump(tester, const Scaffold(body: Text('root')));
        unawaited(
          showSupplierSheet(
            navigatorKey.currentContext!,
          ).then((s) => result = s),
        );
        await flush(tester);
        expect(find.byKey(const Key('s2-row-s1')), findsOneWidget);
        expect(find.text(PeopleHe.walkIn), findsNothing);
        await tap(tester, find.byKey(const Key('s2-new')));
        expect(find.byKey(const Key('s2-consent')), findsNothing);
        await tester.enterText(find.byKey(const Key('s2-name')), 'דלק');
        await tap(tester, find.byKey(const Key('s2-save')));
        expect(result?.name, 'דלק');
        expect(backend.calls('POST', '/suppliers'), hasLength(1));
      },
    );

    testWidgets('viewer: no "+ לקוח חדש" and no walk-in', (tester) async {
      installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
      await pump(
        tester,
        const Scaffold(body: Text('root')),
        preset: Preset.viewer,
      );
      unawaited(showCustomerSheet(navigatorKey.currentContext!));
      for (
        var attempt = 0;
        attempt < 20 && find.byKey(const Key('s2-row-c1')).evaluate().isEmpty;
        attempt++
      ) {
        await flush(tester);
      }
      expect(find.byKey(const Key('s2-new')), findsNothing);
      expect(find.byKey(const Key('s2-walkin')), findsNothing);
      expect(find.byKey(const Key('s2-row-c1')), findsOneWidget);
    });
  });

  group('QA 2026-11-12 · A5', () {
    testWidgets('dark theme: no invented phone, same content as light (0.1)', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה'), customerJson('c2', 'אבי')],
      );
      await pump(
        tester,
        const Scaffold(body: Text('root')),
        brightness: Brightness.dark,
      );
      unawaited(showCustomerSheet(navigatorKey.currentContext!));
      await flush(tester);
      expect(find.text('052-0000111'), findsNothing);
      expect(find.text(PeopleHe.walkInHint), findsOneWidget);
      expect(find.byKey(const Key('s2-row-c1')), findsOneWidget);
    });

    testWidgets('card: "קיבלתי תשלום" opens PAID for this customer (1.9)', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה')],
        documents: docs(),
      );
      await pump(
        tester,
        const PersonScreen(id: 'c1'),
        brightness: Brightness.dark,
      );
      expect(find.text('דנה'), findsWidgets, reason: 'name in the header');
      expect(find.byKey(const Key('person-action-invoice')), findsOneWidget);
      await tap(tester, find.byKey(const Key('person-action-paid')));
      final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
      expect(c.intent, 'PAID');
      expect(c.customerId, 'c1');
    });

    testWidgets('S2 form: back with typed text asks before leaving (1.10)', (
      tester,
    ) async {
      installPeopleFakes(backend);
      Customer? result;
      var closed = false;
      await pump(tester, const Scaffold(body: Text('root')));
      unawaited(
        showCustomerSheet(navigatorKey.currentContext!, startOnNew: true).then((
          c,
        ) {
          result = c;
          closed = true;
        }),
      );
      await flush(tester);
      await tester.enterText(find.byKey(const Key('s2-name')), 'דנה');
      await flush(tester);
      unawaited(Navigator.of(navigatorKey.currentContext!).maybePop());
      await flush(tester);
      expect(find.byKey(const Key('discard-confirm')), findsOneWidget);
      expect(closed, isFalse);
      await tap(tester, find.byKey(const Key('discard-leave')));
      expect(closed, isTrue);
      expect(result, isNull);
      expect(backend.calls('POST', '/customers'), isEmpty);
    });
  });
}
