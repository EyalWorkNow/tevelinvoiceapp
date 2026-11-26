// 0136 וואטסאפ עסקי — screenshots with MOCKED data (the test FakeBackend, no
// server), light and dark. File handshake (host_shot.dart):
//
//   U=<sim udid>; OUT=$PWD/docs/qa/waba; R=/tmp/tevel-shot-waba
//   (while true; do [ -f $R ] && { xcrun simctl io $U screenshot "$OUT/$(cat $R).png"; rm -f $R; }; sleep 0.2; done) &
//   ~/flutter/bin/flutter test integration_test/waba_shots_test.dart -d $U --dart-define=SHOT_REQUEST=$R
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/groups/group_screen.dart';
import 'package:invoice/screens/whatsapp/wa_campaign_screen.dart';
import 'package:invoice/screens/whatsapp/whatsapp_business_screen.dart';
import 'package:invoice/state/caps.dart';

import '../test/business/e_harness.dart';
import '../test/fakes/fake_api.dart';
import 'host_shot.dart';

late WidgetTester t;

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  do {
    await t.pump(const Duration(milliseconds: 50));
  } while (DateTime.now().isBefore(end));
}

Future<void> shot(String name) async {
  await pumpMs(1200);
  await hostShot(name);
  await pumpMs(600);
}

Future<bool> tapIf(Finder f, {int waitMs = 1200}) async {
  for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
    await pumpMs(150);
  }
  if (f.evaluate().isEmpty) {
    print('AUDIT: not found: $f');
    return false;
  }
  await t.ensureVisible(f.first);
  await pumpMs(300);
  await t.tap(f.first, warnIfMissed: false);
  await pumpMs(waitMs);
  return true;
}

Map<String, dynamic> g(String id, String name, {int members = 0}) => {
  'id': id,
  'name': name,
  'color': 'green',
  'memberCount': members,
  'smart': null,
};

Map<String, dynamic> m(String id, String name, String phone) => {
  'id': id,
  'name': name,
  'phone': phone,
  'email': null,
  'balanceMinor': '0',
  'archived': false,
  'marketingConsent': true,
};

FakeBackend backend({
  bool connected = true,
  bool campaigns = false,
  bool sending = true,
}) {
  final b = FakeBackend()..install();
  b
    ..json('GET', '/customer-groups/:id', {
      'group': g('g1', 'לקוחות קבועים', members: 7),
      'status': {
        'members': 7,
        'active': 7,
        'owing': 0,
        'owingMinor': '0',
        'noPhone': 1,
        'noEmail': 3,
        'inactive': 0,
      },
      'members': [
        m('c1', 'דנה כהן', '0501234567'),
        m('c3', 'מיכל ברק', '0527654321'),
        m('c4', 'יוסי אברהם', '0541112233'),
        m('c5', 'רונית שלום', '0533334444'),
      ],
      'invites': null,
    });
  final wa = installWhatsAppBusinessFakes(b, connected: connected);
  wa.campaign = waCampaignJson(status: sending ? 'SENDING' : 'DONE');
  if (campaigns) {
    wa.campaigns = [
      waCampaignJson(status: 'DONE'),
      waCampaignJson(id: 'wc0', status: 'DONE'),
    ];
  }
  return b;
}

Future<void> open(
  FakeBackend b,
  Widget home, {
  Brightness brightness = Brightness.light,
}) async {
  await signInAs(b, Preset.owner);
  await t.pumpWidget(const SizedBox());
  await pumpMs(200);
  await t.pumpWidget(eApp(home, brightness: brightness));
  await pumpMs(2000);
}

Future<void> closeAll() async {
  navigatorKey.currentState!.popUntil((r) => r.isFirst);
  await pumpMs(700);
}

Future<void> run(Brightness br) async {
  final sfx = br == Brightness.dark ? '-dark' : '';

  // Settings: not connected.
  await open(
    backend(connected: false),
    const WhatsAppBusinessScreen(),
    brightness: br,
  );
  await shot('01-not-connected$sfx');

  // Settings: connected (top, then templates).
  await open(backend(), const WhatsAppBusinessScreen(), brightness: br);
  await shot('02-connected$sfx');
  await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
  await pumpMs(700);
  await shot('03-connected-templates$sfx');

  // New template sheet.
  await tapIf(find.byKey(const Key('wa-template-new')));
  await t.enterText(
    find.byKey(const Key('wa-template-text')),
    'שלום {שם}, החל ממחר מבצע חורף: 20% הנחה על כל הטיפולים. מחכים לך!',
  );
  await pumpMs(400);
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpMs(600);
  await shot('04-new-template$sfx');
  await closeAll();

  // Group → choice → campaign sheet → campaign screen.
  await open(backend(), const GroupScreen(id: 'g1'), brightness: br);
  await tapIf(find.byKey(const Key('group-action-broadcast')));
  await shot('05-group-choice$sfx');
  await tapIf(find.byKey(const Key('wa-choice-auto')), waitMs: 2000);
  await shot('06-campaign-sheet$sfx');
  await tapIf(find.byKey(const Key('wa-campaign-send')));
  await shot('07-campaign-confirm$sfx');
  await tapIf(find.byKey(const Key('wa-campaign-confirm-ok')), waitMs: 2000);
  await shot('08-campaign-sending$sfx');
  await t.drag(find.byType(Scrollable).first, const Offset(0, -500));
  await pumpMs(700);
  await shot('09-campaign-recipients$sfx');
  await closeAll();

  // Group page with previous campaigns → the list.
  await open(
    backend(campaigns: true),
    const GroupScreen(id: 'g1'),
    brightness: br,
  );
  await shot('10-group-previous-entry$sfx');
  await open(
    backend(campaigns: true),
    const WaCampaignsScreen(groupId: 'g1', groupName: 'לקוחות קבועים'),
    brightness: br,
  );
  await shot('11-previous-campaigns$sfx');

  // Error state.
  final err = FakeBackend()..install();
  installWhatsAppBusinessFakes(
    err,
    status: waStatusJson(
      status: 'ERROR',
      errorMessage: 'Meta ביטלה את ההרשאה לחשבון. צריך לחבר מחדש.',
    ),
  );
  await open(err, const WhatsAppBusinessScreen(), brightness: br);
  await shot('12-error$sfx');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('waba shots', (tester) async {
    t = tester;
    await eSetUp();
    await run(Brightness.light);
    await run(Brightness.dark);
  });
}
