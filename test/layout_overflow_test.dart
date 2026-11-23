// Every list row type at phone widths × text scale 1.0 / 2.0 must lay out
// without a RenderFlex overflow (STATUS-v2 §8 #4: "overflowed by 3.4 pixels",
// a 370-wide row in a list = a 402pt iPhone minus the 16pt gutters). The
// culprit was the R2 report row: 3 money columns (income) laid out at their
// natural width beside an Expanded label.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customer_timeline_api.dart';
import 'package:invoice/screens/business/team_page.dart';
import 'package:invoice/screens/home/doc_rows.dart';
import 'package:invoice/screens/people/customer_crm_finance_card.dart';
import 'package:invoice/screens/people/customer_timeline_screen.dart';
import 'package:invoice/util/labels/customer_crm_he.dart';
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

  // Codex 2026-11-23: a customer's balance sat ~15 px in from the edge (the
  // amount column floated inside its loose 2/3 share).
  testWidgets('RTL document amounts and customer balances hug the left edge', (
    tester,
  ) async {
    size(tester, 390);
    await tester.pumpWidget(
      eApp(
        Scaffold(
          body: Column(
            children: [
              DocRow(
                title: 'דניאל רוזן',
                subtitle: 'חשבונית מס 1042',
                amountMinor: BigInt.from(28400),
                status: const StatusPill.doc(DocStatus.paid),
              ),
              PersonRow(
                name: 'דניאל רוזן',
                amountLabel: 'חייב לך',
                amountMinor: BigInt.from(28400),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final values = find.byType(AmountText);
    expect(tester.getTopLeft(values.first).dx, closeTo(Space.page, .1));
    expect(tester.getTopLeft(values.last).dx, closeTo(Space.page, .1));
  });

  // 2026-11-23 space-between pass: every label/value row puts the value at
  // the row's end edge (left in RTL), whatever trails or precedes it.
  DocumentSummary summary(String id, String status) => DocumentSummary(
    id: id,
    documentType: 'TAX_INVOICE',
    status: status,
    customerName: 'דניאל רוזן',
    currency: 'ILS',
    totalMinor: BigInt.from(28400),
  );

  testWidgets('a draft row: the amount hugs the edge; delete by long press', (
    tester,
  ) async {
    size(tester, 390);
    var deleted = 0;
    await tester.pumpWidget(
      eApp(
        Scaffold(
          body: Column(
            children: [
              docRowFor(
                summary('d1', 'DRAFT'),
                onTap: () {},
                onDelete: () => deleted++,
              ),
              docRowFor(
                summary('d2', 'FINALIZED'),
                onTap: () {},
                onDelete: () => deleted++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final values = find.byType(AmountText);
    expect(tester.getTopLeft(values.first).dx, closeTo(Space.page, .1));
    expect(tester.getTopLeft(values.last).dx, closeTo(Space.page, .1));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.longPress(find.byKey(const Key('doc-d2')));
    expect(deleted, 0, reason: 'an issued document is never deleted');
    await tester.longPress(find.byKey(const Key('doc-d1')));
    expect(deleted, 1);
  });

  testWidgets('CRM money metrics hug the card edge; no duplicate balance', (
    tester,
  ) async {
    size(tester, 390);
    await tester.pumpWidget(
      eApp(
        Scaffold(
          body: SingleChildScrollView(
            child: CustomerCrmFinanceCard(
              jobs: const [],
              documentsOpenMinor: BigInt.from(119500),
              onOpenJob: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(CustomerCrmHe.documentsBalance), findsNothing);
    for (final label in [
      CustomerCrmHe.completedPrice,
      CustomerCrmHe.upcomingPrice,
      CustomerCrmHe.collected,
    ]) {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final value = find.descendant(of: row, matching: find.text(crmMoney(0)));
      expect(
        tester.getTopLeft(value).dx,
        closeTo(tester.getTopLeft(row).dx, .1),
        reason: label,
      );
    }
    // The big figure sits under its label at the start (right in RTL).
    expect(
      tester.getTopRight(find.byKey(const Key('crm-tracked-remaining'))).dx,
      closeTo(
        tester.getTopRight(find.text(CustomerCrmHe.remainingEstimate)).dx,
        .1,
      ),
    );
  });

  testWidgets('timeline: a tappable row keeps its amount on the shared edge', (
    tester,
  ) async {
    size(tester, 390);
    TimelineItem item(String id, {BigInt? amount}) => TimelineItem(
      id: id,
      kind: 'payment.recorded',
      at: '2026-11-20T10:00:00Z',
      atIsrael: '2026-11-20T12:00:00+02:00',
      amountMinor: amount,
    );
    await tester.pumpWidget(
      eApp(
        Scaffold(
          body: Column(
            children: [
              TimelineRow(
                item: item('t1', amount: BigInt.from(28400)),
                onTap: () {},
              ),
              TimelineRow(item: item('t2', amount: BigInt.from(28400))),
              TimelineRow(item: item('t3'), onTap: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final values = find.byType(AmountText);
    expect(tester.getTopLeft(values.first).dx, closeTo(0, .1));
    expect(tester.getTopLeft(values.last).dx, closeTo(0, .1));
    // A row without an amount still shows it opens something.
    expect(find.byIcon(Iconsax.arrow_left_2), findsOneWidget);
  });
}
