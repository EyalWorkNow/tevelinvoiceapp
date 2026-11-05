// D + S5 / S6 / S8 widget tests (squad C) against the fakes: journeys with
// tap counts (J3, J6, J7), presets (AT-40/42/44), states (loading, error,
// offline, waiting), one PrimaryButton per surface (AT-90).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/signing_api.dart';
import 'package:invoice/util/sms_composer.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_parts.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/payments_ledger.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/screens/document/sheets/s8_cancel.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/primary_button.dart';

import '../fakes/fake_api.dart';

final otherApprover = {
  'mode': 'THRESHOLD',
  'thresholdMinor': '500000',
  'selfApprovalAllowed': false,
  'otherApproverExists': true,
};

void main() {
  late FakeBackend backend;
  late FakeLauncher launcher;
  late Directory tmp;
  late int taps;
  final sharedPdfs = <String>[];

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('document_screen_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    installActionsFakes(backend);
    launcher = FakeLauncher()..install();
    taps = 0;
    sharedPdfs.clear();
    pdfPreviewBuilder = (_) => const SizedBox(key: Key('pdf-preview'));
    pdfSharer = (Uint8List bytes, String name, {String? text}) async => sharedPdfs.add(name);
    signingBiometric = (_) async => true;
    await AppCache.clearAll();
  });

  tearDown(FakeLauncher.uninstall);

  /// Lets fake HTTP + file IO finish (real async), then draws.
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    taps++;
    await tester.ensureVisible(f);
    // Tap from the real zone: the handlers' file IO (AppCache) then completes.
    await tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await settle(tester);
  }

  Future<void> pumpDoc(WidgetTester tester, Preset preset,
      {String id = 'doc-1',
      bool quote = false,
      Map<String, dynamic>? policy,
      double textScale = 1,
      Size size = const Size(1170, 2532)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, preset, approvalPolicy: policy));
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: DocumentScreen(id: id, isQuote: quote),
    ));
    await settle(tester);
  }

  Finder primary() => find.byKey(const Key('doc-primary'));
  String primaryLabel(WidgetTester tester) => tester.widget<PrimaryButton>(primary()).label;

  Future<void> openMenu(WidgetTester tester) => tap(tester, find.byTooltip('עוד'));

  testWidgets('loading → skeleton; then header, PDF preview, status line, one primary', (tester) async {
    await pumpDoc(tester, Preset.owner);
    expect(find.text('חשבונית מס 1042'), findsOneWidget);
    expect(find.byKey(const Key('pdf-preview')), findsOneWidget);
    expect(find.text('ממתין לתשלום'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget); // AT-90
    expect(primaryLabel(tester), 'שלח בווטסאפ'); // row 8: never sent
    await tap(tester, find.byKey(const Key('doc-status-line')));
    expect(find.byKey(const Key('doc-timeline')), findsOneWidget);
    expect(find.text('הופק'), findsWidgets);
  });

  testWidgets('row 8 "שלח בווטסאפ": 1 tap → wa.me/972… with the /d/ link (AT-10 shape)', (tester) async {
    await pumpDoc(tester, Preset.owner);
    await tap(tester, primary());
    expect(taps, 1);
    expect(launcher.last.toString(), startsWith('https://wa.me/972501234567'));
    expect(Uri.decodeFull(launcher.last.toString()), contains('/d/tok123'));
    expect(Uri.decodeFull(launcher.last.toString()), contains("חשבונית מס מס' 1042"));
  });

  testWidgets('J3 / AT-13: D "קיבלתי תשלום" → S5 filled with the balance → "רשום" = 2 taps here', (tester) async {
    backend
      ..json('GET', '/documents', {'total': 1, 'documents': [docListRowJson(sentAt: '2026-10-30T09:00:00Z')]})
      ..on('POST', '/receipts', (_) {
        backend.json('GET', '/documents/:id', docDetailJson(paid: 118000));
        backend.json('GET', '/documents',
            {'total': 1, 'documents': [docListRowJson(open: 0, sentAt: '2026-10-30T09:00:00Z')]});
        return const FakeResponse(
            201, {'receiptDocumentId': 'rcp-1', 'outcome': {'status': 'FINALIZED', 'documentNumber': '77'}});
      });
    await pumpDoc(tester, Preset.owner);
    expect(primaryLabel(tester), 'קיבלתי תשלום'); // row 9
    await tap(tester, primary());
    expect(find.text('תשלום'), findsWidgets);
    final amount = tester.widget<TextField>(find.byKey(const Key('s5-amount-0')));
    expect(amount.controller!.text, '1180');
    expect(find.byType(PrimaryButton), findsNWidgets(2)); // D's + the sheet's (separate routes)
    await tap(tester, find.byKey(const Key('s5-record')));
    expect(taps, 2);
    final pay = backend.last('POST', '/payments')!;
    expect(pay.body['amountMinor'], '118000');
    expect(pay.body['method'], 'CASH');
    expect(backend.last('POST', '/receipts')!.body['forDocumentId'], 'doc-1');
    expect(find.text('הקבלה הופקה ✓'), findsOneWidget);
    expect(find.text('שלח קבלה בווטסאפ'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('doc-status-line')), 300);
    expect(find.text('שולם'), findsOneWidget);
    expect(primaryLabel(tester), 'שתף'); // row 16
  });

  testWidgets('S5: two payments over the balance → error, nothing sent; cheque needs its details',
      (tester) async {
    backend.json('GET', '/documents', {'total': 1, 'documents': [docListRowJson(sentAt: 'x')]});
    await pumpDoc(tester, Preset.owner);
    await tap(tester, primary());
    await tap(tester, find.byKey(const Key('s5-add')));
    await tester.enterText(find.byKey(const Key('s5-amount-1')), '50');
    await tap(tester, find.byKey(const Key('s5-record')));
    expect(find.textContaining('הסכום גבוה מהיתרה'), findsOneWidget);
    expect(backend.calls('POST', '/payments'), isEmpty);
    await tester.enterText(find.byKey(const Key('s5-amount-0')), '1130');
    await tap(tester, find.text("צ'ק").first);
    await tap(tester, find.byKey(const Key('s5-record')));
    expect(find.text("לצ'ק צריך בנק, סניף, חשבון ומספר צ'ק"), findsOneWidget);
    expect(backend.calls('POST', '/payments'), isEmpty);
  });

  testWidgets('J7 / AT-22: "אשר והפק" = 1 tap on D → approve with a key; WhatsApp not opened', (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(status: 'PENDING_APPROVAL', submittedBy: 'u-emp'));
    await pumpDoc(tester, Preset.owner, policy: otherApprover);
    expect(primaryLabel(tester), 'אשר והפק');
    await tap(tester, primary());
    expect(taps, 1);
    expect(backend.last('POST', '/documents/:id/approve')!.idempotencyKey, isNotNull);
    expect(backend.calls('POST', '/documents/:id/artifact'), hasLength(1));
    expect(launcher.opened, isEmpty);
    expect(find.text('אושר והופק ✓'), findsOneWidget);
  });

  testWidgets('AT-23: ⋯ "דחה" → reason is required → POST /reject {reason}', (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(status: 'PENDING_APPROVAL', submittedBy: 'u-emp'));
    await pumpDoc(tester, Preset.owner, policy: otherApprover);
    await openMenu(tester);
    await tap(tester, find.text('דחה'));
    await tap(tester, find.byKey(const Key('dialog-confirm')));
    expect(find.text('צריך לכתוב סיבה'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('reason-field')), 'חסר פירוט');
    await tap(tester, find.byKey(const Key('dialog-confirm')));
    expect(backend.last('POST', '/documents/:id/reject')!.body, {'reason': 'חסר פירוט'});
  });

  testWidgets('row 2: the submitter (another approver exists) sees "ממתין לאישור", no button, no ⋯',
      (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(status: 'PENDING_APPROVAL', submittedBy: 'u-me'));
    await pumpDoc(tester, Preset.employee);
    expect(find.byType(PrimaryButton), findsNothing);
    expect(find.byKey(const Key('doc-waiting')), findsOneWidget);
    expect(find.byTooltip('עוד'), findsNothing);
    expect(find.textContaining('אין הרשאה'), findsNothing);
  });

  testWidgets('row 3 rejected draft: reason above, "תקן ושלח שוב" opens C on the draft', (tester) async {
    backend.json('GET', '/documents/:id',
        docDetailJson(status: 'DRAFT', number: null, rejection: {'reason': 'חסר פירוט', 'by': 'u-o', 'at': 'x'}));
    await pumpDoc(tester, Preset.employee);
    expect(find.text('נדחה: חסר פירוט'), findsOneWidget);
    expect(primaryLabel(tester), 'תקן ושלח שוב');
    await tester.tap(primary());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect((c.intent, c.draftId), ('TYPE:305', 'doc-1'));
  });

  testWidgets('AT-40 viewer: "שתף" → S6 with PDF and PDF copy only (local share sheet)', (tester) async {
    await pumpDoc(tester, Preset.viewer);
    expect(primaryLabel(tester), 'שתף');
    expect(find.byTooltip('עוד'), findsNothing);
    await tap(tester, primary());
    expect(find.byKey(const Key('s6-whatsapp')), findsNothing);
    expect(find.byKey(const Key('s6-email')), findsNothing);
    expect(find.byKey(const Key('s6-qr')), findsNothing);
    expect(find.byKey(const Key('s6-copy')), findsNothing);
    await tap(tester, find.byKey(const Key('s6-pdf-primary')));
    expect(sharedPdfs, ['חשבונית מס 1042']);
    expect(backend.calls('POST', '/documents/:id/share-link'), isEmpty);
  });

  testWidgets('AT-42 employee + "מפיק בעצמו": ⋯ has no "בטל / זכה"', (tester) async {
    backend.json('GET', '/documents', {'total': 1, 'documents': [docListRowJson(sentAt: 'x')]});
    await pumpDoc(tester, Preset.employeeIssuer);
    expect(primaryLabel(tester), 'קיבלתי תשלום');
    await openMenu(tester);
    expect(find.text('בטל / זכה'), findsNothing);
    expect(find.text('שלח שוב'), findsOneWidget); // = S6; no separate "שתף" beside it
  });

  testWidgets('J6 / AT-21: ⋯ → "בטל / זכה" → type ₪200 → "הפק זיכוי" = 3 taps; red, partial lines', (tester) async {
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    // "בטל / זכה" is the last, red item
    await tap(tester, find.text('בטל / זכה'));
    expect(find.text('זיכוי מלא ₪1,180'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('s8-amount')));
    expect(field.focusNode!.hasFocus, isTrue); // typing over it needs no tap (F3.1)
    expect(tester.widget<PrimaryButton>(find.byKey(const Key('s8-credit'))).destructive, isTrue);
    await tester.enterText(find.byKey(const Key('s8-amount')), '200');
    await tester.pump();
    expect(find.text('זיכוי חלקי'), findsOneWidget);
    await tap(tester, find.byKey(const Key('s8-credit')));
    expect(taps, 3);
    final lines = backend.last('POST', '/documents/:id/credit')!.body['lines'] as List;
    expect(lines.single['unitPriceMinor'], '16949');
    // the credit opens in its own D
    expect(find.byType(DocumentScreen, skipOffstage: false), findsNWidgets(2));
    expect(backend.calls('GET', '/documents/:id').last.params['id'], 'cr-1');
  });

  testWidgets('S8: over the maximum after an earlier credit → "אפשר לזכות עד ₪980", no call', (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(credited: 20000));
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('בטל / זכה'));
    expect(find.text('זיכוי מלא ₪980'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('s8-amount')), '1000');
    await tap(tester, find.byKey(const Key('s8-credit')));
    expect(find.text('אפשר לזכות עד ₪980'), findsOneWidget);
    expect(backend.calls('POST', '/documents/:id/credit'), isEmpty);
  });

  testWidgets('S8 on a paid 300: "בטל מסמך" is not offered, the message is', (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(type: 'TRANSACTION_INVOICE', total: 50000, paid: 50000));
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('בטל / זכה'));
    expect(find.byKey(const Key('s8-void-blocked')), findsOneWidget);
    expect(find.byKey(const Key('s8-void')), findsNothing);
  });

  testWidgets('S6 e-mail: CONSENT_REQUIRED → "כן, הסכים" → consent → send again → process', (tester) async {
    var sends = 0;
    backend.on('POST', '/documents/:id/send', (_) {
      sends++;
      return sends == 1
          ? FakeResponse.error(409, 'CONSENT_REQUIRED')
          : const FakeResponse(202, {'deliveryId': 'del-9'});
    });
    backend.json('GET', '/documents', {'total': 1, 'documents': [docListRowJson(sentAt: 'x')]});
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('שלח שוב'));
    expect(find.byType(PrimaryButton), findsNWidgets(2)); // D + S6 (one each)
    await tap(tester, find.byKey(const Key('s6-email')));
    expect(tester.widget<TextField>(find.byKey(const Key('s6-email-field'))).controller!.text,
        'dana@example.test');
    await tap(tester, find.byKey(const Key('s6-email-send')));
    await tap(tester, find.byKey(const Key('consent-yes')));
    expect(backend.calls('POST', '/customers/:id/consent'), hasLength(1));
    expect(sends, 2);
    expect(backend.last('POST', '/deliveries/:id/process')!.params['id'], 'del-9');
    expect(find.text('המייל נשלח ✓'), findsOneWidget);
  });

  testWidgets('S6 QR opens the document independently of payment configuration',
      (tester) async {
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('שתף'));
    expect(find.text('סריקה לקבלת החשבונית'), findsOneWidget);
    await tap(tester, find.byKey(const Key('s6-qr')));
    expect(find.byKey(const Key('s6-qr-image')), findsOneWidget);
    expect(find.byKey(const Key('s6-revoke')), findsOneWidget);
  });

  testWidgets('SMS uses the entered number and cancellation never reports a sent message', (tester) async {
    final original=smsComposer;
    addTearDown(()=>smsComposer=original);
    String? phone,body;
    smsComposer=(to,text) async {phone=to;body=text;return 'CANCELLED';};
    await pumpDoc(tester,Preset.owner);
    await openMenu(tester);
    await tap(tester,find.text('שתף'));
    await tap(tester,find.byKey(const Key('s6-sms')));
    await tester.enterText(find.byKey(const Key('s6-phone-field')),'0501234567');
    await tap(tester,find.byKey(const Key('s6-sms-send')));
    expect(phone,'+972501234567');
    expect(body,contains('/d/'));
    expect(find.text('ההודעה נשלחה מהמכשיר'),findsNothing);
    expect(find.byKey(const Key('s6-sms')),findsOneWidget);
  });

  testWidgets('row 4: "נסה שוב" + allocation ⋯ items', (tester) async {
    backend
      ..json('GET', '/documents/:id', docDetailJson(status: 'WAITING_FOR_ALLOCATION'))
      ..json('GET', '/documents/:id/allocation', {'state': 'USER_ACTION_REQUIRED', 'userFacingHe': 'הרשות ביקשה הבהרה'});
    await pumpDoc(tester, Preset.owner);
    expect(primaryLabel(tester), 'נסה שוב');
    expect(find.text('הרשות ביקשה הבהרה'), findsOneWidget);
    await openMenu(tester);
    expect(find.text('המשך בלי מספר'), findsOneWidget);
    expect(find.text('בטל בקשה'), findsOneWidget);
    expect(find.text('הזן מספר ידנית'), findsNothing); // manualEntryEnabled false
    await tap(tester, find.text('המשך בלי מספר'));
    expect(backend.last('POST', '/documents/:id/allocation/decision')!.body, {'decision': 'CONTINUE'});
  });

  testWidgets('row 6 (AT-64): "חתום והפק PDF" → passphrase dialog → unlock → /sign', (tester) async {
    backend
      ..json('GET', '/documents/:id', docDetailJson(type: 'TAX_INVOICE_RECEIPT', status: 'ARTIFACT_PENDING', paid: 118000))
      ..error('POST', '/documents/:id/sign', 409, 'SIGNING_LOCKED')
      ..on('POST', '/settings/signing/unlock', (_) {
        backend.json('POST', '/documents/:id/sign', {'signing': 'SIGNED'});
        return const FakeResponse(200, {});
      });
    await pumpDoc(tester, Preset.owner);
    expect(primaryLabel(tester), 'חתום והפק PDF');
    await tap(tester, primary());
    await tester.enterText(find.byKey(const Key('passphrase-field')), 'pass-1');
    await tap(tester, find.byKey(const Key('passphrase-confirm')));
    expect(backend.last('POST', '/settings/signing/unlock')!.body, {'passphrase': 'pass-1'});
    expect(backend.calls('POST', '/documents/:id/sign'), hasLength(2));
  });

  testWidgets('quote SENT (AT-20): "הפוך לחשבונית" → ACCEPTED → convert → C on the new draft', (tester) async {
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true);
    expect(find.text('הצעת מחיר'), findsWidgets);
    expect(find.text('אצל הלקוח'), findsOneWidget);
    expect(primaryLabel(tester), 'הפוך לחשבונית');
    await tester.tap(primary());
    await settle(tester);
    expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'ACCEPTED'});
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect((c.draftId, c.fromQuoteId, c.intent), ('doc-new', 'q-1', 'TYPE:305'));
  });

  testWidgets('quote DRAFT: "שלח הצעה" → WhatsApp text, then status SENT', (tester) async {
    backend.json('GET', '/quotes', {'quotes': [quoteRowJson(status: 'DRAFT')]});
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true);
    await tap(tester, primary());
    expect(launcher.last.toString(), startsWith('https://wa.me/972'));
    expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'SENT'});
  });

  testWidgets('error → ErrorView "נסה שוב" → loads', (tester) async {
    backend.error('GET', '/documents/:id', 500, 'INTERNAL');
    await pumpDoc(tester, Preset.owner);
    expect(find.text('נסה שוב'), findsOneWidget);
    installActionsFakes(backend);
    await tap(tester, find.text('נסה שוב'));
    expect(find.text('חשבונית מס 1042'), findsOneWidget);
  });

  testWidgets('offline with a cached copy: banner + primary shows "אין חיבור" (F5 exception)', (tester) async {
    await tester.runAsync(() => AppCache.write('doc_b1_doc-1', docDetailJson()));
    backend.on('GET', '/documents/:id', (_) => throw const SocketException('offline'));
    await pumpDoc(tester, Preset.owner);
    expect(find.text('אין חיבור – מציג נתונים אחרונים'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(primary()).offline, isTrue);
  });

  testWidgets('AT-70: 200% text on a 320pt phone — D, S5, S6, S8 and a quote lay out without overflow',
      (tester) async {
    backend.json('GET', '/documents', {'total': 1, 'documents': [docListRowJson(sentAt: 'x')]});
    await pumpDoc(tester, Preset.owner, textScale: 2, size: const Size(960, 1704));
    expect(tester.takeException(), isNull);
    await tap(tester, primary()); // S5
    expect(tester.takeException(), isNull);
    navigatorKey.currentState!.pop();
    await settle(tester);
    // S8 opened directly: DS's MoreMenu sheet itself overflows at 200% with
    // 4 items on a 320×568 phone (reported to DS; not a squad C surface).
    unawaited(showCancelSheet(navigatorKey.currentContext!, documentId: 'doc-1'));
    await settle(tester);
    expect(find.byKey(const Key('s8-credit')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'S8');
    navigatorKey.currentState!.pop();
    await settle(tester);
    unawaited(showShareSheet(navigatorKey.currentContext!, documentId: 'doc-1'));
    await settle(tester);
    expect(find.byKey(const Key('s6-whatsapp')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'S6');
  });

  testWidgets('AT-70: 200% quote card', (tester) async {
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true, textScale: 2, size: const Size(960, 1704));
    expect(tester.takeException(), isNull);
    expect(find.byType(PrimaryButton), findsOneWidget);
  });

  // ---- P1 (SRV-2 endpoints) -------------------------------------------------

  testWidgets('BE-12: sentAt from the timeline (no list call) → row 9; timeline, payments, links; link opens D',
      (tester) async {
    backend.json(
        'GET',
        '/documents/:id',
        docDetailJson(
          paid: 50000,
          dueDate: '2026-11-29',
          timeline: [
            timelineJson('document.finalized'),
            timelineJson('document.shared', at: '2026-10-30T09:00:00.000Z'),
            timelineJson('document.share_downloaded', at: '2026-10-30T10:00:00.000Z'),
            timelineJson('payment.allocated', detail: {'amountMinor': '50000'}),
            timelineJson('some.internal_event'),
          ],
          payments: [
            {'id': 'p1', 'method': 'CASH', 'amountMinor': '50000', 'allocatedMinor': '50000',
              'paymentDate': '2026-10-30', 'reference': null, 'receiptDocumentId': 'rcp-1', 'voidedAt': null},
          ],
          linked: [
            {'id': 'rcp-1', 'type': 'RECEIPT', 'number': '77', 'status': 'ARCHIVED', 'totalMinor': '50000',
              'relation': 'RECEIPT'},
          ],
        ));
    await pumpDoc(tester, Preset.owner);
    expect(backend.calls('GET', '/documents'), isEmpty, reason: 'BE-12 replaces the list lookup');
    expect(primaryLabel(tester), 'קיבלתי תשלום'); // row 9: already sent
    expect(find.textContaining('לתשלום עד'), findsOneWidget); // BE-07
    expect(find.textContaining('נצפה'), findsOneWidget);
    await tap(tester, find.byKey(const Key('doc-status-line')));
    expect(find.text('הלקוח צפה'), findsOneWidget);
    expect(find.text('נרשם תשלום'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('doc-link-rcp-1')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('doc-payments')), findsOneWidget);
    expect(find.text('קבלה 77'), findsOneWidget);
    backend.json('GET', '/documents/:id', docDetailJson(id: 'rcp-1', type: 'RECEIPT', number: '77', total: 50000));
    await tap(tester, find.byKey(const Key('doc-link-rcp-1')));
    expect(find.byType(DocumentScreen, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('BE-08: paid 300 of a VAT business → ⋯ "הפק חשבונית מס" (2 taps) → linked clone → C on 305',
      (tester) async {
    backend.json('GET', '/documents/:id',
        docDetailJson(type: 'TRANSACTION_INVOICE', paid: 118000, timeline: [timelineJson('document.shared')]));
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('הפק חשבונית מס'));
    expect(taps, 2);
    expect(backend.last('POST', '/documents/:id/clone')!.body, {'documentType': 'TAX_INVOICE', 'link': true});
    final c = tester.widget<ComposeScreen>(find.byType(ComposeScreen));
    expect((c.draftId, c.intent, c.fromDocId), ('doc-dup', 'TYPE:305', 'doc-1'));
  });

  testWidgets('BE-08: a 300 already converted shows no "הפק חשבונית מס"', (tester) async {
    backend.json(
        'GET',
        '/documents/:id',
        docDetailJson(type: 'TRANSACTION_INVOICE', paid: 118000, timeline: const [], linked: [
          {'id': 'd305', 'type': 'TAX_INVOICE', 'number': '12', 'status': 'ARCHIVED', 'totalMinor': '118000',
            'relation': 'CONVERTED_TO'},
        ]));
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    expect(find.text('הפק חשבונית מס'), findsNothing);
  });

  testWidgets('BE-06 quote DRAFT: PDF preview; "שלח הצעה" → share link in the WhatsApp text → SENT', (tester) async {
    installQuoteDetail(backend, status: 'DRAFT');
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true);
    expect(find.byKey(const Key('pdf-preview')), findsOneWidget);
    expect(backend.calls('GET', '/quotes/:id/pdf'), hasLength(1));
    await tap(tester, primary());
    expect(taps, 1);
    expect(backend.calls('POST', '/quotes/:id/share-link'), hasLength(1));
    expect(Uri.decodeFull(launcher.last.toString()), contains('/q/qtok'));
    expect(backend.last('POST', '/quotes/:id/status')!.body, {'to': 'SENT'});
  });

  testWidgets('BE-06 quote: ⋯ "שכפל" → POST /quotes/:id/clone → D of the new quote', (tester) async {
    installQuoteDetail(backend, status: 'REJECTED');
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true);
    expect(find.byKey(const Key('doc-waiting')), findsOneWidget); // row 15
    await openMenu(tester);
    await tap(tester, find.text('שכפל'));
    expect(backend.calls('POST', '/quotes/:id/clone'), hasLength(1));
    expect(find.byType(DocumentScreen, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('BE-06 quote: ⋯ "שתף" → the PDF through the share sheet', (tester) async {
    installQuoteDetail(backend);
    await pumpDoc(tester, Preset.owner, id: 'q-1', quote: true);
    await openMenu(tester);
    await tap(tester, find.text('שתף'));
    expect(sharedPdfs, ['הצעת מחיר']);
  });

  testWidgets('BE-12: a live link (timeline) shows "בטל קישור" in S6 → revoke', (tester) async {
    backend.json('GET', '/documents/:id', docDetailJson(timeline: [timelineJson('document.shared')]));
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('שלח שוב'));
    expect(find.byKey(const Key('s6-revoke')), findsOneWidget);
    await tap(tester, find.byKey(const Key('s6-revoke')));
    expect(backend.calls('POST', '/documents/:id/share-link/revoke'), hasLength(1));
  });

  testWidgets('BE-36: void 300 refused with DOCUMENT_HAS_PAYMENTS → Hebrew message in S8', (tester) async {
    backend
      ..json('GET', '/documents/:id', docDetailJson(type: 'SALES_ORDER', timeline: const []))
      ..error('POST', '/documents/:id/void', 409, 'DOCUMENT_HAS_PAYMENTS');
    await pumpDoc(tester, Preset.owner);
    await openMenu(tester);
    await tap(tester, find.text('בטל / זכה'));
    await tester.enterText(find.byKey(const Key('s8-reason')), 'כפול');
    await tap(tester, find.byKey(const Key('s8-void')));
    expect(find.text('יש תשלום. בטל קודם את הקבלה במחשב'), findsOneWidget);
  });

  testWidgets('BE-11 ledger (R → תקבולים): rows, ⋯ "בטל תשלום" only without a receipt → reason → void',
      (tester) async {
    await tester.runAsync(() => signInAs(backend, Preset.owner));
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      locale: const Locale('he', 'IL'),
      supportedLocales: const [Locale('he', 'IL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(Brightness.light),
      home: const Scaffold(body: SingleChildScrollView(child: PaymentsLedger(from: '2026-10-01', to: '2026-10-31'))),
    ));
    await settle(tester);
    expect(find.byKey(const Key('ledger-pay-1')), findsOneWidget);
    expect(find.textContaining('קבלה 9'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('ledger-pay-2')), matching: find.byTooltip('עוד')), findsNothing);
    await tap(tester, find.descendant(of: find.byKey(const Key('ledger-pay-1')), matching: find.byTooltip('עוד')));
    await tap(tester, find.text('בטל תשלום'));
    await tester.enterText(find.byKey(const Key('reason-field')), 'נרשם פעמיים');
    await tap(tester, find.byKey(const Key('dialog-confirm')));
    expect(backend.last('POST', '/payments/:id/void')!.body, {'reason': 'נרשם פעמיים'});
    expect(backend.calls('GET', '/payments').length, greaterThanOrEqualTo(2));
  });

  group('round-1 fixes (area C)', () {
    testWidgets('§6.D edge: FINALIZED without a stored original → created once, then the PDF', (tester) async {
      var reads = 0;
      backend
        ..json('GET', '/documents/:id', docDetailJson(status: 'FINALIZED'))
        ..on('GET', '/documents/:id/pdf', (_) {
          reads++;
          return reads == 1
              ? FakeResponse.error(404, 'ARTIFACT_REQUIRED')
              : const FakeResponse(200, samplePdfBytes);
        });
      await pumpDoc(tester, Preset.owner);
      expect(backend.calls('POST', '/documents/:id/artifact'), hasLength(1));
      expect(find.byKey(const Key('pdf-preview')), findsOneWidget);
    });

    testWidgets('no PDF for this viewer (ARTIFACT_REQUIRED): lines + total, row 7 text, never a blank box',
        (tester) async {
      backend
        ..json('GET', '/documents/:id', docDetailJson(status: 'FINALIZED', type: 'CREDIT_DOCUMENT'))
        ..error('GET', '/documents/:id/pdf', 404, 'ARTIFACT_REQUIRED');
      await pumpDoc(tester, Preset.viewer);
      expect(backend.calls('POST', '/documents/:id/artifact'), isEmpty);
      expect(find.byKey(const Key('doc-lines')), findsOneWidget);
      expect(find.text('ה-PDF של המסמך עוד לא נוצר'), findsOneWidget);
      expect(find.byKey(const Key('doc-waiting')), findsOneWidget);
      expect(primary(), findsNothing);
    });

    testWidgets('PDF failed (server) → lines + "נסה שוב" → loads', (tester) async {
      var reads = 0;
      backend.on('GET', '/documents/:id/pdf', (_) {
        reads++;
        return reads == 1
            ? FakeResponse.error(503, 'SERVICE_UNAVAILABLE')
            : const FakeResponse(200, samplePdfBytes);
      });
      await pumpDoc(tester, Preset.owner);
      expect(find.text('לא הצלחנו לטעון את ה-PDF'), findsOneWidget);
      await tap(tester, find.byKey(const Key('doc-pdf-retry')));
      expect(find.byKey(const Key('pdf-preview')), findsOneWidget);
    });

    testWidgets('BE-03 hidden amounts (another member\'s document): no PDF request, ₪•••, no share', (tester) async {
      final json = docDetailJson();
      final d = json['document'] as Map<String, dynamic>;
      for (final k in d.keys.toList()) {
        if (k.endsWith('minor')) d[k] = null;
      }
      d['created_by'] = 'u-someone-else';
      for (final l in (d['lines'] as List? ?? const [])) {
        final line = l as Map<String, dynamic>;
        for (final k in line.keys.toList()) {
          if (k.endsWith('minor')) line[k] = null;
        }
      }
      backend.json('GET', '/documents/:id', json);
      await pumpDoc(tester, Preset.employee);
      expect(backend.calls('GET', '/documents/:id/pdf'), isEmpty);
      expect(find.byKey(const Key('doc-total-hidden')), findsOneWidget);
      expect(find.text('₪0'), findsNothing);
      expect(primary(), findsNothing);
    });
  });
}
