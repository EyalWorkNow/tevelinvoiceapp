// 0135 "האזור האישי של הלקוח": the "עוד" item (who sees it), the link sheet
// (WhatsApp / share / copy, the e-mail-missing error), the details row
// (status, revoke, new link) and the customer-message timeline row.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customer_timeline_api.dart';
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/screens/people/customer_timeline_screen.dart';
import 'package:invoice/screens/people/person_logic.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/people/person_sections.dart';
import 'package:invoice/screens/people/sheets/portal_link_sheet.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/util/labels/portal_he.dart';
import 'package:invoice/util/labels/timeline_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

const _url =
    'https://app.tevel.co.il/p/AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_abcde';

Map<String, dynamic> _link({String? lastLoginAt, String? text}) => {
  'url': _url,
  'createdAt': '2026-11-20T08:00:00Z',
  'lastLoginAt': lastLoginAt,
  'canVerify': true,
  'created': text != null,
  'whatsappText': ?text,
};

PersonActionFacts _facts({
  bool manage = true,
  bool money = true,
  bool email = true,
  bool archived = false,
}) => PersonActionFacts(
  hasPhone: true,
  hasWhatsapp: true,
  hasEmail: email,
  archived: archived,
  canDraft: true,
  canMoneyView: money,
  canManage: manage,
  crmReady: true,
);

