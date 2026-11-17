// 0110 · customer timeline (ציר זמן) + payment terms (תנאי תשלום):
// due-date math (Israeli convention, Israel civil date), sentences, the
// timeline screen (pages, hidden amounts, notes), the card's terms row and
// sheet, and the Composer prefill (terms → due date, preferred method).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/customer_timeline_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/compose/compose_loader.dart'
    show applyCustomerTerms;
import 'package:invoice/screens/compose/compose_state.dart';
import 'package:invoice/screens/people/customer_timeline_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/composer_config.dart';
import 'package:invoice/util/israel_date.dart';
import 'package:invoice/util/labels/common_he.dart' show formatDateHe;
import 'package:invoice/util/labels/timeline_he.dart';
import 'package:invoice/util/payment_terms.dart';

import 'fakes/fake_api.dart';

String iso(DateTime d) => isoDate(d);

void main() {
  group('due dates (שוטף+N = end of the issue month + N days)', () {
    test('presets, custom codes, month ends and leap years', () {
      final cases = <(String?, int?, DateTime, String)>[
        ('IMMEDIATE', null, DateTime(2026, 11, 17), '2026-11-17'),
        ('EOM', null, DateTime(2026, 11, 17), '2026-11-30'),
        ('EOM_30', null, DateTime(2026, 1, 15), '2026-03-02'),
        ('EOM_30', null, DateTime(2028, 1, 15), '2028-03-01'),
        ('EOM', null, DateTime(2028, 2, 3), '2028-02-29'),
        ('EOM_30', null, DateTime(2026, 12, 31), '2027-01-30'),
        ('EOM_45', null, DateTime(2026, 12, 5), '2027-02-14'),
        ('EOM_60', null, DateTime(2026, 11, 17), '2027-01-29'),
        ('EOM_90', null, DateTime(2026, 11, 17), '2027-02-28'),
        ('EOM_DAYS', 0, DateTime(2026, 3, 31), '2026-03-31'),
        ('EOM_DAYS', 120, DateTime(2026, 3, 10), '2026-07-29'),
        ('NET_DAYS', 14, DateTime(2026, 11, 17), '2026-12-01'),
        ('NET_DAYS', 10, DateTime(2028, 2, 20), '2028-03-01'),
        // Unknown / none → the Composer's §7 default שוטף+30.
        (null, null, DateTime(2026, 11, 1), '2026-12-30'),
        ('BOGUS', null, DateTime(2026, 11, 1), '2026-12-30'),
      ];
      for (final (code, days, issue, due) in cases) {
        expect(
          iso(dueDateFor(code, issue, days: days)),
          due,
          reason: '$code/$days',
        );
        expect(dueDateForTerms(code, issue, days: days), due);
      }
    });

    test('labels', () {
      expect(paymentTermsLabel('IMMEDIATE'), 'מיידי');
      expect(paymentTermsLabel('EOM'), 'שוטף');
      expect(paymentTermsLabel('EOM_45'), 'שוטף+45');
      expect(paymentTermsLabel('EOM_DAYS', days: 120), 'שוטף+120');
      expect(paymentTermsLabel('EOM_DAYS', days: 0), 'שוטף');
      expect(paymentTermsLabel('NET_DAYS', days: 14), 'תוך 14 ימים');
      expect(paymentTermsLabel(null), isNull);
      expect(
        termsSummary(paymentTermsLabel('EOM_30'), 'BANK_TRANSFER'),
        'שוטף+30 · העברה',
      );
      expect(termsSummary(null, null), isNull);
    });

    test('the Israel civil date, whatever the device time zone', () {
      // Winter (UTC+2): 22:30 UTC is already tomorrow in Israel.
      expect(israelToday(DateTime.utc(2026, 11, 16, 22, 30)), '2026-11-17');
      expect(israelToday(DateTime.utc(2026, 11, 16, 21, 59)), '2026-11-16');
      // Summer (UTC+3): 21:30 UTC is tomorrow.
      expect(israelToday(DateTime.utc(2026, 7, 1, 21, 30)), '2026-07-02');
      expect(israelToday(DateTime.utc(2026, 7, 1, 20, 59)), '2026-07-01');
      // DST 2026: from Fri 27.3 02:00 IST to Sun 25.10 02:00 IDT.
      expect(israelSummerTime(DateTime.utc(2026, 3, 26, 23, 59)), isFalse);
      expect(israelSummerTime(DateTime.utc(2026, 3, 27, 0, 0)), isTrue);
      expect(israelSummerTime(DateTime.utc(2026, 10, 24, 22, 59)), isTrue);
      expect(israelSummerTime(DateTime.utc(2026, 10, 24, 23, 0)), isFalse);
    });
  });

  group('sentences', () {
    test('documents, quotes, payments, reminders, debts, notes', () {
      const inv = {'documentType': 'TAX_INVOICE', 'documentNumber': '1044'};
      expect(timelineSentence('document.issued', inv), 'הופק: חשבונית מס 1044');
      expect(
        timelineSentence('document.sent', {...inv, 'channel': 'WHATSAPP'}),
        'נשלח בוואטסאפ: חשבונית מס 1044',
      );
      expect(timelineSentence('document.voided', inv), 'בוטל: חשבונית מס 1044');
      expect(
        timelineSentence('quote.accepted', {
          'quoteNumber': '12',
          'byCustomer': true,
        }),
        'הצעת מחיר 12 אושרה על ידי הלקוח',
      );
      expect(timelineSentence('quote.declined', {}), 'הצעת מחיר נדחתה');
      expect(
        timelineSentence('payment.recorded', {
          'method': 'BANK_TRANSFER',
          'wallet': 'ביט',
        }),
        'התקבל תשלום · ביט',
      );
      expect(
        timelineSentence('reminder.sent', {'channel': 'WHATSAPP'}),
        'נשלחה תזכורת תשלום בוואטסאפ',
      );
      expect(
        timelineSentence('debt.created', {'note': '2 שיעורים'}),
        'נרשם חוב: 2 שיעורים',
      );
      expect(timelineSentence('note', {'body': 'להתקשר'}), 'להתקשר');
      expect(timelineSentence('mystery.kind', {}), 'עדכון');
    });

    test('integration 2026-11-17: calendar bookings + automatic reminders', () {
      expect(timelineSentence('calendar.booked', {}), 'נקבעה פגישה');
      expect(
        timelineSentence('calendar.booked', {
          'startsAtIsrael': '2026-12-01 09:30',
        }),
        'נקבעה פגישה · 01.12 09:30',
      );
      expect(
        timelineSentence('calendar.cancelled', {
          'startsAtIsrael': '2026-12-01 09:30',
          'cancelledBy': 'CLIENT',
        }),
        'הלקוח ביטל פגישה · 01.12 09:30',
      );
      expect(
        timelineSentence('reminder.sent', {'channel': 'EMAIL', 'auto': true}),
        'נשלחה תזכורת אוטומטית במייל',
      );
      expect(TimelineHe.chips['calendar'], 'פגישות');
    });
  });

  group('screens', () {
    late Directory tmp;
    late FakeBackend backend;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('cus1_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      resetSession();
      await AppCache.clearAll();
      backend = FakeBackend()..install();
    });

    Future<void> flush(WidgetTester tester, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await flush(tester, 3);
      }
      await tester.ensureVisible(f);
      await tester.tap(f);
      await flush(tester);
    }

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Preset preset = Preset.owner,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => signInAs(backend, preset));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: home,
        ),
      );
      await flush(tester);
    }

    Map<String, dynamic> item(
      String id,
      String kind, {
      String atIsrael = '2026-11-10 09:30',
      String? amount,
      bool hidden = false,
      Map<String, dynamic>? link,
      bool mine = false,
      Map<String, dynamic> data = const {},
      String? actor = 'דנה',
    }) => {
      'id': id,
      'kind': kind,
      'at': '2026-11-10T07:30:00.000000Z',
      'atIsrael': atIsrael,
      'actor': {'id': 'u1', 'name': actor},
      'createdBy': 'u1',
      'amountMinor': amount,
      'amountHidden': hidden,
      'link': link,
      'mine': mine,
      'data': data,
    };

    void timeline(List<Map<String, dynamic>> first, {String? cursor}) {
      backend.on('GET', '/customers/:id/timeline', (r) {
        if (r.query['cursor'] == 'c2') {
          return FakeResponse(200, {
            'items': [
              item(
                'reminder.sent:1',
                'reminder.sent',
                atIsrael: '2026-10-01 08:00',
                data: {'channel': 'WHATSAPP', 'items': 1},
              ),
            ],
            'nextCursor': null,
            'sources': ['documents', 'notes', 'reminders'],
          });
        }
        return FakeResponse(200, {
          'items': first,
          'nextCursor': cursor,
          'sources': ['documents', 'payments', 'notes', 'reminders'],
        });
      });
    }

    testWidgets('timeline: rows by day, hidden amount "—", more, filter', (
      tester,
    ) async {
      timeline([
        item(
          'note:n1',
          'note',
          mine: true,
          link: {'type': 'customerNote', 'id': 'n1'},
          data: {'body': 'להתקשר ביום ראשון', 'edited': true},
        ),
        item(
          'document.issued:d1',
          'document.issued',
          amount: null,
          hidden: true,
          link: {'type': 'document', 'id': 'd1'},
          data: {'documentType': 'TAX_INVOICE', 'documentNumber': '1044'},
        ),
        item(
          'payment.recorded:p1',
          'payment.recorded',
          atIsrael: '2026-11-02 10:00',
          amount: '50000',
          link: {'type': 'document', 'id': 'r1'},
          data: {'method': 'CASH'},
        ),
      ], cursor: 'c2');
      await pump(
        tester,
        const CustomerTimelineScreen(customerId: 'c1', customerName: 'דנה'),
      );
      expect(find.text('ציר זמן'), findsOneWidget);
      expect(find.text('להתקשר ביום ראשון'), findsOneWidget);
      expect(find.textContaining('נערכה'), findsOneWidget);
      expect(find.text('הופק: חשבונית מס 1044'), findsOneWidget);
      // Hidden, never ₪0.
      expect(find.byKey(const Key('timeline-amount-hidden')), findsOneWidget);
      expect(find.textContaining('₪0'), findsNothing);
      expect(find.text('התקבל תשלום · מזומן'), findsOneWidget);
      expect(find.text('10.11.2026'), findsOneWidget);
      expect(find.text('2.11.2026'), findsOneWidget);
      // Chips only for the sources the member may read.
      expect(find.text('תשלומים'), findsOneWidget);
      expect(find.text('חובות'), findsNothing);

      await tap(tester, find.byKey(const Key('timeline-more')));
      expect(
        backend.last('GET', '/customers/:id/timeline')!.query['cursor'],
        'c2',
      );
      expect(find.text('נשלחה תזכורת תשלום בוואטסאפ'), findsOneWidget);
      expect(find.byKey(const Key('timeline-more')), findsNothing);

      await tap(tester, find.text('הערות'));
      expect(
        backend.last('GET', '/customers/:id/timeline')!.query['sources'],
        'notes',
      );
    });

    testWidgets('notes: add, edit own (author only), delete with confirm', (
      tester,
    ) async {
      timeline([
        item(
          'note:n1',
          'note',
          mine: true,
          link: {'type': 'customerNote', 'id': 'n1'},
          data: {'body': 'הערה שלי'},
        ),
        item(
          'note:n2',
          'note',
          mine: false,
          link: {'type': 'customerNote', 'id': 'n2'},
          data: {'body': 'הערה של אחר'},
        ),
      ]);
      backend
        ..json('POST', '/customers/:id/notes', {'note': {}}, status: 201)
        ..json('PATCH', '/customer-notes/:id', {'note': {}})
        ..json('DELETE', '/customer-notes/:id', {'deleted': true});
      await pump(
        tester,
        const CustomerTimelineScreen(customerId: 'c1', customerName: 'דנה'),
      );
      await tap(tester, find.byKey(const Key('timeline-add-note')));
      await tester.enterText(find.byKey(const Key('note-text')), '  חדש  ');
      await tap(tester, find.byKey(const Key('note-save')));
      expect(backend.last('POST', '/customers/:id/notes')!.body, {
        'body': 'חדש',
      });
      expect(backend.last('POST', '/customers/:id/notes')!.params['id'], 'c1');

      // Someone else's note is not tappable.
      await tester.tap(find.text('הערה של אחר'));
      await flush(tester);
      expect(find.byKey(const Key('note-edit')), findsNothing);

      await tap(tester, find.text('הערה שלי'));
      await tap(tester, find.byKey(const Key('note-edit')));
      await tester.enterText(find.byKey(const Key('note-text')), 'מעודכן');
      await tap(tester, find.byKey(const Key('note-save')));
      expect(backend.last('PATCH', '/customer-notes/:id')!.body, {
        'body': 'מעודכן',
      });
      expect(backend.last('PATCH', '/customer-notes/:id')!.params['id'], 'n1');

      await tap(tester, find.text('הערה שלי'));
      await tap(tester, find.byKey(const Key('note-delete')));
      await tap(tester, find.byKey(const Key('note-delete-confirm')));
      expect(backend.calls('DELETE', '/customer-notes/:id'), hasLength(1));
    });

    testWidgets('viewer: reads the timeline, no "הוסף הערה"', (tester) async {
      timeline([]);
      await pump(
        tester,
        const CustomerTimelineScreen(customerId: 'c1', customerName: 'דנה'),
        preset: Preset.viewer,
      );
      expect(find.byKey(const Key('timeline-empty')), findsOneWidget);
      expect(find.byKey(const Key('timeline-add-note')), findsNothing);
    });

    Map<String, dynamic> detail({
      String? terms,
      int? days,
      String? method,
      Map<String, dynamic>? effective,
    }) => {
      'customer': {
        ...customerJson('c1', 'דנה', phone: '0501234567', be09: true),
        'paymentTerms': terms,
        'paymentTermsDays': days,
        'preferredPaymentMethod': method,
        'effectivePaymentTerms':
            effective ??
            {
              'code': terms,
              'days': days,
              'preferredPaymentMethod': method,
              'source': terms == null ? null : 'CUSTOMER',
            },
      },
      'stats': {
        'openMinor': '0',
        'overdueMinor': '0',
        'creditMinor': '0',
        'documentsCount': 0,
        'lastDocumentAt': null,
      },
    };

    testWidgets('card: terms row (business default marked) → sheet → PATCH', (
      tester,
    ) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה', be09: true)],
        be09: true,
      );
      backend
        ..json(
          'GET',
          '/customers/:id',
          detail(
            effective: {
              'code': 'EOM_30',
              'days': null,
              'preferredPaymentMethod': 'BANK_TRANSFER',
              'source': 'BUSINESS',
            },
          ),
        )
        ..json('PATCH', '/customers/:id', {'id': 'c1'});
      timeline([]);
      await pump(tester, const PersonScreen(id: 'c1'));
      expect(
        find.text('שוטף+30 · העברה (ברירת המחדל של העסק)'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('person-timeline')), findsOneWidget);

      await tap(tester, find.byKey(const Key('person-terms')));
      expect(find.byKey(const Key('terms-sheet')), findsOneWidget);
      await tap(tester, find.text('מותאם'));
      await tester.enterText(find.byKey(const Key('terms-days')), '400');
      await tap(tester, find.text('מתאריך המסמך'));
      await tap(tester, find.byKey(const Key('terms-save')));
      expect(find.text(TimelineHe.daysInvalid), findsOneWidget);
      expect(backend.calls('PATCH', '/customers/:id'), isEmpty);

      await tester.enterText(find.byKey(const Key('terms-days')), '14');
      await flush(tester);
      expect(
        find.text(
          TimelineHe.dueExample(
            formatDateHe(dueDateTodayFor('NET_DAYS', days: 14)),
          ),
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('ביט'));
      await tap(tester, find.byKey(const Key('terms-save')));
      expect(backend.last('PATCH', '/customers/:id')!.body, {
        'paymentTerms': 'NET_DAYS',
        'paymentTermsDays': 14,
        'preferredPaymentMethod': 'BIT',
      });

      await tap(tester, find.byKey(const Key('person-timeline')));
      expect(find.byType(CustomerTimelineScreen), findsOneWidget);
    });

    testWidgets('employee: sees the terms, cannot edit them', (tester) async {
      installPeopleFakes(
        backend,
        customers: [customerJson('c1', 'דנה', be09: true)],
        be09: true,
      );
      backend.json('GET', '/customers/:id', detail(terms: 'IMMEDIATE'));
      await pump(tester, const PersonScreen(id: 'c1'), preset: Preset.employee);
      expect(find.text('מיידי'), findsOneWidget);
      await tester.tap(find.byKey(const Key('person-terms')));
      await flush(tester);
      expect(find.byKey(const Key('terms-sheet')), findsNothing);
    });
  });

  group('Composer prefill', () {
    late FakeBackend backend;
    setUp(() async {
      resetSession();
      backend = FakeBackend()..install();
      await signInAs(backend, Preset.owner);
    });

    ComposeState st(DocKind k) =>
        ComposeState(kind: k, businessType: 'OSEK_MURSHE', vatBasisPoints: 1800)
          ..customer = const Customer(id: 'c1', name: 'דנה');

    void customer(Map<String, dynamic> effective) =>
        backend.json('GET', '/customers/:id', {
          'customer': {
            'id': 'c1',
            'name': 'דנה',
            'paymentTerms': null,
            'effectivePaymentTerms': effective,
          },
          'stats': <String, dynamic>{},
        });

    test(
      'effective terms → due date (Israel today); preferred method',
      () async {
        customer({
          'code': 'NET_DAYS',
          'days': 10,
          'preferredPaymentMethod': 'BIT',
          'source': 'CUSTOMER',
        });
        final s = st(DocKind.taxInvoice);
        await applyCustomerTerms(s, preferMethod: true);
        expect(s.customerTerms, 'NET_DAYS');
        expect(s.customerTermsDays, 10);
        expect(s.dueDate, dueDateTodayFor('NET_DAYS', days: 10));
        expect(s.requestBody()['dueDate'], s.dueDate);
        expect(s.requestBody()['issueDate'], israelToday());
        expect(s.method, 'BIT');
      },
    );

    test('the user\'s chip / a picked date win over the terms', () async {
      customer({
        'code': 'IMMEDIATE',
        'days': null,
        'preferredPaymentMethod': 'CHECK',
        'source': 'BUSINESS',
      });
      final s = st(DocKind.receipt)
        ..method = 'CASH'
        ..methodTouched = true
        ..pickedDueDate = '2026-12-31';
      await applyCustomerTerms(s, preferMethod: true);
      expect(s.method, 'CASH');
      expect(s.dueDate, '2026-12-31');
      final copied = st(DocKind.receipt)..method = 'CREDIT_CARD';
      await applyCustomerTerms(copied);
      expect(copied.method, 'CREDIT_CARD', reason: 'a source document method');
    });

    test('an older server (no effectivePaymentTerms) keeps the code', () async {
      backend.json('GET', '/customers/:id', {
        'customer': {'id': 'c1', 'name': 'דנה', 'paymentTerms': 'EOM_60'},
        'stats': <String, dynamic>{},
      });
      final s = st(DocKind.taxInvoice);
      await applyCustomerTerms(s);
      expect(s.customerTerms, 'EOM_60');
      expect(s.dueDate, dueDateForTerms('EOM_60', israelTodayDate()));
    });
  });

  test('PaymentTermsValue JSON: days only with a custom code', () {
    expect(
      const PaymentTermsValue(code: 'EOM_30', days: 9, method: null).toJson(),
      {'paymentTerms': 'EOM_30', 'preferredPaymentMethod': null},
    );
    expect(const PaymentTermsValue(code: 'EOM_DAYS', days: 0).toJson(), {
      'paymentTerms': 'EOM_DAYS',
      'paymentTermsDays': 0,
      'preferredPaymentMethod': null,
    });
  });
}
