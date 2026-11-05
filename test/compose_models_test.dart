// BE-03: money fields are null for someone else's document/quote without
// `money:read` → `amountHidden`, never a silent ₪0 (squad B models).

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';

void main() {
  Map<String, dynamic> doc(Object? total) => {
        'document': {
          'id': 'd1',
          'document_type': 'TAX_INVOICE',
          'status': 'DRAFT',
          'subtotal_minor': total,
          'tax_total_minor': total,
          'total_minor': total,
          'paid_total_minor': total,
          'balance_minor': total,
        },
        'lines': [
          {'position': 1, 'description': 'x', 'quantity_micros': '1000000', 'unit_price_minor': total,
            'discount_minor': total, 'subtotal_minor': total, 'tax_amount_minor': total, 'total_minor': total}
        ],
      };

  test('DocumentDetail: null totals → amountHidden; real totals → shown', () {
    expect(DocumentDetail.fromJson(doc(null)).amountHidden, isTrue);
    final shown = DocumentDetail.fromJson(doc('11800'));
    expect(shown.amountHidden, isFalse);
    expect(shown.totalMinor, BigInt.from(11800));
  });

  test('Quote: list row and BE-06 detail with null totals → amountHidden', () {
    expect(Quote.fromJson({'id': 'q1', 'status': 'SENT', 'totalMinor': null}).amountHidden, isTrue);
    expect(Quote.fromJson({'id': 'q1', 'status': 'SENT', 'totalMinor': '500'}).amountHidden, isFalse);
    expect(
        Quote.fromJson({
          'quote': {'id': 'q1', 'status': 'SENT', 'totalMinor': null, 'netMinor': null, 'taxMinor': null},
          'lines': const [],
        }).amountHidden,
        isTrue);
  });
}
