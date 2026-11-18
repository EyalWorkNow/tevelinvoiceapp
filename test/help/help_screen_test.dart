// 0120 "עזרה": the help chat — starters, answers with deep-link chips,
// "העבר לנציג" (from the app bar, after "can't help", when unavailable),
// typing indicator, offline + retry, and the row in B·חשבון.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/help_api.dart';
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/help/help_links.dart';
import 'package:invoice/screens/help/help_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/help_he.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Map<String, dynamic> _reply({
  String answer = 'נכנסים לניהול ובוחרים "בקשת תשלום".',
  bool canHelp = true,
  List<Map<String, String>> chips = const [],
}) => {
  'conversationId': '11111111-2222-4333-8444-555555555555',
  'answer': answer,
  'canHelp': canHelp,
  'chips': chips,
  'kbVersion': 'test',
  'remainingToday': 39,
};

void main() {
  late FakeBackend backend;

  setUp(() async {
    backend = await eSetUp();
    loadHelpStatus = () async => const HelpStatus(available: true);
  });

  tearDown(() => loadHelpStatus = fetchHelpStatus);

  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('help-input')), text);
    await tester.tap(find.byKey(const Key('help-send')));
    await settle(tester);
  }

  testWidgets('greeting, starters and the privacy notice', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    expect(find.text(HelpHe.greeting), findsOneWidget);
    expect(find.byKey(const Key('help-starter-0')), findsOneWidget);
    expect(find.text(HelpHe.privacyNotice), findsOneWidget);
  });

  testWidgets('a starter asks; the answer shows a chip that opens the screen', (
    tester,
  ) async {
    backend.json(
      'POST',
      '/help/chat',
      _reply(
        chips: [
          {
            'id': 'my-account',
            'label': 'החשבון שלי',
            'path': 'פרופיל → הגדרות',
            'route': '/business/account',
          },
        ],
      ),
    );
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await tester.tap(find.byKey(const Key('help-starter-0')));
    await settle(tester);

    final sent = backend.last('POST', '/help/chat')!.body;
    expect(sent['message'], HelpHe.starters.first);
    expect(sent.containsKey('conversationId'), isFalse);
    expect(find.text(HelpHe.starters.first), findsOneWidget); // echoed bubble
    expect(find.textContaining('בקשת תשלום'), findsWidgets);
    expect(find.byKey(const Key('help-starter-0')), findsNothing);

    // The follow-up carries the conversation id.
    await ask(tester, 'ומה אחר כך?');
    expect(
      backend.last('POST', '/help/chat')!.body['conversationId'],
      '11111111-2222-4333-8444-555555555555',
    );

    await tester.tap(find.byKey(const Key('help-chip-my-account')).first);
    await settle(tester);
    expect(find.byType(BusinessScreen), findsOneWidget);
  });

  testWidgets('typing indicator while the assistant answers', (tester) async {
    final answer = Completer<FakeResponse>();
    backend.on('POST', '/help/chat', (_) => answer.future);
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await tester.enterText(find.byKey(const Key('help-input')), 'שאלה');
    await tester.tap(find.byKey(const Key('help-send')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('help-typing')), findsOneWidget);
    answer.complete(FakeResponse(200, _reply()));
    await settle(tester);
    expect(find.byKey(const Key('help-typing')), findsNothing);
  });

  testWidgets('a chip for a screen this build lacks says so', (tester) async {
    backend.json(
      'POST',
      '/help/chat',
      _reply(
        chips: [
          {'id': 'vault', 'label': 'כספת', 'route': '/vault'},
        ],
      ),
    );
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await ask(tester, 'איפה הכספת?');
    await tester.tap(find.byKey(const Key('help-chip-vault')));
    await tester.pump();
    expect(find.text(HelpHe.chipUnavailable), findsOneWidget);
  });

  testWidgets('can\'t help → "העבר לנציג" sends the conversation', (
    tester,
  ) async {
    backend.json(
      'POST',
      '/help/chat',
      _reply(answer: 'לא יודע לענות על זה.', canHelp: false),
    );
    backend.json('POST', '/help/escalate', {
      'ticketId': 't1',
      'emailed': true,
      'escalationEmail': 'help@tevel.space',
      'contactEmail': 'owner@example.test',
    }, status: 201);
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await ask(tester, 'איך מחברים את הבנק?');
    expect(find.text(HelpHe.cannotHelpHint), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('help-cannot-escalate')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byKey(const Key('help-escalate-note')), 'דחוף');
    await tester.tap(find.byKey(const Key('help-escalate-send')));
    await settle(tester);

    final body = backend.last('POST', '/help/escalate')!.body;
    expect(body['conversationId'], '11111111-2222-4333-8444-555555555555');
    expect(body['reason'], 'ASSISTANT_CANNOT_HELP');
    expect(body['note'], 'דחוף');
    expect(body['appVersion'], isNotEmpty);
    expect(find.text(HelpHe.escalated('owner@example.test')), findsOneWidget);
  });

  testWidgets('unavailable (no key) → banner, input off, e-mail hand-over', (
    tester,
  ) async {
    loadHelpStatus = () async => const HelpStatus(available: false);
    backend.json('POST', '/help/escalate', {
      'ticketId': 't2',
      'emailed': true,
      'contactEmail': null,
    }, status: 201);
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    expect(find.text(HelpHe.unavailableTitle), findsOneWidget);
    expect(find.textContaining('help@tevel.space'), findsWidgets);
    final input = tester.widget<TextField>(find.byKey(const Key('help-input')));
    expect(input.enabled, isFalse);

    // Nothing written yet: the sheet asks for a note first.
    await tester.tap(find.byKey(const Key('help-unavailable-escalate')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('help-escalate-send')));
    await settle(tester);
    expect(backend.calls('POST', '/help/escalate'), isEmpty);
    expect(find.text(HelpHe.escalateEmpty), findsOneWidget);

    await tester.tap(find.byKey(const Key('help-unavailable-escalate')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('help-escalate-note')),
      'איך מוסיפים לוגו?',
    );
    await tester.tap(find.byKey(const Key('help-escalate-send')));
    await settle(tester);
    final body = backend.last('POST', '/help/escalate')!.body;
    expect(body['reason'], 'ASSISTANT_UNAVAILABLE');
    expect(body['note'], 'איך מוסיפים לוגו?');
    expect(body.containsKey('conversationId'), isFalse);
    expect(find.text(HelpHe.escalated(null)), findsOneWidget);
  });

  testWidgets('a 503 from /help/chat switches to the unavailable state', (
    tester,
  ) async {
    backend.error('POST', '/help/chat', 503, 'HELP_ASSISTANT_UNAVAILABLE');
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await ask(tester, 'שאלה');
    expect(find.byKey(const Key('help-unavailable')), findsOneWidget);
  });

  testWidgets('offline → error bubble; "נסו שוב" re-asks', (tester) async {
    var calls = 0;
    backend.on('POST', '/help/chat', (_) {
      calls++;
      if (calls == 1) throw const SocketException('offline');
      return FakeResponse(200, _reply(answer: 'תשובה אחרי חיבור'));
    });
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await ask(tester, 'שאלה');
    expect(find.byKey(const Key('help-retry')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('help-retry')),
        matching: find.byType(OutlinedButton),
      ),
    );
    await settle(tester);
    expect(find.text('תשובה אחרי חיבור'), findsOneWidget);
    expect(find.text('שאלה'), findsOneWidget); // not echoed twice
  });

  testWidgets('daily limit → message without retry', (tester) async {
    backend.error('POST', '/help/chat', 429, 'HELP_DAILY_LIMIT');
    await pumpAs(tester, backend, Preset.owner, const HelpScreen());
    await ask(tester, 'שאלה');
    expect(find.text(HelpHe.dailyLimit('help@tevel.space')), findsOneWidget);
    expect(find.byKey(const Key('help-retry')), findsNothing);
  });

  testWidgets('B·חשבון has the help row for every member', (tester) async {
    await pumpAs(tester, backend, Preset.employee, const AccountPage());
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-help')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('account-help')));
    await settle(tester);
    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('the "תמיכה" row opens the help chat too, with "העבר לנציג"', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const AccountPage());
    await tester.scrollUntilVisible(
      find.byKey(const Key('account-support')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('account-support')));
    await settle(tester);
    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.byKey(const Key('help-escalate')), findsOneWidget);
  });

  test('help extras and §5 routes are openable locations', () {
    expect(isHelpLocation('/sign-requests'), isTrue);
    expect(isHelpLocation('/compose?intent=REQUEST'), isTrue);
    expect(isHelpLocation('/business/team'), isTrue);
    expect(
      isHelpLocation('/doc/123'),
      isFalse,
    ); // no entity ids from the corpus
    expect(isHelpLocation('/vault'), isFalse);
  });
}
