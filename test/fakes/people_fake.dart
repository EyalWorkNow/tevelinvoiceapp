// Fakes owned by squad D (SPEC-v2 §18.1). Register this domain's endpoints on
// a [FakeBackend] with sensible defaults; tests override single routes after.
// Endpoints: GET/POST /customers, GET/PATCH /customers/:id, /customers/:id/
// consent|archive, GET/POST /suppliers, GET/POST /items, /expenses/inbox,
// /expense-categories, /expenses/:id/{draft,extract,approve,reject,duplicate,
// undo-duplicate,source}. P2 switches: [be16] GET/PATCH /suppliers/:id +
// archive, [be17] /customers/:id/statement{,.pdf,/send}, [be44] GET /expenses,
// PATCH/DELETE /expenses/:id.
//
// Stateful: POST /customers adds to the list GET /customers returns, approve
// / reject / draft change the inbox row, so a widget test can follow a flow.

import 'fake_backend.dart';

/// V1 customer row (snake_case). [be09] adds the BE-09 camelCase fields.
Map<String, dynamic> customerJson(
  String id,
  String name, {
  String? phone,
  String? email,
  String? taxId,
  bool archived = false,
  bool be09 = false,
  String balance = '0',
  String? lastDocumentAt,
  bool walkIn = false,
  bool consent = false,
}) =>
    {
      'id': id,
      'name': name,
      'tax_id': taxId,
      'email': email,
      'phone': phone,
      'archived_at': archived ? '2026-10-01T00:00:00Z' : null,
      'vat_dealer_status': 'UNKNOWN',
      'customer_type': taxId == null ? 'INDIVIDUAL' : 'BUSINESS',
      if (be09) ...{
        'balanceMinor': balance,
        'creditMinor': '0',
        'lastDocumentAt': lastDocumentAt,
        'lastLineDescription': null,
        'isWalkIn': walkIn,
        'consent': {'granted': consent},
      },
    };

/// GET /expenses/inbox row.
Map<String, dynamic> expenseJson(
  String id, {
  String status = 'NEEDS_REVIEW',
  String? supplierName,
  String? total,
  String? vat,
  String? date,
  String? categoryId,
  String? duplicateOf,
  String? extractionSource,
  String filename = 'r.jpg',
}) =>
    {
      'id': id,
      'status': status,
      'supplier_name': supplierName,
      'supplier_tax_id': null,
      'external_document_number': null,
      'expense_date': date,
      'currency': 'ILS',
      'subtotal_minor': null,
      'vat_minor': vat,
      'total_minor': total,
      'duplicate_of_expense_id': duplicateOf,
      'supplier_id': null,
      'category_id': categoryId,
      'allocation_number': null,
      'extraction_source': extractionSource,
      'original_filename': filename,
    };

/// Live state of the people fakes (tests read and change it).
class PeopleFakeState {
  final List<Map<String, dynamic>> customers = [];
  final List<Map<String, dynamic>> suppliers = [];
  final List<Map<String, dynamic>> items = [];
  final List<Map<String, dynamic>> expenses = [];
  final List<Map<String, dynamic>> categories = [];
  final List<Map<String, dynamic>> documents = [];
  int _seq = 0;

  String nextId(String prefix) => '$prefix-new-${++_seq}';

  Map<String, dynamic>? expense(String id) {
    for (final e in expenses) {
      if (e['id'] == id) return e;
    }
    return null;
  }
}

