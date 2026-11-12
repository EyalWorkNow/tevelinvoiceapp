import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/people/customer_crm_jobs.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/state/customer_crm_job_budget.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/allowed_urls.dart';
import 'package:invoice/util/crm_visit.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';

import 'fakes/fake_launcher.dart';

void main() {
  CustomerCrmJob sample() => CustomerCrmJob(
    id: 'visit',
    customerId: 'c1',
    customerName: 'דנה',
    title: 'ביקור שירות',
    scheduledAt: DateTime(2026, 11, 12, 14, 30),
    createdAt: DateTime(2026, 11),
    address: 'הרצל 12 & כניסה א',
    details: 'PRIVATE-ACCESS-CODE',
    budget: const CustomerCrmJobBudget(priceMinor: 125000, costMinor: 25000),
  );

  test(
    'appointment message contains public visit details, never internal notes or costs',
    () {
      final uri = crmVisitMessageUri(sample(), '0521234567')!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/972521234567');
      final message = uri.queryParameters['text']!;
      expect(message, contains('12.11.2026 בשעה 14:30'));
      expect(message, contains(sample().address));
      expect(message, isNot(contains('PRIVATE-ACCESS-CODE')));
      expect(message, isNot(contains('125000')));
      expect(crmVisitMessageUri(sample(), null), isNull);
    },
  );

  test('navigation opens only a fixed, encoded map search', () async {
    final launcher = FakeLauncher()..install();
    addTearDown(FakeLauncher.uninstall);
    final uri = crmVisitMapUri(sample())!;
    expect(uri.host, 'maps.apple.com');
    expect(uri.queryParameters, {'q': sample().address});
    expect(await launchAllowed(uri), isTrue);
    expect(launcher.last, uri);
    for (final target in [
      'https://maps.apple.com/redirect?q=x',
      'https://maps.apple.com/?q=x&url=https://evil.example',
      'https://maps.apple.com/?q=x&q=y',
      'https://maps.apple.com/?q=',
      'https://maps.apple.com/?q=x#other',
      'https://maps.apple.com:444/?q=x',
      'https://maps.apple.com.evil.example/?q=x',
      'https://user@maps.apple.com/?q=x',
    ]) {
      expect(isAllowedLaunch(Uri.parse(target)), isFalse, reason: target);
    }
    expect(crmVisitMapUri(sample().copyWith(address: '  ')), isNull);
  });

  testWidgets(
    'visit actions stay reachable on a small screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var navigated = false, composed = false;
      int? rescheduled;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CustomerCrmJobs(
                  jobs: [sample()],
                  enabled: true,
                  onEdit: (_) {},
                  onRepeat: (_) {},
                  onDelete: (_) {},
                  onStatus: (_, _) {},
                  onNavigate: (_) => navigated = true,
                  onMessage: (_) => composed = true,
                  onReschedule: (_, days) => rescheduled = days,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(CustomerCrmHe.navigate));
      await tester.tap(find.text(CustomerCrmHe.navigate));
      await tester.ensureVisible(find.text(CustomerCrmHe.visitMessage));
      await tester.tap(find.text(CustomerCrmHe.visitMessage));
      expect(navigated, isTrue);
      expect(composed, isTrue);
      final menu = find.byKey(const Key('crm-job-menu-visit'));
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(CustomerCrmHe.tomorrow));
      await tester.pumpAndSettle();
      expect(rescheduled, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
