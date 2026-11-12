// Fakes owned by squad B (SPEC-v2 §18.1). The Composer's endpoints with a
// small in-memory document store, in the server's real response shapes:
// POST /documents, PUT, /allocation/evaluate, /finalize, /submit, /artifact,
// /sign, /settings/signing/unlock, /share-link, /payments,
// /documents/:id/payments, /receipts, /quotes* (BE-06: GET/PUT /quotes/:id,
// clone, share-link), POST /documents/:id/clone (BE-08), dueDate/notes on
// documents (BE-07), GET /tax-rates, /customers, GET /customers/:id (BE-09
// paymentTerms), /sequences, PATCH /customers/:id. Tests override single
// routes after.

import 'fake_backend.dart';

/// Customers of the fixtures: דנה (phone), "לקוח מזדמן" (no phone),
/// "בע״מ" with a tax id and an unknown VAT-dealer status.
const List<Map<String, dynamic>> fakeCustomers = [
  {
    'id': 'c1',
    'name': 'דנה',
    'phone': '050-1234567',
    'email': 'dana@example.com',
  },
  {'id': 'c2', 'name': 'לקוח מזדמן', 'vat_dealer_status': 'PRIVATE'},
  {
    'id': 'c3',
    'name': 'רון בע״מ',
    'tax_id': '514000002',
    'vat_dealer_status': 'UNKNOWN',
    'phone': '052-7654321',
  },
];

class IssueFake {
  IssueFake(this.backend);

  final FakeBackend backend;

  /// documentId → server document (snake_case like GET /documents/:id).
  final Map<String, Map<String, dynamic>> docs = {};
  final Map<String, List<Map<String, dynamic>>> lines = {};
  final Map<String, String> quoteStatus = {};

  /// quoteId → POST/PUT /quotes body (customerId, validUntil, notes, lines).
  final Map<String, Map<String, dynamic>> quotes = {};

  /// customerId → BE-09 payment terms code (GET /customers/:id).
  final Map<String, String> paymentTerms = {};
  int _quotes = 0;

  /// Next POST /artifact answer: SIGNED | LOCKED | NOT_APPLICABLE.
  String artifactSigning = 'SIGNED';

  /// The server signing session (LOCKED artifacts sign only after unlock).
  bool signingUnlocked = false;
  String signingPassphrase = 'secret';

  /// Next POST /finalize status: FINALIZED | WAITING_FOR_ALLOCATION.
  String finalizeStatus = 'FINALIZED';

  /// Next evaluate answers, in order (then NOT_REQUIRED).
  final List<Map<String, dynamic>> evaluateAnswers = [];
  int _docs = 0;
  int _numbers = 0;

  Map<String, dynamic> detail(String id) => {
    'document': docs[id],
    'lines': lines[id] ?? const [],
  };

  /// GET /quotes/:id (BE-06 shape: totals WITH the VAT of rated lines).
  Map<String, dynamic> quoteDetail(String id) {
    final q = quotes[id]!;
    var net = BigInt.zero;
    var tax = BigInt.zero;
    final ls = <Map<String, dynamic>>[];
    for (final l in (q['lines'] as List).cast<Map<String, dynamic>>()) {
      final qty = BigInt.parse(l['quantityMicros'] as String);
      final unit = BigInt.parse(l['unitPriceMinor'] as String);
      final disc =
          BigInt.tryParse(l['discountMinor'] as String? ?? '') ?? BigInt.zero;
      final bp = l['taxRateBasisPoints'] as int?;
      final n = _round(qty * unit, BigInt.from(1000000)) - disc;
      final t = _round(n * BigInt.from(bp ?? 0), BigInt.from(10000));
      net += n;
      tax += t;
      ls.add({
        ...l,
        'discountMinor': '$disc',
        'netMinor': '$n',
        'taxMinor': '$t',
        'totalMinor': '${n + t}',
        'taxRateBasisPoints': bp,
        'itemId': l['itemId'],
      });
    }
    return {
      'quote': {
        'id': id,
        'status': quoteStatus[id] ?? 'DRAFT',
        'customerId': q['customerId'],
        'customerName': null,
        'currency': 'ILS',
        'validUntil': q['validUntil'],
        'notes': q['notes'],
        'convertedDocumentId': null,
        'netMinor': '$net',
        'taxMinor': '$tax',
        'totalMinor': '${net + tax}',
        'hasLinesWithoutRate': ls.any((l) => l['taxRateBasisPoints'] == null),
      },
      'lines': ls,
    };
  }

