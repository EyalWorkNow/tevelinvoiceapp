// QA 2026-11-12 · A5: CRM card, board, editors and the contacts prompt.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/people/customer_crm_agenda_screen.dart';
import 'package:invoice/screens/people/customer_crm_editors.dart';
import 'package:invoice/screens/people/customer_crm_finance_card.dart';
import 'package:invoice/screens/people/customer_crm_jobs.dart';
import 'package:invoice/screens/people/customer_crm_panel.dart';
import 'package:invoice/state/contacts_permission.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';
import 'package:invoice/util/labels/people_he.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.dark),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

CustomerCrmJob _job({DateTime? at}) => CustomerCrmJob.create(
  customerId: 'c1',
  customerName: 'דנה',
  title: 'תיקון',
  scheduledAt: at ?? DateTime(2026, 11, 12, 9),
);

void main() {
  test('a customer with documents is not shown as a new lead', () {
    expect(
      displayStage(CustomerCrmStage.lead, hasDocuments: true),
      CustomerCrmStage.active,
    );
    expect(
      displayStage(CustomerCrmStage.lead, hasDocuments: false),
      CustomerCrmStage.lead,
    );
    expect(
      displayStage(CustomerCrmStage.quoteSent, hasDocuments: true),
      CustomerCrmStage.quoteSent,
    );
  });

  test('board: an overdue open job stays in "today" and "7 days"', () {
    final now = DateTime(2026, 11, 12, 10);
    final overdue = DateTime(2026, 11, 9, 9);
    expect(crmJobInRange(overdue, 1, now), isTrue);
    expect(crmJobInRange(overdue, 2, now), isTrue);
    expect(crmJobInRange(DateTime(2026, 11, 13, 9), 1, now), isFalse);
    expect(crmJobInRange(DateTime(2026, 11, 18, 9), 2, now), isTrue);
    expect(crmJobInRange(DateTime(2026, 11, 19, 9), 2, now), isFalse);
  });

  testWidgets('money tab: documents balance first; month arrows on both '
      'sides in RTL', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        CustomerCrmFinanceCard(
          jobs: const [],
          documentsOpenMinor: BigInt.from(119500),
          onOpenJob: (_) {},
        ),
      ),
    );
    expect(find.text(CustomerCrmHe.documentsBalance), findsOneWidget);
    expect(find.text(CustomerCrmHe.remainingEstimate), findsOneWidget);
    final previous = tester.getCenter(
      find.byKey(const Key('crm-month-previous')),
    );
    final next = tester.getCenter(find.byKey(const Key('crm-month-next')));
    final month = tester.getCenter(find.textContaining('2026'));
    expect(previous.dx, greaterThan(month.dx), reason: 'start = right in RTL');
    expect(next.dx, lessThan(month.dx));
  });

  testWidgets('job menu has one "edit" entry', (tester) async {
    await tester.pumpWidget(
      _app(
        CustomerCrmJobs(
          jobs: [_job(at: DateTime.now().add(const Duration(days: 2)))],
          enabled: true,
          showMoney: true,
          onEdit: (_) {},
          onRepeat: (_) {},
          onDelete: (_) {},
          onStatus: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.byWidgetPredicate(
      (w) =>
          w is PopupMenuButton<String> &&
          (w.key as ValueKey?)?.value.toString().startsWith('crm-job-menu-') ==
              true,
    );
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    final items = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .map((item) => item.value)
        .toList();
    expect(items.where((v) => v == 'edit'), hasLength(1));
    expect(items.toSet(), hasLength(items.length));
  });

  testWidgets('note editor: a tap outside with typed text asks first', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const SizedBox(width: 10, height: 10)));
    final context = tester.element(find.byType(SizedBox).last);
    String? result = 'unset';
    unawaited(showCustomerNoteEditor(context).then((v) => result = v));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('crm-note-text')), 'קוד 1234');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text(PeopleHe.discardTitle), findsOneWidget);
    await tester.tap(find.text(PeopleHe.discardStay));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crm-note-text')), findsOneWidget);
    expect(result, 'unset');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discard-leave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crm-note-text')), findsNothing);
    expect(result, isNull);
  });

  testWidgets('contacts access is never asked on app entry', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(width: 10, height: 10)));
    await requestContactsPermissionOnEntry(
      tester.element(find.byType(SizedBox).last),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
