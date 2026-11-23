// C4 (QA 2026-11-16, persona 03 + 05): "חבילת ריטיינר" — the month's
// recurring drafts, row actions, one "הפק הכל" (one request per tap), the
// templates page, and who sees the entry points.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/screens/retainers/make_monthly_sheet.dart';
import 'package:invoice/screens/retainers/retainer_templates_screen.dart';
import 'package:invoice/screens/retainers/retainers_api.dart';
import 'package:invoice/screens/retainers/retainers_month_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/retainer_he.dart';

import '../business/e_harness.dart';
import '../fakes/fake_api.dart';

Caps capsOf(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));

Map<String, dynamic> run(
  String id,
  String name,
  String total, {
  String status = 'DRAFTED',
  List<String> hints = const [],
}) => {
  'runId': id,
  'templateId': 't-$id',
  'customerId': 'c-$id',
  'customerName': name,
  'title': null,
  'status': status,
  'errorCode': null,
  'documentId': 'd-$id',
  'documentStatus': status == 'DRAFTED' ? 'DRAFT' : 'FINALIZED',
  'documentNumber': null,
  'documentType': 'TAX_INVOICE',
  'subtotalMinor': total,
  'totalMinor': total,
  'lineCount': 1,
  'hints': hints,
  'hasEmail': true,
  'hasPhone': false,
};

void month(FakeBackend b, List<Map<String, dynamic>> items) {
  final pending = items.where((i) => i['status'] == 'DRAFTED');
  b.json('GET', '/recurring/months/:period', {
    'period': '2026-11',
    'labelHe': 'נובמבר 2026',
    'items': items,
    'pendingCount': pending.length,
    'pendingTotalMinor': pending
        .fold<BigInt>(BigInt.zero, (s, i) => s + BigInt.parse(i['totalMinor']))
        .toString(),
  });
}

DocumentDetail doc({
  String type = 'TAX_INVOICE',
  String status = 'FINALIZED',
  String? customerId = 'c1',
}) => DocumentDetail(
  id: 'd1',
  documentType: type,
  status: status,
  currency: 'ILS',
  subtotalMinor: BigInt.from(600000),
  taxTotalMinor: BigInt.from(108000),
  totalMinor: BigInt.from(708000),
  paidTotalMinor: BigInt.zero,
  balanceMinor: BigInt.from(708000),
  customerId: customerId,
  lines: const [],
);

