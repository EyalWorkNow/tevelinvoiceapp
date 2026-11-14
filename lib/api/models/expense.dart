// Expenses (squad D, SPEC-v2 §6.E). GET /expenses/inbox rows (snake_case),
// categories, and the draft the review card PATCHes. BE-44 adds createdBy.

import 'json.dart';

/// Statuses a reviewer acts on (one card each).
const Set<String> expenseReviewStatuses = {
  'NEEDS_REVIEW',
  'READY_TO_APPROVE',
  'DUPLICATE',
};

/// Still being received / scanned / read: the card shows "קורא את הקבלה…".
const Set<String> expenseProcessingStatuses = {
  'UPLOADED',
  'SCANNING',
  'NORMALIZING',
  'EXTRACTING',
};

/// GET /expenses/inbox → {expenses:[…]} (max 200, newest first).
class ExpenseRow {
  const ExpenseRow({
    required this.id,
    required this.status,
    this.supplierName,
    this.supplierTaxId,
    this.documentNumber,
    this.expenseDate,
    this.currency = 'ILS',
    this.subtotalMinor,
    this.vatMinor,
    this.totalMinor,
    this.duplicateOfExpenseId,
    this.supplierId,
    this.categoryId,
    this.allocationNumber,
    this.extractionSource,
    this.originalFilename,
    this.createdBy,
  });

  factory ExpenseRow.fromJson(Map<String, dynamic> j) => ExpenseRow(
    id: j['id'] as String,
    status: jStr(j['status']) ?? 'NEEDS_REVIEW',
    supplierName: jStr(jPick(j, ['supplier_name', 'supplierName'])),
    supplierTaxId: jStr(jPick(j, ['supplier_tax_id', 'supplierTaxId'])),
    documentNumber: jStr(
      jPick(j, ['external_document_number', 'documentNumber']),
    ),
    expenseDate: jStr(jPick(j, ['expense_date', 'expenseDate'])),
    currency: jStr(j['currency']) ?? 'ILS',
    subtotalMinor: jBigOrNull(jPick(j, ['subtotal_minor', 'subtotalMinor'])),
    vatMinor: jBigOrNull(jPick(j, ['vat_minor', 'vatMinor'])),
    totalMinor: jBigOrNull(jPick(j, ['total_minor', 'totalMinor'])),
    duplicateOfExpenseId: jStr(
      jPick(j, ['duplicate_of_expense_id', 'duplicateOfExpenseId']),
    ),
    supplierId: jStr(jPick(j, ['supplier_id', 'supplierId'])),
    categoryId: jStr(jPick(j, ['category_id', 'categoryId'])),
    allocationNumber: jStr(jPick(j, ['allocation_number', 'allocationNumber'])),
    extractionSource: jStr(jPick(j, ['extraction_source', 'extractionSource'])),
    originalFilename: jStr(jPick(j, ['original_filename', 'originalFilename'])),
    createdBy: jStr(jPick(j, ['created_by', 'createdBy'])),
  );

  final String id;

  /// UPLOADED … ERROR (packages/expense-ingestion state-machine.ts).
  final String status;
  final String? supplierName;
  final String? supplierTaxId;
  final String? documentNumber;

  /// 'YYYY-MM-DD'.
  final String? expenseDate;
  final String currency;
  final BigInt? subtotalMinor;
  final BigInt? vatMinor;
  final BigInt? totalMinor;
  final String? duplicateOfExpenseId;
  final String? supplierId;
  final String? categoryId;
  final String? allocationNumber;

  /// null = nothing read yet; 'MANUAL' after a draft save; else the OCR provider.
  final String? extractionSource;
  final String? originalFilename;

  /// BE-44.
  final String? createdBy;

  bool get isReviewable => expenseReviewStatuses.contains(status);
  bool get isProcessing => expenseProcessingStatuses.contains(status);
  bool get isDuplicate => status == 'DUPLICATE';
  bool get isPdf => (originalFilename ?? '').toLowerCase().endsWith('.pdf');
}

