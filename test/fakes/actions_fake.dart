// Fakes owned by squad C (SPEC-v2 §18.1): D, S5, S6, S8 endpoints with the
// §6/§14 response shapes. Tests override single routes after install.
//
//   installActionsFakes(backend);                       // a 305 of ₪1,180, open
//   backend.json('GET', '/documents/:id', docDetailJson(status: 'PENDING_APPROVAL'));

import 'fake_backend.dart';

/// GET /documents/:id body (snake_case `document` + `lines`, BE-36/37 fields).
/// Default: TAX_INVOICE 1042 of ₪1,180 (1,000 + 18%), open, customer cus-1.
Map<String, dynamic> docDetailJson({
  String id = 'doc-1',
  String type = 'TAX_INVOICE',
  String status = 'ARCHIVED',
  String? number = '1042',
  int total = 118000,
  int paid = 0,
  int credited = 0,
  int? balance,
  String? customerId = 'cus-1',
  String? submittedBy,
  String? voidedAt,
  String? allocationNumber,
  Map<String, dynamic>? rejection,
  List<Map<String, dynamic>>? lines,
  // V2 (SRV-2 P1) — omitted unless given, i.e. an older server by default.
  List<Map<String, dynamic>>? timeline,
  List<Map<String, dynamic>>? payments,
  List<Map<String, dynamic>>? linked,
  String? notes,
  String? dueDate,
}) {
  final open = balance ?? (total - paid - credited < 0 ? 0 : total - paid - credited);
  return {
    'document': {
      'id': id,
      'document_type': type,
      'status': status,
      'document_number': number,
      'currency': 'ILS',
      'issue_date': '2026-10-30',
      'subtotal_minor': '${(total / 1.18).round()}',
      'tax_total_minor': '${total - (total / 1.18).round()}',
      'total_minor': '$total',
      'paid_total_minor': '$paid',
      'balance_minor': '$open',
      'credited_minor': '$credited',
      'open_minor': '$open',
      'customer_id': customerId,
      'numbering_scope_key': 'default',
      'allocation_number': allocationNumber,
      'submitted_by': submittedBy,
      'voided_at': voidedAt,
      'rejection': rejection,
      'due_date': ?dueDate,
      'notes': ?notes,
      'timeline': ?timeline,
      'payments': ?payments,
      'linkedDocuments': ?linked,
    },
    'lines': lines ??
        [
          {
            'position': 1,
            'item_id': null,
            'description': 'תיקון דוד',
            'quantity_micros': '1000000',
            'unit_price_minor': '${(total / 1.18).round()}',
            'discount_minor': '0',
            'subtotal_minor': '${(total / 1.18).round()}',
            'tax_rate_basis_points': 1800,
            'tax_amount_minor': '${total - (total / 1.18).round()}',
            'total_minor': '$total',
          }
        ],
  };
}

/// A GET /documents row (BE-10a camelCase).
Map<String, dynamic> docListRowJson({
  String id = 'doc-1',
  String type = 'TAX_INVOICE',
  String status = 'ARCHIVED',
  String number = '1042',
  int total = 118000,
  int open = 118000,
  String? sentAt,
}) =>
    {
      'id': id,
      'documentType': type,
      'status': status,
      'documentNumber': number,
      'customerId': 'cus-1',
      'customerName': 'דנה כהן',
      'issueDate': '2026-10-30',
      'currency': 'ILS',
      'totalMinor': '$total',
      'balanceMinor': '$open',
      'openMinor': '$open',
      'creditedMinor': '0',
      'sentAt': sentAt,
    };

/// GET /customers with the document's customer (phone + email).
Map<String, dynamic> customerListJson({String? phone = '0501234567', String? email = 'dana@example.test'}) => {
      'customers': [
        {
          'id': 'cus-1',
          'name': 'דנה כהן',
          'tax_id': null,
          'email': email,
          'phone': phone,
          'archived_at': null,
          'vat_dealer_status': 'UNKNOWN',
        }
      ]
    };

