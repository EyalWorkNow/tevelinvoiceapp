// Every list row type at phone widths × text scale 1.0 / 2.0 must lay out
// without a RenderFlex overflow (STATUS-v2 §8 #4: "overflowed by 3.4 pixels",
// a 370-wide row in a list = a 402pt iPhone minus the 16pt gutters). The
// culprit was the R2 report row: 3 money columns (income) laid out at their
// natural width beside an Expanded label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/screens/business/business_template.dart';
import 'package:invoice/screens/reports/report_view.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/status_map.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

const widths = [320.0, 375.0, 402.0];
const scales = [1.0, 2.0];

const longName =
    'חברת הבנייה והשיפוצים של משפחת אברהמוביץ בע״מ – סניף ראשון לציון';
final big = BigInt.parse('123456789');

void size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void scale(WidgetTester tester, double s) {
  tester.platformDispatcher.textScaleFactorTestValue = s;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Server-shaped BE-18 reports (packages/postgres/src/reports.ts).
Map<String, dynamic> serverReport(
  List<String> money, {
  String first = 'label',
}) => {
  'kpis': [
    {
      'key': 'totalMinor',
      'label': 'סה״כ הכנסות (כולל מע״מ)',
      'type': 'money',
      'value': '$big',
    },
    {'key': 'documentsCount', 'label': 'מסמכים', 'type': 'number', 'value': 3},
  ],
  'columns': [
    {'key': first, 'label': 'לקוח', 'type': 'text'},
    {'key': 'count', 'label': 'מסמכים', 'type': 'number'},
    for (final m in money) {'key': m, 'label': 'עמודה $m', 'type': 'money'},
  ],
  'rows': [
    for (final label in ['ינואר', longName])
      {first: label, 'count': 12, for (final m in money) m: '$big'},
  ],
};

void main() {
  late FakeBackend backend;
  setUp(() async => backend = await eSetUp());

  for (final w in widths) {
    for (final s in scales) {
      final tag = '${w.toInt()}pt × $s';

      testWidgets(
        'DocRow · PersonRow · InboxCard · BusinessRow · SummaryRow fit ($tag)',
        (tester) async {
          size(tester, w);
          scale(tester, s);
          await tester.pumpWidget(
            eApp(
              Scaffold(
                body: ListView(
                  children: [
                    DocRow(
                      title: longName,
                      subtitle: 'חשבונית מס/קבלה 104212',
                      amountMinor: big,
                      status: const StatusPill.doc(DocStatus.pendingApproval),
                      attributes: const ['נשלח', 'נצפה'],
                      onTap: () {},
                      swipeLabel: 'קיבלתי תשלום',
                      onSwipe: () {},
                    ),
                    DocRow(
                      title: 'א',
                      subtitle: 'הצעת מחיר 7',
                      amountMinor: big * big,
                      status: const StatusPill.quote(QuoteListStatus.converted),
                    ),
                    PersonRow(
                      name: longName,
                      badge: 'בארכיון',
                      subtitle: '+972 54-123-4567',
                      amountLabel: 'חייב לך',
                      amountMinor: big,
                      onTap: () {},
                    ),
                    PersonRow(
                      name: 'דנה',
                      amountLabel: 'חייב לך',
                      amountMinor: big * big,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(Space.page),
                      child: InboxCard(
                        icon: Iconsax.clock,
                        title: longName,
                        subtitle: 'באיחור 45 ימים',
                        amountMinor: big,
                        actionLabel: 'שלח תזכורת לתשלום',
                        tone: InboxTone.danger,
                        onAction: () {},
                        onDismiss: () {},
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.page,
                      ),
                      child: Column(
                        children: [
                          BusinessRow(
                            icon: Iconsax.profile_2user,
                            label: longName,
                            value: longName,
                            onTap: () {},
                          ),
                          BusinessRow(
                            label: longName,
                            trailing: Switch(value: true, onChanged: (_) {}),
                          ),
                          const BusinessRow(
                            label: 'מחק את החשבון',
                            destructive: true,
                          ),
                        ],
                      ),
                    ),
                    SummaryCard(
                      children: [
                        SummaryRow(
                          icon: Iconsax.user,
                          value: longName,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('team rows (B·צוות) fit ($tag)', (tester) async {
        backend.json(
          'GET',
          '/business/members',
          teamJson(
            members: [
              memberJson('u-me', 'OWNER', self: true, name: longName),
              memberJson(
                'u-cpa',
                'READ_ONLY',
                permissions: const ['expense:record', 'expense:approve'],
                email:
                    'very.long.accountant.address@accounting-firm.example.co.il',
              ),
              memberJson(
                'u-emp',
                'EMPLOYEE',
                name: longName,
                permissions: const ['document:finalize'],
              ),
            ],
            invitations: [
              invitationJson(
                'i1',
                'someone.with.a.long.address@example.co.il',
                'EMPLOYEE',
              ),
            ],
            expired: [
              invitationJson(
                'i2',
                'x@y.z',
                'READ_ONLY',
                expiresAt: DateTime(2020),
              ),
            ],
          ),
        );
        scale(tester, s);
        await pumpAs(tester, backend, Preset.owner, const TeamPage());
        size(tester, w);
        await settle(tester);
        expect(tester.takeException(), isNull);
      });

      for (final (kind, money) in [
        ('income', ['netMinor', 'vatMinor', 'totalMinor']),
        ('vat', ['a', 'b', 'c', 'd', 'e', 'vatPayableMinor']),
        ('items', ['netMinor']),
      ]) {
        testWidgets(
          'report rows R2 · $kind (${money.length} money columns) fit ($tag)',
          (tester) async {
            backend.json('GET', '/reports/:kind', serverReport(money));
            scale(tester, s);
            await pumpAs(
              tester,
              backend,
              Preset.owner,
              ReportView(kind: kind, period: PeriodKey.current),
            );
            size(tester, w);
            await settle(tester);
            expect(tester.takeException(), isNull);
            // The long-label row (built lazily at 2.0) lays out too.
            await tester.scrollUntilVisible(find.text(longName), 200);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            // Every money cell of that row is drawn (none dropped to make room).
            final cells = find.descendant(
              of: find
                  .ancestor(
                    of: find.text(longName),
                    matching: find.byType(Container),
                  )
                  .first,
              matching: find.byType(AmountText),
            );
            expect(cells, findsNWidgets(money.length));
          },
        );
      }
    }
  }
}
