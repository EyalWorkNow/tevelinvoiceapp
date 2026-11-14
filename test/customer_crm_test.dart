import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/people/customer_crm_panel.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/ui/theme.dart';

void main() {
  late Directory directory;
  var counter = 0;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('tevel-crm-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDownAll(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Future<void> commit(WidgetTester tester, bool Function() done) async {
    await tester.pump();
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final business = 'crm-${counter++}';
    final loading = CustomerCrmStore.instance.loadForBusiness(business);
    await commit(tester, () => CustomerCrmStore.instance.isLoadedFor(business));
    await loading;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CustomerCrmPanel(
              businessId: business,
              customerId: 'c1',
              customerName: 'דניאל',
              canEdit: true,
              canViewMoney: true,
              onOpenAgenda: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'customer CRM saves focused notes and reminders and completes a job',
    (tester) async {
      await openPanel(tester);
      await tester.tap(find.text('פתק חדש'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crm-note-text')),
        'השער נפתח מצד ימין',
      );
      await tester.tap(find.byKey(const Key('crm-note-save')));
      await commit(
        tester,
        () => CustomerCrmStore.instance.entryFor('c1').notes.isNotEmpty,
      );
      expect(find.text('השער נפתח מצד ימין'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.ensureVisible(find.byTooltip('אפשרויות'));
      await tester.tap(find.byTooltip('אפשרויות'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('להציג לפני הביקור'));
      await commit(
        tester,
        () => CustomerCrmStore.instance.entryFor('c1').notes.single.pinned,
      );
      await tester.ensureVisible(find.byKey(const Key('crm-section-0')));
      await tester.tap(find.byKey(const Key('crm-section-0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          Key(
            'crm-pinned-${CustomerCrmStore.instance.entryFor('c1').notes.single.id}',
          ),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(const Key('crm-add-job')));
      await tester.tap(find.byKey(const Key('crm-add-job')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crm-work-save')));
      await tester.pumpAndSettle();
      expect(find.text('יש למלא את השדה'), findsOneWidget);
      expect(CustomerCrmStore.instance.entryFor('c1').jobs, isEmpty);
      await tester.enterText(
        find.byKey(const Key('crm-work-title')),
        'תיקון נזילה',
      );
      await tester.enterText(
        find.byKey(const Key('crm-work-address')),
        'רחוב הדוגמה 12',
      );
      await tester.tap(find.byKey(const Key('crm-job-more')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crm-work-details')),
        'להביא ברז חלופי',
      );
      for (final (key, value) in const [
        ('crm-work-checklist', 'להביא ברז חלופי\nלבדוק לחץ מים'),
        ('crm-work-price', '1250.50'),
        ('crm-work-cost', '250.25'),
        ('crm-work-minutes', '120'),
        ('crm-work-paid', '200'),
      ]) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.enterText(find.byKey(Key(key)), value);
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('crm-work-save')));
      await tester.tap(find.byKey(const Key('crm-work-save')));
      await commit(
        tester,
        () => CustomerCrmStore.instance.entryFor('c1').jobs.isNotEmpty,
      );
      final job = CustomerCrmStore.instance.entryFor('c1').jobs.single;
      expect(job.address, 'רחוב הדוגמה 12');
      expect(job.details, 'להביא ברז חלופי');
      expect(job.budget.priceMinor, 125050);
      expect(job.budget.costMinor, 25025);
      expect(job.budget.remainingMinor, 105050);
      expect(job.budget.hourlyMinor, 50013);
      final check = find.byKey(Key('crm-check-${job.checklist.first.id}'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await commit(
        tester,
        () => CustomerCrmStore.instance
            .entryFor('c1')
            .jobs
            .single
            .checklist
            .first
            .done,
      );
      final next = find.byKey(Key('crm-job-next-${job.id}'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await commit(
        tester,
        () =>
            CustomerCrmStore.instance.entryFor('c1').jobs.single.status ==
            CustomerCrmJobStatus.active,
      );
      await tester.ensureVisible(next);
      await tester.tap(next);
      await commit(
        tester,
        () =>
            CustomerCrmStore.instance.entryFor('c1').jobs.single.status ==
            CustomerCrmJobStatus.completed,
      );
      await tester.ensureVisible(find.byKey(const Key('crm-job-history')));
      await tester.tap(find.byKey(const Key('crm-job-history')));
      await tester.pumpAndSettle();
      expect(find.text('תיקון נזילה'), findsOneWidget);
      expect(find.text('הושלמה'), findsOneWidget);

      await tester.ensureVisible(find.text('תזכורת'));
      await tester.tap(find.text('תזכורת'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('crm-work-title')),
        'להתקשר לתיאום ביקור',
      );
      await tester.tap(find.byKey(const Key('crm-work-save')));
      await commit(
        tester,
        () => CustomerCrmStore.instance.entryFor('c1').reminders.isNotEmpty,
      );
      expect(find.text('להתקשר לתיאום ביקור'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('crm-follow-tomorrow')));
      await tester.tap(find.byKey(const Key('crm-follow-tomorrow')));
      await commit(
        tester,
        () => CustomerCrmStore.instance.entryFor('c1').reminders.length == 2,
      );
      final followup = CustomerCrmStore.instance.entryFor('c1').reminders.last;
      final now = DateTime.now();
      expect(followup.dueAt, DateTime(now.year, now.month, now.day + 1, 9));
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