/// GET /quotes row.
Map<String, dynamic> quoteRowJson({String id = 'q-1', String status = 'SENT', String? convertedDocumentId}) => {
      'id': id,
      'status': status,
      'customerId': 'cus-1',
      'customerName': 'דנה כהן',
      'currency': 'ILS',
      'validUntil': '2026-11-13',
      'totalMinor': '118000',
      'convertedDocumentId': convertedDocumentId,
      'createdAt': '2026-10-30',
    };

/// BE-12 timeline entry.
Map<String, dynamic> timelineJson(String event, {String at = '2026-10-30T08:00:00.000Z', Map<String, dynamic>? detail}) =>
    {'at': at, 'event': event, 'by': 'u-owner', 'byEmail': 'owner@example.test', 'detail': detail ?? {}};

/// BE-06 GET /quotes/:id ({quote, lines}; totals include VAT).
Map<String, dynamic> quoteDetailJson({String id = 'q-1', String status = 'SENT', String? convertedDocumentId}) => {
      'quote': {
        'id': id,
        'status': status,
        'customerId': 'cus-1',
        'customerName': 'דנה כהן',
        'currency': 'ILS',
        'validUntil': '2026-11-13',
        'notes': null,
        'convertedDocumentId': convertedDocumentId,
        'createdBy': 'u-owner',
        'createdAt': '2026-10-30T08:00:00.000Z',
        'updatedAt': '2026-10-30T08:00:00.000Z',
        'netMinor': '100000',
        'taxMinor': '18000',
        'totalMinor': '118000',
        'hasLinesWithoutRate': false,
        'sentAt': null,
      },
      'lines': [
        {
          'position': 1,
          'description': 'התקנת מזגן',
          'quantity': '1',
          'quantityMicros': '1000000',
          'unitPriceMinor': '100000',
          'discountMinor': '0',
          'netMinor': '100000',
          'taxRateBasisPoints': 1800,
          'taxMinor': '18000',
          'totalMinor': '118000',
          'itemId': null,
        }
      ],
    };

/// Registers the BE-06 quote detail (GET /quotes/:id) — the P1 server.
void installQuoteDetail(FakeBackend b, {String status = 'SENT', String? convertedDocumentId}) =>
    b.json('GET', '/quotes/:id', quoteDetailJson(status: status, convertedDocumentId: convertedDocumentId));

/// A BE-11 GET /payments row.
Map<String, dynamic> ledgerRowJson({
  String id = 'pay-1',
  String method = 'CASH',
  int amount = 50000,
  String? receiptId,
  String? receiptNumber,
  String? voidedAt,
}) =>
    {
      'id': id,
      'method': method,
      'amountMinor': '$amount',
      'currency': 'ILS',
      'paymentDate': '2026-10-29',
      'reference': null,
      'customerId': 'cus-1',
      'customerName': 'דנה כהן',
      'allocations': <Object>[],
      'receiptDocumentId': receiptId,
      'receiptDocumentNumber': receiptNumber,
      'recordedBy': 'u-owner',
      'recordedAt': '2026-10-29T08:00:00.000Z',
      'voidedAt': voidedAt,
      'voidReason': null,
    };

/// Minimal valid PDF bytes.
const List<int> samplePdfBytes = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a];

