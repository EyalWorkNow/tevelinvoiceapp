// Customers and suppliers (squad D). V1 rows are snake_case; BE-09 adds
// camelCase balanceMinor/creditMinor/lastDocumentAt/lastLineDescription/
// isWalkIn/consent. Every BE-09 field is optional, so the app runs against a
// server without it.

import 'json.dart';

/// GET /customers → {customers:[…]} (V1 snake_case + BE-09 camelCase).
class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.taxId,
    this.email,
    this.phone,
    this.archivedAt,
    this.vatDealerStatus,
    this.customerType,
    this.balanceMinor,
    this.creditMinor,
    this.lastDocumentAt,
    this.lastLineDescription,
    this.isWalkIn = false,
    this.consentGranted,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    final consent = json['consent'];
    return Customer(
      id: json['id'] as String,
      name: jStr(json['name']) ?? '',
      taxId: jStr(jPick(json, ['tax_id', 'taxId'])),
      email: jStr(json['email']),
      phone: jStr(json['phone']),
      archivedAt: jStr(jPick(json, ['archived_at', 'archivedAt'])),
      vatDealerStatus: jStr(jPick(json, ['vat_dealer_status', 'vatDealerStatus'])),
      customerType: jStr(jPick(json, ['customer_type', 'customerType'])),
      balanceMinor: jBigOrNull(jPick(json, ['balanceMinor', 'balance_minor'])),
      creditMinor: jBigOrNull(jPick(json, ['creditMinor', 'credit_minor'])),
      lastDocumentAt: jStr(jPick(json, ['lastDocumentAt', 'last_document_at'])),
      lastLineDescription: jStr(jPick(json, ['lastLineDescription', 'last_line_description'])),
      isWalkIn: jBool(jPick(json, ['isWalkIn', 'is_walk_in'])),
      consentGranted: consent is Map ? consent['granted'] == true : null,
    );
  }

  final String id;
  final String name;
  final String? taxId;
  final String? email;
  final String? phone;
  final String? archivedAt;
  final String? vatDealerStatus;

  /// INDIVIDUAL | BUSINESS
  final String? customerType;

  /// BE-09: open receivables (300/305). Null = unknown (server without BE-09).
  final BigInt? balanceMinor;
  final BigInt? creditMinor;

  /// BE-09: newest document of this customer (ISO-8601), for "recent first".
  final String? lastDocumentAt;
  final String? lastLineDescription;

  /// BE-09 `is_walk_in` (the one "לקוח מזדמן" record of the business).
  final bool isWalkIn;

  /// BE-09 consent.granted; null = unknown.
  final bool? consentGranted;

  bool get isArchived => archivedAt != null;

  Customer copyWith(
          {String? name, String? phone, String? email, String? taxId, String? customerType, String? vatDealerStatus}) =>
      Customer(
        id: id,
        name: name ?? this.name,
        taxId: taxId ?? this.taxId,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        archivedAt: archivedAt,
        vatDealerStatus: vatDealerStatus ?? this.vatDealerStatus,
        customerType: customerType ?? this.customerType,
        balanceMinor: balanceMinor,
        creditMinor: creditMinor,
        lastDocumentAt: lastDocumentAt,
        lastLineDescription: lastLineDescription,
        isWalkIn: isWalkIn,
        consentGranted: consentGranted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tax_id': taxId,
        'email': email,
        'phone': phone,
        'archived_at': archivedAt,
        'vat_dealer_status': vatDealerStatus,
        'customer_type': customerType,
        if (balanceMinor != null) 'balanceMinor': balanceMinor.toString(),
        if (creditMinor != null) 'creditMinor': creditMinor.toString(),
        if (lastDocumentAt != null) 'lastDocumentAt': lastDocumentAt,
        if (lastLineDescription != null) 'lastLineDescription': lastLineDescription,
        if (isWalkIn) 'isWalkIn': true,
        if (consentGranted != null) 'consent': {'granted': consentGranted},
      };
}

