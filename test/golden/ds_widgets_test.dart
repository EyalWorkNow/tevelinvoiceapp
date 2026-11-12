import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/status_map.dart';

import 'ds_harness.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

void main() {
  group('spoken amounts (AT-71)', () {
    final cases = <int, String>{
      118000: 'אלף מאה שמונים שקלים',
      0: 'אפס שקלים',
      100: 'שקל אחד',
      200: 'שני שקלים',
      1100: 'אחד עשר שקלים',
      150: 'שקל אחד וחמישים אגורות',
      1: 'אגורה אחת',
      2: 'שתי אגורות',
      1205: 'שנים עשר שקלים וחמש אגורות',
      200000: 'אלפיים שקלים',
      500000: 'חמשת אלפים שקלים',
      1240000: 'שנים עשר אלף ארבע מאות שקלים',
      5000000: 'חמישים אלף שקלים',
      99999999999: 'תשע מאות תשעים ותשעה מיליון',
      -5000: 'מינוס חמישים שקלים',
      100000000: 'מיליון שקלים',
      250000000: 'שני מיליון חמש מאות אלף שקלים',
    };
    cases.remove(99999999999); // too long to read as one case; covered below
    for (final e in cases.entries) {
      test(
        '${e.key} → ${e.value}',
        () => expect(spokenAmountHe(BigInt.from(e.key)), e.value),
      );
    }
    test('keypad max reads as words', () {
      expect(
        spokenAmountHe(BigInt.from(99999999999)),
        'תשע מאות תשעים תשעה מיליון תשע מאות תשעים תשעה אלף תשע מאות תשעים תשעה שקלים '
        'ותשעים תשע אגורות',
      );
    });
  });

  testWidgets(
    'AmountDisplay(118000): VoiceOver reads Hebrew words, text stays LTR',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        dsApp(AmountDisplay(amountMinor: BigInt.from(118000))),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('אלף מאה שמונים שקלים'), findsOneWidget);
      expect(find.text('₪1,180'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('₪1,180'))),
        TextDirection.ltr,
      );
      handle.dispose();
    },
  );

  testWidgets('"הסתר סכומים" hides money card, rows and inbox amounts', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      dsApp(
        hideAmounts: true,
        ListView(
          children: [
            MoneyCard(label: 'מגיע לך', amountMinor: BigInt.from(1240000)),
            DocRow(
              title: 'דנה',
              subtitle: 'חשבונית מס 1',
              amountMinor: BigInt.from(118000),
              status: const StatusPill.doc(DocStatus.paid),
            ),
            PersonRow(
              name: 'דנה',
              amountLabel: 'חייב לך',
              amountMinor: BigInt.from(5000),
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('1,'), findsNothing);
    expect(find.text(hiddenAmountText), findsNWidgets(3));
    expect(find.bySemanticsLabel(RegExp('שקלים')), findsNothing);
    handle.dispose();
  });

  testWidgets('moneyInline isolates the amount for Hebrew sentences', (
    tester,
  ) async {
    expect(moneyInline(BigInt.from(500000)), '\u2066₪5,000\u2069');
  });

  group('PrimaryButton', () {
    testWidgets(
      'tap fires; offline shows "אין חיבור" and is the only disabled state',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          dsApp(PrimaryButton(label: 'הפק', onPressed: () => taps++)),
        );
        await tester.tap(find.text('הפק'));
        expect(taps, 1);
        expect(
          tester.getSize(find.byType(PrimaryButton)).height,
          greaterThanOrEqualTo(56),
        );

        await tester.pumpWidget(
          dsApp(
            PrimaryButton(label: 'הפק', offline: true, onPressed: () => taps++),
          ),
        );
        expect(find.text('הפק'), findsNothing);
        await tester.tap(find.text('אין חיבור'));
        expect(taps, 1);
      },
    );

    testWidgets('loading shows the step text and blocks taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        dsApp(
          PrimaryButton(
            label: 'הפק',
            loadingText: 'חותם…',
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.text('חותם…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('חותם…'));
      expect(taps, 0);
    });

    testWidgets('two in one screen trips the debug assert (F2)', (
      tester,
    ) async {
      await tester.pumpWidget(
        dsApp(
          Column(
            children: [
              PrimaryButton(label: 'א', onPressed: () {}),
              PrimaryButton(label: 'ב', onPressed: () {}),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('separate PrimaryScopes and sheets each allow one', (
      tester,
    ) async {
      await tester.pumpWidget(
        dsApp(
          Column(
            children: [
              PrimaryScope(
                child: PrimaryButton(label: 'א', onPressed: () {}),
              ),
              PrimaryScope(
                child: PrimaryButton(label: 'ב', onPressed: () {}),
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // A sheet over a screen that has its own primary.
      await tester.pumpWidget(
        dsApp(
          Builder(
            builder: (context) => PrimaryButton(
              label: 'פתח',
              onPressed: () => showAppSheet<void>(
                context,
                builder: (_) => PrimaryButton(label: 'רשום', onPressed: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      expect(find.text('רשום'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets(
    'MoreMenu: nothing when empty; destructive item last; runs after close',
    (tester) async {
      await tester.pumpWidget(dsApp(const MoreMenu(items: [])));
      expect(find.byType(IconButton), findsNothing);

      final chosen = <String>[];
      await tester.pumpWidget(
        dsApp(
          MoreMenu(
            items: [
              MoreMenuItem(
                label: 'בטל / זכה',
                destructive: true,
                onSelected: () => chosen.add('x'),
              ),
              MoreMenuItem(label: 'שתף', onSelected: () => chosen.add('share')),
              MoreMenuItem(label: 'שכפל', onSelected: () => chosen.add('dup')),
            ],
          ),
        ),
      );
      await tester.tap(find.byTooltip('עוד'));
      await tester.pumpAndSettle();
      final ys = [
        'שתף',
        'שכפל',
        'בטל / זכה',
      ].map((t) => tester.getCenter(find.text(t)).dy).toList();
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue);
      await tester.tap(find.text('שכפל'));
      await tester.pumpAndSettle();
      expect(chosen, ['dup']);
      expect(find.text('שתף'), findsNothing);
    },
  );

  testWidgets('ChipRow: single select, 44pt targets, selected in semantics', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      dsApp(
        ChipRow<String>(
          options: const [ChipOption('a', 'הכל'), ChipOption('b', 'לא שולם')],
          selected: 'a',
          onSelected: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.text('הכל'));
    expect(picked, isNull); // already selected
    await tester.tap(find.text('לא שולם'));
    expect(picked, 'b');
    expect(
      tester.getSize(find.text('לא שולם').hitTestable()).height,
      lessThan(44),
    );
    final chip = find
        .ancestor(of: find.text('לא שולם'), matching: find.byType(Material))
        .first;
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
  });

  test('StatusPill covers exactly the §15.5 enums with Hebrew words', () {
    expect(DocStatus.values.map((s) => StatusPill.doc(s).label), [
      'טיוטה',
      'ממתין לאישור',
      'ממתין לתשלום',
      'באיחור',
      'שולם',
      'בוטל',
      'הופק',
    ]);
    expect(QuoteListStatus.values.map((s) => StatusPill.quote(s).label), [
      'טיוטה',
      'אצל הלקוח',
      'אושרה',
      'הפכה לחשבונית',
      'לא רלוונטית',
    ]);
    expect(
      const StatusPill.doc(DocStatus.overdue).colorIn(AppPalette.light),
      AppPalette.light.danger,
    );
  });

  testWidgets('InboxCard: one action; ✕ only with onDismiss', (tester) async {
    var acted = 0, dismissed = 0;
    await tester.pumpWidget(
      dsApp(
        Column(
          children: [
            InboxCard(
              icon: Iconsax.tick_circle,
              title: '2 ממתינים לאישורך',
              amountMinor: BigInt.from(740000),
              actionLabel: 'פתח',
              onAction: () => acted++,
            ),
            InboxCard(
              icon: Iconsax.gallery,
              title: 'הוסף לוגו',
              actionLabel: 'הוסף',
              onAction: () {},
              onDismiss: () => dismissed++,
            ),
          ],
        ),
      ),
    );
    expect(find.byTooltip('סגור'), findsOneWidget);
    await tester.tap(find.text('פתח'));
    expect(acted, 1);
    await tester.tap(
      find.text('2 ממתינים לאישורך'),
    ); // card body is tappable too
    expect(acted, 2);
    await tester.tap(find.byTooltip('סגור'));
    expect((acted, dismissed), (2, 1)); // ✕ does not run the action
    expect(find.text('₪7,400'), findsOneWidget);
  });

  testWidgets('DocRow: ≥64pt, swipe runs the shortcut and snaps back', (
    tester,
  ) async {
    var swiped = 0;
    await tester.pumpWidget(
      dsApp(
        DocRow(
          title: 'דנה כהן',
          subtitle: 'חשבונית מס 1042',
          amountMinor: BigInt.from(118000),
          status: const StatusPill.doc(DocStatus.awaitingPayment),
          attributes: const ['נשלח'],
          swipeLabel: 'קיבלתי תשלום',
          onSwipe: () => swiped++,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(DocRow)).height,
      greaterThanOrEqualTo(64),
    );
    await tester.fling(
      find.text('דנה כהן'),
      const Offset(-500, 0),
      2000,
    ); // RTL start→end
    await tester.pumpAndSettle();
    expect(swiped, 1);
    expect(find.text('דנה כהן'), findsOneWidget);
  });

  testWidgets('200% text on a 320pt phone: no overflow in any component', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      dsApp(
        textScale: 2,
        brightness: Brightness.dark,
        ListView(
          children: [
            MoneyCard(
              label: 'מגיע לך',
              amountMinor: BigInt.from(123456789),
              secondaryLabel: 'מתוכם באיחור',
              secondaryMinor: BigInt.from(320000),
            ),
            Row(
              children: [
                Expanded(
                  child: IntentButton(
                    icon: Iconsax.tick_circle,
                    label: 'קיבלתי תשלום',
                    emphasized: true,
                    onPressed: () {},
                  ),
                ),
                Expanded(
                  child: IntentButton(
                    icon: Iconsax.send_2,
                    label: 'בקש תשלום',
                    onPressed: () {},
                  ),
                ),
              ],
            ),
            DocRow(
              title: 'שם לקוח ארוך מאוד מאוד מאוד',
              subtitle: 'חשבונית מס/קבלה 104212',
              amountMinor: BigInt.from(9999999999),
              status: const StatusPill.doc(DocStatus.awaitingPayment),
              attributes: const ['נשלח', 'נצפה'],
            ),
            PersonRow(
              name: 'שם לקוח ארוך מאוד מאוד',
              subtitle: '050-123-4567',
              amountLabel: 'חייב לך',
              amountMinor: BigInt.from(599000),
            ),
            InboxCard(
              icon: Iconsax.warning_2,
              title: 'דנה שילמה על חשבון עסקה – הפק חשבונית מס עד 14/11',
              amountMinor: BigInt.from(120000),
              actionLabel: 'הפק',
              onAction: () {},
            ),
            SummaryCard(
              children: [SummaryRow(value: 'תיקון דוד', onTap: () {})],
            ),
            ChipRow<int>(
              options: const [
                ChipOption(1, 'הכל'),
                ChipOption(2, 'לא שולם'),
                ChipOption(3, 'טיוטות'),
                ChipOption(4, 'הצעות'),
              ],
              selected: 1,
              onSelected: (_) {},
            ),
            PrimaryButton(label: 'הפק ושלח בווטסאפ', onPressed: () {}),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
