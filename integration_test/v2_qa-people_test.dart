// ignore_for_file: file_names
//
// QA · qa-people (SPEC-v2 §17): people / suppliers / statement (P, P2, S2,
// BE-09/16/17), expenses review + list (E, BE-44) and items (S3, BE-15),
// against the real app and the dev API (never prod). The single simulator
// runner runs it:
//
//   ~/flutter/bin/flutter test integration_test/v2_qa-people_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
//
// MAILDIR is required: the owner and "עובד + מפיק" sign in with an e-mail
// code, and AT-28 checks the statement e-mail. Every record it creates in the
// dev business carries "QA … <runTag>"; expenses it leaves pending are
// rejected at the end of their test.
//
// Dev has no OCR provider (POST /expenses/:id/extract → 503). AT-19 measures
// J4 with OCR succeeding, as §1 F3.1 says, through OcrFixtureClient: the
// extract call stores fixed values on the real server. The camera is the
// image_picker_ios channel answering with a generated JPEG; its shutter is
// counted as one tap.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/router.dart' show openCompose, openExpenses, openPerson;
import 'package:invoice/screens/compose/compose_memory.dart'
    show clearLocalDraft;
import 'package:invoice/screens/document/sheets/s6_share.dart' show pdfSharer;
import 'package:invoice/screens/people/sheets/s2_customer.dart'
    show PickedContact, pickContact;
import 'package:invoice/util/allowed_urls.dart'
    show defaultUrlOpener, urlOpener;
import 'package:invoice/util/labels/common_he.dart';
import 'package:invoice/util/labels/people_he.dart';