void installActionsFakes(FakeBackend b) {
  b
    // D reads
    ..json('GET', '/documents/:id', docDetailJson())
    ..json('GET', '/documents', {'total': 1, 'limit': 5, 'documents': [docListRowJson()]})
    ..on('GET', '/documents/:id/pdf', (_) => const FakeResponse(200, samplePdfBytes))
    ..json('GET', '/customers', customerListJson())
    ..json('GET', '/quotes', {'quotes': [quoteRowJson()]})
    ..json('GET', '/documents/:id/allocation',
        {'state': 'RETRYABLE_FAILURE', 'labelHe': 'כשל זמני', 'allocationNumber': null})
    // original / signing (§6.C step 4)
    ..json('POST', '/documents/:id/artifact', {'artifactId': 'a1', 'signing': 'NOT_APPLICABLE'}, status: 201)
    ..json('POST', '/documents/:id/sign', {'signing': 'SIGNED'})
    ..json('POST', '/settings/signing/unlock', {'session': {'unlocked': true}})
    // share (S6)
    ..json('POST', '/documents/:id/share-link',
        {'url': 'https://invoice.test/d/tok123', 'expiresAt': '2026-11-29T00:00:00Z'}, status: 201)
    ..json('POST', '/documents/:id/share-link/revoke', {'revoked': 1})
    ..json('POST', '/documents/:id/send', {'deliveryId': 'del-1'}, status: 202)
    ..json('POST', '/deliveries/:id/process', {'status': 'SENT', 'attemptCount': 1})
    ..json('POST', '/customers/:id/consent', {'granted': true})
    // payments (S5)
    ..on('POST', '/payments', (r) => FakeResponse(201, {'paymentId': 'pay-${r.idempotencyKey?.substring(0, 6)}', 'reused': false}))
    ..json('POST', '/documents/:id/payments', {'allocated': true})
    ..json('POST', '/receipts',
        {'receiptDocumentId': 'rcp-1', 'outcome': {'status': 'FINALIZED', 'documentNumber': '77'}}, status: 201)
    // approvals (§4.8)
    ..json('POST', '/documents/:id/approve', {'status': 'FINALIZED', 'documentNumber': '1043'})
    ..json('POST', '/documents/:id/reject', {'status': 'DRAFT'})
    // credit / void (S8)
    ..json('POST', '/documents/:id/credit',
        {'creditDocumentId': 'cr-1', 'outcome': {'status': 'FINALIZED', 'documentNumber': '5'}}, status: 201)
    ..json('POST', '/documents/:id/void', {'id': 'doc-1', 'voidedAt': '2026-10-30T09:00:00.000Z'})
    // allocation (row 4)
    ..json('POST', '/documents/:id/allocation/request', {'state': 'REQUESTING'})
    ..json('POST', '/documents/:id/allocation/reconcile', {'state': 'APPROVED'})
    ..json('POST', '/documents/:id/allocation/manual', {'state': 'MANUAL_ALLOCATION_ATTACHED'})
    ..json('POST', '/documents/:id/allocation/decision', {'state': 'CONTINUED_WITHOUT_ALLOCATION'})
    ..json('POST', '/documents/:id/allocation/cancel', {'id': 'doc-1', 'status': 'READY_TO_FINALIZE'})
    // quotes on D
    ..on('POST', '/quotes/:id/status', (r) => FakeResponse(200, {'status': r.body['to']}))
    ..json('POST', '/quotes/:id/convert', {'documentId': 'doc-new'}, status: 201)
    // duplicate (BE-08)
    ..json('POST', '/documents/:id/clone', {'id': 'doc-dup', 'documentType': 'TAX_INVOICE', 'convertedFromDocumentId': null},
        status: 201)
    // BE-06 quote extras (GET /quotes/:id itself: installQuoteDetail)
    ..on('GET', '/quotes/:id/pdf', (_) => const FakeResponse(200, samplePdfBytes))
    ..json('POST', '/quotes/:id/share-link', {'url': 'https://invoice.test/d/qtok', 'expiresAt': '2026-11-29T00:00:00Z'},
        status: 201)
    ..json('POST', '/quotes/:id/clone', {'id': 'q-2'}, status: 201)
    // BE-11 payments ledger
    ..json('GET', '/payments', {
      'total': 2,
      'limit': 50,
      'offset': 0,
      'payments': [ledgerRowJson(), ledgerRowJson(id: 'pay-2', receiptId: 'rcp-9', receiptNumber: '9')],
    })
    ..json('POST', '/payments/:id/void', {'id': 'pay-1', 'voidedAt': '2026-10-30T09:00:00.000Z', 'reused': false});
}
