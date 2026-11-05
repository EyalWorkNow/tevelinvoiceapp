import 'fake_backend.dart';

/// Fixtures only for widget/native visual tests; the application always reads the real API.
void installCommerceFakes(FakeBackend backend) {
  backend.json('GET', '/billing/plans', {
    'plans': [
      {
        'code': 'START',
        'name': 'מתחילים',
        'monthlyMinor': 800,
        'invoiceLimit': 21,
      },
      {
        'code': 'GROW',
        'name': 'צומחים',
        'monthlyMinor': 1000,
        'invoiceLimit': 30,
      },
      {
        'code': 'UNLIMITED',
        'name': 'בלי גבולות',
        'monthlyMinor': 1500,
        'invoiceLimit': null,
      },
    ],
    'checkoutAvailable': false,
    'pricesIncludeVat': true,
    'renewal': 'MANUAL',
  });
  backend.json('GET', '/billing/subscription', {
    'active': false,
    'needsPlan': false,
    'usedInvoices': 9,
    'subscription': null,
  });
  backend.error('POST', '/billing/checkout', 503, 'PAYMENT_NOT_CONFIGURED');
  final expenses = <Map<String, dynamic>>[
    {
      'id': 'e1',
      'supplierName': 'כלי העבודה של העסק',
      'totalMinor': '11800',
      'vatMinor': '1800',
      'expenseDate': '2026-11-03',
      'categoryName': 'תוכנה ושירותים',
      'categoryId': 'software',
      'classification': 'BUSINESS',
      'expensePercent': 100,
      'vatPercent': 100,
      'status': 'APPROVED',
    },
    {
      'id': 'e2',
      'supplierName': 'הדרך לפגישה הבאה',
      'totalMinor': '5900',
      'vatMinor': '900',
      'expenseDate': '2026-11-02',
      'categoryName': 'נסיעות ורכב',
      'categoryId': 'travel',
      'classification': 'MIXED',
      'expensePercent': 50,
      'vatPercent': 50,
      'status': 'APPROVED',
    },
    {
      'id': 'e3',
      'supplierName': 'דברים קטנים למשרד',
      'totalMinor': '2360',
      'vatMinor': '360',
      'expenseDate': '2026-11-01',
      'categoryName': 'ציוד משרדי',
      'categoryId': 'office',
      'classification': 'REVIEW',
      'expensePercent': null,
      'vatPercent': null,
      'status': 'NEEDS_REVIEW',
    },
  ];
  backend.on(
    'GET',
    '/expenses/overview',
    (request) => FakeResponse(200, {
      'month': request.query['month'] ?? '2026-11',
      'currency': 'ILS',
      'totalMinor': '20060',
      'recognizedMinor': '12725',
      'recoverableVatMinor': '2250',
      'unclassifiedMinor': '2360',
      'count': 3,
      'categories': [
        {'name': 'תוכנה ושירותים', 'totalMinor': '11800', 'count': 1},
        {'name': 'נסיעות ורכב', 'totalMinor': '5900', 'count': 1},
        {'name': 'ציוד משרדי', 'totalMinor': '2360', 'count': 1},
      ],
      'trend': [
        for (final pair in [
          ('2026-06', '12000'),
          ('2026-07', '16500'),
          ('2026-08', '14300'),
          ('2026-09', '26000'),
          ('2026-10', '18000'),
          ('2026-11', '20060'),
        ])
          {'month': pair.$1, 'totalMinor': pair.$2},
      ],
      'expenses': expenses,
      'recognitionNote':
          'אומדן לפי הסיווג שהוזן להוצאות מאושרות. הכרה במס הכנסה וקיזוז מע״מ נקבעים בנפרד, לפי נסיבות ההוצאה ובדיקת רואה החשבון.',
    }),
  );
  backend.json('GET', '/expense-categories', {
    'categories': [
      {'id': 'software', 'name': 'תוכנה ושירותים'},
      {'id': 'travel', 'name': 'נסיעות ורכב'},
      {'id': 'office', 'name': 'ציוד משרדי'},
    ],
  });
  backend.on('PATCH', '/expenses/:id/recognition', (request) {
    final row = expenses.firstWhere((r) => r['id'] == request.params['id']);
    row.addAll(request.body);
    return FakeResponse(200, request.body);
  });
}