void main() {
  group('"עוד" → שלח קישור לאזור האישי', () {
    List<String> more(PersonActionFacts f) =>
        personMoreActions(f, personRowActions(f));

    test('owner with money + an e-mail on file sees it (last action)', () {
      final ids = more(_facts());
      expect(ids, contains('portal'));
      expect(ids.last, 'portal');
      expect(serverActions, contains('portal'));
    });

    test('hidden without e-mail, without money / manage, or when archived', () {
      expect(more(_facts(email: false)), isNot(contains('portal')));
      expect(more(_facts(money: false)), isNot(contains('portal')));
      expect(more(_facts(manage: false)), isNot(contains('portal')));
      expect(more(_facts(archived: true)), isNot(contains('portal')));
    });
  });

  group('screens', () {
    late FakeBackend b;
    late FakeLauncher launcher;
    final shared = <String>[];

    setUp(() async {
      b = await eSetUp();
      loadReminderHold = ({customerId, documentId}) async => false;
      launcher = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      shared.clear();
      final before = textSharer;
      textSharer = (t) async => shared.add(t);
      addTearDown(() => textSharer = before);
    });

    Future<void> openPerson(
      WidgetTester t, {
      String? email = 'dana@example.com',
    }) async {
      installPeopleFakes(
        b,
        customers: [
          customerJson('c1', 'דנה לוי', phone: '050-1234567', email: email),
        ],
      );
      phone(t);
      await t.runAsync(() async {
        await signInAs(b, Preset.owner);
        await CustomerCrmStore.instance.loadForBusiness('b1', force: true);
      });
      await t.pumpWidget(eApp(const PersonScreen(id: 'c1')));
      await settle(t);
    }

    testWidgets('the "עוד" item opens the sheet: link, WhatsApp to the '
        'customer, share sheet, copy', (t) async {
      b
        ..json('GET', '/customers/:id/portal-link', {'link': null})
        ..json(
          'POST',
          '/customers/:id/portal-link',
          _link(text: 'היי דנה, האזור האישי שלך: $_url'),
          status: 201,
        );
      final copied = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openPerson(t);
      await t.tap(find.byKey(const Key('person-action-more')));
      await settle(t);
      expect(find.text(PortalHe.sendLink), findsOneWidget);
      await t.tap(find.byKey(const Key('person-more-portal')));
      await settle(t);
      expect(find.byKey(const Key('portal-link-sheet')), findsOneWidget);
      expect(find.text(_url), findsOneWidget);
      expect(find.text(PortalHe.neverLoggedIn), findsOneWidget);
      expect(b.calls('POST', '/customers/:id/portal-link'), hasLength(1));

      await t.tap(find.byKey(const Key('portal-link-whatsapp')));
      await settle(t);
      final wa = launcher.last!;
      expect(wa.host, 'wa.me');
      expect(wa.path, '/972501234567');
      expect(wa.queryParameters['text'], contains(_url));

      await t.tap(find.byKey(const Key('portal-link-share')));
      await settle(t);
      expect(shared.single, contains(_url));

      await t.tap(find.byKey(const Key('portal-link-copy')));
      await settle(t);
      expect(copied.single, _url);
      expect(find.text(PortalHe.copied), findsOneWidget);
    });

    testWidgets('no "עוד" item for a customer without an e-mail', (t) async {
      b.json('GET', '/customers/:id/portal-link', {'link': null});
      await openPerson(t, email: null);
      await t.tap(find.byKey(const Key('person-action-more')));
      await settle(t);
      expect(find.byKey(const Key('person-more-portal')), findsNothing);
    });

    testWidgets('a server refusal shows the error, never a half link', (
      t,
    ) async {
      b.error(
        'POST',
        '/customers/:id/portal-link',
        422,
        'CUSTOMER_EMAIL_MISSING',
      );
      phone(t);
      await t.runAsync(() => signInAs(b, Preset.owner));
      await t.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showPortalLinkSheet(
                    context,
                    customerId: 'c1',
                    name: 'דנה',
                    email: 'dana@example.com',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await settle(t);
      expect(find.byKey(const Key('portal-link-url')), findsNothing);
      expect(find.byKey(const Key('portal-link-whatsapp')), findsNothing);
      expect(find.textContaining('אימייל'), findsWidgets);
    });

    testWidgets('details row: status + last sign-in; revoke asks, calls '
        'DELETE and hides the row', (t) async {
      b
        ..json('GET', '/customers/:id/portal-link', {
          'link': _link(lastLoginAt: '2026-11-24T12:05:00Z'),
        })
        ..json('DELETE', '/customers/:id/portal-link', {'revoked': true});
      phone(t);
      await t.runAsync(() => signInAs(b, Preset.owner));
      await t.pumpWidget(
        eApp(
          const Scaffold(
            body: PersonPortalRow(customerId: 'c1', name: 'דנה'),
          ),
        ),
      );
      await settle(t);
      final value = t.widget<Text>(
        find.byKey(const Key('person-portal-value')),
      );
      expect(value.data, contains(PortalHe.rowActive));
      expect(value.data, contains('נכנס לאחרונה'));
      await t.tap(find.byKey(const Key('person-portal')));
      await settle(t);
      expect(find.byKey(const Key('portal-manage-sheet')), findsOneWidget);
      await t.tap(find.byKey(const Key('portal-revoke')));
      await settle(t);
      expect(find.text(PortalHe.revokeConfirmTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('portal-confirm')));
      await settle(t);
      expect(b.calls('DELETE', '/customers/:id/portal-link'), hasLength(1));
      expect(find.byKey(const Key('person-portal')), findsNothing);
      expect(find.text(PortalHe.revoked), findsOneWidget);
    });

    testWidgets('details row: "קישור חדש" confirms, regenerates, shows it', (
      t,
    ) async {
      b
        ..json('GET', '/customers/:id/portal-link', {'link': _link()})
        ..json(
          'POST',
          '/customers/:id/portal-link/regenerate',
          _link(text: 'חדש $_url'),
          status: 201,
        );
      phone(t);
      await t.runAsync(() => signInAs(b, Preset.owner));
      await t.pumpWidget(
        eApp(
          const Scaffold(
            body: PersonPortalRow(customerId: 'c1', name: 'דנה'),
          ),
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const Key('person-portal')));
      await settle(t);
      await t.tap(find.byKey(const Key('portal-regenerate')));
      await settle(t);
      expect(find.text(PortalHe.regenerateConfirmTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('portal-confirm')));
      await settle(t);
      expect(
        b.calls('POST', '/customers/:id/portal-link/regenerate'),
        hasLength(1),
      );
      expect(find.byKey(const Key('portal-link-sheet')), findsOneWidget);
    });

    testWidgets('no link → no row', (t) async {
      b.json('GET', '/customers/:id/portal-link', {'link': null});
      phone(t);
      await t.runAsync(() => signInAs(b, Preset.owner));
      await t.pumpWidget(
        eApp(
          const Scaffold(
            body: PersonPortalRow(customerId: 'c1', name: 'דנה'),
          ),
        ),
      );
      await settle(t);
      expect(find.byKey(const Key('person-portal')), findsNothing);
    });

    testWidgets('timeline: "הודעות מהלקוח" chip label and a multi-line row', (
      t,
    ) async {
      phone(t);
      await t.pumpWidget(
        eApp(
          const Scaffold(
            body: TimelineRow(
              item: TimelineItem(
                id: 'portal.message:1',
                kind: 'portal.message',
                at: '2026-11-25T09:00:00Z',
                atIsrael: '2026-11-25 11:00',
                data: {'text': 'אפשר לקבל עותק של החשבונית?'},
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('הודעה מהלקוח: אפשר לקבל עותק של החשבונית?'),
        findsOneWidget,
      );
      expect(TimelineHe.chips[TimelineSource.portal.name], 'הודעות מהלקוח');
    });
  });

  test('PortalHe.when: local day.month.year hour:minute', () {
    final s = PortalHe.when('2026-11-24T12:05:00Z');
    expect(s, matches(RegExp(r'^24\.11\.2026 \d\d:05$')));
    expect(PortalHe.when('nope'), '');
  });
}
