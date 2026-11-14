// Golden images for every DS component: light/dark × text 100%/200%.
// Regenerate after an intended visual change:
//   flutter test test/golden --update-goldens
// Text renders in the test font (boxes), so the goldens pin layout, sizes and
// colours, not glyph shapes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/status_map.dart';

import 'ds_harness.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

void _noop() {}

final Map<String, Widget Function()> specimens = {
  'primary_button': () => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      PrimaryScope(
        child: BottomActionArea(
          note: 'מסמך מ-₪5,000 כולל מע״מ דורש אישור',
          child: PrimaryButton(label: 'הפק ושלח בווטסאפ', onPressed: _noop),
        ),
      ),
      const PrimaryScope(
        child: BottomActionArea(
          child: PrimaryButton(
            label: 'הפק',
            loadingText: 'חותם…',
            onPressed: _noop,
          ),
        ),
      ),
      const PrimaryScope(
        child: BottomActionArea(
          child: PrimaryButton(label: 'הפק', offline: true, onPressed: _noop),
        ),
      ),
      const PrimaryScope(
        child: BottomActionArea(
          child: PrimaryButton(
            label: 'הפק זיכוי',
            destructive: true,
            onPressed: _noop,
          ),
        ),
      ),
    ],
  ),
  'intent_button': () => const Padding(
    padding: EdgeInsets.all(Space.page),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: IntentButton(
            icon: Iconsax.tick_circle,
            label: 'קיבלתי תשלום',
            emphasized: true,
            onPressed: _noop,
          ),
        ),
        SizedBox(width: Space.m),
        Expanded(
          child: IntentButton(
            icon: Iconsax.send_2,
            label: 'בקש תשלום',
            onPressed: _noop,
          ),
        ),
      ],
    ),
  ),
  'inbox_card': () => Padding(
    padding: const EdgeInsets.all(Space.page),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InboxCard(
          icon: Iconsax.verify,
          title: '2 ממתינים לאישורך',
          amountMinor: BigInt.from(740000),
          actionLabel: 'פתח',
          tone: InboxTone.attention,
          onAction: _noop,
        ),
        const SizedBox(height: Space.m),
        const InboxCard(
          icon: Iconsax.danger,
          title: 'החשבונית לדנה נדחתה',
          subtitle: 'חסר פירוט',
          actionLabel: 'תקן',
          tone: InboxTone.danger,
          onAction: _noop,
        ),
        const SizedBox(height: Space.m),
        const InboxCard(
          icon: Iconsax.gallery,
          title: 'הוסף לוגו למסמכים',
          actionLabel: 'הוסף',
          onAction: _noop,
          onDismiss: _noop,
        ),
      ],
    ),
  ),
  'money_card': () => Padding(
    padding: const EdgeInsets.all(Space.page),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MoneyCard(
          label: 'מגיע לך',
          amountMinor: BigInt.from(1240000),
          secondaryLabel: 'מתוכם באיחור',
          secondaryMinor: BigInt.from(320000),
          onTap: _noop,
        ),
        const SizedBox(height: Space.m),
        MoneyCard(label: 'מגיע לך', amountMinor: BigInt.zero),
      ],
    ),
  ),
  'summary_card': () => Padding(
    padding: const EdgeInsets.all(Space.page),
    child: SummaryCard(
      children: [
        const SummaryRow(
          icon: Iconsax.note_text,
          value: 'תיקון דוד',
          onTap: _noop,
        ),
        ChipRow<String>(
          padding: const EdgeInsets.all(Space.m),
          options: const [
            ChipOption('cash', 'מזומן'),
            ChipOption('bank', 'העברה / ביט'),
            ChipOption('card', 'אשראי'),
          ],
          selected: 'bank',
          onSelected: (_) {},
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: _noop,
            child: const Text('פרטים נוספים'),
          ),
        ),
      ],
    ),
  ),
  'person_row': () => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      PersonRow(
        name: 'דנה כהן',
        subtitle: '050-123-4567',
        amountLabel: 'חייב לך',
        amountMinor: BigInt.from(599000),
        onTap: _noop,
      ),
      const PersonRow(
        name: 'אבי ספקים בע"מ',
        subtitle: 'avi@example.com',
        badge: 'ספק',
      ),
      const PersonRow(name: 'רון', badge: 'בארכיון'),
    ],
  ),
  'doc_row': () => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DocRow(
        title: 'דנה כהן',
        subtitle: 'חשבונית מס 1042',
        amountMinor: BigInt.from(118000),
        status: const StatusPill.doc(DocStatus.awaitingPayment),
        attributes: const ['נשלח'],
        onTap: _noop,
      ),
      DocRow(
        title: 'רון לוי',
        subtitle: 'חשבון עסקה 77',
        amountMinor: BigInt.from(820000),
        status: const StatusPill.doc(DocStatus.overdue),
      ),
      DocRow(
        title: 'נועה ברק',
        subtitle: 'הצעת מחיר 12',
        amountMinor: BigInt.from(60000),
        status: const StatusPill.quote(QuoteListStatus.withCustomer),
      ),
      DocRow(
        title: 'מיכל',
        subtitle: 'חשבונית מס/קבלה 1040',
        amountMinor: BigInt.from(35050),
        status: const StatusPill.doc(DocStatus.cancelled),
      ),
    ],
  ),
  'chip_row': () => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.page),
    child: ChipRow<String>(
      options: const [
        ChipOption('all', 'הכל'),
        ChipOption('unpaid', 'לא שולם'),
        ChipOption('drafts', 'טיוטות'),
        ChipOption('quotes', 'הצעות'),
      ],
      selected: 'unpaid',
      onSelected: (_) {},
    ),
  ),
  'more_menu': () => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      MoreMenu(
        items: [MoreMenuItem(label: 'שתף', onSelected: _noop)],
      ),
    ],
  ),
  'status_pill': () => Padding(
    padding: const EdgeInsets.all(Space.page),
    child: Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final s in DocStatus.values) StatusPill.doc(s),
        for (final s in QuoteListStatus.values) StatusPill.quote(s),
      ],
    ),
  ),
  'amount_keypad': () => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      AmountDisplay(amountMinor: BigInt.from(118000)),
      Keypad(onKey: (_) {}),
    ],
  ),
  'states': () => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const OfflineBanner(visible: true, onRetry: _noop),
      const SkeletonList(rows: 2),
      const EmptyState(
        icon: Iconsax.profile_2user,
        title: 'עוד אין לקוחות',
        message: 'הוסף מאנשי הקשר',
        actionLabel: 'הוסף לקוח',
        onAction: _noop,
      ),
      ErrorView(error: StateError('x'), onRetry: _noop),
    ],
  ),
};

void main() {
  for (final entry in specimens.entries) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        final name = '${entry.key}_${brightness.name}_${scale.toInt()}x';
        testWidgets('golden $name', (tester) async {
          tester.view.physicalSize = const Size(390, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            dsApp(
              brightness: brightness,
              textScale: scale,
              SingleChildScrollView(
                child: RepaintBoundary(
                  key: const ValueKey('specimen'),
                  child: ColoredBox(
                    color: brightness == Brightness.dark
                        ? AppPalette.dark.canvas
                        : AppPalette.light.canvas,
                    child: entry.value(),
                  ),
                ),
              ),
            ),
          );
          // Fixed pumps, not pumpAndSettle: the loading spinner never settles.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('specimen')),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