import 'v2_qa_people_helpers.dart';
import 'qa_plans_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();

  late DevApi owner;
  late DevApi staff;
  late DevApi employee;
  late DevApi viewer;

  // A customer who owes ₪118 (one finalized 305), with e-mail + consent.
  final debtorName = 'QA חייב $runTag';
  final debtorEmail = 'qa-people-$runTag@example.test';
  late String debtorId;
  late String debtorDocId;

  final opened = <Uri>[];
  final sharedPdfs = <String>[];

  setUpAll(() async {
    if (!apiBase.startsWith('http://127.0.0.1') &&
        !apiBase.startsWith('http://localhost')) {
      fail('qa-people writes test data: dev API only (API_BASE=$apiBase)');
    }
    owner = await signInApi(ownerEmail);
    staff = await signInApi(staffEmail);
    viewer = await signInApi(viewerEmail);
    employee = await signInApi(employeeEmail);

    debtorId = await owner.createCustomer(
      debtorName,
      email: debtorEmail,
      phone: '0501234567',
      consent: true,
    );
    debtorDocId = await owner.issueTaxInvoice(
      debtorId,
    ); // ₪100 + 18% = ₪118 open

    // No real launches / share sheets from the simulator (AT-95 style fakes).
    urlOpener = (uri, {inApp = false}) async {
      opened.add(uri);
      return true;
    };
    pdfSharer = (bytes, name, {text}) async => sharedPdfs.add(name);
    pickContact = () async => null; // the native picker "cancelled"
  });

  tearDownAll(() async {
    urlOpener = defaultUrlOpener;
    for (final api in [owner, staff, viewer, employee]) {
      await api.logout();
    }
  });

  // ---- P · P2 · statement ------------------------------------------------------

  testWidgets(
    'AT-28 (P2) J11: לקוחות → לקוח → "שלח כרטסת" ≤3 taps; the statement PDF is e-mailed (BE-17)',
    (tester) async {
      // Contract first: the statement has the 305 as a debit and closes at ₪118.
      final st = DevApi.expectOk(
        await owner.get('/customers/$debtorId/statement'),
        200,
      ).map;
      expect(st['closingBalanceMinor'], '11800', reason: '$st');
      final rows = [
        for (final r in st['rows'] as List) Map<String, dynamic>.from(r as Map),
      ];
      expect(
        rows.where(
          (r) => r['documentId'] == debtorDocId && r['debitMinor'] == '11800',
        ),
        hasLength(1),
        reason: '$rows',
      );
      final pdf = DevApi.expectOk(
        await owner.get('/customers/$debtorId/statement.pdf'),
        200,
      );
      expect(ascii.decode(pdf.bytes.take(4).toList()), '%PDF');

      await launchAppAs(tester, owner);
      final since = DateTime.now().subtract(const Duration(seconds: 2));
      final taps = TapCounter();

      await openPeopleTab(tester, taps: taps);
      await pumpUntil(tester, find.byKey(const Key('people-search')));
      await tester.enterText(
        find.byKey(const Key('people-search')),
        debtorName,
      ); // typing: free
      await pumpUntil(
        tester,
        find.byKey(Key('person-$debtorId')),
        what: 'debtor row',
      );
      await taps.tap(tester, find.byKey(Key('person-$debtorId')), 'לקוח');

      // The CRM panel pushes these rows below the fold of P2's lazy list.
      await pumpUntilScrolled(
        tester,
        find.byKey(const Key('person-statement')),
        what: '"שלח כרטסת" (BE-17 probe)',
      );
      // P2: "חייב לך ₪118" and the one primary is "בקש תשלום" (balance > 0).
      await pumpUntilScrolled(tester, find.byKey(const Key('person-owes')));
      await pumpUntilScrolled(
        tester,
        find.byKey(const Key('person-statement')),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('person-primary')),
          matching: find.text(CommonHe.requestPayment),
        ),
        findsOneWidget,
      );

      await taps.tap(
        tester,
        find.byKey(const Key('person-statement')),
        'שלח כרטסת',
      );
      await pumpUntil(
        tester,
        find.text(PeopleHe.statementSent(debtorEmail)),
        what: 'sent toast',
      );
      // J11 = 3 taps again: לקוחות is a tab (PM 2026-11-12).
      expect(taps.count, lessThanOrEqualTo(3), reason: '$taps');
      expect(
        sharedPdfs,
        isEmpty,
        reason: 'owner with an e-mail on file sends, not the share sheet',
      );

      final mail = await eventually(() async {
        final m = mailsTo(debtorEmail, since);
        return m.isEmpty ? null : m.first;
      }, what: 'statement e-mail to $debtorEmail in $mailDir');
      expect('${mail['subject']}', contains('כרטסת'));
      expect((mail['attachment'] as Map)['bytes'], greaterThan(1000));
      debugPrint('AT-28 $taps');
      await closeApp(tester);
    },
  );

  testWidgets(
    '§6.P (P0b) owner: chip "חייבים" lists the debtor with "חייב לך"; "ספקים" chip present',
    (tester) async {
      await launchAppAs(tester, owner);
      await openPeopleTab(tester);
      await pumpUntil(
        tester,
        find.text(PeopleHe.chipDebtors),
        what: 'debtors chip (BE-09 balances)',
      );
      expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
      await tapSafe(tester, find.text(PeopleHe.chipDebtors));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const Key('people-search')),
        debtorName,
      );
      await pumpUntil(tester, find.byKey(Key('person-$debtorId')));
      expect(
        find.descendant(
          of: find.byKey(Key('person-$debtorId')),
          matching: find.text(PeopleHe.owesYou),
        ),
        findsOneWidget,
      );
      await closeApp(tester);
    },
  );

  testWidgets(
    'AT-31 (P0a) S2 consent switch on → consent granted; off → e-mail send answers CONSENT_REQUIRED',
    (tester) async {
      final withConsent = 'QA הסכמה $runTag';
      final noConsent = 'QA בלי הסכמה $runTag';
      final noConsentEmail = 'qa-noconsent-$runTag@example.test';

      await launchAppAs(tester, owner);
      await openPeopleTab(tester);
      await pumpUntil(tester, find.byKey(const Key('people-add')));

      Future<void> addCustomer(
        String name,
        String email, {
        required bool consent,
      }) async {
        pickContact = () async =>
            PickedContact(name: name, phones: const ['0501234567']);
        await backToPeopleList(tester);
        await tapSafe(tester, find.byKey(const Key('people-add')));
        await pumpUntil(tester, find.byKey(const Key('s2-name')));
        // QA 1.4 (A5): contacts are read only from "ייבוא מאנשי קשר".
        await tapSafe(tester, find.byKey(const Key('s2-import-contact')));
        await pumpFor(
          tester,
          const Duration(milliseconds: 600),
        ); // contact import
        expect(
          fieldText(tester, find.byKey(const Key('s2-name'))),
          name,
          reason: 'filled from the contact',
        );
        await tester.enterText(find.byKey(const Key('s2-email')), email);
        if (consent) {
          await tester.ensureVisible(find.byKey(const Key('s2-consent')));
          await tapSafe(tester, find.byKey(const Key('s2-consent')));
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.ensureVisible(find.byKey(const Key('s2-save')));
        await tapSafe(tester, find.byKey(const Key('s2-save')));
        await pumpUntilGone(
          tester,
          find.byKey(const Key('s2-save')),
          what: 'S2 after "שמור"',
        );
        pickContact = () async => null;
      }

      Future<Map<String, dynamic>> customerNamed(String name) async {
        final id = await eventually(() async {
          final r = DevApi.expectOk(
            await owner.get('/customers', {'q': name, 'limit': '5'}),
          );
          final hit = r.list('customers').where((c) => c['name'] == name);
          return hit.isEmpty ? null : hit.first['id'] as String;
        }, what: 'customer "$name" on the server');
        return DevApi.expectOk(
              await owner.get('/customers/$id'),
            ).map['customer']
            as Map<String, dynamic>;
      }

      await addCustomer(
        withConsent,
        'qa-consent-$runTag@example.test',
        consent: true,
      );
      final a = await customerNamed(withConsent);
      expect((a['consent'] as Map)['granted'], isTrue, reason: '$a');
      expect(
        a['customerType'],
        'INDIVIDUAL',
        reason: 'no tax id → INDIVIDUAL (§6 S2)',
      );
      expect(
        a['vatDealerStatus'],
        'UNKNOWN',
        reason: 'S2 never asks vatDealerStatus (§4.9)',
      );

      await addCustomer(noConsent, noConsentEmail, consent: false);
      final b = await customerNamed(noConsent);
      expect((b['consent'] as Map)['granted'], isFalse, reason: '$b');
      await closeApp(tester);

      // The e-mail half (S6 dialog belongs to squad C): the server refuses
      // without consent and sends once consent is recorded. The server asks for
      // consent only for SIGNED documents or with the business policy
      // deliveryConsentRequired (packages/postgres/src/consent.ts); the dev
      // business has neither, so there this half can only be reported.
      final bId = b['id'] as String;
      final doc = await owner.issueTaxInvoice(bId, netMinor: 1000);
      final refused = await owner.post('/documents/$doc/send', {
        'recipient': noConsentEmail,
      });
      if (refused.status == 202) {
        debugPrint(
          'AT-31 SKIPPED (server half): this environment does not require consent '
          '(unsigned document, deliveryConsentRequired off) → run on staging AT-Murshe',
        );
        await owner.post('/deliveries/${refused.map['deliveryId']}/process');
        return;
      }
      expect(refused.status, 409, reason: '$refused');
      expect(refused.error, 'CONSENT_REQUIRED', reason: '$refused');
      DevApi.expectOk(
        await owner.post('/customers/$bId/consent', {
          'method': 'VERBAL_IN_APP',
        }),
      );
      final sent = DevApi.expectOk(
        await owner.post('/documents/$doc/send', {'recipient': noConsentEmail}),
        202,
      );
      final processed = DevApi.expectOk(
        await owner.post('/deliveries/${sent.map['deliveryId']}/process'),
        200,
      ).map;
      expect(processed['status'], 'SENT', reason: '$processed');
    },
  );

  testWidgets(
    'AT-51 (P2) + §4.4: people/expense/item/supplier writes per preset (API) and hidden UI for עובד / צפייה',
    (tester) async {
      final sup = DevApi.expectOk(
        await owner.post('/suppliers', {'name': 'QA ספק הרשאות $runTag'}),
        201,
      ).map['id'];
      final item = DevApi.expectOk(
        await owner.post('/items', {
          'name': 'QA פריט הרשאות $runTag',
          'itemType': 'SERVICE',
          'defaultUnitPriceMinor': '1000',
          'currency': 'ILS',
        }),
        201,
      ).map['id'];

      Future<void> forbidden(
        DevApi who,
        String method,
        String path, [
        Object? body,
      ]) async {
        final r = await who.send(method, path, body: body);
        expect(r.status, 403, reason: '${who.email} $method $path → $r');
        expect(r.error, 'DOCUMENT_ACTION_FORBIDDEN', reason: '$r');
      }

      await forbidden(staff, 'PATCH', '/customers/$debtorId', {'notes': 'x'});
      await forbidden(employee, 'GET', '/customers/$debtorId/statement');
      await forbidden(staff, 'GET', '/customers/$debtorId/statement');
      await forbidden(staff, 'PATCH', '/suppliers/$sup', {
        'phone': '0500000000',
      });
      await forbidden(staff, 'PATCH', '/items/$item', {
        'defaultUnitPriceMinor': '2000',
      });
      await forbidden(viewer, 'GET', '/expenses/inbox');
      await forbidden(viewer, 'POST', '/customers', {
        'name': 'x',
        'customerType': 'INDIVIDUAL',
      });
      // Read gating (/me.enforcement.readGating): no money for עובד.
      final staffList = DevApi.expectOk(
        await staff.get('/customers', {'q': debtorName}),
      );
      expect(
        staffList.list('customers').single['balanceMinor'],
        isNull,
        reason: '$staffList',
      );

      // עובד: no debtors / suppliers chips; P2 without edit, statement, ⋯, balance.
      await launchAppAs(tester, staff);
      await openPeopleTab(tester);
      await pumpUntil(tester, find.byKey(const Key('people-search')));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text(PeopleHe.chipDebtors), findsNothing);
      // §4.4 matrix: עובד views suppliers (creates them from an expense); no "+ ספק".
      expect(find.text(PeopleHe.chipSuppliers), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('people-search')),
        debtorName,
      );
      await pumpUntil(tester, find.byKey(Key('person-$debtorId')));
      await tapSafe(tester, find.byKey(Key('person-$debtorId')));
      await pumpUntil(
        tester,
        find.byKey(const Key('person-mail')),
        what: 'staff P2 loaded',
      );
      await pumpFor(
        tester,
        const Duration(seconds: 2),
      ); // statement probe would answer by now
      expect(find.byKey(const Key('person-edit')), findsNothing);
      expect(find.byKey(const Key('person-statement')), findsNothing);
      expect(find.byKey(const Key('person-owes')), findsNothing);
      expect(find.byTooltip(CommonHe.more), findsNothing);
      await closeApp(tester);

      // צפייה בלבד: no "+ לקוח"; P2 read-only.
      await launchAppAs(tester, viewer);
      await openPeopleTab(tester);
      await pumpUntil(tester, find.byKey(const Key('people-search')));
      expect(find.byKey(const Key('people-add')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('people-search')),
        debtorName,
      );
      await pumpUntil(tester, find.byKey(Key('person-$debtorId')));
      await tapSafe(tester, find.byKey(Key('person-$debtorId')));
      await pumpUntil(
        tester,
        find.byKey(const Key('person-mail')),
        what: 'viewer P2 loaded',
      );
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.byKey(const Key('person-edit')), findsNothing);
      expect(find.byKey(const Key('person-primary')), findsNothing);
      expect(find.byTooltip(CommonHe.more), findsNothing);
      await closeApp(tester);

      await owner.post('/suppliers/$sup/archive');
      await owner.post('/items/$item/archive');
    },
  );

  testWidgets(
    '§6.P2 (P0b) archive with an open balance → dialog "ללקוח יש ₪X פתוח"; cancel keeps the customer',
    (tester) async {
      await launchAppAs(tester, owner);
      atRoot((c) => openPerson(c, debtorId));
      await pumpUntil(tester, find.byKey(const Key('person-owes')));
      await pumpFor(
        tester,
        const Duration(seconds: 1),
      ); // let the push transition finish (it hit off-screen)
      await tapSafe(tester, find.byTooltip(CommonHe.more).last);
      await pumpUntil(tester, find.text(PeopleHe.archive));
      await tapSafe(tester, find.text(PeopleHe.archive).last);
      final tail = PeopleHe.archiveWithBalance('§').split('§').last;
      await pumpUntil(
        tester,
        find.textContaining(tail),
        what: 'archive-with-balance dialog',
      );
      expect(find.textContaining('118'), findsWidgets);
      await tapSafe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(CommonHe.cancel),
        ),
      );
      await pumpUntilGone(tester, find.byType(AlertDialog));
      final c =
          DevApi.expectOk(
                await owner.get('/customers/$debtorId'),
              ).map['customer']
              as Map;
      expect(c['archivedAt'], isNull);
      await closeApp(tester);
    },
  );

  // ---- suppliers (BE-16) -------------------------------------------------------

  testWidgets(
    'BE-16 (P2) suppliers: "+ ספק" → card → "פרטים ועריכה" → ⋯ "ארכב" (owner)',
    (tester) async {
      final name = 'QA ספק $runTag';
      await launchAppAs(tester, owner);
      await openPeopleTab(tester);
      await pumpUntil(tester, find.text(PeopleHe.chipSuppliers));
      await tapSafe(tester, find.text(PeopleHe.chipSuppliers));
      await pumpUntil(tester, find.text(PeopleHe.addSupplier));
      await tapSafe(tester, find.byKey(const Key('people-add')));
      await pumpUntil(tester, find.byKey(const Key('s2-name')));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('s2-consent')),
        findsNothing,
        reason: 'suppliers have no consent switch',
      );
      await tester.enterText(find.byKey(const Key('s2-name')), name);
      await tapSafe(tester, find.byKey(const Key('s2-save')));
      await pumpUntilGone(tester, find.byKey(const Key('s2-save')));

      final id = await eventually(() async {
        final r = DevApi.expectOk(await owner.get('/suppliers', {'q': name}));
        final hit = r.list('suppliers').where((s) => s['name'] == name);
        return hit.isEmpty ? null : hit.first['id'] as String;
      }, what: 'supplier on the server');

      await backToPeopleList(tester);
      await tester.enterText(find.byKey(const Key('people-search')), name);
      await pumpUntil(tester, find.byKey(Key('supplier-$id')));
      await tapSafe(tester, find.byKey(Key('supplier-$id')));
      await pumpUntil(
        tester,
        find.byKey(const Key('person-edit')),
        what: 'BE-16 "פרטים ועריכה"',
      );
      await tapSafe(tester, find.byKey(const Key('person-edit')));
      await pumpUntil(tester, find.byKey(const Key('s2-phone')));
      await tester.enterText(find.byKey(const Key('s2-phone')), '0521234567');
      await tester.ensureVisible(find.byKey(const Key('s2-save')));
      await tapSafe(tester, find.byKey(const Key('s2-save')));
      await pumpUntilGone(tester, find.byKey(const Key('s2-save')));
      await eventually(() async {
        final s =
            DevApi.expectOk(await owner.get('/suppliers/$id')).map['supplier']
                as Map;
        return '${s['phone']}'.contains('521234567') ? s : null;
      }, what: 'supplier phone updated');

      await pumpFor(
        tester,
        const Duration(seconds: 1),
      ); // let the push transition finish (it hit off-screen)
      await tapSafe(tester, find.byTooltip(CommonHe.more).last);
      await pumpUntil(tester, find.text(PeopleHe.archive));
      await tapSafe(tester, find.text(PeopleHe.archive).last);
      await pumpUntil(tester, find.text(PeopleHe.supplierArchiveConfirm));
      await tapSafe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(PeopleHe.archive),
        ),
      );
      await pumpUntil(tester, find.text(PeopleHe.supplierArchived));
      final s =
          DevApi.expectOk(await owner.get('/suppliers/$id')).map['supplier']
              as Map;
      expect(s['archivedAt'], isNotNull, reason: '$s');
      await closeApp(tester);
    },
  );

  // ---- E · expenses --------------------------------------------------------------

  testWidgets(
    'AT-19 (P0b) J4: ＋ → "הוצאה" → צילום → (OCR fixture) → "אשר" = 4 taps → APPROVED with category',
    (tester) async {
      final category = await owner.firstExpenseCategoryId();
      final ocr = OcrValues(
        supplierName: 'QA ספק קבלה $runTag',
        categoryId: category,
      );
      await launchAppAs(tester, owner);
      await mockCamera(tester, uniqueJpeg());
      final real = ApiClient.instance.httpClient;
      final fixture = OcrFixtureClient(
        real,
        (id) => owner.applyOcrFixture(id, ocr),
      );
      ApiClient.instance.httpClient = fixture;
      addTearDown(() {
        ApiClient.instance.httpClient = real;
        unmockCamera(tester);
      });

      final taps = TapCounter();
      // S1 is gone: home "הוצאות" → overview → "העלאת הוצאה".
      await taps.tap(
        tester,
        find.byKey(const Key('intent-expenses')),
        'הוצאות',
      );
      await pumpUntil(tester, find.byKey(const Key('expense-upload-new')));
      await taps.tap(
        tester,
        find.byKey(const Key('expense-upload-new')),
        'הוצאה חדשה',
      );
      taps.virtual(
        'צילום',
      ); // the camera opens by itself; the shutter is the user's tap

      await pumpUntil(
        tester,
        find.text(ocr.supplierName),
        timeout: const Duration(seconds: 60),
        what: 'review card filled by the OCR fixture',
      );
      await pumpUntil(tester, find.byKey(const Key('expense-primary')));
      expect(fixture.extracted, hasLength(1));
      final id = fixture.extracted.single;
      expect(fieldText(tester, find.byKey(const Key('expense-amount'))), '236');
      expect(
        find.descendant(
          of: find.byKey(const Key('expense-primary')),
          matching: find.text(ExpenseHe.approve),
        ),
        findsOneWidget,
      );

      await taps.tap(tester, find.byKey(const Key('expense-primary')), 'אשר');
      await pumpUntil(
        tester,
        find.text(ExpenseHe.approved),
        what: 'approved toast',
      );
      expect(taps.count, lessThanOrEqualTo(4), reason: '$taps');

      final row = await eventually(() async {
        final r = await owner.findExpense(id, q: ocr.supplierName);
        return r?['status'] == 'APPROVED' ? r : null;
      }, what: 'expense $id APPROVED');
      expect(row['categoryId'], category);
      expect(row['totalMinor'], '23600');
      expect(row['createdBy'], await owner.userId());
      debugPrint('AT-19 $taps');
      await closeApp(tester);
    },
  );

  testWidgets(
    '§6.E (P0b) עובד: J4 ends on "שמור" → waits for the owner; עובד sees only own expenses (BE-44)',
    (tester) async {
      final category = await staff.firstExpenseCategoryId();
      final ocr = OcrValues(
        supplierName: 'QA ספק עובד $runTag',
        categoryId: category,
        totalMinor: 5900,
        vatMinor: 900,
      );
      await launchAppAs(tester, staff);
      await mockCamera(tester, uniqueJpeg());
      final real = ApiClient.instance.httpClient;
      final fixture = OcrFixtureClient(
        real,
        (id) => staff.applyOcrFixture(id, ocr),
      );
      ApiClient.instance.httpClient = fixture;
      addTearDown(() {
        ApiClient.instance.httpClient = real;
        unmockCamera(tester);
      });

      final taps = TapCounter();
      // S1 is gone: home "הוצאות" opens capture for a capture-only role.
      await taps.tap(
        tester,
        find.byKey(const Key('intent-expenses')),
        'הוצאות',
      );
      taps.virtual('צילום');
      await pumpUntil(
        tester,
        find.text(ocr.supplierName),
        timeout: const Duration(seconds: 60),
      );
      await pumpUntil(tester, find.byKey(const Key('expense-primary')));
      expect(
        find.descendant(
          of: find.byKey(const Key('expense-primary')),
          matching: find.text(ExpenseHe.save),
        ),
        findsOneWidget,
        reason: 'no expense.approve → "שמור"',
      );
      expect(
        find.byTooltip(CommonHe.more),
        findsNothing,
        reason: 'no ⋯ "דחה" without expense.approve',
      );
      final id = fixture.extracted.single;
      await taps.tap(tester, find.byKey(const Key('expense-primary')), 'שמור');
      await pumpUntil(tester, find.text(ExpenseHe.saved));
      expect(taps.count, lessThanOrEqualTo(4), reason: '$taps');
      await closeApp(tester);

      final staffId = await staff.userId();
      final ownerInbox = DevApi.expectOk(
        await owner.get('/expenses/inbox'),
      ).list('expenses');
      final mine = ownerInbox.where((e) => e['id'] == id).toList();
      expect(mine, hasLength(1), reason: 'owner/accountant review it');
      expect(mine.single['status'], 'READY_TO_APPROVE');
      expect(mine.single['created_by'] ?? mine.single['createdBy'], staffId);

      final staffInbox = DevApi.expectOk(
        await staff.get('/expenses/inbox'),
      ).list('expenses');
      for (final e in staffInbox) {
        expect(
          e['created_by'] ?? e['createdBy'],
          staffId,
          reason: 'עובד sees only own expenses: $e',
        );
      }
      final staffList = DevApi.expectOk(
        await staff.get('/expenses', {'limit': '50'}),
      ).map;
      expect(staffList['mine'], isTrue);

      DevApi.expectOk(
        await owner.post('/expenses/$id/reject', {
          'reason': 'QA ניקוי $runTag',
        }),
      );
    },
  );

  testWidgets(
    '§6.E (P0b) ⋯ "דחה": reason is required → POST /expenses/:id/reject → REJECTED',
    (tester) async {
      final ocr = OcrValues(
        supplierName: 'QA ספק דחייה $runTag',
        categoryId: await owner.firstExpenseCategoryId(),
      );
      final up = await owner.uploadExpense(uniqueJpeg());
      final id = up['expenseId'] as String;
      await owner.applyOcrFixture(id, ocr);

      await launchAppAs(tester, owner);
      atRoot((c) => openExpenses(c, expenseId: id));
      await pumpUntil(
        tester,
        find.text(ocr.supplierName),
        what: 'card $id first',
      );
      await pumpFor(
        tester,
        const Duration(seconds: 1),
      ); // let the push transition finish (it hit off-screen)
      await tapSafe(tester, find.byKey(const Key('expense-more')));
      await pumpUntil(tester, find.text(ExpenseHe.reject));
      await tapSafe(tester, find.text(ExpenseHe.reject).last);
      await pumpUntil(tester, find.byKey(const Key('expense-reject-confirm')));
      await tapSafe(
        tester,
        find.byKey(const Key('expense-reject-confirm')),
      ); // empty reason
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('expense-reject-reason')),
        findsOneWidget,
        reason: 'the reason is required',
      );
      await tester.enterText(
        find.byKey(const Key('expense-reject-reason')),
        'QA כפילות $runTag',
      );
      await tapSafe(tester, find.byKey(const Key('expense-reject-confirm')));
      await pumpUntil(tester, find.text(ExpenseHe.rejected));
      await eventually(
        () => owner.findExpense(id, status: 'REJECTED'),
        what: 'expense $id REJECTED',
      );
      await closeApp(tester);
    },
  );

  testWidgets(
    'BE-44 (P2) E list: search → edit an approved expense (stays APPROVED) → ⋯ "מחק" (soft delete)',
    (tester) async {
      final ocr = OcrValues(
        supplierName: 'QA ספק רשימה $runTag',
        categoryId: await owner.firstExpenseCategoryId(),
      );
      final up = await owner.uploadExpense(uniqueJpeg());
      final id = up['expenseId'] as String;
      await owner.applyOcrFixture(id, ocr);
      DevApi.expectOk(await owner.post('/expenses/$id/approve'));
      // E shows the list switch only next to a non-empty review inbox.
      final pending =
          (await owner.uploadExpense(uniqueJpeg()))['expenseId'] as String;

      await launchAppAs(tester, owner);
      atRoot((c) => openExpenses(c));
      await pumpUntil(tester, find.byKey(const Key('expense-mode')));
      await tapSafe(tester, find.byKey(const Key('expense-mode')));
      await pumpUntil(tester, find.byKey(const Key('expense-search')));
      await tester.enterText(
        find.byKey(const Key('expense-search')),
        ocr.supplierName,
      );
      await pumpUntil(
        tester,
        find.byKey(Key('expense-row-$id')),
        what: 'approved expense in the list',
      );
      await tapUntil(
        tester,
        find.byKey(Key('expense-row-$id')),
        find.byKey(ValueKey('edit-$id')),
      );
      await tester.enterText(find.byKey(const Key('expense-amount')), '300');
      await tester.ensureVisible(find.byKey(const Key('expense-primary')));
      await tapSafe(tester, find.byKey(const Key('expense-primary')));
      await pumpUntil(tester, find.text(ExpenseHe.updated));
      final edited = await eventually(() async {
        final r = await owner.findExpense(id, q: ocr.supplierName);
        return r?['totalMinor'] == '30000' ? r : null;
      }, what: 'edited total');
      expect(edited['status'], 'APPROVED');
      expect(edited['editedAfterApproval'], isTrue);

      await pumpUntil(tester, find.byKey(Key('expense-row-$id')));
      await tapUntil(
        tester,
        find.byKey(Key('expense-row-$id')),
        find.byKey(ValueKey('edit-$id')),
      );
      await pumpFor(
        tester,
        const Duration(seconds: 1),
      ); // let the push transition finish (it hit off-screen)
      await tapSafe(tester, find.byKey(const Key('expense-more')));
      await pumpUntil(tester, find.text(ExpenseHe.delete));
      await tapSafe(tester, find.text(ExpenseHe.delete).last);
      await pumpUntil(tester, find.byKey(const Key('expense-delete-confirm')));
      await tapSafe(tester, find.byKey(const Key('expense-delete-confirm')));
      await pumpUntil(tester, find.text(ExpenseHe.deleted));
      await eventually(
        () => owner.findExpense(id, status: 'DELETED'),
        what: 'expense $id DELETED',
      );
      expect(
        await owner.findExpense(id, q: ocr.supplierName),
        isNull,
        reason: 'DELETED rows only with status=DELETED',
      );
      await closeApp(tester);

      DevApi.expectOk(
        await owner.post('/expenses/$pending/reject', {
          'reason': 'QA ניקוי $runTag',
        }),
      );
    },
  );

  testWidgets(
    'AT-03 / AT-04 (stage 0) upload: JPEG → expense created; EICAR → no expense (API)',
    (tester) async {
      final ok = await owner.uploadExpense(uniqueJpeg());
      expect(ok['status'], isNot('REFUSED'), reason: '$ok');
      expect(ok['expenseId'], isA<String>(), reason: '$ok');
      final upload = DevApi.expectOk(
        await owner.get('/expenses/uploads/${ok['uploadId']}'),
      ).map;
      expect(upload['status'], 'CLEAN', reason: '$upload');
      DevApi.expectOk(
        await owner.post('/expenses/${ok['expenseId']}/reject', {
          'reason': 'QA ניקוי $runTag',
        }),
      );

      const eicar =
          r'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*';
      final bad = await owner.uploadExpense(ascii.encode(eicar));
      final record = DevApi.expectOk(
        await owner.get('/expenses/uploads/${bad['uploadId']}'),
      ).map;
      debugPrint(
        'AT-04 dev answer: $bad / ${record['status']} ${record['lastError']}',
      );
      expect(
        record['expenseId'],
        isNull,
        reason: 'EICAR must never become an expense: $record',
      );
      // A real scanner answers REJECTED_MALWARE (app: SCANNER_INFECTED); without
      // one the dev content check refuses it first (UPLOAD_REJECTED / SCAN_FAILED).
      expect(
        ['REJECTED_MALWARE', 'SCAN_FAILED'],
        contains(record['status']),
        reason: '$record',
      );
    },
  );

  // ---- items (BE-15, S3) ---------------------------------------------------------

  testWidgets(
    'BE-15 (P1) items: PATCH / archive / restore (API) + S3 catalog autocomplete and "לשמור כפריט?"',
    (tester) async {
      final apiName = 'QA פריט API $runTag';
      final itemId =
          DevApi.expectOk(
                await owner.post('/items', {
                  'name': apiName,
                  'itemType': 'SERVICE',
                  'defaultUnitPriceMinor': '2500',
                  'currency': 'ILS',
                }),
                201,
              ).map['id']
              as String;
      DevApi.expectOk(
        await owner.patch('/items/$itemId', {'defaultUnitPriceMinor': '3000'}),
      );
      Future<Map<String, dynamic>?> item(
        String name, {
        bool archived = false,
      }) async {
        final r = DevApi.expectOk(
          await owner.get('/items', {
            'q': name,
            if (archived) 'includeArchived': '1',
          }),
        );
        final hit = r.list('items').where((i) => i['name'] == name);
        return hit.isEmpty ? null : hit.first;
      }

      expect((await item(apiName))?['default_unit_price_minor'], '3000');
      DevApi.expectOk(await owner.post('/items/$itemId/archive'));
      expect(
        await item(apiName),
        isNull,
        reason: 'archived items leave the catalog',
      );
      expect((await item(apiName, archived: true))?['archivedAt'], isNotNull);
      DevApi.expectOk(await owner.post('/items/$itemId/restore'));
      expect(await item(apiName), isNotNull);
      DevApi.expectOk(await owner.post('/items/$itemId/archive'));

      // S3 (squad B screen, D's items API): pick a catalog item, then save a new line as an item.
      final catalogName = 'QA קטלוג $runTag';
      final catalogId =
          DevApi.expectOk(
                await owner.post('/items', {
                  'name': catalogName,
                  'itemType': 'SERVICE',
                  'defaultUnitPriceMinor': '10000',
                  'currency': 'ILS',
                }),
                201,
              ).map['id']
              as String;
      final newName = 'QA חדש $runTag';

      await launchAppAs(tester, owner);
      atRoot((c) => openCompose(c, intent: 'REQUEST', customerId: debtorId));
      // "פרטים נוספים" lives in C's summary, which appears once there is an amount.
      await pumpUntil(
        tester,
        find.text('1'),
        timeout: const Duration(seconds: 30),
      );
      for (final d in ['1', '0', '0']) {
        await tapSafe(tester, find.text(d).last);
        await tester.pump(const Duration(milliseconds: 80));
      }
      await pumpUntil(
        tester,
        find.byKey(const Key('compose-more-details')),
        timeout: const Duration(seconds: 30),
      );
      await tester.ensureVisible(find.byKey(const Key('compose-more-details')));
      await tapSafe(tester, find.byKey(const Key('compose-more-details')));
      await pumpUntil(tester, find.byKey(const Key('s3-add-line')));
      await tester.ensureVisible(find.byKey(const Key('s3-add-line')));
      await tapSafe(tester, find.byKey(const Key('s3-add-line')));
      await pumpUntil(tester, find.byKey(const Key('s3-line-0-description')));
      await tester.enterText(
        find.byKey(const Key('s3-line-0-description')),
        'קטלוג $runTag',
      );
      await pumpUntil(
        tester,
        find.text(catalogName),
        what: 'catalog suggestion',
      );
      await tapSafe(tester, find.text(catalogName).last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        fieldText(tester, find.byKey(const Key('s3-line-0-price'))),
        anyOf('100', '118'),
        reason: 'catalog price (net, or gross when amounts include VAT)',
      );
      expect(
        find.byKey(const Key('s3-line-0-save-item')),
        findsNothing,
        reason: 'already a catalog item',
      );

      await tester.ensureVisible(find.byKey(const Key('s3-add-line')));
      await tapSafe(tester, find.byKey(const Key('s3-add-line')));
      await pumpUntil(tester, find.byKey(const Key('s3-line-1-description')));
      await tester.enterText(
        find.byKey(const Key('s3-line-1-description')),
        newName,
      );
      await tester.enterText(find.byKey(const Key('s3-line-1-price')), '55');
      await pumpUntil(
        tester,
        find.byKey(const Key('s3-line-1-save-item')),
        what: '"לשמור כפריט?"',
      );
      await tester.ensureVisible(find.byKey(const Key('s3-line-1-save-item')));
      await tapSafe(tester, find.byKey(const Key('s3-line-1-save-item')));
      await pumpUntil(
        tester,
        find.byKey(const Key('s3-line-1-item')),
        what: '"נשמר כפריט ✓"',
      );
      final saved = await eventually(
        () => item(newName),
        what: 'new item on the server',
      );
      expect(
        BigInt.parse('${saved['default_unit_price_minor']}'),
        greaterThan(BigInt.zero),
      );

      await closeApp(tester);
      await clearLocalDraft();
      await owner.post('/items/$catalogId/archive');
      await owner.post('/items/${saved['id']}/archive');
    },
  );
}