/// GET /customers/:id (BE-09) → {customer:{…}, stats:{…}}. Without BE-09 the
/// app builds one from the list row ([stats] fields stay null).
class CustomerDetail {
  const CustomerDetail({
    required this.customer,
    this.address,
    this.contactPerson,
    this.paymentTerms,
    this.notes,
    this.accountKey,
    this.consentMethod,
    this.consentAt,
    this.openMinor,
    this.overdueMinor,
    this.documentsCount,
    this.fromBe09 = false,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    final c = jMap(json['customer']);
    final s = jMap(json['stats']);
    final consent = jMap(c['consent']);
    final a = c['address'];
    return CustomerDetail(
      customer: Customer.fromJson(c),
      address: a is Map ? CustomerAddress.fromJson(Map<String, dynamic>.from(a)) : null,
      contactPerson: jStr(c['contactPerson']),
      paymentTerms: jStr(c['paymentTerms']),
      notes: jStr(c['notes']),
      accountKey: jStr(c['accountKey']),
      consentMethod: jStr(consent['method']),
      consentAt: jStr(consent['at']),
      openMinor: jBigOrNull(s['openMinor']),
      overdueMinor: jBigOrNull(s['overdueMinor']),
      documentsCount: jIntOrNull(s['documentsCount']),
      fromBe09: true,
    );
  }

  final Customer customer;
  final CustomerAddress? address;
  final String? contactPerson;

  /// IMMEDIATE | EOM | EOM_30 | EOM_45 | EOM_60 | EOM_90
  final String? paymentTerms;
  final String? notes;
  final String? accountKey;
  final String? consentMethod;
  final String? consentAt;
  final BigInt? openMinor;
  final BigInt? overdueMinor;
  final int? documentsCount;

  /// True when the server has BE-09 (so P1 fields can be edited).
  final bool fromBe09;
}

/// BE-09 customer address {street, number, city, postalCode} (same shape as
/// the business address). The server requires a city when any part is set.
class CustomerAddress {
  const CustomerAddress({this.street = '', this.number = '', this.city = '', this.postalCode});

  factory CustomerAddress.fromJson(Map<String, dynamic> j) => CustomerAddress(
        street: jStr(j['street']) ?? '',
        number: jStr(j['number']) ?? '',
        city: jStr(j['city']) ?? '',
        postalCode: jStr(j['postalCode']),
      );

  final String street;
  final String number;
  final String city;
  final String? postalCode;

  bool get isEmpty => street.trim().isEmpty && number.trim().isEmpty && city.trim().isEmpty;

  /// "הרצל 5, תל אביב".
  String get display => [
        [street.trim(), number.trim()].where((v) => v.isNotEmpty).join(' '),
        city.trim(),
      ].where((v) => v.isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'street': street.trim(),
        'number': number.trim(),
        'city': city.trim(),
        'postalCode': (postalCode ?? '').trim().isEmpty ? null : postalCode!.trim(),
      };

  @override
  bool operator ==(Object other) =>
      other is CustomerAddress &&
      other.street.trim() == street.trim() &&
      other.number.trim() == number.trim() &&
      other.city.trim() == city.trim() &&
      (other.postalCode ?? '').trim() == (postalCode ?? '').trim();

  @override
  int get hashCode => Object.hash(street.trim(), number.trim(), city.trim(), (postalCode ?? '').trim());
}

/// GET /suppliers → {suppliers:[snake_case]}.
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.taxId,
    this.email,
    this.phone,
    this.archivedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: json['id'] as String,
        name: jStr(json['name']) ?? '',
        taxId: jStr(jPick(json, ['tax_id', 'taxId'])),
        email: jStr(json['email']),
        phone: jStr(json['phone']),
        archivedAt: jStr(jPick(json, ['archived_at', 'archivedAt'])),
      );

  final String id;
  final String name;
  final String? taxId;
  final String? email;
  final String? phone;
  final String? archivedAt;

  bool get isArchived => archivedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tax_id': taxId,
        'email': email,
        'phone': phone,
        'archived_at': archivedAt,
      };
}
