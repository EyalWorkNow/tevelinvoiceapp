// Squad D unit tests: customers / suppliers / items / expense-review APIs and
// their pure helpers (SPEC-v2 §6.P, §6.P2, S2, §6.E, §10).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/customers_api.dart';
import 'package:invoice/api/expenses_api.dart';
import 'package:invoice/api/items_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/suppliers_api.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';

import 'fakes/fake_api.dart';

Customer _c(
  String name, {
  String? phone,
  String id = '',
  String? last,
  String? taxId,
  bool archived = false,
}) => Customer(
  id: id.isEmpty ? name : id,
  name: name,
  phone: phone,
  taxId: taxId,
  lastDocumentAt: last,
  archivedAt: archived ? '2026-01-01' : null,
);

DocumentSummary _d(
  String type,
  String status,
  int open, {
  String customer = 'c1',
  String? voided,
}) => DocumentSummary(
  id: '$type$open',
  documentType: type,
  status: status,
  customerId: customer,
  currency: 'ILS',
  totalMinor: BigInt.from(open),
  balanceMinor: BigInt.from(open),
  voidedAt: voided,
);

void main() {
  late Directory tmp;
  late FakeBackend backend;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('d_api');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    resetSession();
    await AppCache.clearAll();
    backend = FakeBackend()..install();
    await signInAs(backend, Preset.owner);
  });

  group('pure helpers', () {
    test('search by name, e-mail, phone or tax id digits', () {
      const c = Customer(
        id: '1',
        name: 'דנה כהן',
        email: 'dana@x.co',
        phone: '050-123-4567',
        taxId: '514713288',
      );
      expect(customerMatches(c, ''), isTrue);
      expect(customerMatches(c, 'דנה'), isTrue);
      expect(customerMatches(c, 'DANA@'), isTrue);
      expect(customerMatches(c, '1234'), isTrue);
      expect(customerMatches(c, '4713'), isTrue);
      expect(
        customerMatches(c, '12'),
        isFalse,
        reason: 'fewer than 3 digits do not match numbers',
      );
      expect(customerMatches(c, 'משה'), isFalse);
    });

    test(
      '§6.P order: with documents newest first, then recent picks, then א–ת',
      () {
        final list = sortForPeople(
          [
            _c('תמר'),
            _c('אבי'),
            _c('גל', last: '2026-10-01T00:00:00Z'),
            _c('בני', last: '2026-10-20T00:00:00Z'),
            _c('דן'),
          ],
          recentIds: ['דן'],
        );
        expect(list.map((c) => c.name), ['בני', 'גל', 'דן', 'אבי', 'תמר']);
      },
    );

    test(
      'S2 recent circles: device picks first (even with no documents), then by documents, max 8',
      () {
        final sorted = sortForPeople([
          for (var i = 0; i < 10; i++)
            _c('ל$i', last: '2026-10-${(10 + i).toString()}T00:00:00Z'),
          _c('חדש'),
          _c('ישן', archived: true),
        ]);
        final circles = recentCircles(
          sorted,
          (c) => c.id,
          ['חדש', 'ישן', 'ל0'],
          eligible: (c) => c.lastDocumentAt != null,
          excluded: (c) => c.isArchived,
        );
        expect(circles.map((c) => c.name).toList(), [
          'חדש',
          'ל0',
          'ל9',
          'ל8',
          'ל7',
          'ל6',
          'ל5',
          'ל4',
        ]);
      },
    );

    test(
      'S2 duplicate check: name, phone (last 9 digits) or tax id; archived ignored',
      () {
        final all = [
          _c('דנה', id: '1', phone: '0501234567'),
          _c('משה', id: '2', taxId: '514713288'),
          _c('ישן', id: '3', archived: true),
        ];
        expect(findDuplicateCustomer(all, name: ' דנה ')?.id, '1');
        expect(
          findDuplicateCustomer(all, name: 'x', phone: '+972 50-123-4567')?.id,
          '1',
        );
        expect(
          findDuplicateCustomer(all, name: 'x', taxId: '514713288')?.id,
          '2',
        );
        expect(findDuplicateCustomer(all, name: 'ישן'), isNull);
        expect(findDuplicateCustomer(all, name: 'דנה', exceptId: '1'), isNull);
        expect(findDuplicateCustomer(all, name: 'חדש', phone: '052'), isNull);
      },
    );

    test('customerType is derived from the tax id (§10)', () {
      expect(customerTypeFor(null), 'INDIVIDUAL');
      expect(customerTypeFor('  '), 'INDIVIDUAL');
      expect(customerTypeFor('514713288'), 'BUSINESS');
    });

    test('contact phone: prefer an Israeli mobile; normalized', () {
      expect(
        preferredPhone(['03-555-1234', '+972 52-111-2222']),
        '+972521112222',
      );
      expect(preferredPhone(['03-555-1234']), '035551234');
      expect(preferredPhone(const []), isNull);
      expect(normalizePhoneInput(' 050-123 4567 '), '0501234567');
      expect(normalizePhoneInput(''), isNull);
    });

    test('validators', () {
      expect(isValidIsraeliId('514713288'), isTrue);
      expect(isValidIsraeliId('514713289'), isFalse);
      expect(isValidIsraeliId('12a'), isFalse);
      expect(isValidEmail('a@b.co'), isTrue);
      expect(isValidEmail('a@b'), isFalse);
      expect(isValidPhoneInput('050-1234567'), isTrue);
      expect(isValidPhoneInput('1234'), isFalse);
      expect(initialsOf('דנה כהן'), 'דכ');
      expect(initialsOf(''), '?');
      expect(
        initialsOf('QA חייב 17'),
        'Q',
        reason: 'mixed scripts → one initial (no RTL reversal)',
      );
      expect(initialsOf('John Smith'), 'JS');
    });

    test('open balance: issued 300/305 only, openMinor, voided excluded', () {
      final docs = [
        _d('TAX_INVOICE', 'ARCHIVED', 118000),
        _d('TRANSACTION_INVOICE', 'SENT', 5000),
        _d('TAX_INVOICE_RECEIPT', 'ARCHIVED', 7),
        _d('RECEIPT', 'ARCHIVED', 50000),
        _d('TAX_INVOICE', 'DRAFT', 9999),
        _d('TAX_INVOICE', 'PENDING_APPROVAL', 9999),
        _d('TRANSACTION_INVOICE', 'ARCHIVED', 3000, voided: '2026-10-01'),
      ];
      expect(openBalanceOf(docs), BigInt.from(123000));
    });

    test('item suggestions: prefix first, then contains; archived never', () {
      Item it(String id, String name, {bool active = true}) => Item(
        id: id,
        name: name,
        itemType: 'SERVICE',
        currency: 'ILS',
        isActive: active,
      );
      final items = [
        it('1', 'תיקון דוד'),
        it('2', 'דוד שמש'),
        it('3', 'דוד ישן', active: false),
      ];
      expect(itemSuggestions(items, 'דוד').map((i) => i.id), ['2', '1']);
      expect(itemSuggestions(items, ''), isEmpty);
      expect(shouldOfferSaveAsItem(items, ' תיקון דוד '), isFalse);
      expect(shouldOfferSaveAsItem(items, 'התקנה'), isTrue);
      expect(shouldOfferSaveAsItem(items, ' '), isFalse);
    });

    test(
      'expense draft: whole body; subtotal only with VAT; missing fields',
      () {
        const empty = ExpenseDraft();
        expect(empty.missing(), ['supplier', 'amount', 'date']);
        expect(empty.missing(needCategory: true), [
          'supplier',
          'amount',
          'date',
          'category',
        ]);
        final d = ExpenseDraft(
          supplierName: ' חשמל ',
          documentDate: '2026-10-12',
          totalMinor: BigInt.from(11800),
          categoryId: 'cat-1',
        );
        expect(d.missing(), isEmpty);
        expect(d.toJson(), {
          'supplierName': 'חשמל',
          'documentDate': '2026-10-12',
          'total': {'amountMinor': '11800', 'currency': 'ILS'},
          'categoryId': 'cat-1',
        });
        final withVat = d.copyWith(vatMinor: BigInt.from(1800));
        expect(withVat.toJson()['vat'], {
          'amountMinor': '1800',
          'currency': 'ILS',
        });
        expect(withVat.toJson()['subtotal'], {
          'amountMinor': '10000',
          'currency': 'ILS',
        });
      },
    );

    test(
      'expense queue: reviewable + processing, oldest first; members see only theirs',
      () {
        final rows = [
          ExpenseRow.fromJson(expenseJson('e3')),
          ExpenseRow.fromJson(expenseJson('e2', status: 'APPROVED')),
          ExpenseRow.fromJson(expenseJson('e1', status: 'EXTRACTING')),
          ExpenseRow.fromJson(
            expenseJson('e0', status: 'DUPLICATE', duplicateOf: 'e2'),
          ),
        ];
        expect(expenseReviewQueue(rows, approver: true).map((r) => r.id), [
          'e0',
          'e1',
          'e3',
        ]);
        expect(
          expenseReviewQueue(
            rows,
            approver: false,
            mine: {'e3'},
          ).map((r) => r.id),
          ['e3'],
        );
        expect(expenseListRows(rows, approver: true).length, 4);
        expect(
          expenseListRows(
            rows,
            approver: true,
            mineOnly: true,
            mine: {'e2'},
          ).map((r) => r.id),
          ['e2'],
        );
        expect(
          expenseListRows(rows, approver: false, mine: {'e1'}).map((r) => r.id),
          ['e1'],
        );
      },
    );
  });

  group('API (FakeBackend)', () {
    test(
      'V1 list: recent+limit query, archived kept, cached; not BE-09',
      () async {
        installPeopleFakes(
          backend,
          customers: [
            customerJson('1', 'דנה', phone: '0501234567'),
            customerJson('2', 'ישן', archived: true),
          ],
        );
        final list = await fetchCustomerList();
        expect(backend.last('GET', '/customers')!.query, {
          'sort': 'recent',
          'limit': '500',
        });
        expect(list.customers.length, 2);
        expect(list.active.map((c) => c.id), ['1']);
        expect(list.be09, isFalse);
        expect(list.capped, isFalse);
        expect((await readCachedCustomerList())!.customers.length, 2);
      },
    );

    test(
      'BE-09 list is detected; 500 rows = capped; BE-09 total decides when present',
      () async {
        installPeopleFakes(
          backend,
          customers: [
            for (var i = 0; i < 500; i++)
              customerJson('c$i', 'לקוח $i', be09: true),
          ],
        );
        final list = await fetchCustomerList();
        expect(list.be09, isTrue);
        expect(list.capped, isTrue);
        backend.json('GET', '/customers', {
          'total': 500,
          'offset': 0,
          'limit': 500,
          'customers': [
            for (var i = 0; i < 500; i++)
              customerJson('c$i', 'לקוח $i', be09: true),
          ],
        });
        expect(
          (await fetchCustomerList()).capped,
          isFalse,
          reason: 'exactly 500: nothing more',
        );
      },
    );

    test(
      'detail: BE-09 route, else the list row; unknown id → CUSTOMER_NOT_FOUND',
      () async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', be09: true, balance: '5000')],
          be09: true,
        );
        final d = await fetchCustomerDetail('c1');
        expect(d.fromBe09, isTrue);
        expect(d.openMinor, BigInt.from(5000));
        expect(d.paymentTerms, 'EOM_30');

        backend.off('GET', '/customers/:id');
        final v1 = await fetchCustomerDetail('c1');
        expect(v1.fromBe09, isFalse);
        expect(v1.customer.name, 'דנה');
        await expectLater(
          fetchCustomerDetail('nope'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'CUSTOMER_NOT_FOUND',
            ),
          ),
        );
      },
    );

    test(
      'create: derived customerType, no vatDealerStatus; consent; patch; archive',
      () async {
        installPeopleFakes(backend);
        final c = await createCustomer(
          name: 'מוסך',
          taxId: '514713288',
          phone: '0501234567',
        );
        expect(c.customerType, 'BUSINESS');
        final body = backend.last('POST', '/customers')!.body;
        expect(body['customerType'], 'BUSINESS');
        expect(body.containsKey('vatDealerStatus'), isFalse);

        await grantConsent(c.id);
        expect(backend.last('POST', '/customers/:id/consent')!.body, {
          'method': 'VERBAL_IN_APP',
        });

        await updateCustomer(c.id, {'email': null});
        expect(backend.last('PATCH', '/customers/:id')!.body, {'email': null});
        final before = backend.requests.length;
        await updateCustomer(c.id, {});
        expect(backend.requests.length, before);

        await archiveCustomer(c.id);
        expect(backend.calls('POST', '/customers/:id/archive'), hasLength(1));
      },
    );

    test(
      'open balances: one call limit=500; a capped answer → null (no partial number)',
      () async {
        installPeopleFakes(
          backend,
          documents: [
            {
              'id': 'a',
              'documentType': 'TAX_INVOICE',
              'status': 'SENT',
              'customerId': 'c1',
              'totalMinor': '118000',
              'balanceMinor': '118000',
              'openMinor': '98000',
            },
            {
              'id': 'b',
              'documentType': 'TRANSACTION_INVOICE',
              'status': 'ARCHIVED',
              'customerId': 'c2',
              'totalMinor': '3000',
              'balanceMinor': '3000',
            },
          ],
        );
        final b = await fetchOpenBalances();
        expect(backend.last('GET', '/documents')!.query, {
          'unpaid': '1',
          'limit': '500',
        });
        expect(b, {'c1': BigInt.from(98000), 'c2': BigInt.from(3000)});
        expect(await fetchCustomerOpenMinor('c1'), BigInt.from(98000));
        expect(backend.last('GET', '/documents')!.query, {
          'customerId': 'c1',
          'unpaid': '1',
          'limit': '500',
        });

        backend.json('GET', '/documents', {
          'total': 501,
          'documents': [
            {
              'id': 'x',
              'documentType': 'TAX_INVOICE',
              'status': 'SENT',
              'customerId': 'c1',
              'totalMinor': '1',
              'balanceMinor': '1',
            },
          ],
        });
        expect(await fetchOpenBalances(), isNull);
      },
    );

    test(
      'walk-in: reuses BE-09 isWalkIn / remembered id; else creates one INDIVIDUAL once',
      () async {
        final s = installPeopleFakes(backend);
        final first = await walkInCustomer(const [], name: 'לקוח מזדמן');
        expect(
          backend.last('POST', '/customers')!.body['customerType'],
          'INDIVIDUAL',
        );
        // AT-17: the walk-in is PRIVATE, so ₪6,000 never asks "עוסק מורשה?".
        expect(
          backend.last('POST', '/customers')!.body['vatDealerStatus'],
          'PRIVATE',
        );
        expect(first.vatDealerStatus, 'PRIVATE');
        final loaded = [for (final c in s.customers) Customer.fromJson(c)];
        final again = await walkInCustomer(loaded, name: 'לקוח מזדמן');
        expect(again.id, first.id);
        expect(backend.calls('POST', '/customers'), hasLength(1));
        expect(backend.calls('PATCH', '/customers/:id'), isEmpty);

        // An existing UNKNOWN walk-in (V1 / before this fix) is made PRIVATE when picked.
        s.customers.add(customerJson('w', 'אחר', be09: true, walkIn: true));
        final flagged = Customer.fromJson(s.customers.last);
        expect(flagged.vatDealerStatus, 'UNKNOWN');
        final w = await walkInCustomer([flagged], name: 'לקוח מזדמן');
        expect(w.id, 'w');
        expect(w.vatDealerStatus, 'PRIVATE');
        expect(backend.last('PATCH', '/customers/:id')!.params['id'], 'w');
        expect(backend.last('PATCH', '/customers/:id')!.body, {
          'vatDealerStatus': 'PRIVATE',
        });
        expect(s.customers.last['vat_dealer_status'], 'PRIVATE');

        await AppCache.clearAll();
        await walkInCustomer(const [], name: 'לקוח מזדמן', be09: true);
        expect(backend.last('PATCH', '/customers/:id')!.body, {
          'isWalkIn': true,
        });
      },
    );

    test('recent picks: newest first, ≤8, per business', () async {
      for (var i = 0; i < 10; i++) {
        await rememberRecentCustomer('c$i');
      }
      await rememberRecentCustomer('c3');
      final ids = await readRecentCustomerIds();
      expect(ids.first, 'c3');
      expect(ids.length, 8);
    });

    test(
      'suppliers: list, create, card falls back to the list without BE-16',
      () async {
        installPeopleFakes(
          backend,
          suppliers: [
            {
              'id': 's1',
              'name': 'חשמל',
              'tax_id': null,
              'email': null,
              'phone': null,
              'archived_at': null,
            },
          ],
        );
        expect((await fetchSuppliers()).single.name, 'חשמל');
        final created = await createSupplier(name: 'דלק', taxId: '514713288');
        expect(backend.last('POST', '/suppliers')!.body['taxId'], '514713288');
        expect((await fetchSupplier(created.id)).name, 'דלק');
        expect((await readCachedSuppliers())!.length, 2);
      },
    );

    test(
      'items: create always sends a price; BE-15 patch / archive paths',
      () async {
        installPeopleFakes(backend);
        final item = await createItem(name: ' ייעוץ ');
        expect(backend.last('POST', '/items')!.body, {
          'name': 'ייעוץ',
          'itemType': 'SERVICE',
          'defaultUnitPriceMinor': '0',
          'currency': 'ILS',
        });
        expect((await fetchItems()).single.id, item.id);
        backend
          ..json('PATCH', '/items/:id', {'id': item.id})
          ..json('POST', '/items/:id/archive', {'archived': true});
        await updateItem(item.id, priceMinor: BigInt.from(25000));
        expect(backend.last('PATCH', '/items/:id')!.body, {
          'defaultUnitPriceMinor': '25000',
        });
        await archiveItem(item.id);
        expect(backend.calls('POST', '/items/:id/archive'), hasLength(1));
      },
    );

    test(
      'expense review: approve = full draft PATCH then approve; incomplete → nothing approved',
      () async {
        final s = installPeopleFakes(
          backend,
          expenses: [expenseJson('e1'), expenseJson('e2')],
        );
        final rows = await fetchExpenseInbox();
        expect(rows.map((r) => r.id), ['e1', 'e2']);
        expect((await fetchExpenseCategories()).length, 2);

        await saveAndApproveExpense(
          'e1',
          ExpenseDraft(
            supplierName: 'חשמל',
            documentDate: '2026-10-12',
            totalMinor: BigInt.from(11800),
          ),
        );
        expect(s.expense('e1')!['status'], 'APPROVED');
        expect(backend.last('PATCH', '/expenses/:id/draft')!.body['total'], {
          'amountMinor': '11800',
          'currency': 'ILS',
        });

        await expectLater(
          saveAndApproveExpense('e2', const ExpenseDraft(supplierName: 'x')),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'EXPENSE_VALIDATION_FAILED',
            ),
          ),
        );
        expect(backend.calls('POST', '/expenses/:id/approve'), hasLength(1));

        await rejectExpense('e2', '  לא שלנו ');
        expect(backend.last('POST', '/expenses/:id/reject')!.body, {
          'reason': 'לא שלנו',
        });
        expect(
          await runExpenseExtraction('e2'),
          isFalse,
          reason: '503 → manual entry',
        );
      },
    );

    test(
      '"mine" ids and category memory are per device and per business',
      () async {
        await rememberMyExpense('e1');
        await rememberMyExpense('e2');
        expect(await readMyExpenseIds(), {'e1', 'e2'});
        await rememberExpenseCategory('חשמל', 'cat-2');
        await rememberExpenseCategory('דלק', 'cat-1');
        expect(await lastExpenseCategory('חשמל'), 'cat-2');
        expect(await lastExpenseCategory('חדש'), 'cat-1');
      },
    );
  });

  group('P1/P2 additions', () {
    setUp(resetStatementProbe);

    test(
      'BE-09 address: parsed, shown, compared, sent as the server shape',
      () {
        final d = CustomerDetail.fromJson({
          'customer': {
            'id': 'c1',
            'name': 'דנה',
            'address': {
              'street': 'הרצל',
              'number': '5',
              'city': 'תל אביב',
              'postalCode': null,
            },
            'consent': {'granted': false, 'method': null, 'at': null},
          },
          'stats': {'openMinor': '0'},
        });
        expect(d.address!.display, 'הרצל 5, תל אביב');
        expect(
          d.address,
          const CustomerAddress(street: 'הרצל ', number: '5', city: 'תל אביב'),
        );
        expect(const CustomerAddress(city: ' חיפה', postalCode: ' ').toJson(), {
          'street': '',
          'number': '',
          'city': 'חיפה',
          'postalCode': null,
        });
        expect(const CustomerAddress().isEmpty, isTrue);
      },
    );

    test(
      'BE-17 statement: period = 1 Jan → today; probe once; a missing route hides it',
      () async {
        final p = statementPeriod(DateTime(2026, 3, 7));
        expect(p.from, '2026-01-01');
        expect(p.to, '2026-03-07');

        installPeopleFakes(backend, customers: [customerJson('c1', 'דנה')]);
        expect(await statementAvailable('c1'), isFalse);
        expect(await statementAvailable('c1'), isFalse);
        expect(
          backend.requests.where((r) => r.raw.url.path.endsWith('/statement')),
          hasLength(1),
          reason: 'probed once per business',
        );

        resetStatementProbe();
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה')],
          be17: true,
        );
        expect(await statementAvailable('c1'), isTrue);
        await sendStatement('c1', now: DateTime(2026, 10, 30));
        expect(backend.last('POST', '/customers/:id/statement/send')!.body, {
          'channel': 'EMAIL',
          'from': '2026-01-01',
          'to': '2026-10-30',
        });
        expect(await fetchStatementPdf('c1'), [0x25, 0x50, 0x44, 0x46]);
      },
    );

    test(
      'BE-16 supplier card: be16 flag, patch only changes, archive',
      () async {
        final sup = {
          'id': 's1',
          'name': 'חשמל',
          'tax_id': null,
          'email': null,
          'phone': null,
          'archived_at': null,
        };
        installPeopleFakes(backend, suppliers: [sup]);
        expect((await fetchSupplierCard('s1')).be16, isFalse);
        installPeopleFakes(backend, suppliers: [sup], be16: true);
        final card = await fetchSupplierCard('s1');
        expect(card.be16, isTrue);
        expect(card.supplier.name, 'חשמל');
        await updateSupplier('s1', {'phone': '036000000'});
        expect(backend.last('PATCH', '/suppliers/:id')!.body, {
          'phone': '036000000',
        });
        await updateSupplier('s1', {});
        expect(
          backend.calls('PATCH', '/suppliers/:id'),
          hasLength(1),
          reason: 'nothing changed → no call',
        );
        await archiveSupplier('s1');
        expect(backend.calls('POST', '/suppliers/:id/archive'), hasLength(1));
      },
    );

    test(
      'BE-44: list (null without the route), patch, delete; local search',
      () async {
        installPeopleFakes(
          backend,
          expenses: [expenseJson('e1', supplierName: 'חשמל', total: '11800')],
        );
        expect(
          await fetchExpenses(),
          isNull,
          reason: 'no GET /expenses → inbox fallback',
        );

        installPeopleFakes(
          backend,
          expenses: [
            {
              ...expenseJson(
                'e1',
                status: 'APPROVED',
                supplierName: 'חשמל',
                total: '11800',
              ),
              'created_by': 'u-me',
            },
            expenseJson('e2', supplierName: 'דלק'),
          ],
          be44: true,
        );
        final all = await fetchExpenses(q: ' חשמל ');
        expect(all!.expenses.single.id, 'e1');
        expect(all.expenses.single.createdBy, 'u-me');
        expect(backend.last('GET', '/expenses')!.query, {
          'q': 'חשמל',
          'limit': '50',
        });
        await fetchExpenses(mine: true);
        expect(backend.last('GET', '/expenses')!.query['mine'], '1');

        await updateExpense(
          'e1',
          ExpenseDraft(
            supplierName: 'חשמל',
            documentDate: '2026-10-12',
            totalMinor: BigInt.from(12000),
          ),
        );
        expect(backend.last('PATCH', '/expenses/:id')!.body['total'], {
          'amountMinor': '12000',
          'currency': 'ILS',
        });
        await deleteExpense('e1');
        expect(backend.calls('DELETE', '/expenses/:id'), hasLength(1));

        final r = ExpenseRow.fromJson(
          expenseJson('x', supplierName: 'חברת החשמל', total: '11800'),
        );
        expect(expenseMatches(r, 'חשמל'), isTrue);
        expect(
          expenseMatches(r, '118'),
          isTrue,
          reason: 'amount digits (₪118)',
        );
        expect(expenseMatches(r, 'דלק'), isFalse);
        expect(expenseMatches(r, ''), isTrue);
      },
    );
  });
}
