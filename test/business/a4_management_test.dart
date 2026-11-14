// A4 (QA 2026-11-12): פרופיל לפי תפקיד (0.7), ניהול בלי כפילויות (1.5),
// "לצאת בלי לשמור?" (1.10), צוות busy-guard.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/account_page.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/sheets/s13_editor.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/screens/profile/profile_settings_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/allowed_urls.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  testWidgets('0.7: פרופיל = business form only with settingsBusiness', (
    tester,
  ) async {
    await pumpAs(
      tester,
      backend,
      Preset.employee,
      const ProfileSettingsScreen(),
    );
    expect(find.byType(AccountPage), findsOneWidget);
    expect(find.byType(EditorPage), findsNothing);
    expect(find.byKey(const Key('profile-settings-switcher')), findsNothing);
    expect(find.byKey(const Key('profile-plan-cta')), findsNothing);
    expect(find.byType(DesignBackButton), findsNothing); // a root tab

    resetSession();
    await pumpAs(tester, backend, Preset.owner, const ProfileSettingsScreen());
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.byKey(const Key('profile-settings-switcher')), findsOneWidget);
    expect(find.byKey(const Key('profile-plan-cta')), findsOneWidget);
  });

  testWidgets('1.5: quick actions do not repeat the settings rows', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const BusinessScreen());
    for (final id in [
      'reports',
      'team',
      'branding',
      'profile',
      'integrations',
      'numbering',
      'desktop',
    ]) {
      expect(
        find.byKey(Key('management-action-$id')),
        findsNothing,
        reason: id,
      );
    }
    // Customers are a tab of their own (§5, PM 2026-11-12).
    expect(find.byKey(const Key('management-action-customers')), findsNothing);
    expect(find.byKey(const Key('brow-team')), findsOneWidget);
    expect(find.text('עיצוב מסמכים ומיתוג'), findsOneWidget);
  });

  testWidgets('1.10: S13 with changes asks before closing; clean closes', (
    tester,
  ) async {
    var saves = 0;
    final config = EditorConfig(
      title: 'טופס',
      fields: const [EditorField(key: 'name', label: 'שם')],
      onSave: (_) async => saves++,
    );
    await pumpAs(
      tester,
      backend,
      Preset.owner,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  showEditorSheet(context, instance: 'x', config: config),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('text-name')), 'דנה');
    await settle(tester);

    await tester.tapAt(const Offset(20, 20)); // the barrier
    await settle(tester);
    expect(find.text('לצאת בלי לשמור?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discard-keep')));
    await settle(tester);
    expect(find.byType(EditorForm), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    await tester.tap(find.byKey(const Key('discard-confirm')));
    await settle(tester);
    expect(find.byType(EditorForm), findsNothing);
    expect(saves, 0);

    // Untouched form: one tap closes, no question.
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tapAt(const Offset(20, 20));
    await settle(tester);
    expect(find.text('לצאת בלי לשמור?'), findsNothing);
    expect(find.byType(EditorForm), findsNothing);
  });

  testWidgets('team: no second "שלח שוב" while the first is in flight', (
    tester,
  ) async {
    final hold = Completer<void>();
    backend.on('POST', '/business/invitations/:id/resend', (_) async {
      await hold.future;
      return FakeResponse(200, {'status': 'ok'});
    });
    await pumpAs(tester, backend, Preset.owner, const TeamPage());
    final menu = find.descendant(
      of: find.byKey(const Key('invitation-i1')),
      matching: find.byType(MoreMenu),
    );
    await tester.tap(menu);
    await settle(tester);
    await tester.tap(find.text('שלח שוב'));
    await tester.pump();
    await tester.pump();
    expect(menu, findsNothing); // ⋯ hidden while busy
    hold.complete();
    await settle(tester);
    expect(menu, findsOneWidget);
    expect(
      backend.calls('POST', '/business/invitations/:id/resend'),
      hasLength(1),
    );
  });

  test(
    'billing: Apple subscriptions go through the launch allow-list',
    () async {
      final launcher = FakeLauncher()..install();
      addTearDown(FakeLauncher.uninstall);
      expect(isAllowedLaunch(appleSubscriptionsUri), isTrue);
      expect(
        isAllowedLaunch(Uri.parse('https://apps.apple.com/other')),
        isFalse,
      );
      expect(await launchAllowed(appleSubscriptionsUri), isTrue);
      expect(launcher.opened, [appleSubscriptionsUri]);
    },
  );
}
