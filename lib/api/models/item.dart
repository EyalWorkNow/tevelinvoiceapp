// Catalog items (squad D; S3 autocomplete). BE-15 adds edit/archive.

import 'json.dart';

/// GET /items → {items:[snake_case]}.
class Item {
  const Item({
    required this.id,
    this.sku,
    required this.name,
    required this.itemType,
    this.unit,
    this.defaultUnitPriceMinor,
    required this.currency,
    required this.isActive,
  });

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        sku: jStr(json['sku']),
        name: jStr(json['name']) ?? '',
        itemType: jStr(json['item_type']) ?? 'SERVICE',
        unit: jStr(json['unit']),
        defaultUnitPriceMinor: jBigOrNull(json['default_unit_price_minor']),
        currency: jStr(json['currency']) ?? 'ILS',
        isActive: json['is_active'] != false,
      );

  final String id;
  final String? sku;
  final String name;
  final String itemType;
  final String? unit;
  final BigInt? defaultUnitPriceMinor;
  final String currency;
  final bool isActive;
}
