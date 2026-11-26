// The customer page audit (2611, 21 items): header collapse, menus with the
// current value, theme-aware orbs / avatars, one DocRow design, one place
// for terms + reminders, plain money words, the calendar booking sheet,
// the supplier's honest expenses state, the month picker in dark mode and
// the pinned "שמור" of the terms sheet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customer_timeline_api.dart' show PaymentTermsValue;
import 'package:invoice/screens/calendar/booking_detail_sheet.dart';
import 'package:invoice/screens/calendar/new_booking_sheet.dart'
    show CalendarMonthPicker;
import 'package:invoice/screens/debts/reminder_hold_tile.dart';
import 'package:invoice/screens/people/customer_crm_finance_card.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/people/sheets/payment_terms_sheet.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/customer_crm_job_budget.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/ui/widgets/quick_action_grid.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';
import 'package:invoice/util/labels/person_page_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

void main() {
  group('pure', () {
    test('#15 balanced orb rows: nothing alone on a row', () {
      expect(balancedPerRow(3), 4);
      expect(balancedPerRow(5), 3);
      expect(balancedPerRow(6), 3);
      expect(balancedPerRow(7), 4);
      expect(balancedPerRow(8), 4);
    });

    test(
      '#7 pastels: dark tints are dark and low-saturation, ink is light',
      () {
        for (final h in Pastel.values) {
          final (lc, li) = AppPalette.light.pastel(h);
          final (dc, di) = AppPalette.dark.pastel(h);
          expect(lc.computeLuminance(), greaterThan(.5));
          expect(li.computeLuminance(), lessThan(.2));
          expect(dc.computeLuminance(), lessThan(.1), reason: '$h');
          expect(di.computeLuminance(), greaterThan(.5), reason: '$h');
        }
      },
    );

    test('#14 the CRM stage is "בעבודה", not "לקוח פעיל"', () {
      expect(CustomerCrmStage.active.label, 'בעבודה');
    });
  });

  group('page', () {
    late FakeBackend b;

    setUp(() async {
      b = await eSetUp();
      loadReminderHold = ({customerId, documentId}) async => false;
    });

    Future<void> open(
      WidgetTester t, {
      Brightness brightness = Brightness.light,
      CustomerCrmEntry entry = const CustomerCrmEntry(),
      List<Map<String, dynamic>> bookings = const [],
    }) async {
      installPeopleFakes(
        b,
        customers: [customerJson('c1', 'דנה', phone: '050-1234567')],
      );
      b
        ..json('GET', '/crm/customers', {
          'total': 1,
          'records': [
            {'customerId': 'c1', 'revision': 1, 'record': entry.toJson()},
          ],
        })
        ..json('GET', '/calendar/agenda', {
          'enabled': true,
          'busy': <Object>[],
          'bookings': bookings,
        });
      phone(t);
      await t.runAsync(() async {
        await signInAs(b, Preset.owner);
        await CustomerCrmStore.instance.loadForBusiness('b1', force: true);
      });
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        eApp(const PersonScreen(id: 'c1'), brightness: brightness),
      );
      await settle(t);
    }

    testWidgets('#7 #15 dark orbs use the dark pastel tints, one-line labels', (
      t,
    ) async {
      await open(t, brightness: Brightness.dark);
      final orbs = t.widgetList<ActionOrb>(find.byType(ActionOrb)).toList();
      expect(orbs, isNotEmpty);
      for (final o in orbs) {
        expect(o.singleLineLabel, isTrue);
        expect(o.color.computeLuminance(), lessThan(.1));
      }
      final call = t.widget<ActionOrb>(
        find.byKey(const Key('person-action-call')),
      );
      expect(call.color, AppPalette.dark.pastel(Pastel.blue).$1);
    });

    testWidgets('#4 the header turns compact with an edge once scrolled', (
      t,
    ) async {
      await open(t);
      TextStyle nameStyle() =>
          t.widget<Text>(find.byKey(const Key('person-name'))).style!;
      expect(nameStyle().fontSize, AppText.displayTitle.fontSize);
      expect(find.byKey(const Key('person-stage')), findsOneWidget);
      await t.drag(find.byKey(const Key('person-list')), const Offset(0, -300));
      await settle(t);
      expect(nameStyle().fontSize, AppText.title.fontSize);
      expect(find.byKey(const Key('person-stage')), findsNothing);
      await t.drag(find.byKey(const Key('person-list')), const Offset(0, 900));
      await settle(t);
      expect(nameStyle().fontSize, AppText.displayTitle.fontSize);
    });

    testWidgets('#5 #14 the stage menu marks the current stage', (t) async {
      await open(
        t,
        entry: const CustomerCrmEntry(stage: CustomerCrmStage.orderApproved),
      );
      await t.tap(find.byKey(const Key('person-stage')));
      await settle(t);
      expect(
        find.descendant(
          of: find.byKey(const Key('stage-item-orderApproved')),
          matching: find.byKey(const Key('stage-current')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stage-current')), findsOneWidget);
      expect(find.text('בעבודה'), findsOneWidget);
      expect(find.text('לקוח פעיל'), findsNothing);
      // Under the chip, not over it.
      final chip = t.getRect(find.byKey(const Key('person-stage')));
      final item = t.getRect(find.byKey(const Key('stage-item-lead')));
      expect(item.top, greaterThanOrEqualTo(chip.bottom - 1));
    });

    testWidgets('#19 a meeting opens the יומן detail sheet (approve there)', (
      t,
    ) async {
      final n = DateTime.now();
      final at = DateTime(n.year, n.month, n.day + 1, 11);
      await open(
        t,
        bookings: [
          {
            'id': 'bk1',
            'startsAt': at.toUtc().toIso8601String(),
            'endsAt': at
                .add(const Duration(minutes: 30))
                .toUtc()
                .toIso8601String(),
            'status': 'PENDING',
            'clientName': 'דנה',
            'clientPhone': '0501234567',
            'clientEmail': '',
            'createdAt': '2026-11-01T10:00:00Z',
            'customerId': 'c1',
          },
        ],
      );
      b.json('POST', '/calendar/bookings/:id/approve', {
        'booking': {
          'id': 'bk1',
          'startsAt': at.toUtc().toIso8601String(),
          'endsAt': at
              .add(const Duration(minutes: 30))
              .toUtc()
              .toIso8601String(),
          'status': 'CONFIRMED',
          'clientName': 'דנה',
          'clientPhone': '0501234567',
          'clientEmail': '',
          'createdAt': '2026-11-01T10:00:00Z',
          'customerId': 'c1',
        },
      });
      await t.scrollUntilVisible(
        find.byKey(const Key('person-visit-booking-bk1')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('person-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.tap(find.byKey(const Key('person-visit-booking-bk1')));
      await settle(t);
      expect(find.byType(BookingDetailSheet), findsOneWidget);
      await t.tap(find.byKey(const Key('booking-detail-approve')));
      await settle(t);
      expect(b.calls('POST', '/calendar/bookings/:id/approve'), hasLength(1));
    });

    testWidgets('#9 #17 money: plain words, a different name than "חייב לך", '
        'no "—" rows', (t) async {
      await open(
        t,
        entry: CustomerCrmEntry(
          jobs: [
            CustomerCrmJob(
              id: 'j1',
              customerId: 'c1',
              customerName: 'דנה',
              title: 'תיקון',
              scheduledAt: DateTime.now().subtract(const Duration(days: 2)),
              createdAt: DateTime(2026, 11, 1),
              status: CustomerCrmJobStatus.completed,
              budget: const CustomerCrmJobBudget(priceMinor: 50000),
            ),
          ],
        ),
      );
      final list = find
          .descendant(
            of: find.byKey(const Key('person-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.byKey(const Key('person-money')),
        200,
        scrollable: list,
      );
      await t.tap(find.byKey(const Key('person-money')));
      await settle(t);
      expect(find.byType(CustomerCrmFinanceCard), findsOneWidget);
      expect(find.text(CustomerCrmHe.remainingEstimate), findsOneWidget);
      expect(find.textContaining('נותר לגבייה'), findsNothing);
      expect(find.text('—'), findsNothing);
      expect(find.text(CustomerCrmHe.contribution), findsNothing);
      // Terms live in "פרטי הלקוח" only.
      expect(find.byKey(const Key('person-terms-reminders')), findsNothing);
    });

    testWidgets('#20 supplier: an honest expenses state + "הוצאה חדשה"', (
      t,
    ) async {
      installPeopleFakes(
        b,
        suppliers: [
          {
            'id': 's1',
            'name': 'חשמל',
            'tax_id': null,
            'email': null,
            'phone': '036000000',
            'archived_at': null,
          },
        ],
      );
      phone(t);
      await t.runAsync(() => signInAs(b, Preset.owner));
      await t.pumpWidget(eApp(const PersonScreen(id: 's1', isSupplier: true)));
      await settle(t);
      expect(find.byKey(const Key('person-supplier-expenses')), findsOneWidget);
      expect(find.text(PersonPageHe.supplierExpensesHint), findsOneWidget);
      expect(
        find.byKey(const Key('person-supplier-new-expense')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('person-action-more')), findsNothing);
    });
  });

  group('widgets', () {
    Widget app(Widget child, {Brightness brightness = Brightness.light}) =>
        MaterialApp(
          theme: buildTheme(brightness),
          locale: const Locale('he', 'IL'),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: child),
          ),
        );

    testWidgets('#6 dark month picker: selected = accent / accentInk, free '
        'days tinted, today ringed', (t) async {
      final now = DateTime.now();
      final month = DateTime(now.year, now.month);
      String ymd(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      // Two free days this month that are not today.
      final d1 = DateTime(now.year, now.month, now.day == 10 ? 11 : 10);
      final d2 = DateTime(now.year, now.month, now.day == 20 ? 21 : 20);
      await t.pumpWidget(
        app(
          CalendarMonthPicker(
            month: month,
            days: {ymd(d1), ymd(d2)},
            selected: ymd(d1),
            onMonth: (_) {},
            onDay: (_) {},
          ),
          brightness: Brightness.dark,
        ),
      );
      const p = AppPalette.dark;
      BoxDecoration deco(DateTime d) =>
          t
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(Key('new-booking-day-${ymd(d)}')),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(deco(d1).color, p.accent);
      final selText = t.widget<Text>(
        find.descendant(
          of: find.byKey(Key('new-booking-day-${ymd(d1)}')),
          matching: find.byType(Text),
        ),
      );
      expect(selText.style!.color, p.accentInk);
      expect(deco(d2).color, isNotNull);
      expect(deco(d2).color, isNot(p.accent));
      expect(deco(DateTime(now.year, now.month, now.day)).border, isNotNull);
    });

    testWidgets('#18 a scrolling chip row keeps every chip on one line', (
      t,
    ) async {
      t.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        app(
          ChipRow<int>(
            scroll: true,
            options: [for (var i = 0; i < 7; i++) ChipOption(i, 'מסננים $i')],
            selected: 0,
            onSelected: (_) {},
          ),
        ),
      );
      final tops = {
        for (var i = 0; i < 3; i++) t.getTopLeft(find.text('מסננים $i')).dy,
      };
      expect(tops, hasLength(1));
    });

    testWidgets('#1 the terms sheet keeps "שמור" visible on a short phone', (
      t,
    ) async {
      t.view
        ..physicalSize = const Size(1170, 1800)
        ..devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        app(
          Builder(
            builder: (c) => TextButton(
              onPressed: () => showPaymentTermsSheet(
                c,
                customerId: 'c1',
                initial: const PaymentTermsValue(code: 'EOM_30'),
                cadence: 'BUSINESS',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final save = t.getRect(find.byKey(const Key('terms-save')));
      expect(save.bottom, lessThanOrEqualTo(600));
      expect(save.top, greaterThan(0));
      // The choices scroll above it; the button never moves.
      await t.drag(
        find.byKey(const Key('terms-method')),
        const Offset(0, -400),
      );
      await t.pumpAndSettle();
      expect(t.getRect(find.byKey(const Key('terms-save'))), save);
    });
  });
}