/// GET /expense-categories → {categories:[{id, name, is_default}]}.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  factory ExpenseCategory.fromJson(Map<String, dynamic> j) => ExpenseCategory(
    id: j['id'] as String,
    name: jStr(j['name']) ?? '',
    isDefault: jBool(jPick(j, ['is_default', 'isDefault'])),
  );

  final String id;
  final String name;
  final bool isDefault;
}

/// What the review card sends. PATCH /expenses/:id/draft REPLACES every field
/// (omitted = cleared), so the whole draft is always sent.
class ExpenseDraft {
  const ExpenseDraft({
    this.supplierId,
    this.supplierName,
    this.supplierTaxId,
    this.documentNumber,
    this.documentDate,
    this.totalMinor,
    this.vatMinor,
    this.categoryId,
    this.allocationNumber,
    this.currency = 'ILS',
  });

  factory ExpenseDraft.fromRow(ExpenseRow r) => ExpenseDraft(
    supplierId: r.supplierId,
    supplierName: r.supplierName,
    supplierTaxId: r.supplierTaxId,
    documentNumber: r.documentNumber,
    documentDate: r.expenseDate,
    totalMinor: r.totalMinor,
    vatMinor: r.vatMinor,
    categoryId: r.categoryId,
    allocationNumber: r.allocationNumber,
    currency: r.currency,
  );

  final String? supplierId;
  final String? supplierName;
  final String? supplierTaxId;
  final String? documentNumber;
  final String? documentDate;
  final BigInt? totalMinor;
  final BigInt? vatMinor;
  final String? categoryId;
  final String? allocationNumber;
  final String currency;

  ExpenseDraft copyWith({
    String? supplierId,
    String? supplierName,
    String? supplierTaxId,
    String? documentNumber,
    String? documentDate,
    BigInt? totalMinor,
    BigInt? vatMinor,
    String? categoryId,
    bool clearVat = false,
  }) => ExpenseDraft(
    supplierId: supplierId ?? this.supplierId,
    supplierName: supplierName ?? this.supplierName,
    supplierTaxId: supplierTaxId ?? this.supplierTaxId,
    documentNumber: documentNumber ?? this.documentNumber,
    documentDate: documentDate ?? this.documentDate,
    totalMinor: totalMinor ?? this.totalMinor,
    vatMinor: clearVat ? null : (vatMinor ?? this.vatMinor),
    categoryId: categoryId ?? this.categoryId,
    allocationNumber: allocationNumber,
    currency: currency,
  );

  static bool _blank(String? s) => s == null || s.trim().isEmpty;

  /// Keys of required fields still missing: 'supplier', 'amount', 'date'
  /// (the server's readyToApprove) + 'category' when [needCategory].
  List<String> missing({bool needCategory = false}) => [
    if (_blank(supplierName)) 'supplier',
    if (totalMinor == null || totalMinor! <= BigInt.zero) 'amount',
    if (_blank(documentDate)) 'date',
    if (needCategory && _blank(categoryId)) 'category',
  ];

  /// Body of PATCH /expenses/:id/draft. subtotal = total − VAT only when VAT
  /// is known (the server checks subtotal + vat == total).
  Map<String, dynamic> toJson() {
    Map<String, String> money(BigInt v) => {
      'amountMinor': v.toString(),
      'currency': currency,
    };
    final vat = vatMinor;
    final total = totalMinor;
    return {
      'supplierId': ?supplierId,
      if (!_blank(supplierName)) 'supplierName': supplierName!.trim(),
      if (!_blank(supplierTaxId)) 'supplierTaxId': supplierTaxId!.trim(),
      if (!_blank(documentNumber)) 'documentNumber': documentNumber!.trim(),
      'documentDate': ?documentDate,
      if (!_blank(allocationNumber)) 'allocationNumber': allocationNumber,
      if (total != null) 'total': money(total),
      if (total != null && vat != null) ...{
        'vat': money(vat),
        'subtotal': money(total - vat),
      },
      'categoryId': ?categoryId,
    };
  }
}