/// Registers D's endpoints. Without BE-09 by default (V1 shapes); pass
/// [be09] to also serve GET /customers/:id.
PeopleFakeState installPeopleFakes(
  FakeBackend backend, {
  List<Map<String, dynamic>> customers = const [],
  List<Map<String, dynamic>> suppliers = const [],
  List<Map<String, dynamic>> items = const [],
  List<Map<String, dynamic>> expenses = const [],
  List<Map<String, dynamic>> documents = const [],
  List<Map<String, dynamic>>? categories,
  bool be09 = false,
  bool be16 = false,
  bool be17 = false,
  bool be44 = false,
}) {
  final s = PeopleFakeState()
    ..customers.addAll(customers)
    ..suppliers.addAll(suppliers)
    ..items.addAll(items)
    ..expenses.addAll(expenses)
    ..documents.addAll(documents)
    ..categories.addAll(categories ??
        [
          {'id': 'cat-1', 'name': 'משרד', 'is_default': true},
          {'id': 'cat-2', 'name': 'רכב', 'is_default': true},
        ]);

  backend
    ..on('GET', '/customers', (_) => FakeResponse(200, {'customers': s.customers}))
    ..on('POST', '/customers', (r) {
      final id = s.nextId('c');
      s.customers.add(customerJson(id, r.body['name'] as String,
          phone: r.body['phone'] as String?,
          email: r.body['email'] as String?,
          taxId: r.body['taxId'] as String?,
          be09: be09));
      final vat = r.body['vatDealerStatus'];
      if (vat != null) s.customers.last['vat_dealer_status'] = vat;
      return FakeResponse(201, {'id': id});
    })
    ..on('PATCH', '/customers/:id', (r) {
      final c = s.customers.firstWhere((c) => c['id'] == r.params['id'], orElse: () => {});
      if (c.isEmpty) return FakeResponse.error(404, 'CUSTOMER_NOT_FOUND');
      for (final e in r.body.entries) {
        c[switch (e.key) { 'taxId' => 'tax_id', 'customerType' => 'customer_type', 'vatDealerStatus' => 'vat_dealer_status', _ => e.key }] = e.value;
      }
      return FakeResponse(200, {'id': c['id']});
    })
    ..on('POST', '/customers/:id/archive', (r) {
      for (final c in s.customers) {
        if (c['id'] == r.params['id']) c['archived_at'] = '2026-10-30T00:00:00Z';
      }
      return const FakeResponse(200, {'archived': true});
    })
    ..on('POST', '/customers/:id/consent', (_) => const FakeResponse(201, {'consentId': 'k1'}))
    ..on('GET', '/documents', (r) {
      final q = r.query;
      final rows = [
        for (final d in s.documents)
          if ((q['customerId'] == null || d['customerId'] == q['customerId']) &&
              (q['unpaid'] != '1' || BigInt.parse('${d['openMinor'] ?? d['balanceMinor'] ?? '0'}') > BigInt.zero))
            d
      ];
      return FakeResponse(200, {'total': rows.length, 'documents': rows});
    })
    ..on('GET', '/suppliers', (_) => FakeResponse(200, {'suppliers': s.suppliers}))
    ..on('POST', '/suppliers', (r) {
      final id = s.nextId('s');
      s.suppliers.add({
        'id': id,
        'name': r.body['name'],
        'tax_id': r.body['taxId'],
        'email': r.body['email'],
        'phone': r.body['phone'],
        'archived_at': null,
      });
      return FakeResponse(201, {'id': id});
    })
    ..on('GET', '/items', (_) => FakeResponse(200, {'items': s.items}))
    ..on('POST', '/items', (r) {
      final id = s.nextId('i');
      s.items.add({
        'id': id,
        'sku': null,
        'name': r.body['name'],
        'item_type': r.body['itemType'] ?? 'SERVICE',
        'unit': r.body['unit'],
        'default_unit_price_minor': r.body['defaultUnitPriceMinor'],
        'currency': 'ILS',
        'is_active': true,
      });
      return FakeResponse(201, {'id': id});
    })
    ..on('GET', '/expenses/inbox', (_) => FakeResponse(200, {'expenses': s.expenses}))
    ..on('GET', '/expense-categories', (_) => FakeResponse(200, {'categories': s.categories}))
    ..on('POST', '/expenses/:id/extract', (_) => FakeResponse.error(503, 'EXTRACTION_UNAVAILABLE'))
    ..on('PATCH', '/expenses/:id/draft', (r) {
      final e = s.expense(r.params['id']!);
      if (e == null) return FakeResponse.error(404, 'EXPENSE_NOT_FOUND');
      final b = r.body;
      String? amount(String k) => (b[k] as Map?)?['amountMinor'] as String?;
      e
        ..['supplier_name'] = b['supplierName']
        ..['supplier_id'] = b['supplierId']
        ..['expense_date'] = b['documentDate']
        ..['total_minor'] = amount('total')
        ..['vat_minor'] = amount('vat')
        ..['category_id'] = b['categoryId']
        ..['external_document_number'] = b['documentNumber']
        ..['extraction_source'] = 'MANUAL';
      final ready = b['supplierName'] != null && b['total'] != null && b['documentDate'] != null;
      e['status'] = ready ? 'READY_TO_APPROVE' : 'NEEDS_REVIEW';
      return FakeResponse(200, {'status': e['status'], 'errors': [], 'warnings': [], 'taxIdValid': null});
    })
    ..on('POST', '/expenses/:id/approve', (r) {
      final e = s.expense(r.params['id']!);
      if (e == null) return FakeResponse.error(404, 'EXPENSE_NOT_FOUND');
      if (e['status'] != 'READY_TO_APPROVE') return FakeResponse.error(422, 'EXPENSE_VALIDATION_FAILED');
      e['status'] = 'APPROVED';
      return const FakeResponse(200, {'status': 'APPROVED'});
    })
    ..on('POST', '/expenses/:id/reject', (r) {
      s.expense(r.params['id']!)?['status'] = 'REJECTED';
      return const FakeResponse(200, {'status': 'REJECTED'});
    })
    ..on('POST', '/expenses/:id/duplicate', (r) {
      s.expense(r.params['id']!)?['status'] = 'DUPLICATE';
      return const FakeResponse(200, {'status': 'DUPLICATE'});
    })
    ..on('POST', '/expenses/:id/undo-duplicate', (r) {
      s.expense(r.params['id']!)?['status'] = 'NEEDS_REVIEW';
      return const FakeResponse(200, {'status': 'NEEDS_REVIEW'});
    })
    ..on('GET', '/expenses/:id/source', (_) => const FakeResponse(200, <int>[0x25, 0x50, 0x44, 0x46]));

  if (be09) {
    backend.on('GET', '/customers/:id', (r) {
      final c = s.customers.firstWhere((c) => c['id'] == r.params['id'], orElse: () => {});
      if (c.isEmpty) return FakeResponse.error(404, 'CUSTOMER_NOT_FOUND');
      return FakeResponse(200, {
        'customer': {
          ...c,
          'address': c['address'],
          'contactPerson': c['contactPerson'],
          'paymentTerms': c['paymentTerms'] ?? 'EOM_30',
          'notes': c['notes'],
          'accountKey': c['accountKey'],
          'consent': {'granted': c['consent']?['granted'] ?? false, 'method': null, 'at': null},
        },
        'stats': {
          'openMinor': c['balanceMinor'] ?? '0',
          'overdueMinor': '0',
          'creditMinor': '0',
          'documentsCount': 0,
          'lastDocumentAt': c['lastDocumentAt'],
        },
      });
    });
  }
  if (be16) {
    Map<String, dynamic>? supplier(String? id) {
      for (final x in s.suppliers) {
        if (x['id'] == id) return x;
      }
      return null;
    }

    backend
      ..on('GET', '/suppliers/:id', (r) {
        final x = supplier(r.params['id']);
        return x == null ? FakeResponse.error(404, 'SUPPLIER_NOT_FOUND') : FakeResponse(200, {'supplier': x});
      })
      ..on('PATCH', '/suppliers/:id', (r) {
        final x = supplier(r.params['id']);
        if (x == null) return FakeResponse.error(404, 'SUPPLIER_NOT_FOUND');
        for (final e in r.body.entries) {
          x[e.key == 'taxId' ? 'tax_id' : e.key] = e.value;
        }
        return FakeResponse(200, {'id': x['id']});
      })
      ..on('POST', '/suppliers/:id/archive', (r) {
        supplier(r.params['id'])?['archived_at'] = '2026-10-30T00:00:00Z';
        return const FakeResponse(200, {'archived': true});
      });
  }
  if (be17) {
    backend
      ..on('GET', '/customers/:id/statement',
          (r) => FakeResponse(200, {'customerId': r.params['id'], 'openingMinor': '0', 'lines': []}))
      ..on('GET', '/customers/:id/statement.pdf', (_) => const FakeResponse(200, <int>[0x25, 0x50, 0x44, 0x46]))
      ..on('POST', '/customers/:id/statement/send', (_) => const FakeResponse(202, {'deliveryId': 'dl-1'}));
  }
  if (be44) {
    backend
      ..on('GET', '/expenses', (r) {
        final q = (r.query['q'] ?? '').trim();
        final rows = [
          for (final e in s.expenses)
            if (e['status'] != 'DELETED' &&
                (r.query['mine'] != '1' || e['created_by'] == 'u-me') &&
                (q.isEmpty || '${e['supplier_name'] ?? ''}'.contains(q)))
              e
        ];
        return FakeResponse(200, {'total': rows.length, 'expenses': rows});
      })
      ..on('PATCH', '/expenses/:id', (r) {
        final e = s.expense(r.params['id']!);
        if (e == null) return FakeResponse.error(404, 'EXPENSE_NOT_FOUND');
        String? amount(String k) => (r.body[k] as Map?)?['amountMinor'] as String?;
        e
          ..['supplier_name'] = r.body['supplierName']
          ..['expense_date'] = r.body['documentDate']
          ..['total_minor'] = amount('total')
          ..['category_id'] = r.body['categoryId'];
        return FakeResponse(200, {'id': e['id'], 'status': e['status']});
      })
      ..on('DELETE', '/expenses/:id', (r) {
        s.expense(r.params['id']!)?['status'] = 'DELETED';
        return const FakeResponse(200, {'deleted': true});
      });
  }
  return s;
}
