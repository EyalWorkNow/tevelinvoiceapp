import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:invoice/screens/people/customer_crm_editors.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/screens/people/customer_crm_job_fields.dart';
import 'package:invoice/state/customer_crm_insights.dart';
import 'package:invoice/state/customer_crm_job_budget.dart';
import 'package:invoice/state/customer_crm_store.dart';

void main() {
  CustomerCrmJob job(
    String id, {
    int? price,
    int? cost,
    int? minutes,
    int paid = 0,
    DateTime? due,
    DateTime? date,
    CustomerCrmJobStatus status = CustomerCrmJobStatus.completed,
  }) => CustomerCrmJob(
    id: id,
    customerId: 'c1',
    customerName: 'דנה',
    title: 'ביקור',
    scheduledAt: date ?? DateTime(2026, 11, 9),
    createdAt: DateTime(2026, 11),
    status: status,
    budget: CustomerCrmJobBudget(
      priceMinor: price,
      costMinor: cost,
      workMinutes: minutes,
      paidMinor: paid,
      paymentDueAt: due,
    ),
  );

  test(
    'unknown costs stay unknown, zero costs and losses remain meaningful',
    () {
      expect(job('unknown', price: 10000).budget.contributionMinor, isNull);
      expect(
        job('free', price: 10000, cost: 0, minutes: 30).budget.hourlyMinor,
        20000,
      );
      expect(
        job(
          'loss',
          price: 10000,
          cost: 15000,
          minutes: 60,
        ).budget.contributionMinor,
        -5000,
      );
      expect(const CustomerCrmJobBudget(paidMinor: 100).isValid, isFalse);
      expect(
        const CustomerCrmJobBudget(priceMinor: 100, paidMinor: 101).isValid,
        isFalse,
      );
      expect(const CustomerCrmJobBudget(priceMinor: -1).isValid, isFalse);
      expect(const CustomerCrmJobBudget(workMinutes: 0).isValid, isFalse);
    },
  );

  test(
    'monthly figures isolate completed, open, cancelled and unpriced jobs',
    () {
      final summary = CustomerCrmInsights(
        [
          job('done', price: 100000, cost: 20000, minutes: 60, paid: 30000),
          job('long', price: 50000, cost: 10000, minutes: 120),
          job('unknown', price: 90000),
          job('unpriced'),
          job(
            'open',
            price: 60000,
            paid: 15000,
            status: CustomerCrmJobStatus.active,
          ),
          job(
            'cancelled',
            price: 9999999,
            cost: 0,
            status: CustomerCrmJobStatus.cancelled,
          ),
          job('october', price: 10000, cost: 0, date: DateTime(2026, 10, 1)),
        ],
        month: DateTime(2026, 11),
        now: DateTime(2026, 11, 10),
      );
      expect(summary.completedCount, 4);
      expect(summary.completedPriceMinor, 240000);
      expect(summary.trackedPaidMinor, 45000);
      expect(summary.openPriceMinor, 60000);
      expect(summary.unpricedCount, 1);
      expect(summary.costedCount, 2);
      expect(summary.contributionMinor, 120000);
      expect(
        summary.hourlyMinor,
        40000,
      ); // weighted by 180 minutes, not mean of rates.
      expect(
        summary.remainingMinor,
        220000,
      ); // all months; no open/cancelled work.
    },
  );

  test(
    'collection due dates use calendar days and retain unknown deadlines',
    () {
      final summary = CustomerCrmInsights(
        [
          job('late', price: 10000, due: DateTime(2026, 11, 9)),
          job('today', price: 20000, due: DateTime(2026, 11, 10)),
          job('no-deadline', price: 5000),
          job('settled', price: 10000, paid: 10000, due: DateTime(2026, 10)),
        ],
        month: DateTime(2027, 1),
        now: DateTime(2026, 11, 10, 18),
      );
      expect(summary.collections, hasLength(3));
      expect(summary.overdueCount, 1);
      expect(summary.remainingMinor, 35000);
      expect(summary.completedPriceMinor, 0);
      expect(summary.hourlyMinor, isNull);
    },
  );

  test(
    'repeat visits use cadence and reset actual costs, payments and checklist',
    () {
      final original =
          job(
            'one',
            price: 125050,
            cost: 25000,
            minutes: 120,
            paid: 50000,
            due: DateTime(2026, 11, 10),
          ).copyWith(
            repeatEveryDays: 14,
            checklist: const [
              CustomerCrmChecklistItem(
                id: 'task',
                text: 'להביא ברז',
                done: true,
              ),
            ],
          );
      expect(
        original.nextVisitAt(DateTime(2026, 12, 25, 12)),
        DateTime(2027, 1, 8),
      );
      final draft = CustomerCrmJobDraft(original, repeat: true);
      addTearDown(draft.dispose);
      expect(draft.budget.priceMinor, 125050);
      expect(draft.budget.costMinor, isNull);
      expect(draft.budget.workMinutes, isNull);
      expect(draft.budget.paidMinor, 0);
      expect(draft.budget.paymentDueAt, isNull);
      expect(draft.repeatEveryDays, 14);
      expect(draft.checklist.single.done, isFalse);
      expect(draft.checklist.single.id, isNot('task'));
    },
  );

  test('editing a checklist retains completion for unchanged tasks only', () {
    final original = job('one').copyWith(
      checklist: const [
        CustomerCrmChecklistItem(id: 'a', text: 'להביא ברז', done: true),
        CustomerCrmChecklistItem(id: 'b', text: 'בדיקת לחץ'),
      ],
    );
    final draft = CustomerCrmJobDraft(original, repeat: false);
    addTearDown(draft.dispose);
    draft.tasks.text = 'בדיקת לחץ\nלהביא ברז\nלנקות';
    final tasks = draft.checklist;
    expect(tasks.map((item) => item.id).take(2), ['b', 'a']);
    expect(tasks[1].done, isTrue);
    expect(tasks[2].done, isFalse);
  });

  testWidgets(
    'finance fields validate overpayment and hidden fields stay absent',
    (tester) async {
      final draft = CustomerCrmJobDraft(null, repeat: false);
      addTearDown(draft.dispose);
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: form,
                child: CustomerCrmJobFields(draft: draft, showMoney: true),
              ),
            ),
          ),
        ),
      );
      draft.price.text = '100.25';
      draft.paid.text = '100.26';
      expect(form.currentState!.validate(), isFalse);
      draft.paid.text = '100.25';
      draft.cost.text = '10.123';
      expect(form.currentState!.validate(), isFalse);
      draft.cost.text = '0';
      expect(form.currentState!.validate(), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CustomerCrmJobFields(draft: draft, showMoney: false),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('crm-work-price')), findsNothing);
      expect(find.byKey(const Key('crm-work-paid')), findsNothing);
      expect(find.byKey(const Key('crm-work-checklist')), findsOneWidget);
    },
  );
  testWidgets('failed job saves retain all input and can be retried', (
    tester,
  ) async {
    var attempts = 0;
    CustomerCrmJob? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                saved = await showCustomerJobEditor(
                  context,
                  customerId: 'c1',
                  customerName: 'דנה',
                  showMoney: true,
                  onSave: (_) async {
                    if (++attempts == 1) throw StateError('disk unavailable');
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('crm-work-title')),
      'תיקון נזילה',
    );
    await tester.tap(find.byKey(const Key('crm-job-more')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('crm-work-price')));
    await tester.enterText(find.byKey(const Key('crm-work-price')), '1250.50');
    await tester.tap(find.byKey(const Key('crm-work-save')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text(CustomerCrmHe.saveError), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('crm-work-price')))
          .controller!
          .text,
      '1250.50',
    );
    await tester.tap(find.byKey(const Key('crm-work-save')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(saved!.title, 'תיקון נזילה');
    expect(saved!.budget.priceMinor, 125050);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'quick visit templates fill preparation without overwriting entered details',
    (tester) async {
      CustomerCrmJob? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showCustomerJobEditor(
                    context,
                    customerId: 'c1',
                    customerName: 'דנה',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('crm-work-checklist')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('crm-work-title')),
        'החלפת ראש השקיה',
      );
      await tester.enterText(
        find.byKey(const Key('crm-work-address')),
        'הרצל 12',
      );
      await tester.tap(find.byKey(const Key('crm-template-garden')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('crm-work-save')));
      await tester.pumpAndSettle();
      expect(saved!.title, 'החלפת ראש השקיה');
      expect(saved!.address, 'הרצל 12');
      expect(saved!.repeatEveryDays, 14);
      expect(saved!.checklist, hasLength(3));
      expect(
        saved!.checklist.map((item) => item.text),
        contains('לבדוק השקיה'),
      );
      expect(saved!.budget.priceMinor, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
