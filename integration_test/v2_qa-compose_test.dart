// QA · qa-compose: SPEC-v2 §17 acceptance tests for the Composer, every
// document-type flow, quotes, approvals, signing and allocation — the real
// app against the dev API (:3031), with tap budgets from §7 (F3.1 counting,
// see qa_compose_helpers.dart). Server state is prepared and verified over
// HTTP as the preset users of docs/API-MOBILE.md. Creates test data in the
// dev business (customers "QA-C …"); never touches prod.
//
// Run (simulator runner only; one simulator, nothing else on :3031):
//   ~/flutter/bin/flutter test integration_test/v2_qa-compose_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3031 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-mobile-dev-storage/outgoing-emails
// Environment-dependent ATs are skipped unless enabled:
//   --dart-define=QA_SIGNING=true  (the dev business has a signing certificate + passphrase in QA_SIGNING_PASS)
//   --dart-define=QA_SHAAM=true    (ITA sandbox connected to the dev business)
//
// Not automated here (reason in the report): AT-18 (process kill mid-issue),
// AT-19 (camera/OCR, qa owner of expenses), AT-53 (no NONPROFIT dev business).
// ignore_for_file: file_names (the file name is fixed by the QA plan)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/signing_api.dart' as signing;
import 'package:invoice/screens/business/business_screen.dart'
    show businessRows;
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/compose/compose_submit.dart' show shareText;
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart'
    show pdfSharer, textSharer;
import 'package:invoice/screens/people/sheets/s2_customer.dart'
    show PickedContact, pickContact;
import 'package:invoice/ui/ds.dart';
import 'package:invoice/state/business_context.dart';
import 'package:invoice/util/composer_config.dart' show DocKind;
import 'package:invoice/util/labels/labels.dart';
import 'package:invoice/util/status_map.dart' show DocStatus;

import '../test/fakes/fake_launcher.dart';
import 'qa_compose_helpers.dart';
import 'qa_plans_guard.dart';

const bool qaSigning = bool.fromEnvironment('QA_SIGNING');
const String qaSigningPass = String.fromEnvironment('QA_SIGNING_PASS');
const bool qaShaam = bool.fromEnvironment('QA_SHAAM');