void main() {
  group('who sees it', () {
    test(
      'Management entry: drafts + amounts (owner yes, plain employee no)',
      () {
        expect(mayUseRetainers(capsOf(Preset.owner)), isTrue);
        expect(mayUseRetainers(capsOf(Preset.employee)), isFalse);
        expect(mayUseRetainers(capsOf(Preset.viewer)), isFalse);
      },
    );

    test('"הפוך לחודשי": only an issued 305/300 with a customer', () {
      final owner = capsOf(Preset.owner);
      expect(mayMakeMonthly(doc(), owner), isTrue);
      expect(mayMakeMonthly(doc(type: 'TRANSACTION_INVOICE'), owner), isTrue);
      expect(mayMakeMonthly(doc(type: 'RECEIPT'), owner), isFalse);
      expect(mayMakeMonthly(doc(type: 'TAX_INVOICE_RECEIPT'), owner), isFalse);
      expect(mayMakeMonthly(doc(status: 'DRAFT'), owner), isFalse);
      expect(mayMakeMonthly(doc(customerId: null), owner), isFalse);
      expect(mayMakeMonthly(doc(), capsOf(Preset.employee)), isFalse);
    });

    test('this month is the Israel month (UTC+2 / +3), not the UTC one', () {
      // 30.11 23:30 UTC = 1.12 01:30 in Israel.
      expect(currentPeriod(DateTime.utc(2026, 11, 30, 23, 30)), '2026-12');
      expect(currentPeriod(DateTime.utc(2026, 11, 30, 21, 30)), '2026-11');
      // Summer (+3): 31.7 21:30 UTC = 1.8 00:30.
      expect(currentPeriod(DateTime.utc(2026, 7, 31, 21, 30)), '2026-08');
    });
  });

  group('חשבוניות החודש', () {
    late FakeBackend b;
    setUp(() async => b = await eSetUp());

    testWidgets('lists the drafts with totals, hints and one issue button', (
      t,
    ) async {
      month(b, [
        run('r1', 'סטודיו אלף', '708000', hints: ['APPROVAL', 'ALLOCATION']),
        run('r2', 'חברת בית', '118000'),
        run('r3', 'לקוח שהופק', '50000', status: 'ISSUED'),
      ]);
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      expect(find.text('סטודיו אלף'), findsOneWidget);
      expect(find.text('₪7,080'), findsOneWidget);
      expect(find.text(RetainerHe.hintApproval), findsOneWidget);
      expect(find.text(RetainerHe.hintAllocation), findsOneWidget);
      expect(find.byKey(const Key('retainer-status-r3')), findsOneWidget);
      expect(find.text(RetainerHe.status('ISSUED')), findsOneWidget);
      // Only waiting drafts have row actions.
      expect(find.byKey(const Key('retainer-menu-r3')), findsNothing);
      expect(find.byKey(const Key('retainer-menu-r1')), findsOneWidget);
      // Totals share the card's end edge, menu or not (2026-11-23).
      expect(
        t.getTopLeft(find.byKey(const Key('retainer-total-r1'))).dx,
        closeTo(
          t.getTopLeft(find.byKey(const Key('retainer-total-r3'))).dx,
          .1,
        ),
      );
      expect(find.textContaining(RetainerHe.readyCount(2)), findsOneWidget);
      expect(
        find.textContaining('${RetainerHe.issueAll} · ₪8,260'),
        findsOneWidget,
      );
    });

    testWidgets('"הפק הכל": a double tap sends ONE request, then reloads', (
      t,
    ) async {
      month(b, [run('r1', 'סטודיו אלף', '708000')]);
      b.on('POST', '/recurring/months/:period/issue', (r) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const FakeResponse(200, {
          'items': [
            {'runId': 'r1', 'outcome': 'ISSUED', 'errorCode': null},
          ],
          'summary': {
            'issued': 1,
            'submitted': 0,
            'waitingAllocation': 0,
            'failed': 0,
            'signingLocked': 0,
          },
        });
      });
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      final button = find.byKey(const Key('retainers-issue-all'));
      await t.tap(button);
      await t.tap(button, warnIfMissed: false);
      await settle(t);
      expect(b.calls('POST', '/recurring/months/:period/issue'), hasLength(1));
      final body = b.last('POST', '/recurring/months/:period/issue')!.body;
      expect(body['scopeKey'], isNotNull);
      expect(body['send'], isFalse);
      expect(
        b.calls('GET', '/recurring/months/:period').length,
        greaterThan(1),
      );
    });

    testWidgets('"ושלח" is sent with the issue when ticked', (t) async {
      month(b, [run('r1', 'סטודיו אלף', '708000')]);
      b.json('POST', '/recurring/months/:period/issue', {
        'items': [],
        'summary': {'issued': 1},
      });
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      await t.tap(find.byKey(const Key('retainers-send')));
      await settle(t);
      await t.tap(find.byKey(const Key('retainers-issue-all')));
      await settle(t);
      expect(
        b.last('POST', '/recurring/months/:period/issue')!.body['send'],
        isTrue,
      );
    });

    testWidgets('row: skip this month', (t) async {
      month(b, [run('r1', 'סטודיו אלף', '708000')]);
      b.json('POST', '/recurring/runs/:id/skip', {'status': 'SKIPPED'});
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      await t.tap(find.byKey(const Key('retainer-menu-r1')));
      await settle(t);
      await t.tap(find.text(RetainerHe.skip));
      await settle(t);
      expect(b.last('POST', '/recurring/runs/:id/skip')!.params['id'], 'r1');
    });

    testWidgets('row: edit amount → new unit price for this month', (t) async {
      month(b, [run('r1', 'סטודיו אלף', '708000')]);
      b.json('GET', '/documents/:id', {
        'document': {'id': 'd-r1'},
        'lines': [
          {'description': 'ריטיינר', 'unit_price_minor': '600000'},
        ],
      });
      b.json('PUT', '/recurring/runs/:id/prices', {'status': 'DRAFTED'});
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      await t.tap(find.byKey(const Key('retainer-menu-r1')));
      await settle(t);
      await t.tap(find.text(RetainerHe.editAmount));
      await settle(t);
      await t.enterText(find.byKey(const Key('retainer-price-0')), '6500');
      await t.pump();
      await t.tap(find.byKey(const Key('retainer-price-save')));
      await settle(t);
      expect(b.last('PUT', '/recurring/runs/:id/prices')!.body, {
        'unitPricesMinor': ['650000'],
      });
    });

    testWidgets('empty month explains where drafts come from', (t) async {
      month(b, []);
      await pumpAs(
        t,
        b,
        Preset.owner,
        const RetainersMonthScreen(period: '2026-11'),
      );
      expect(find.text(RetainerHe.nothingYet), findsOneWidget);
      expect(find.byKey(const Key('retainers-issue-all')), findsNothing);
    });
  });

  group('חשבוניות חודשיות (templates)', () {
    late FakeBackend b;
    setUp(() async => b = await eSetUp());

    testWidgets('#13: a template without VAT (0%) shows its amount bare', (
      t,
    ) async {
      b.json('GET', '/recurring/templates', {
        'templates': [
          {
            'id': 'tp0',
            'customerName': 'עמותה',
            'dayOfMonth': 5,
            'status': 'ACTIVE',
            'subtotalMinor': '45000',
            'lines': [
              {
                'description': 'שירות',
                'quantityMicros': '1000000',
                'unitPriceMinor': '45000',
                'discountMinor': '0',
                'taxRateBasisPoints': 0,
              },
            ],
          },
        ],
      });
      await pumpAs(t, b, Preset.owner, const RetainerTemplatesScreen());
      expect(find.textContaining('₪450'), findsOneWidget);
      expect(find.textContaining('מע״מ'), findsNothing);
    });

    testWidgets('pause sends status PAUSED', (t) async {
      final template = {
        'id': 'tp1',
        'customerName': 'סטודיו אלף',
        'dayOfMonth': 1,
        'status': 'ACTIVE',
        'subtotalMinor': '600000',
        'lines': [
          {
            'description': 'ריטיינר',
            'quantityMicros': '1000000',
            'unitPriceMinor': '600000',
            'discountMinor': '0',
            'taxRateBasisPoints': 1800,
          },
        ],
      };
      b.json('GET', '/recurring/templates', {
        'templates': [template],
      });
      b.json('PATCH', '/recurring/templates/:id', {
        'template': {...template, 'status': 'PAUSED'},
      });
      await pumpAs(t, b, Preset.owner, const RetainerTemplatesScreen());
      expect(find.textContaining(RetainerHe.every(1)), findsOneWidget);
      // Walkthrough #13: the net amount says it is before VAT.
      expect(find.textContaining('₪6,000 + מע״מ'), findsOneWidget);
      await t.tap(find.byKey(const Key('template-tp1')));
      await settle(t);
      await t.tap(find.byKey(const Key('template-pause')));
      await settle(t);
      expect(b.last('PATCH', '/recurring/templates/:id')!.body, {
        'status': 'PAUSED',
      });
    });
  });
}