  void _create(
    String id,
    String type,
    String? customerId,
    List<Map<String, dynamic>> ls,
  ) {
    var sub = BigInt.zero;
    var tax = BigInt.zero;
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < ls.length; i++) {
      final l = ls[i];
      final qty = BigInt.parse(l['quantityMicros'] as String);
      final unit = BigInt.parse(l['unitPriceMinor'] as String);
      final disc =
          BigInt.tryParse(l['discountMinor'] as String? ?? '') ?? BigInt.zero;
      final bp = l['taxRateBasisPoints'] as int? ?? 0;
      final net = _round(qty * unit, BigInt.from(1000000)) - disc;
      final t = _round(net * BigInt.from(bp), BigInt.from(10000));
      sub += net;
      tax += t;
      rows.add({
        'position': i + 1,
        'description': l['description'],
        'quantity_micros': '$qty',
        'unit_price_minor': '$unit',
        'discount_minor': '$disc',
        'subtotal_minor': '$net',
        'tax_rate_basis_points': bp,
        'tax_amount_minor': '$t',
        'total_minor': '${net + t}',
      });
    }
    final total = sub + tax;
    docs[id] = {
      'id': id,
      'document_type': type,
      'status': 'DRAFT',
      'document_number': null,
      'currency': 'ILS',
      'customer_id': customerId,
      'subtotal_minor': '$sub',
      'tax_total_minor': '$tax',
      'total_minor': '$total',
      'paid_total_minor': '0',
      'balance_minor': '$total',
      'numbering_scope_key': 'default',
      'notes': null,
      'due_date': null,
    };
    lines[id] = rows;
  }

  /// An already issued document (e.g. the paid 300 of TAX_INVOICE_DUE).
  /// [lines]: POST /documents line bodies.
  String seedIssued(
    String type,
    String customerId,
    List<Map<String, dynamic>> lines,
  ) {
    final id = 'd${++_docs}';
    _create(id, type, customerId, lines);
    docs[id]!
      ..['status'] = 'ARCHIVED'
      ..['document_number'] = '${++_numbers}';
    return id;
  }

  static BigInt _round(BigInt n, BigInt d) {
    final neg = n.isNegative;
    final q = (BigInt.two * n.abs() + d) ~/ (BigInt.two * d);
    return neg ? -q : q;
  }

  void _status(String id, String status) => docs[id]!['status'] = status;

  /// BE-07: absent keeps, null / '' clears.
  void _notes(String id, Map<String, dynamic> body) {
    String? v(Object? x) => x == null || x == '' ? null : x as String;
    if (body.containsKey('notes')) docs[id]!['notes'] = v(body['notes']);
    if (body.containsKey('dueDate')) docs[id]!['due_date'] = v(body['dueDate']);
  }

  void install() {
    final b = backend;
    b
      ..json('GET', '/tax-rates', {
        'rates': [
          {'tax_code': 'VAT', 'rate_basis_points': 1800},
        ],
      })
      ..json('GET', '/customers', {'customers': fakeCustomers})
      ..json('PATCH', '/customers/:id', {'ok': true})
      ..on('GET', '/customers/:id', (r) {
        final id = r.params['id']!;
        final c = fakeCustomers.where((c) => c['id'] == id).firstOrNull;
        if (c == null) return FakeResponse.error(404, 'CUSTOMER_NOT_FOUND');
        return FakeResponse(200, {
          'customer': {...c, 'paymentTerms': paymentTerms[id]},
          'stats': {'openMinor': '0', 'overdueMinor': '0', 'documentsCount': 0},
        });
      })
      ..json('GET', '/sequences', {
        'sequences': [
          {'numbering_scope_key': 'default', 'next_number': '1'},
        ],
      })
      ..json('GET', '/documents', {'total': 0, 'documents': []})
      ..on('POST', '/documents', (r) {
        final id = 'd${++_docs}';
        final body = r.body;
        _create(
          id,
          body['documentType'] as String,
          body['customerId'] as String?,
          [
            for (final l in body['lines'] as List)
              Map<String, dynamic>.from(l as Map),
          ],
        );
        _notes(id, body);
        return FakeResponse(201, {'id': id, 'status': 'DRAFT'});
      })
      ..on('PUT', '/documents/:id', (r) {
        final id = r.params['id']!;
        final type = docs[id]!['document_type'] as String;
        final keep = {
          'converted_from_document_id': docs[id]!['converted_from_document_id'],
          'notes': docs[id]!['notes'],
          'due_date': docs[id]!['due_date'],
        };
        _create(id, type, r.body['customerId'] as String?, [
          for (final l in r.body['lines'] as List)
            Map<String, dynamic>.from(l as Map),
        ]);
        docs[id]!.addAll(keep);
        _notes(id, r.body);
        return FakeResponse(200, {'id': id});
      })
      ..on('POST', '/documents/:id/clone', (r) {
        final src = docs[r.params['id']!];
        if (src == null) return FakeResponse.error(404, 'DOCUMENT_NOT_FOUND');
        final link = r.body['link'] == true;
        if (link && src['document_number'] == null)
          return FakeResponse.error(409, 'DOCUMENT_NOT_FINAL');
        final id = 'd${++_docs}';
        final type =
            r.body['documentType'] as String? ?? src['document_type'] as String;
        _create(id, type, src['customer_id'] as String?, [
          for (final l in lines[src['id']] ?? const <Map<String, dynamic>>[])
            {
              'description': l['description'],
              'quantityMicros': l['quantity_micros'],
              'unitPriceMinor': l['unit_price_minor'],
              'discountMinor': l['discount_minor'],
              'taxRateBasisPoints': l['tax_rate_basis_points'],
            },
        ]);
        docs[id]!['converted_from_document_id'] = link ? src['id'] : null;
        return FakeResponse(201, {
          'id': id,
          'documentType': type,
          'convertedFromDocumentId': link ? src['id'] : null,
        });
      })
      ..on('GET', '/documents/:id', (r) {
        final id = r.params['id']!;
        if (!docs.containsKey(id))
          return FakeResponse.error(404, 'DOCUMENT_NOT_FOUND');
        return FakeResponse(200, detail(id));
      })
      ..on('POST', '/documents/:id/allocation/evaluate', (r) {
        final next = evaluateAnswers.isEmpty
            ? {'state': 'NOT_REQUIRED'}
            : evaluateAnswers.removeAt(0);
        return FakeResponse(200, next);
      })
      ..on('POST', '/documents/:id/finalize', (r) {
        final id = r.params['id']!;
        _numbers++;
        docs[id]!['document_number'] = '$_numbers';
        _status(id, finalizeStatus);
        return FakeResponse(200, {
          'status': finalizeStatus,
          'documentNumber': '$_numbers',
        });
      })
      ..on('POST', '/documents/:id/submit', (r) {
        _status(r.params['id']!, 'PENDING_APPROVAL');
        return const FakeResponse(200, {'status': 'PENDING_APPROVAL'});
      })
      ..on('POST', '/documents/:id/artifact', (r) {
        final id = r.params['id']!;
        final locked = artifactSigning == 'LOCKED' && !signingUnlocked;
        _status(id, locked ? 'ARTIFACT_PENDING' : 'ARCHIVED');
        return FakeResponse(201, {
          'artifactId': 'a-$id',
          'signing': locked ? 'LOCKED' : artifactSigning,
        });
      })
      ..on('POST', '/documents/:id/sign', (r) {
        if (!signingUnlocked) return FakeResponse.error(409, 'SIGNING_LOCKED');
        _status(r.params['id']!, 'ARCHIVED');
        return const FakeResponse(200, {'signing': 'SIGNED'});
      })
      ..on('POST', '/settings/signing/unlock', (r) {
        if (r.body['passphrase'] != signingPassphrase) {
          return FakeResponse.error(422, 'SIGNING_ACTIVATION_INVALID');
        }
        signingUnlocked = true;
        return const FakeResponse(200, {
          'session': {'unlocked': true},
        });
      })
      ..on(
        'POST',
        '/documents/:id/share-link',
        (r) => FakeResponse(201, {
          'url': 'https://invoice.example/d/tok-${r.params['id']}',
        }),
      )
      ..on(
        'POST',
        '/payments',
        (r) => FakeResponse(201, {'paymentId': 'p-${r.idempotencyKey}'}),
      )
      ..on('POST', '/documents/:id/payments', (r) {
        final d = docs[r.params['id']!]!;
        final amount = BigInt.parse(r.body['amountMinor'] as String);
        final paid = BigInt.parse(d['paid_total_minor'] as String) + amount;
        d['paid_total_minor'] = '$paid';
        d['balance_minor'] =
            '${BigInt.parse(d['total_minor'] as String) - paid}';
        return const FakeResponse(200, {'allocated': true});
      })
      ..on('POST', '/receipts', (r) {
        final id = 'r${++_docs}';
        _create(id, 'RECEIPT', r.body['customerId'] as String?, const []);
        _numbers++;
        docs[id]!
          ..['status'] = 'FINALIZED'
          ..['document_number'] = '$_numbers';
        return FakeResponse(201, {
          'receiptDocumentId': id,
          'outcome': {'status': 'FINALIZED', 'documentNumber': '$_numbers'},
        });
      })
      ..json('GET', '/quotes', {'quotes': []})
      ..on('POST', '/quotes', (r) {
        final id = 'q${++_quotes}';
        quoteStatus[id] = 'DRAFT';
        quotes[id] = Map<String, dynamic>.from(r.body);
        return FakeResponse(201, {'id': id});
      })
      ..on('GET', '/quotes/:id', (r) {
        final id = r.params['id']!;
        if (!quotes.containsKey(id))
          return FakeResponse.error(404, 'QUOTE_NOT_FOUND');
        return FakeResponse(200, quoteDetail(id));
      })
      ..on('PUT', '/quotes/:id', (r) {
        final id = r.params['id']!;
        if (!quotes.containsKey(id))
          return FakeResponse.error(404, 'QUOTE_NOT_FOUND');
        final status = quoteStatus[id] ?? 'DRAFT';
        if (status != 'DRAFT' && status != 'SENT') {
          return FakeResponse.error(409, 'QUOTE_INVALID_TRANSITION');
        }
        quotes[id] = Map<String, dynamic>.from(r.body);
        return FakeResponse(200, {'id': id, 'status': status});
      })
      ..on('POST', '/quotes/:id/clone', (r) {
        final src = quotes[r.params['id']!];
        if (src == null) return FakeResponse.error(404, 'QUOTE_NOT_FOUND');
        final id = 'q${++_quotes}';
        quoteStatus[id] = 'DRAFT';
        quotes[id] = Map<String, dynamic>.from(src);
        return FakeResponse(201, {'id': id});
      })
      ..on('POST', '/quotes/:id/share-link', (r) {
        final id = r.params['id']!;
        if (quoteStatus[id] == 'CONVERTED')
          return FakeResponse.error(409, 'QUOTE_INVALID_TRANSITION');
        return FakeResponse(201, {
          'url': 'https://invoice.example/d/qtok-$id',
          'expiresAt': null,
        });
      })
      ..on('POST', '/quotes/:id/status', (r) {
        quoteStatus[r.params['id']!] = r.body['to'] as String;
        return FakeResponse(200, {'status': r.body['to']});
      })
      ..on('POST', '/quotes/:id/convert', (r) {
        final id = 'd${++_docs}';
        _create(id, r.body['documentType'] as String, 'c1', [
          {
            'description': 'עיצוב לוגו',
            'quantityMicros': '1000000',
            'unitPriceMinor': '100000',
            'taxRateBasisPoints': r.body['taxRateBasisPoints'],
          },
        ]);
        quoteStatus[r.params['id']!] = 'CONVERTED';
        return FakeResponse(201, {'documentId': id});
      });
  }
}

/// Registers the Composer defaults on [backend] and returns the store.
IssueFake installIssueFakes(FakeBackend backend) =>
    IssueFake(backend)..install();