const Key composePrimary = Key('compose-primary');
const Key docPrimary = Key('doc-primary');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dismissPlansDuringTests();
  late FakeLauncher launcher;
  final shared = <String>[];

  setUp(() {
    launcher = FakeLauncher()..install();
    shared.clear();
    shareText = (t) async => shared.add(t);
    textSharer = (t) async => shared.add(t);
    pdfSharer = (bytes, name, {text}) async => shared.add('PDF $name');
    signing.signingBiometric = (_) async => true; // Face ID (mock) = success
  });
  tearDown(FakeLauncher.uninstall);
  tearDownAll(revokeDevUsers);

  // ---- shared steps ----------------------------------------------------------

  /// S2 page 1: the recent circle of [customerId] (1 tap, auto-advance).
  Future<void> pickRecent(
    WidgetTester tester,
    TapCounter t,
    String customerId,
  ) async {
    // "קיבלתי תשלום" shows the customers who paid you (s2-recent-payment-…).
    final circle = find.byWidgetPredicate(
      (w) =>
          w.key == Key('s2-recent-$customerId') ||
          w.key == Key('s2-recent-payment-$customerId'),
    );
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (circle.evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (circle.evaluate().isNotEmpty) {
      await t.tap(circle, why: 'S2 circle');
    } else {
      // QA round 1 finding (D): S2 sorts customers with documents ahead of the
      // ones picked on this device, so a just-picked customer without
      // documents never gets a circle once ≥8 customers have documents. Fall
      // back to search (typing is not counted, F3.1) so the rest of the AT runs.
      debugPrint('QA-FALLBACK: no S2 recent circle for $customerId → search');
      final name = await tester.runAsync(
        () async =>
            ((await ApiClient.instance.get(
                      '/customers/$customerId',
                    ))['customer']
                    as Map?)?['name']
                as String?,
      );
      await tester.enterText(find.byKey(const Key('s2-search')), name ?? '');
      final row = find.byKey(Key('s2-row-$customerId'));
      await pumpUntil(tester, row, reason: 'S2 search row of $customerId');
      await t.tap(row, why: 'S2 row (search)');
    }
    await pumpUntil(tester, find.byKey(const Key('compose-customer')));
  }

  /// Marks [customerId] as recently used on this device (a "לקוח אחרון").
  Future<void> makeRecent(WidgetTester tester, String customerId) =>
      tester.runAsync(() => rememberRecentForTest(customerId)).then((_) {});

  /// After the Composer's button: D is on screen.
  /// (+1.5 s so the C → D route transition finishes; until then the
  /// Composer's primary is still on stage and AT-90 would count it.)
  Future<void> waitForD(WidgetTester tester) async {
    await pumpUntil(
      tester,
      find.byType(DocumentScreen),
      timeout: const Duration(seconds: 90),
      reason: 'D after issuing',
    );
    await pumpFor(tester, const Duration(milliseconds: 1500));
  }

  /// Server: newest document of [customerId] (optionally of [type]).
  Future<Map<String, dynamic>> newestDoc(
    DevUser u,
    String customerId, {
    String? type,
  }) async {
    final docs = await docsOf(u, customerId);
    final list = type == null
        ? docs
        : docs.where((d) => d['documentType'] == type).toList();
    expect(
      list,
      isNotEmpty,
      reason: 'no ${type ?? ''} document for customer $customerId',
    );
    return docDetail(u, list.first['id'] as String);
  }

  /// The wa.me link of the last send. The dev API has no WhatsApp provider
  /// and QA customers have no e-mail, so POST /documents/:id/dispatch answers
  /// MANUAL_REQUIRED and D opens S6 instead of WhatsApp (by design, see
  /// test/compose_screen_test.dart "missing delivery channel"). Then the send
  /// is finished from S6 → "שלח בווטסאפ"; that tap is outside the journey's
  /// tap budget, which every caller checks before.
  Future<void> expectWhatsAppLink(WidgetTester tester, String needle) async {
    if (launcher.last == null && needle == '/d/') {
      // D's "הופק ✓" state or S6, whichever offers it.
      final send = find.text(DocumentHe.sendWhatsApp).hitTestable();
      await pumpUntil(
        tester,
        send,
        reason:
            '"${DocumentHe.sendWhatsApp}" after MANUAL_REQUIRED (no automatic channel on dev)',
      );
      await tester.tap(send.last);
      await pumpFor(tester, const Duration(seconds: 2));
    }
    final last = launcher.last;
    expect(last, isNotNull, reason: 'FakeLauncher was never called');
    expect(last.toString(), startsWith('https://wa.me/972'));
    expect(Uri.decodeFull(last.toString()), contains(needle));
  }

  /// Opens D of [id] (as a row in L would) and waits for its primary / ⋯.
  Future<void> openD(
    WidgetTester tester,
    String id, {
    bool quote = false,
  }) async {
    if (quote) {
      // ignore: unawaited_futures
      openQuoteForTest(id);
    } else {
      // ignore: unawaited_futures
      openDocumentForTest(id);
    }
    await pumpUntil(tester, find.byType(DocumentScreen));
    await pumpFor(
      tester,
      const Duration(seconds: 3),
    ); // GET /documents/:id + extras
  }

  /// ⋯ on D → [label] (2 counted taps).
  Future<void> menu(WidgetTester tester, TapCounter t, String label) async {
    await t.tap(moreButton(), why: '⋯');
    await pumpUntil(tester, find.text(label), reason: '⋯ item "$label"');
    await t.tap(find.text(label).last, why: label);
  }

  // ==== §7 journeys + Composer (P0a) ===============================================

  group('Composer journeys (§7, F3)', () {
    testWidgets(
      'AT-10 J1 מורשה: 3 taps → 320 FINALIZED, payment allocated, wa.me/972…/d/',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-paid')), why: 'קיבלתי תשלום');
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        expect(
          find.text(kindLabels[DocKind.taxInvoiceReceipt]!),
          findsNothing,
          reason: 'F1: no type name before issuing',
        );
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.issueAndWhatsApp,
        );
        expectAtMostOnePrimary('C');
        await t.tap(find.byKey(composePrimary), why: 'הפק ושלח בווטסאפ');
        await waitForD(tester);

        expect(t.taps, lessThanOrEqualTo(3), reason: 'J1 budget');
        await expectWhatsAppLink(tester, '/d/');
        final doc = await newestDoc(owner, cid);
        expect(doc['document_type'], 'TAX_INVOICE_RECEIPT');
        expect(['FINALIZED', 'ARCHIVED', 'SENT'], contains(doc['status']));
        expect(minor(doc['total_minor']), 118000);
        expect(
          minor(doc['paid_total_minor']),
          118000,
          reason: 'payment allocated to the 320',
        );
        expect(minor(doc['balance_minor']), 0);
        expectAtMostOnePrimary('D');
      },
    );

    testWidgets('AT-10b J1-לקוח-חדש: ≤5 taps (contact picker cell = 1)', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final name = 'QA-C חדש ${uniq()}';
      final phone = randomPhone();
      await signInApp(tester, owner);
      final t = TapCounter(tester);
      pickContact = () async {
        t.system(); // the contact cell in CNContactPicker
        return PickedContact(name: name, phones: [phone]);
      };

      await t.tap(find.byKey(const Key('intent-paid')), why: 'קיבלתי תשלום');
      // "+ לקוח חדש" opens an empty form; the contact picker is its own
      // action ("ייבוא מאנשי קשר": form + picker in one tap).
      final import = find.text(PeopleHe.importContactAction);
      await pumpUntil(tester, import);
      await t.tap(import, why: 'ייבוא מאנשי קשר');
      await pumpUntil(tester, find.byKey(const Key('s2-save')));
      await t.tap(find.byKey(const Key('s2-save')), why: 'שמור');
      await pumpUntil(tester, find.byKey(const Key('compose-customer')));
      await typeAmount(tester, '590');
      await t.tap(find.byKey(composePrimary), why: 'הפק ושלח בווטסאפ');
      await waitForD(tester);

      expect(t.taps, lessThanOrEqualTo(5), reason: 'J1-לקוח-חדש budget');
      await expectWhatsAppLink(tester, '/d/');
      // The dev business has hundreds of QA customers: search, not the first page.
      final customers =
          (await owner.must(
                'GET',
                '/customers?q=${Uri.encodeQueryComponent(name)}',
              ))['customers']
              as List;
      final created = customers
          .cast<Map<String, dynamic>>()
          .where((c) => c['name'] == name)
          .toList();
      expect(created, hasLength(1), reason: 'the new customer exists once');
      final doc = await newestDoc(owner, created.single['id'] as String);
      expect(doc['document_type'], 'TAX_INVOICE_RECEIPT');
    });

    testWidgets(
      'AT-10c J1-פעם-ראשונה (signing LOCKED, no saved passphrase): ≤5 taps',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final me = await owner.must('GET', '/me');
        expect(
          (me['signing'] as Map)['configured'],
          isTrue,
          reason: 'QA_SIGNING needs a signing certificate',
        );
        await owner.post('/settings/signing/lock'); // best effort: start LOCKED
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await tester.runAsync(() => signing.signingStorage.deleteAll());
        await makeRecent(tester, cid);
        final t = TapCounter(tester);
        signing.signingBiometric = (_) async {
          t.system(); // Face ID confirm
          return true;
        };

        await t.tap(find.byKey(const Key('intent-paid')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        await t.tap(find.byKey(composePrimary));
        await pumpUntil(
          tester,
          find.byKey(const Key('signing-dialog')),
          timeout: const Duration(seconds: 60),
        );
        await tester.enterText(
          find.byKey(const Key('signing-passphrase')),
          qaSigningPass,
        ); // autofocus: typing
        await t.tap(
          find.byKey(const Key('signing-save')),
          why: 'שמור עם Face ID',
        );
        await waitForD(tester);

        expect(t.taps, lessThanOrEqualTo(5), reason: 'J1-פעם-ראשונה budget');
        await expectWhatsAppLink(tester, '/d/');
      },
      skip: !qaSigning,
    );

    testWidgets(
      'AT-11 J1 פטור: 3 taps → 400, no VAT widget or "מע״מ" anywhere on the path',
      (tester) async {
        final owner = await devUser(paturEmail, businessId: patur);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        void noVat(String where) {
          expect(
            find.byKey(const Key('vat-breakdown')),
            findsNothing,
            reason: where,
          );
          expect(
            find.byKey(const Key('vat-toggle')),
            findsNothing,
            reason: where,
          );
          expect(find.text('מע״מ'), findsNothing, reason: where);
        }

        noVat('H');
        await t.tap(find.byKey(const Key('intent-paid')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '500');
        noVat('C');
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);
        noVat('D');

        expect(t.taps, lessThanOrEqualTo(3), reason: 'J13 budget');
        final doc = await newestDoc(owner, cid);
        expect(doc['document_type'], 'RECEIPT');
        expect(minor(doc['tax_total_minor']), anyOf(0, -1));
        await expectWhatsAppLink(tester, '/d/');
      },
    );

    testWidgets(
      'AT-12 J2: 3 taps → 305; wa.me…/d/; public page shows "לתשלום"',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-request')), why: 'בקש תשלום');
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.issueAndWhatsApp,
        );
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);

        expect(t.taps, lessThanOrEqualTo(3), reason: 'J2 budget');
        await expectWhatsAppLink(tester, '/d/');
        final doc = await newestDoc(owner, cid);
        expect(doc['document_type'], 'TAX_INVOICE');
        expect(minor(doc['balance_minor']), 118000);

        final profile =
            (await owner.must('GET', '/business/profile'))['profile']
                as Map<String, dynamic>;
        final url = RegExp(
          r'https?://\S+/d/[A-Za-z0-9_-]+',
        ).firstMatch(Uri.decodeFull(launcher.last.toString()))!.group(0)!;
        final page = await tester.runAsync(() => getPublic(url));
        expect(page!.status, 200);
        if ((profile['paymentLinkUrl'] as String? ?? '').isNotEmpty) {
          expect(
            page.raw,
            contains('לתשלום'),
            reason: 'public page with paymentLinkUrl',
          );
        }
      },
    );

    testWidgets(
      'AT-13 J3: row → D → "קיבלתי תשלום" → S5 → "רשום" = 3 taps → linked 400, open 0, "שולם"',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        // The state J2 leaves: a 305 with a PDF, sent by a WhatsApp link.
        final id = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 100000,
            shareLink: true,
          ),
        );
        await signInApp(tester, owner);
        final t = TapCounter(tester);

        final row = find.byKey(Key('doc-$id'));
        // "אחרונים" sits under the money card, intents and "לטיפול": below the
        // fold of H's lazy ListView, so scroll (not a tap) until the row is built.
        final end = DateTime.now().add(const Duration(seconds: 30));
        while (row.evaluate().isEmpty && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 300));
          final list = find.byKey(const Key('home-list'));
          if (list.evaluate().isNotEmpty)
            await tester.drag(list, const Offset(0, -250), warnIfMissed: false);
        }
        await pumpUntil(tester, row, reason: 'the 305 in "אחרונים"');
        await tester.ensureVisible(row);
        await tester.pump(const Duration(milliseconds: 300));
        await t.tap(row, why: 'row');
        await pumpUntil(tester, find.byKey(docPrimary));
        await pumpFor(tester, const Duration(seconds: 2));
        expectAtMostOnePrimary('D');
        if (primaryLabel(tester, docPrimary) == DocumentHe.recordPayment) {
          await t.tap(find.byKey(docPrimary), why: 'קיבלתי תשלום');
        } else {
          await menu(
            tester,
            t,
            DocumentHe.recordPayment,
          ); // costs 2 → over budget, reported below
        }
        await pumpUntil(tester, find.byKey(const Key('s5-record')));
        await t.tap(find.byKey(const Key('s5-record')), why: 'רשום');
        await pumpUntil(
          tester,
          find.descendant(
            of: find.byKey(const Key('doc-status-line')),
            matching: find.text(docStatusLabels[DocStatus.paid]!),
          ),
          timeout: const Duration(seconds: 60),
          reason: 'D status "שולם"',
        );

        expect(
          t.taps,
          lessThanOrEqualTo(3),
          reason: 'J3 budget (primary on a sent 305 must be "קיבלתי תשלום")',
        );
        final doc = await docDetail(owner, id!);
        expect(minor(doc['open_minor'] ?? doc['balance_minor']), 0);
        final docs = await docsOf(owner, cid);
        expect(
          docs.where((d) => d['documentType'] == 'RECEIPT'),
          isNotEmpty,
          reason: 'receipt 400 issued',
        );
      },
    );

    testWidgets('AT-14 מורשה switches to 300 in S3 ("פרטים נוספים")', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final cid = await createCustomer(owner, phone: randomPhone());
      await signInApp(tester, owner);
      await makeRecent(tester, cid);
      final t = TapCounter(tester);

      await t.tap(find.byKey(const Key('intent-request')));
      await pickRecent(tester, t, cid);
      await typeAmount(tester, '1180');
      await t.tap(find.byKey(const Key('compose-more-details')));
      final chip = find.descendant(
        of: find.byKey(const Key('s3-type')),
        matching: find.text(kindLabels[DocKind.transactionInvoice]!),
      );
      await pumpUntil(tester, chip, reason: 'S3 type chip 300');
      await t.tap(chip);
      await t.tap(find.text(CommonHe.done).last, why: 'סיום');
      await t.tap(find.byKey(composePrimary));
      await waitForD(tester);

      final doc = await newestDoc(owner, cid);
      expect(doc['document_type'], 'TRANSACTION_INVOICE');
    });

    testWidgets(
      'AT-15 defaults: description "תיקון דוד" and last method "העברה / ביט" come back',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-paid')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '354');
        await t.tap(find.byKey(const Key('compose-description')));
        await tester.enterText(
          find.byKey(const Key('description-field')),
          'תיקון דוד',
        );
        await t.tap(find.text(CommonHe.save).last);
        await t.tap(
          find.descendant(
            of: find.byKey(const Key('compose-methods')),
            matching: find.text(paymentMethodLabels['BANK_TRANSFER']!),
          ),
        );
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);
        final first = await newestDoc(owner, cid);
        expect(
          ((first['lines'] as List).first as Map)['description'],
          'תיקון דוד',
        );

        // Again from H: both defaults are pre-filled.
        resetHomeForTest();
        await pumpFor(tester, const Duration(seconds: 2));
        await t.tap(find.byKey(const Key('intent-paid')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '100');
        expect(
          find.descendant(
            of: find.byKey(const Key('compose-description')),
            matching: find.text('תיקון דוד'),
          ),
          findsOneWidget,
        );
        final chips = tester.widget<ChipRow<String>>(
          find.byKey(const Key('compose-methods')),
        );
        expect(chips.selected, 'BANK_TRANSFER');
        expect(paymentMethodLabels['BANK_TRANSFER'], 'העברה / ביט');
      },
    );

    testWidgets('AT-16 ₪50,000 → exactly one confirmation dialog', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final cid = await createCustomer(owner, phone: randomPhone());
      await signInApp(tester, owner);
      await makeRecent(tester, cid);
      final t = TapCounter(tester);

      await t.tap(find.byKey(const Key('intent-request')));
      await pickRecent(tester, t, cid);
      await typeAmount(tester, '50000');
      await t.tap(find.byKey(composePrimary));
      await pumpUntil(tester, find.byKey(const Key('big-amount-dialog')));
      expect(find.byKey(const Key('big-amount-dialog')), findsOneWidget);
      await t.tap(find.text(CommonHe.cancel).last);
      expect(
        find.byType(ComposeScreen),
        findsOneWidget,
        reason: 'cancel stays on C, nothing issued',
      );
      expect(await docsOf(owner, cid), isEmpty);
    });

    testWidgets(
      'AT-17 walk-in, 320 ₪6,000 before VAT → issued without allocation request',
      (tester) async {
        final owner = await devUser(ownerEmail);
        await signInApp(tester, owner);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-paid')));
        await pumpUntil(tester, find.byKey(const Key('s2-walkin')));
        await t.tap(find.byKey(const Key('s2-walkin')), why: 'לקוח מזדמן');
        await pumpUntil(tester, find.byKey(const Key('compose-customer')));
        await typeAmount(tester, '7080'); // 6,000 + 18%
        await t.tap(find.byKey(composePrimary));
        await pumpWhile(
          tester,
          () =>
              find.byType(DocumentScreen).evaluate().isEmpty &&
              find.byKey(const Key('vat-dealer-dialog')).evaluate().isEmpty,
          timeout: const Duration(seconds: 90),
        );
        expect(
          find.byKey(const Key('vat-dealer-dialog')),
          findsNothing,
          reason: 'walk-in is private (§4.9)',
        );
        await waitForD(tester);
        expect(launcher.opened, isEmpty, reason: 'walk-in has no phone');
        final list =
            (await owner.must(
                  'GET',
                  '/documents?documentType=TAX_INVOICE_RECEIPT&limit=1',
                ))['documents']
                as List;
        final doc = await docDetail(owner, (list.first as Map)['id'] as String);
        expect(minor(doc['total_minor']), 708000);
        expect(
          ['FINALIZED', 'ARCHIVED', 'SENT'],
          contains(doc['status']),
          reason: 'not WAITING_FOR_ALLOCATION',
        );
        expect(doc['allocation_number'], isNull);
      },
    );

    testWidgets(
      'AT-17b ח.פ. + unknown status, ₪6,000 before VAT → "עוסק מורשה?" → כן → issued; ₪5,000.00 → no dialog',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final over = await createCustomer(
          owner,
          phone: randomPhone(),
          taxId: '514000002',
          vatDealerStatus: 'UNKNOWN',
        );
        final at = await createCustomer(
          owner,
          phone: randomPhone(),
          taxId: '514000002',
          vatDealerStatus: 'UNKNOWN',
        );
        await signInApp(tester, owner);
        await makeRecent(tester, over);
        await makeRecent(tester, at);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, over);
        await typeAmount(tester, '7080');
        await t.tap(find.byKey(composePrimary));
        await pumpUntil(
          tester,
          find.byKey(const Key('vat-dealer-dialog')),
          timeout: const Duration(seconds: 60),
          reason: 'evaluate → REQUIRES_USER_INPUT → dialog',
        );
        await t.tap(find.byKey(const Key('vat-dealer-yes')));
        await waitForD(tester);
        final c = (await owner.must('GET', '/customers/$over'));
        final cust = (c['customer'] ?? c) as Map<String, dynamic>;
        expect(
          cust['vat_dealer_status'] ?? cust['vatDealerStatus'],
          'AUTHORIZED_DEALER',
        );

        resetHomeForTest();
        // The first issue's toasts ("הופק", first-issue note) are still queued and
        // cover C's primary button at the bottom; the tap below would land on them.
        tester
            .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
            .clearSnackBars();
        await pumpFor(tester, const Duration(seconds: 2));
        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, at);
        await typeAmount(tester, '5900'); // exactly 5,000.00 before VAT
        await t.tap(find.byKey(composePrimary));
        await pumpWhile(
          tester,
          () =>
              find.byType(DocumentScreen).evaluate().isEmpty &&
              find.byKey(const Key('vat-dealer-dialog')).evaluate().isEmpty,
          timeout: const Duration(seconds: 90),
        );
        expect(
          find.byKey(const Key('vat-dealer-dialog')),
          findsNothing,
          reason: '5,000.00 is not > threshold (GT)',
        );
        final doc = await newestDoc(owner, at);
        expect(['FINALIZED', 'ARCHIVED', 'SENT'], contains(doc['status']));
      },
    );

    testWidgets('AT-30 שכפל → draft with the same lines and today\'s date', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final cid = await createCustomer(owner, phone: randomPhone());
      final id = await tester.runAsync(
        () => createDocument(
          owner,
          type: 'TAX_INVOICE',
          customerId: cid,
          unitPriceMinor: 25000,
          description: 'QA שכפול',
        ),
      );
      await signInApp(tester, owner);
      final t = TapCounter(tester);
      await openD(tester, id!);
      await menu(tester, t, DocumentHe.duplicate);
      await pumpUntil(
        tester,
        find.byType(ComposeScreen),
        reason: 'C on the duplicated draft',
      );

      final drafts = (await docsOf(
        owner,
        cid,
      )).where((d) => d['status'] == 'DRAFT').toList();
      expect(drafts, hasLength(1));
      final draft = await docDetail(owner, drafts.single['id'] as String);
      // A draft carries no issue date (null = "today" at finalize), never the source's date.
      expect(
        draft['issue_date'],
        anyOf(isNull, today()),
        reason: 'clone must not keep the source date',
      );
      final lines = (draft['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.single['description'], 'QA שכפול');
      expect(minor(lines.single['unit_price_minor']), 25000);
    });
  });

  // ==== quotes (§8.2.4, J5) ===========================================================

  group('Quotes (J5, AT-20)', () {
    testWidgets(
      'J5 create: ＋ → "הצעת מחיר" → customer → "שלח הצעה בווטסאפ" = 4 taps → SENT, wa.me…/q/',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        // ＋ now opens the invoice Composer directly (S1 is gone); a quote starts
        // from the management tab's "הצעת מחיר" action: same 2 taps.
        await t.tap(find.byKey(const Key('tab-business')), why: 'ניהול');
        await pumpUntil(
          tester,
          find.byKey(const Key('management-action-quote')),
        );
        await t.tap(
          find.byKey(const Key('management-action-quote')),
          why: 'הצעת מחיר',
        );
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.sendQuoteWhatsApp,
        );
        await t.tap(find.byKey(composePrimary));
        await pumpUntil(
          tester,
          find.byType(DocumentScreen),
          timeout: const Duration(seconds: 60),
        );

        expect(t.taps, lessThanOrEqualTo(4), reason: 'J5 create budget');
        await expectWhatsAppLink(tester, '/q/');
        final quotes = ((await owner.must('GET', '/quotes'))['quotes'] as List)
            .cast<Map<String, dynamic>>()
            .where((q) => q['customerId'] == cid)
            .toList();
        expect(quotes, hasLength(1));
        expect(quotes.single['status'], 'SENT');
      },
    );

    testWidgets(
      'AT-20 J5: SENT quote → D "הפוך לחשבונית" → C → issue = 3 taps → 305, same total, quote CONVERTED',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final qid = await tester.runAsync(
          () => createQuote(owner, cid, 100000, sent: true),
        );
        final quote = await quoteDetail(owner, qid!);
        await signInApp(tester, owner);
        final t = TapCounter(tester);

        t.system(); // (1) the quote row in L / its card
        await openD(tester, qid, quote: true);
        expect(primaryLabel(tester, docPrimary), DocumentHe.convertToInvoice);
        await t.tap(find.byKey(docPrimary), why: 'הפוך לחשבונית');
        await pumpUntil(tester, find.byType(ComposeScreen));
        await pumpUntil(
          tester,
          find.byKey(composePrimary),
          reason: 'C pre-filled from the quote',
        );
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);

        expect(t.taps, lessThanOrEqualTo(3), reason: 'J5 convert budget');
        final after = await quoteDetail(owner, qid);
        expect(
          after['status'],
          'CONVERTED',
          reason: 'SENT → ACCEPTED → CONVERTED',
        );
        final doc = await docDetail(
          owner,
          after['convertedDocumentId'] as String,
        );
        expect(doc['document_type'], 'TAX_INVOICE');
        expect(minor(doc['total_minor']), minor(quote['totalMinor']));
        expect(
          ((doc['lines'] as List).first as Map)['tax_rate_basis_points'],
          1800,
        );
      },
    );

    testWidgets('AT-20b DRAFT quote → ⋯ "הפוך לחשבונית" → convert directly', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final cid = await createCustomer(owner, phone: randomPhone());
      final qid = await tester.runAsync(() => createQuote(owner, cid, 50000));
      await signInApp(tester, owner);
      final t = TapCounter(tester);
      await openD(tester, qid!, quote: true);
      await menu(tester, t, DocumentHe.convertToInvoice);
      await pumpUntil(tester, find.byType(ComposeScreen));
      final after = await quoteDetail(owner, qid);
      expect(after['status'], 'CONVERTED');
      expect(after['convertedDocumentId'], isNotNull);
    });
  });

  // ==== credit / cancel (§8.3, J6) ====================================================

  group('Credit (J6, AT-21, AT-56)', () {
    testWidgets(
      'AT-21 J6 partial ₪200 of ₪1,180 = 3 taps → 330 169.49 + 30.51; source credited 200, open 980',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final id = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 100000,
            shareLink: true,
          ),
        );
        await signInApp(tester, owner);
        final t = TapCounter(tester);
        await openD(tester, id!);

        await menu(tester, t, DocumentHe.cancelOrCredit);
        await pumpUntil(tester, find.byKey(const Key('s8-amount')));
        await tester.enterText(
          find.byKey(const Key('s8-amount')),
          '200',
        ); // typing over = partial
        await tester.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const Key('s8-credit')), why: 'הפק זיכוי');
        await pumpWhile(
          tester,
          () => find.byKey(const Key('s8-credit')).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        expect(t.taps, lessThanOrEqualTo(3), reason: 'J6 budget');

        final src = await docDetail(owner, id);
        expect(minor(src['credited_minor'] ?? src['creditedMinor']), 20000);
        expect(minor(src['open_minor'] ?? src['openMinor']), 98000);
        final credit = (await docsOf(
          owner,
          cid,
        )).firstWhere((d) => d['documentType'] != 'TAX_INVOICE');
        final c = await docDetail(owner, credit['id'] as String);
        final lines = (c['lines'] as List).cast<Map<String, dynamic>>();
        expect(lines, hasLength(1));
        expect(minor(lines.single['subtotal_minor']), 16949);
        expect(minor(lines.single['tax_amount_minor']), 3051);
        expect(minor(c['total_minor']), 20000);

        // Source D: still "ממתין לתשלום".
        await openD(tester, id);
        expect(
          find.descendant(
            of: find.byKey(const Key('doc-status-line')),
            matching: find.text('ממתין לתשלום'),
          ),
          findsOneWidget,
        );

        // ₪1,000 more → refused; the maximum ₪980 is shown.
        await menu(tester, t, DocumentHe.cancelOrCredit);
        await pumpUntil(tester, find.byKey(const Key('s8-amount')));
        await tester.enterText(find.byKey(const Key('s8-amount')), '1000');
        await tester.pump(const Duration(milliseconds: 300));
        await t.tap(find.byKey(const Key('s8-credit')));
        // 's8-error' is the Text.rich itself and is always on stage (empty until
        // an error), so wait for its text, not for the widget.
        String s8Error() {
          final f = find.byKey(const Key('s8-error'));
          if (f.evaluate().isEmpty) return '';
          return tester.widget<Text>(f).textSpan?.toPlainText() ?? '';
        }

        await pumpWhile(
          tester,
          () => s8Error().isEmpty,
          timeout: const Duration(seconds: 30),
        );
        expect(s8Error(), contains('980'));
        final direct = await owner.post('/documents/$id/credit', {
          'scopeKey': 'default',
          'lines': [line('QA זיכוי', 100000)],
        }, true);
        // AT-21 names only the code; the server answers it as 409 (a state conflict).
        expect(direct.status, anyOf(409, 422));
        expect(direct.error, 'CREDIT_LIMIT_EXCEEDED');
      },
    );

    testWidgets('AT-21 full credit on another 305 → source label "בוטל"', (
      tester,
    ) async {
      final owner = await devUser(ownerEmail);
      final cid = await createCustomer(owner, phone: randomPhone());
      final id = await tester.runAsync(
        () => createDocument(
          owner,
          type: 'TAX_INVOICE',
          customerId: cid,
          unitPriceMinor: 50000,
          shareLink: true,
        ),
      );
      await signInApp(tester, owner);
      final t = TapCounter(tester);
      await openD(tester, id!);
      await menu(tester, t, DocumentHe.cancelOrCredit);
      await pumpUntil(tester, find.byKey(const Key('s8-credit')));
      await t.tap(find.byKey(const Key('s8-credit')), why: 'זיכוי מלא');
      await pumpWhile(
        tester,
        () => find.byKey(const Key('s8-credit')).evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );
      final src = await docDetail(owner, id);
      expect(src['cancelled'], isTrue);
      await openD(tester, id);
      // D opens from its cache first (02 §cache-first) and then refreshes.
      await pumpUntil(
        tester,
        find.descendant(
          of: find.byKey(const Key('doc-status-line')),
          matching: find.text('בוטל'),
        ),
        reason: 'status line "בוטל" after the refresh',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('doc-status-line')),
          matching: find.text('בוטל'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'AT-56 "בטל / זכה" only on 305/320; POST /credit on a 400 → 422 CREDIT_SOURCE_TYPE_INVALID',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final pay = await owner.must('POST', '/payments', {
          'method': 'CASH',
          'amountMinor': '20000',
          'currency': 'ILS',
          'paymentDate': today(),
        }, true);
        final rec = await owner.must('POST', '/receipts', {
          'scopeKey': 'default',
          'paymentIds': [
            {'id': pay['paymentId']},
          ],
          'customerId': cid,
        }, true);
        final receiptId = rec['receiptDocumentId'] as String;
        await owner.must('POST', '/documents/$receiptId/artifact');
        final inv = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 10000,
          ),
        );
        await signInApp(tester, owner);
        final t = TapCounter(tester);

        await openD(tester, receiptId);
        // A 400 may have no "⋯" at all (nothing to list) — then "בטל / זכה" is absent too.
        if (find.byTooltip('עוד').evaluate().isNotEmpty) {
          await t.tap(moreButton());
          expect(
            onScreen(DocumentHe.cancelOrCredit),
            isFalse,
            reason: '400: no "בטל / זכה"',
          );
          await tester.tapAt(const Offset(10, 10)); // close the ⋯ sheet
          await pumpFor(tester, const Duration(seconds: 1));
        } else {
          expect(
            onScreen(DocumentHe.cancelOrCredit),
            isFalse,
            reason: '400: no "בטל / זכה"',
          );
        }
        final bad = await owner.post('/documents/$receiptId/credit', {
          'scopeKey': 'default',
          'lines': [line('QA', 1000, vatBp: 0)],
        }, true);
        expect(bad.status, 422);
        expect(bad.error, 'CREDIT_SOURCE_TYPE_INVALID');

        await openD(tester, inv!);
        await t.tap(moreButton());
        expect(
          onScreen(DocumentHe.cancelOrCredit),
          isTrue,
          reason: '305: "בטל / זכה" present',
        );
      },
    );
  });

  // ==== approvals (§4.8, J7) ==========================================================

  group('Approvals (AT-22, 23, 41, 42, 43, 43b, 45, 57)', () {
    /// A 305 draft by [maker] submitted for approval.
    Future<String> submitted(
      DevUser maker,
      String cid,
      int unitPriceMinor,
    ) async {
      final d = await maker.must('POST', '/documents', {
        'documentType': 'TAX_INVOICE',
        'customerId': cid,
        'currency': 'ILS',
        'fiscalContext': 'default',
        'lines': [line('QA לאישור', unitPriceMinor)],
      });
      final id = d['id'] as String;
      await maker.must('POST', '/documents/$id/submit');
      return id;
    }

    /// Leaves exactly the QA approvals we create: older QA leftovers are rejected.
    Future<void> clearQaApprovals(DevUser owner) async {
      final pending =
          (await owner.must(
                'GET',
                '/documents?status=PENDING_APPROVAL&limit=100',
              ))['documents']
              as List;
      for (final d in pending.cast<Map<String, dynamic>>()) {
        if ('${d['customerName']}'.startsWith('QA')) {
          await owner.post('/documents/${d['id']}/reject', {
            'reason': 'QA cleanup',
          });
        }
      }
    }

    testWidgets(
      'AT-41 EMPLOYEE: no money card; Composer → "שלח לאישור" → PENDING_APPROVAL',
      (tester) async {
        final staff = await devUser(staffEmail);
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, staff);
        expect(find.byKey(const Key('home-money')), findsNothing);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);
        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        expect(primaryLabel(tester, composePrimary), ComposeHe.submit);
        await t.tap(find.byKey(composePrimary));
        await pumpWhile(
          tester,
          () => find.byType(ComposeScreen).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        final doc = await newestDoc(owner, cid);
        expect(doc['status'], 'PENDING_APPROVAL');
        expect(
          launcher.opened,
          isEmpty,
          reason: 'nothing is sent before approval',
        );
      },
    );

    testWidgets(
      'AT-22 J7: employee submits → owner: card → "אשר והפק" = 2 taps → FINALIZED, no launcher',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final staff = await devUser(staffEmail);
        await clearQaApprovals(owner);
        final cid = await createCustomer(owner, phone: randomPhone());
        final id = await submitted(staff, cid, 100000);
        await signInApp(tester, owner);
        final t = TapCounter(tester);

        final card = find.byKey(const Key('inbox-APPROVAL_NEEDED'));
        await pumpUntil(tester, card, reason: 'H card "ממתינים לאישורך"');
        await t.tap(card, why: 'card'); // the summary row itself is the action
        await pumpUntil(
          tester,
          find.byKey(docPrimary),
          reason: 'D of the single pending document',
        );
        await pumpFor(tester, const Duration(seconds: 2));
        expect(primaryLabel(tester, docPrimary), DocumentHe.approveAndIssue);
        await t.tap(find.byKey(docPrimary), why: 'אשר והפק');
        final end = DateTime.now().add(const Duration(seconds: 60));
        Map<String, dynamic> doc = await docDetail(owner, id);
        while (doc['status'] == 'PENDING_APPROVAL' &&
            DateTime.now().isBefore(end)) {
          await pumpFor(tester, const Duration(seconds: 1));
          doc = await docDetail(owner, id);
        }

        expect(
          t.taps,
          lessThanOrEqualTo(2),
          reason: 'J7 budget (needs exactly one pending approval)',
        );
        expect(['FINALIZED', 'ARCHIVED', 'SENT'], contains(doc['status']));
        expect(launcher.opened, isEmpty, reason: 'approving does not send');
      },
    );

    testWidgets(
      'AT-23 reject: reason required; the maker sees MY_REJECTED with the reason',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final staff = await devUser(staffEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final id = await submitted(staff, cid, 20000);
        final reason = 'QA סיבה ${uniq()}';
        await signInApp(tester, owner);
        final t = TapCounter(tester);
        await openD(tester, id);
        await menu(tester, t, DocumentHe.reject);
        await pumpUntil(tester, find.byKey(const Key('reason-field')));
        await t.tap(
          find.text(DocumentHe.reject).last,
          why: 'דחה with an empty reason',
        );
        expect(
          find.byKey(const Key('reason-field')),
          findsOneWidget,
          reason: 'reason is required',
        );
        await tester.enterText(find.byKey(const Key('reason-field')), reason);
        await t.tap(find.text(DocumentHe.reject).last);
        await pumpWhile(
          tester,
          () => find.byKey(const Key('reason-field')).evaluate().isNotEmpty,
        );
        await pumpFor(tester, const Duration(seconds: 2));

        final doc = await docDetail(staff, id);
        expect((doc['rejection'] as Map?)?['reason'], reason);
        final inbox = await staff.must('GET', '/mobile/inbox?limit=20');
        final cards = (inbox['cards'] ?? inbox['items'] ?? const []) as List;
        expect(
          cards.cast<Map<String, dynamic>>().where(
            (c) => c['kind'] == 'MY_REJECTED',
          ),
          isNotEmpty,
        );

        await signInApp(tester, staff);
        await openD(tester, id);
        expect(find.byKey(const Key('doc-rejection')), findsOneWidget);
        expect(find.textContaining(reason), findsWidgets);
      },
    );

    testWidgets(
      'AT-42 EMPLOYEE + מפיק בעצמו: "הפק ושלח בווטסאפ"; no "בטל / זכה", no "אשר והפק"; POST /credit → 403',
      (tester) async {
        final emp = await devUser(employeeSelfEmail);
        final owner = await devUser(ownerEmail);
        final staff = await devUser(staffEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final issued = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 10000,
            shareLink: true,
          ),
        );
        final pending = await submitted(staff, cid, 10000);
        await signInApp(tester, emp);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '118');
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.issueAndWhatsApp,
        );
        closeTopForTest(); // C has a close ✕, not a Cupertino back button
        await pumpFor(tester, const Duration(seconds: 1));

        await openD(tester, issued!);
        await t.tap(moreButton());
        expect(onScreen(DocumentHe.cancelOrCredit), isFalse);
        await tester.tapAt(const Offset(10, 10));
        await pumpFor(tester, const Duration(seconds: 1));

        await openD(tester, pending);
        expect(
          primaryLabel(tester, docPrimary),
          isNot(DocumentHe.approveAndIssue),
        );
        expect(onScreen(DocumentHe.approveAndIssue), isFalse);

        final credit = await emp.post('/documents/$issued/credit', {
          'scopeKey': 'default',
          'lines': [line('QA', 1000)],
        }, true);
        expect(credit.status, 403);
      },
    );

    testWidgets(
      'AT-57 EMPLOYEE backdated POST /documents → 403 BACKDATING_OWNER_ONLY',
      (tester) async {
        final staff = await devUser(staffEmail);
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner);
        final r = await staff.post('/documents', {
          'documentType': 'TAX_INVOICE',
          'customerId': cid,
          'currency': 'ILS',
          'fiscalContext': 'default',
          'issueDate': yesterday(),
          'lines': [line('QA', 1000)],
        });
        expect(r.status, 403);
        expect(r.error, 'BACKDATING_OWNER_ONLY');
      },
    );

    testWidgets(
      'AT-43 THRESHOLD ₪5,000 incl. VAT: 6,000 & 5,000.00 → "שלח לאישור", 4,999.99 → issue; partner approves',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final partner = await devUser(partnerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final set = await setApproval(
          owner,
          mode: 'THRESHOLD',
          thresholdMinor: 500000,
        );
        expect(set.ok, isTrue, reason: '$set');
        addTearDown(() => setApproval(owner, mode: 'NONE'));
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);

        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '4999.99');
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.issueAndWhatsApp,
        );
        await clearAmount(tester);
        await typeAmount(tester, '5000');
        expect(
          primaryLabel(tester, composePrimary),
          ComposeHe.submit,
          reason: '>= threshold',
        );
        await clearAmount(tester);
        await typeAmount(tester, '6000');
        expect(primaryLabel(tester, composePrimary), ComposeHe.submit);
        expectAtMostOnePrimary('C');
        await t.tap(find.byKey(composePrimary));
        await pumpWhile(
          tester,
          () => find.byType(ComposeScreen).evaluate().isNotEmpty,
          timeout: const Duration(seconds: 60),
        );
        final doc = await newestDoc(owner, cid);
        expect(doc['status'], 'PENDING_APPROVAL');

        await signInApp(tester, partner);
        await openD(tester, doc['id'] as String);
        expect(primaryLabel(tester, docPrimary), DocumentHe.approveAndIssue);
        await t.tap(find.byKey(docPrimary));
        final end = DateTime.now().add(const Duration(seconds: 60));
        var after = await docDetail(owner, doc['id'] as String);
        while (after['status'] == 'PENDING_APPROVAL' &&
            DateTime.now().isBefore(end)) {
          await pumpFor(tester, const Duration(seconds: 1));
          after = await docDetail(owner, doc['id'] as String);
        }
        expect(['FINALIZED', 'ARCHIVED', 'SENT'], contains(after['status']));
      },
    );

    testWidgets(
      'AT-45 THRESHOLD: owner receipt ₪6,000 and partner credit ₪6,000 issue without approval (BE-37)',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final partner = await devUser(partnerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final src = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 600000,
          ),
        ); // before the policy
        expect(
          (await setApproval(
            owner,
            mode: 'THRESHOLD',
            thresholdMinor: 500000,
          )).ok,
          isTrue,
        );
        addTearDown(() => setApproval(owner, mode: 'NONE'));

        final pay = await owner.must('POST', '/payments', {
          'method': 'CASH',
          'amountMinor': '600000',
          'currency': 'ILS',
          'paymentDate': today(),
        }, true);
        final rec = await owner.must('POST', '/receipts', {
          'scopeKey': 'default',
          'paymentIds': [
            {'id': pay['paymentId']},
          ],
          'customerId': cid,
        }, true);
        expect((rec['outcome'] as Map)['status'], 'FINALIZED');

        final credit = await partner.post('/documents/$src/credit', {
          'scopeKey': 'default',
          'lines': [line('QA זיכוי', 508474)],
        }, true);
        expect(credit.ok, isTrue, reason: '$credit');
        expect((credit.json['outcome'] as Map)['status'], 'FINALIZED');
      },
    );

    testWidgets(
      'AT-43b solo business: THRESHOLD without self-approval → 422 APPROVAL_NO_OTHER_APPROVER',
      (tester) async {
        final solo = await devUser(
          paturEmail,
          businessId: patur,
        ); // the only member of its business
        final r = await setApproval(
          solo,
          mode: 'THRESHOLD',
          thresholdMinor: 100000,
        );
        addTearDown(() => setApproval(solo, mode: 'NONE'));
        expect(r.status, 422);
        expect(r.error, 'APPROVAL_NO_OTHER_APPROVER');
      },
    );
  });

  // ==== types, signing, allocation =====================================================

  group('Types, signing, allocation (AT-55, 63, 64, 60, 62, 90)', () {
    testWidgets(
      'AT-55 / AT-63 ניהול → more kinds: ≤6 allowed kinds, never 200/210/600/610',
      (tester) async {
        // S1 ("＋ → עוד סוגים") is gone: the other kinds are the management
        // tab's quick actions, the overflow ones under "פעולות נוספות".
        final owner = await devUser(ownerEmail);
        await signInApp(tester, owner);
        final t = TapCounter(tester);
        await t.tap(find.byKey(const Key('tab-business')));
        await pumpUntil(
          tester,
          find.byKey(const Key('management-quick-actions')),
        );
        Set<String> codes(String prefix) => {
          for (final e
              in find
                  .byWidgetPredicate(
                    (w) =>
                        w.key is ValueKey<String> &&
                        (w.key! as ValueKey<String>).value.startsWith(prefix),
                  )
                  .evaluate())
            (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
        };
        final kinds = codes('management-action-type-');
        if (find
            .byKey(const Key('management-action-more'))
            .evaluate()
            .isNotEmpty) {
          await t.tap(find.byKey(const Key('management-action-more')));
          await pumpUntil(tester, find.text('פעולות נוספות'));
          kinds.addAll(codes('management-more-type-'));
        }
        expect(kinds.length, inInclusiveRange(1, 6), reason: 'kinds: $kinds');
        for (final code in ['200', '210', '600', '610', '205', '310']) {
          expect(kinds, isNot(contains(code)), reason: 'type $code is W');
        }
        expect(
          businessRows(businessContext.caps, memberCount: 1).map((r) => r.key),
          contains('desktop'),
          reason: '"המשך במחשב" row in ניהול',
        );
      },
    );

    testWidgets(
      'AT-64 signing LOCKED → Face ID (mock) → unlock → artifact → share-link',
      (tester) async {
        final owner = await devUser(ownerEmail);
        await owner.post('/settings/signing/lock');
        final cid = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);
        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '1180');
        await t.tap(find.byKey(composePrimary));
        await pumpWhile(
          tester,
          () =>
              find.byType(DocumentScreen).evaluate().isEmpty &&
              find.byKey(const Key('signing-dialog')).evaluate().isEmpty,
          timeout: const Duration(seconds: 90),
        );
        if (find.byKey(const Key('signing-dialog')).evaluate().isNotEmpty) {
          await tester.enterText(
            find.byKey(const Key('signing-passphrase')),
            qaSigningPass,
          );
          await t.tap(find.byKey(const Key('signing-save')));
        }
        await waitForD(tester);
        await expectWhatsAppLink(tester, '/d/');

        // Face ID cancelled → D state 6 ("חתום והפק PDF").
        await owner.post('/settings/signing/lock');
        signing.signingBiometric = (_) async => false;
        final cid2 = await createCustomer(owner, phone: randomPhone());
        await signInApp(tester, owner);
        await makeRecent(tester, cid2);
        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid2);
        await typeAmount(tester, '590');
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);
        await pumpFor(tester, const Duration(seconds: 2));
        expect(primaryLabel(tester, docPrimary), DocumentHe.signAndIssue);
      },
      skip: !qaSigning,
    );

    testWidgets(
      'AT-60 successful allocation → "✓ אושר ברשות המסים" on D, no extra screen',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(
          owner,
          phone: randomPhone(),
          taxId: '514000002',
          vatDealerStatus: 'AUTHORIZED_DEALER',
        );
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);
        await t.tap(find.byKey(const Key('intent-request')));
        await pickRecent(tester, t, cid);
        await typeAmount(tester, '7080');
        await t.tap(find.byKey(composePrimary));
        await waitForD(tester);
        expect(t.taps, lessThanOrEqualTo(3));
        final doc = await newestDoc(owner, cid);
        if (doc['status'] == 'WAITING_FOR_ALLOCATION') {
          // AT-62: "המשך בלי מספר" only when the decision allows it.
          final alloc = await owner.must(
            'GET',
            '/documents/${doc['id']}/allocation',
          );
          await t.tap(moreButton());
          final allows = '${alloc['decision'] ?? ''}'.contains('CONTINUE');
          expect(onScreen(DocumentHe.continueWithoutNumber), allows);
        } else {
          expect(doc['allocation_number'], isNotNull);
          expect(find.textContaining('אושר ברשות המסים'), findsWidgets);
        }
      },
      skip: !qaShaam,
    );

    testWidgets(
      'AT-90 one PrimaryButton at most on C, D (every nextAction state reached above), S5, S8',
      (tester) async {
        final owner = await devUser(ownerEmail);
        final cid = await createCustomer(owner, phone: randomPhone());
        final id = await tester.runAsync(
          () => createDocument(
            owner,
            type: 'TAX_INVOICE',
            customerId: cid,
            unitPriceMinor: 10000,
            shareLink: true,
          ),
        );
        await signInApp(tester, owner);
        await makeRecent(tester, cid);
        final t = TapCounter(tester);
        await t.tap(find.byKey(const Key('intent-paid')));
        await pickRecent(tester, t, cid);
        expectAtMostOnePrimary('C (amount 0)');
        await typeAmount(tester, '10');
        expectAtMostOnePrimary('C');
        closeTopForTest(); // C has a close ✕, not a Cupertino back button
        await pumpFor(tester, const Duration(seconds: 1));

        await openD(tester, id!);
        expectAtMostOnePrimary('D 305 open');
        // On an open 305 "קיבלתי תשלום" is D's primary (§6.D), not a ⋯ item.
        if (primaryLabel(tester, docPrimary) == DocumentHe.recordPayment) {
          await t.tap(find.byKey(docPrimary), why: 'קיבלתי תשלום');
        } else {
          await menu(tester, t, DocumentHe.recordPayment);
        }
        await pumpUntil(tester, find.byKey(const Key('s5-record')));
        expectAtMostOnePrimary('S5');
      },
    );
  });
}
