// 0136 וואטסאפ עסקי: the pure logic ({שם} preview / Meta body, error and
// block mapping, preview lines, status maths, the connect-URL guard, the
// settings rows) and every screen / sheet: the settings page in its four
// states (unavailable / not connected → connect / connected / error), the
// new-template sheet, template details + delete, disconnect, the group's
// send choice, the campaign sheet (auto-select, preview, block, 409, no
// approved template), the campaign screen (auto-refresh while SENDING) and
// the previous-campaigns list.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/me.dart';
import 'package:invoice/api/whatsapp_business_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/groups/group_screen.dart';
import 'package:invoice/screens/whatsapp/wa_campaign_screen.dart';
import 'package:invoice/screens/whatsapp/wa_campaign_sheet.dart';
import 'package:invoice/screens/whatsapp/whatsapp_business_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/allowed_urls.dart';
import 'package:invoice/util/labels/whatsapp_business_he.dart';

import '../fakes/fake_api.dart';
import '../groups/groups_test.dart' show detailJson, installGroupFakes;

ApiException _api(String code, {int status = 409}) =>
    ApiException(status, code, 'שגיאה מהשרת');

void main() {
  group('logic', () {
    test('{שם} → the first name; Meta body maps {שם} → {{1}}', () {
      expect(waPreviewText('שלום {שם}!', 'דנה כהן'), 'שלום דנה!');
      expect(waPreviewText('{שם}, {שם}', 'רון'), 'רון, רון');
      expect(waPreviewText('בלי שם', 'דנה'), 'בלי שם');
      expect(waMetaBody('שלום {שם}, מבצע'), 'שלום {{1}}, מבצע');
      expect(waMetaBody('בלי שם'), 'בלי שם');
    });

    test('error mapping: the 409 codes in Hebrew, else the client text', () {
      expect(waErrorText(_api('QUOTA_EXCEEDED')), WaHe.errQuota);
      expect(waErrorText(_api('TEMPLATE_NOT_APPROVED')), WaHe.errNotApproved);
      expect(waErrorText(_api('WHATSAPP_NOT_CONNECTED')), WaHe.errNotConnected);
      expect(waErrorText(_api('DEMO_BUSINESS')), WaHe.errDemo);
      expect(waBlockText('NO_RECIPIENTS'), WaHe.nobody);
      expect(waBlockText('TEMPLATE_NOT_FOUND'), WaHe.errTemplateMissing);
      expect(waErrorText(_api('SOMETHING_ELSE')), 'שגיאה מהשרת');
      expect(waErrorText(StateError('x')), WaHe.errorFallback);
      expect(waBlockText(null), isNull);
      expect(waBlockText('QUOTA_EXCEEDED'), WaHe.errQuota);
      expect(waBlockText('אין מספיק מכסה'), 'אין מספיק מכסה');
      expect(waBlockText('weird'), WaHe.errorFallback);
    });

    test('preview lines: recipients, each skip reason, quota left', () {
      const p = WaCampaignPreview(
        recipients: 7,
        skippedNoConsent: 2,
        skippedNoPhone: 1,
        skippedArchived: 1,
        quotaLeft: 93,
        canSend: true,
      );
      expect(waPreviewLines(p), [
        'יישלח ל-7 לקוחות',
        '2 לא אישרו דיוור — מדולגים',
        'אחד בלי טלפון תקין — מדולג',
        'אחד לא פעיל — מדולג',
        'נשארו במכסה החודשית: 93',
      ]);
      expect(waPreviewLines(const WaCampaignPreview()).first, WaHe.nobody);
    });

    test('status: connected needs available; quota maths', () {
      final s = WaBusinessStatus.fromJson(waStatusJson(used: 450));
      expect(s.connected, isTrue);
      expect(s.quotaLeft, 50);
      expect(s.quotaFraction, closeTo(0.9, 1e-9));
      final over = WaBusinessStatus.fromJson(waStatusJson(used: 600));
      expect(over.quotaLeft, 0);
      expect(over.quotaFraction, 1.0);
      final off = WaBusinessStatus.fromJson(waStatusJson(available: false));
      expect(off.connected, isFalse);
      expect(WaHe.qualityLabel('GREEN'), 'גבוהה');
      expect(WaHe.qualityLabel('RED'), 'נמוכה');
      expect(WaHe.qualityLabel(null), 'עוד לא נקבעה');
      expect(WaHe.templateStatus('PENDING'), 'ממתין לאישור');
      expect(WaHe.templateStatus('APPROVED'), 'מאושר');
      expect(WaHe.templateStatus('REJECTED'), 'נדחה');
    });

    test('campaign JSON: counts, recipients, accepted', () {
      final c = WaCampaign.fromJson(waCampaignJson());
      expect(c.sending, isTrue);
      expect(c.counts.total, 4);
      expect(c.counts.accepted, 2);
      expect(c.recipients.map((r) => r.status), [
        'DELIVERED',
        'SENT',
        'FAILED',
        'QUEUED',
      ]);
      expect(c.recipients[2].errorMessage, 'המספר לא רשום בוואטסאפ');
    });

    test('connect page guard: only /wa/connect/<token> on the API host', () {
      bool ok(String u, [String? origin]) =>
          isWaConnectUrl(Uri.parse(u), apiOrigin: origin);
      expect(ok('https://invoice.crm.tevel.space/wa/connect/abc'), isTrue);
      expect(ok('https://evil.example/wa/connect/abc'), isFalse);
      expect(ok('http://invoice.crm.tevel.space/wa/connect/abc'), isFalse);
      expect(ok('https://invoice.crm.tevel.space/wa/connect/'), isFalse);
      expect(ok('https://invoice.crm.tevel.space/d/abc'), isFalse);
      expect(ok('https://a@invoice.crm.tevel.space/wa/connect/x'), isFalse);
      expect(
        ok('http://127.0.0.1:3031/wa/connect/abc', 'http://127.0.0.1:3031'),
        isTrue,
      );
      expect(
        ok('http://127.0.0.1:9999/wa/connect/abc', 'http://127.0.0.1:3031'),
        isFalse,
      );
      expect(
        () => openWaConnectPage(Uri.parse('https://evil.example/wa/connect/x')),
        throwsArgumentError,
      );
    });

    test('settings row: only when available, only with business:configure, '
        'under "עוד הגדרות"', () {
      final owner = Caps.fromMe(Me.fromJson(meJson(Preset.owner)));
      final employee = Caps.fromMe(Me.fromJson(meJson(Preset.employee)));
      List<String> keys(List<BusinessRowSpec> r) => [for (final x in r) x.key];
      expect(
        keys(moreSettingsRows(owner, memberCount: 3)),
        isNot(contains('whatsapp')),
      );
      expect(
        keys(moreSettingsRows(owner, memberCount: 3, whatsapp: true)),
        contains('whatsapp'),
      );
      expect(
        keys(businessRows(owner, memberCount: 3, whatsapp: true)),
        isNot(contains('whatsapp')),
      );
      expect(
        businessRows(
          owner,
          memberCount: 3,
          reminders: true,
          whatsapp: true,
        ).length,
        lessThanOrEqualTo(10),
      );
      expect(
        keys(allBusinessRows(employee, memberCount: 3, whatsapp: true)),
        isNot(contains('whatsapp')),
      );
    });
  });

  group('widgets', () {
    late FakeBackend backend;
    late Directory tmp;
    late FakeLauncher launcher;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('wa_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      resetSession();
      await AppCache.clearAll();
      backend = FakeBackend()..install();
      launcher = FakeLauncher()..install();
      waConnectPollEvery = const Duration(milliseconds: 300);
      waCampaignRefreshEvery = const Duration(milliseconds: 300);
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

    /// Scrolls the page's list until a lazily built [f] exists.
    Future<void> reveal(WidgetTester tester, Finder f) async {
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
        await tester.drag(list, const Offset(0, -300));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await flush(tester, 3);
      }
      if (f.evaluate().isEmpty) await reveal(tester, f);
      await tester.ensureVisible(f);
      await flush(tester, 3);
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await flush(tester);
    }

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Preset preset = Preset.owner,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => signInAs(backend, preset));
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

    testWidgets('unavailable: a plain sentence, nothing to tap', (
      tester,
    ) async {
      installWhatsAppBusinessFakes(
        backend,
        status: waStatusJson(available: false, status: 'NOT_CONNECTED'),
      );
      await pump(tester, const WhatsAppBusinessScreen());
      expect(find.byKey(const Key('wa-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('wa-connect')), findsNothing);
    });

    testWidgets('not connected: explanation → connect opens the one-time '
        'page in-app → the status refreshes to connected', (tester) async {
      final wa = installWhatsAppBusinessFakes(backend, connected: false);
      await pump(tester, const WhatsAppBusinessScreen());
      expect(find.byKey(const Key('wa-intro')), findsOneWidget);
      for (final line in WaHe.introPoints) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.byKey(const Key('wa-templates-empty')), findsNothing);
      await tap(tester, find.byKey(const Key('wa-connect')));
      expect(
        backend.calls('POST', '/whatsapp-business/connect-link'),
        hasLength(1),
      );
      expect(launcher.inApp, [Uri.parse(wa.connectUrl)]);
      expect(launcher.opened, isEmpty);
      expect(find.byKey(const Key('wa-waiting')), findsOneWidget);
      // The owner finishes on Meta's page; the poll picks it up.
      wa.status = waStatusJson();
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      expect(find.byKey(const Key('wa-connected')), findsOneWidget);
      expect(find.byKey(const Key('wa-waiting')), findsNothing);
    });

    testWidgets('connected: number, quality, quota bar, templates with '
        'status pills and the rejection reason', (tester) async {
      installWhatsAppBusinessFakes(backend);
      await pump(tester, const WhatsAppBusinessScreen());
      expect(find.text('+972 50-123-4567'), findsOneWidget);
      expect(find.text('סטודיו נועה'), findsWidgets);
      expect(find.text('גבוהה'), findsOneWidget);
      expect(find.byKey(const Key('wa-coexistence')), findsOneWidget);
      expect(find.text('120 מתוך 500 הודעות'), findsOneWidget);
      expect(find.text('נשארו 380 הודעות החודש'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('wa-quota-bar')),
      );
      expect(bar.value, closeTo(0.24, 1e-9));
      await reveal(tester, find.text('נדחה'));
      expect(find.text('מאושר'), findsOneWidget);
      expect(find.text('ממתין לאישור'), findsOneWidget);
      expect(find.text('נדחה'), findsOneWidget);
      expect(find.text('סיבה: תוכן פרסומי לא ברור'), findsOneWidget);
    });

    testWidgets('dark mode: the connected page renders', (tester) async {
      installWhatsAppBusinessFakes(backend);
      await pump(
        tester,
        const WhatsAppBusinessScreen(),
        brightness: Brightness.dark,
      );
      expect(find.byKey(const Key('wa-connected')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('new template: "הוסף שם לקוח" inserts {שם}, the bubble shows '
        'the name, footer and opt-out button; submit → PENDING', (
      tester,
    ) async {
      final wa = installWhatsAppBusinessFakes(backend);
      await pump(tester, const WhatsAppBusinessScreen());
      await tap(tester, find.byKey(const Key('wa-template-new')));
      expect(find.byKey(const Key('wa-template-sheet')), findsOneWidget);
      expect(find.byKey(const Key('wa-template-note')), findsOneWidget);
      // Empty → a validation message, nothing sent.
      await tap(tester, find.byKey(const Key('wa-template-submit')));
      expect(find.text(WaHe.textRequired), findsOneWidget);
      expect(backend.calls('POST', '/whatsapp-business/templates'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('wa-template-text')),
        'שלום ',
      );
      await tester.pump();
      await tap(tester, find.byKey(const Key('wa-template-name')));
      final field = tester.widget<TextField>(
        find.byKey(const Key('wa-template-text')),
      );
      expect(field.controller!.text, 'שלום {שם}');
      expect(
        tester.widget<Text>(find.byKey(const Key('wa-bubble-body'))).data,
        'שלום דנה',
      );
      expect(find.text(WaHe.footer), findsOneWidget);
      expect(find.text(WaHe.optOutButton), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-template-submit')));
      final post = backend.last('POST', '/whatsapp-business/templates')!;
      expect(post.body, {'bodyText': 'שלום {שם}'});
      expect(find.byKey(const Key('wa-template-sheet')), findsNothing);
      expect(wa.templates.first['status'], 'PENDING');
      await reveal(tester, find.byKey(const Key('wa-template-t2')));
      expect(find.text('ממתין לאישור'), findsNWidgets(2));
    });

    testWidgets('template details → delete with a confirm', (tester) async {
      final wa = installWhatsAppBusinessFakes(backend);
      await pump(tester, const WhatsAppBusinessScreen());
      await tap(tester, find.byKey(const Key('wa-template-t3')));
      expect(find.byKey(const Key('wa-template-details')), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-template-delete')));
      await tap(tester, find.byKey(const Key('wa-template-delete-confirm')));
      expect(
        backend
            .last('DELETE', '/whatsapp-business/templates/:id')!
            .params['id'],
        't3',
      );
      expect(wa.templates.map((t) => t['id']), ['t1', 't2']);
      expect(find.byKey(const Key('wa-template-t3')), findsNothing);
    });

    testWidgets('disconnect asks first, then shows the connect state', (
      tester,
    ) async {
      installWhatsAppBusinessFakes(backend);
      await pump(tester, const WhatsAppBusinessScreen());
      await tap(tester, find.byKey(const Key('wa-disconnect')));
      expect(find.text(WaHe.disconnectTitle), findsOneWidget);
      expect(backend.calls('DELETE', '/whatsapp-business'), isEmpty);
      await tap(tester, find.byKey(const Key('wa-disconnect-confirm')));
      expect(backend.calls('DELETE', '/whatsapp-business'), hasLength(1));
      expect(find.byKey(const Key('wa-intro')), findsOneWidget);
    });

    testWidgets('error: the message and "חיבור מחדש"', (tester) async {
      installWhatsAppBusinessFakes(
        backend,
        status: waStatusJson(
          status: 'ERROR',
          errorMessage: 'המספר נותק בצד של Meta',
        ),
      );
      await pump(tester, const WhatsAppBusinessScreen());
      expect(find.text('המספר נותק בצד של Meta'), findsOneWidget);
      expect(find.text(WaHe.reconnect), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-connect')));
      expect(launcher.inApp, hasLength(1));
    });

    testWidgets('group, not connected: the WhatsApp action is as before '
        '(straight to the broadcast sheet)', (tester) async {
      installGroupFakes(backend);
      installWhatsAppBusinessFakes(backend, connected: false);
      await pump(tester, const GroupScreen(id: 'g1'));
      await tap(tester, find.byKey(const Key('group-action-broadcast')));
      expect(find.byKey(const Key('wa-choice')), findsNothing);
      expect(find.byKey(const Key('group-broadcast')), findsOneWidget);
      expect(find.byKey(const Key('group-wa-campaigns')), findsNothing);
    });

    testWidgets('group, connected: choice → "תור הקשה" keeps the queue flow', (
      tester,
    ) async {
      installGroupFakes(backend);
      installWhatsAppBusinessFakes(backend);
      await pump(tester, const GroupScreen(id: 'g1'));
      await tap(tester, find.byKey(const Key('group-action-broadcast')));
      expect(find.byKey(const Key('wa-choice')), findsOneWidget);
      expect(find.text(WaHe.choiceAuto), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-choice-queue')));
      expect(find.byKey(const Key('group-broadcast')), findsOneWidget);
    });

    testWidgets('group, connected: automatic send → preview → confirm → the '
        'campaign screen refreshes until DONE; previous campaigns entry', (
      tester,
    ) async {
      installGroupFakes(backend);
      final wa = installWhatsAppBusinessFakes(backend);
      await pump(tester, const GroupScreen(id: 'g1'));
      expect(find.byKey(const Key('group-wa-campaigns')), findsNothing);
      await tap(tester, find.byKey(const Key('group-action-broadcast')));
      await tap(tester, find.byKey(const Key('wa-choice-auto')));
      expect(find.byKey(const Key('wa-campaign-sheet')), findsOneWidget);
      // Only approved templates are offered; the single one is preselected.
      expect(find.byKey(const Key('wa-campaign-template-t1')), findsOneWidget);
      expect(find.byKey(const Key('wa-campaign-template-t2')), findsNothing);
      await flush(tester);
      final preview = backend.last(
        'POST',
        '/customer-groups/:id/whatsapp-campaigns/preview',
      )!;
      expect(preview.body, {'templateId': 't1'});
      expect(find.text('יישלח ל-4 לקוחות'), findsWidgets);
      expect(find.text('2 לא אישרו דיוור — מדולגים'), findsOneWidget);
      expect(find.text('אחד בלי טלפון תקין — מדולג'), findsOneWidget);
      expect(find.text('נשארו במכסה החודשית: 380'), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-campaign-send')));
      expect(find.byKey(const Key('wa-campaign-confirm')), findsOneWidget);
      expect(
        backend.calls('POST', '/customer-groups/:id/whatsapp-campaigns'),
        isEmpty,
      );
      await tap(tester, find.byKey(const Key('wa-campaign-confirm-ok')));
      final start = backend.last(
        'POST',
        '/customer-groups/:id/whatsapp-campaigns',
      )!;
      expect(start.body, {'templateId': 't1'});
      expect(start.idempotencyKey, isNotNull);
      // The campaign screen.
      expect(find.byKey(const Key('wa-campaign')), findsOneWidget);
      expect(find.text(WaHe.sending), findsOneWidget);
      expect(find.byKey(const Key('wa-campaign-refreshing')), findsOneWidget);
      expect(find.byKey(const Key('wa-recipient-c4')), findsOneWidget);
      expect(find.text('המספר לא רשום בוואטסאפ'), findsOneWidget);
      expect(find.text('נכשל'), findsOneWidget);
      final before = backend.calls('GET', '/whatsapp-campaigns/:id').length;
      wa.campaign = waCampaignJson(status: 'DONE');
      await tester.pump(const Duration(milliseconds: 350));
      await flush(tester);
      expect(
        backend.calls('GET', '/whatsapp-campaigns/:id').length,
        greaterThan(before),
      );
      expect(find.text(WaHe.done), findsOneWidget);
      expect(find.byKey(const Key('wa-campaign-refreshing')), findsNothing);
      // DONE: no more polling.
      final settled = backend.calls('GET', '/whatsapp-campaigns/:id').length;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(
        backend.calls('GET', '/whatsapp-campaigns/:id'),
        hasLength(settled),
      );
      // Back on the group page: "קמפיינים קודמים".
      await tap(tester, find.byType(DesignBackButton).last);
      await flush(tester);
      expect(find.byKey(const Key('group-wa-campaigns')), findsOneWidget);
      await tap(tester, find.byKey(const Key('group-wa-campaigns')));
      expect(find.byKey(const Key('wa-campaigns')), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-campaign-row-wc1')));
      expect(find.byKey(const Key('wa-campaign')), findsOneWidget);
    });

    testWidgets('campaign sheet: no approved template → a link to create one', (
      tester,
    ) async {
      installGroupFakes(backend);
      final wa = installWhatsAppBusinessFakes(backend);
      wa.templates.removeWhere((t) => t['status'] == 'APPROVED');
      await pump(
        tester,
        const Scaffold(
          body: WaCampaignSheet(groupId: 'g1', groupName: 'ועד בית'),
        ),
      );
      expect(find.byKey(const Key('wa-campaign-none')), findsOneWidget);
      expect(find.text(WaHe.pendingNote), findsOneWidget);
      expect(find.byKey(const Key('wa-campaign-send')), findsNothing);
      await tap(tester, find.byKey(const Key('wa-campaign-create-template')));
      expect(find.byKey(const Key('wa-business')), findsOneWidget);
    });

    testWidgets('campaign sheet: a blocked preview disables send', (
      tester,
    ) async {
      final wa = installWhatsAppBusinessFakes(backend);
      wa.preview = {
        'recipients': 40,
        'skippedNoConsent': 0,
        'skippedNoPhone': 0,
        'skippedArchived': 0,
        'quotaLeft': 10,
        'canSend': false,
        'blockReason': 'QUOTA_EXCEEDED',
      };
      await pump(
        tester,
        const Scaffold(
          body: WaCampaignSheet(groupId: 'g1', groupName: 'ועד בית'),
        ),
      );
      await flush(tester);
      expect(find.byKey(const Key('wa-campaign-block')), findsOneWidget);
      expect(find.text(WaHe.errQuota), findsOneWidget);
      final send = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('wa-campaign-send')),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('campaign sheet: a 409 on send shows the Hebrew reason', (
      tester,
    ) async {
      installWhatsAppBusinessFakes(backend);
      backend.error(
        'POST',
        '/customer-groups/:id/whatsapp-campaigns',
        409,
        'TEMPLATE_NOT_APPROVED',
      );
      await pump(
        tester,
        const Scaffold(
          body: WaCampaignSheet(groupId: 'g1', groupName: 'ועד בית'),
        ),
      );
      await flush(tester);
      await tap(tester, find.byKey(const Key('wa-campaign-send')));
      await tap(tester, find.byKey(const Key('wa-campaign-confirm-ok')));
      expect(find.text(WaHe.errNotApproved), findsOneWidget);
      expect(find.byKey(const Key('wa-campaign-sheet')), findsOneWidget);
    });

    testWidgets('choice sheet: both paths, each returns its choice', (
      tester,
    ) async {
      WaSendChoice? got;
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open'),
                onPressed: () async => got = await showWaSendChoice(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.byKey(const Key('open')));
      expect(find.text(WaHe.choiceQueue), findsOneWidget);
      await tap(tester, find.byKey(const Key('wa-choice-auto')));
      expect(got, WaSendChoice.auto);
    });

    testWidgets('previous campaigns: rows with date, counts and pill', (
      tester,
    ) async {
      final wa = installWhatsAppBusinessFakes(backend);
      wa.campaigns = [waCampaignJson(status: 'DONE')];
      await pump(
        tester,
        const WaCampaignsScreen(groupId: 'g1', groupName: 'ועד בית'),
      );
      expect(find.byKey(const Key('wa-campaign-row-wc1')), findsOneWidget);
      expect(find.textContaining('3 מתוך 4 נשלחו'), findsOneWidget);
      expect(find.text(WaHe.done), findsOneWidget);
    });

    testWidgets('group detail fixture still loads with WhatsApp off', (
      tester,
    ) async {
      installGroupFakes(backend, detail: detailJson());
      await pump(tester, const GroupScreen(id: 'g1'));
      expect(find.byKey(const Key('group-status')), findsOneWidget);
      expect(find.byKey(const Key('group-wa-campaigns')), findsNothing);
    });
  });
}
