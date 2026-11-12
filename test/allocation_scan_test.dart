// R7 · missing-allocation scan over the existing endpoints (no new server
// route): list filters sent, per-row allocation state, the local fallback on
// a server without SHAAM (NOT_EVALUATED), and a failed row → partial.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/allocation_scan_api.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';

import 'fakes/fake_api.dart';

Map<String, dynamic> row(
  String id, {
  String type = 'TAX_INVOICE',
  int total = 826000,
  String customerId = 'c1',
  String date = '2026-09-01',
}) => {
  'id': id,
  'documentType': type,
  'status': 'ARCHIVED',
  'documentNumber': id.hashCode.abs().toString(),
  'customerId': customerId,
  'customerName': 'לקוח $id',
  'issueDate': date,
  'currency': 'ILS',
  'totalMinor': '$total',
};

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('allocation_scan_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    await signInAs(backend, Preset.owner);
    backend.json('GET', '/customers', {
      'customers': [
        {'id': 'c1', 'name': 'א', 'vat_dealer_status': 'AUTHORIZED_DEALER'},
        {'id': 'c2', 'name': 'ב', 'vat_dealer_status': 'EXEMPT_DEALER'},
      ],
    });
    backend.on('GET', '/documents', (r) {
      final type = r.query['documentType'];
      final docs = type == 'TAX_INVOICE'
          ? [
              row('a'),
              row('b'),
              row('c'),
              row('exempt', customerId: 'c2'),
              row('local'),
              row('broken'),
            ]
          : [row('r1', type: 'TAX_INVOICE_RECEIPT')];
      return FakeResponse(200, {'total': docs.length, 'documents': docs});
    });
    backend.on('GET', '/documents/:id/allocation', (r) {
      return switch (r.params['id']) {
        'a' => const FakeResponse(200, {
          'state': 'TECHNICAL_FAILURE',
          'allocationNumber': null,
        }),
        'b' => const FakeResponse(200, {
          'state': 'APPROVED',
          'allocationNumber': '123456789',
        }),
        'c' => const FakeResponse(200, {
          'state': 'OPTIONAL',
          'allocationNumber': null,
          'evaluation': {'requirement': 'OPTIONAL'},
        }),
        'r1' => const FakeResponse(200, {
          'state': 'CONTINUED_WITHOUT_ALLOCATION',
          'allocationNumber': null,
        }),
        'local' => const FakeResponse(200, {
          'state': 'NOT_EVALUATED',
          'allocationNumber': null,
          'evaluation': null,
        }),
        _ => const FakeResponse(500, {'error': 'INTERNAL'}),
      };
    });
    backend.json(
      'GET',
      '/documents/:id',
      docDetailJson(id: 'local', total: 826000),
    );
    await AppCache.clearAll();
  });

  test(
    'lists what needs a number and has none; filters and fallbacks',
    () async {
      final r = await scanMissingAllocations(now: DateTime(2026, 11, 12));
      expect([for (final m in r.missing) m.document.id]..sort(), [
        'a',
        'local',
        'r1',
      ]);
      expect(
        r.missing.firstWhere((m) => m.document.id == 'local').local,
        isTrue,
      );
      // 'broken' answered 500 → reported as partial, never as "all good".
      expect(r.partial, isTrue);
      // The exempt-dealer customer is never asked about.
      expect(
        backend
            .calls('GET', '/documents/:id/allocation')
            .map((c) => c.params['id']),
        isNot(contains('exempt')),
      );
      final q = backend.calls('GET', '/documents').first.query;
      expect(q['issuedFrom'], '2025-11-12');
      expect(q['minTotal'], '500001'); // total ≥ amount before VAT > ₪5,000
      expect(
        {
          for (final c in backend.calls('GET', '/documents'))
            c.query['documentType'],
        },
        {'TAX_INVOICE', 'TAX_INVOICE_RECEIPT'},
      );
    },
  );
}
