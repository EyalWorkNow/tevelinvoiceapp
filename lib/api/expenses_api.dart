// Expenses (squad D, SPEC-v2 §3.5, §6.E).
// * Capture (kept from V1): image → JPEG ≤ 4MB → sha256 → initiate → PUT
//   bytes → complete → poll. Server: apps/api/src/expense-upload-routes.ts,
//   docs/API-MOBILE.md §6.10. HEIC is rejected, so everything is sent as JPEG.
// * Review (V2): inbox, extraction, draft, approve / reject, duplicate.
// * "Mine" (P0, before BE-44 createdBy): ids captured on this device.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../state/cache.dart';
import '../state/session.dart';
import '../util/errors_he.dart';
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

/// Upload size budget (spec S10). The server allows 20MB; 4MB keeps uploads fast.
const int maxExpenseBytes = 4 * 1024 * 1024;

/// Longest side after resizing — plenty for reading a receipt.
const int maxExpenseSide = 2400;

/// The picked file is not an image we can convert (e.g. HEIC that the picker
/// did not transcode, or a corrupt file).
class ExpenseFileUnsupported implements Exception {
  const ExpenseFileUnsupported();
}

bool _isJpeg(Uint8List b) =>
    b.length > 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

/// Server limit (packages/expense-ingestion upload-validation.ts). PDFs are
/// sent as-is, so they only have to fit this.
const int maxExpensePdfBytes = 20 * 1024 * 1024;

/// Starts with `%PDF-` (the server sniffs the same magic bytes).
bool isPdf(Uint8List b) =>
    b.length > 4 &&
    b[0] == 0x25 &&
    b[1] == 0x50 &&
    b[2] == 0x44 &&
    b[3] == 0x46 &&
    b[4] == 0x2d;

/// Bytes ready for upload: a JPEG ≤ [maxBytes]. A small JPEG passes through
/// untouched; anything else is decoded (EXIF rotation applied), resized to
/// [maxSide] and re-encoded with decreasing quality until it fits.
/// Runs in a background isolate. Throws [ExpenseFileUnsupported].
Future<Uint8List> prepareExpenseJpeg(
  Uint8List input, {
  int maxBytes = maxExpenseBytes,
  int maxSide = maxExpenseSide,
}) {
  if (_isJpeg(input) && input.length <= maxBytes) return Future.value(input);
  return Isolate.run(() => _toJpeg(input, maxBytes, maxSide));
}

Uint8List _toJpeg(Uint8List input, int maxBytes, int maxSide) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } on Object {
    decoded = null;
  }
  if (decoded == null) throw const ExpenseFileUnsupported();
  var image = img.bakeOrientation(decoded);
  var side = maxSide;
  while (true) {
    if (image.width > side || image.height > side) {
      image = image.width >= image.height
          ? img.copyResize(image, width: side)
          : img.copyResize(image, height: side);
    }
    for (final quality in const [85, 70, 55]) {
      final out = img.encodeJpg(image, quality: quality);
      if (out.length <= maxBytes) return out;
    }
    if (side <= 600) throw const ExpenseFileUnsupported();
    side = (side * 3) ~/ 4;
  }
}

/// Lower-case hex SHA-256 (the server re-checks it on complete).
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

enum ExpenseUploadStage { uploading, scanning }

class ExpenseUploadResult {
  const ExpenseUploadResult({
    this.expenseId,
    this.duplicate = false,
    this.stillScanning = false,
  });

  final String? expenseId;

  /// The same file was uploaded before (server `duplicateOfExpenseId`).
  final bool duplicate;

  /// Received, but the scan did not finish while we polled. Not an error:
  /// it shows up in the expense inbox once the scan completes.
  final bool stillScanning;
}

/// Full upload flow for a JPEG (or, with [contentType] `application/pdf`, a
/// PDF). Polling stops early when [cancelled] returns true (screen closed).
/// Throws [ApiException] (e.g. SCANNER_INFECTED, UPLOAD_REJECTED,
/// SCAN_FAILED, UPLOAD_EXPIRED, network).
Future<ExpenseUploadResult> uploadExpense(
  Uint8List bytes, {
  required String filename,
  String contentType = 'image/jpeg',
  bool Function()? cancelled,
  void Function(ExpenseUploadStage stage)? onStage,
  Duration pollEvery = const Duration(seconds: 2),
  Duration pollTimeout = const Duration(seconds: 30),
}) async {
  onStage?.call(ExpenseUploadStage.uploading);
  final init = await _api.post('/expenses/uploads/initiate', {
    'filename': filename,
    'contentType': contentType,
    'sizeBytes': bytes.length,
    'sha256': sha256Hex(bytes),
  });
  final uploadId = init['uploadId'] as String;
  final target = init['upload'] as Map<String, dynamic>;
  final headers = {
    for (final e in (target['headers'] as Map? ?? const {}).entries)
      '${e.key}': '${e.value}',
  };
  final url = target['url'] as String;
  if (target['kind'] == 'signed') {
    await _putSigned(url, bytes, headers);
  } else {
    await _api.putBytes(
      url,
      bytes,
      headers['Content-Type'] ?? contentType,
      filename: filename,
    );
  }

  onStage?.call(ExpenseUploadStage.scanning);
  var json = await _api.post('/expenses/uploads/$uploadId/complete');
  final deadline = DateTime.now().add(pollTimeout);
  while (json['status'] == 'SCAN_PENDING') {
    if (DateTime.now().isAfter(deadline) || (cancelled?.call() ?? false)) {
      return const ExpenseUploadResult(stillScanning: true);
    }
    await Future<void>.delayed(pollEvery);
    if (cancelled?.call() ?? false) {
      return const ExpenseUploadResult(stillScanning: true);
    }
    json = await _api.get('/expenses/uploads/$uploadId');
  }
  return switch (json['status']) {
    'REJECTED_MALWARE' => throw _fail('SCANNER_INFECTED', 422),
    'SCAN_FAILED' => throw _fail('SCAN_FAILED', 422),
    _ => ExpenseUploadResult(
      expenseId: json['expenseId'] as String?,
      duplicate: json['duplicateOfExpenseId'] != null,
    ),
  };
}

ApiException _fail(String code, int status) =>
    ApiException(status, code, errorMessageHe(code, status: status));

/// Signed storage URL (prod: Supabase): plain PUT, no app credentials.
Future<void> _putSigned(
  String url,
  Uint8List bytes,
  Map<String, String> headers,
) async {
  final http.Response response;
  try {
    response = await _api.httpClient
        .put(Uri.parse(url), headers: headers, body: bytes)
        .timeout(ApiClient.timeout);
  } on Exception {
    throw ApiException(0, 'NETWORK', errorMessageHe('NETWORK'));
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw _fail('UPLOAD_BYTES_MISSING', response.statusCode);
  }
}

// ---- review (§6.E) -----------------------------------------------------------

/// GET /expenses/inbox (≤200, newest first, every status).
Future<List<ExpenseRow>> fetchExpenseInbox() async {
  final json = await _api.get('/expenses/inbox');
  return [
    for (final e in (json['expenses'] as List? ?? const []))
      ExpenseRow.fromJson(Map<String, dynamic>.from(e as Map)),
  ];
}

String _categoriesKey(String? bid) => 'expense_categories_$bid';

/// GET /expense-categories (default ones first). Network failure → cache.
Future<List<ExpenseCategory>> fetchExpenseCategories() async {
  final bid = session.business?.businessId;
  List<ExpenseCategory> parse(Object? list) => [
    for (final c in (list as List? ?? const []))
      ExpenseCategory.fromJson(Map<String, dynamic>.from(c as Map)),
  ];
  try {
    final raw =
        (await _api.get('/expense-categories'))['categories'] as List? ??
        const [];
    try {
      await AppCache.write(_categoriesKey(bid), raw);
    } on Object {
      // best effort
    }
    return parse(raw);
  } on ApiException catch (e) {
    if (!e.isNetwork) rethrow;
    try {
      return parse(await AppCache.read(_categoriesKey(bid)));
    } on Object {
      return const [];
    }
  }
}

/// POST /expenses/:id/extract (OCR). False when the server has no provider
/// (503 EXTRACTION_UNAVAILABLE) or the expense is not reviewable: the card
/// then goes straight to manual entry.
Future<bool> runExpenseExtraction(String id) async {
  try {
    await _api.post('/expenses/$id/extract');
    return true;
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return false;
  }
}

/// Result of PATCH /expenses/:id/draft.
class ExpenseDraftResult {
  const ExpenseDraftResult(this.status, this.warnings);

  /// NEEDS_REVIEW | READY_TO_APPROVE.
  final String status;
  final List<String> warnings;

  bool get readyToApprove => status == 'READY_TO_APPROVE';
}

/// PATCH /expenses/:id/draft with the whole draft (the server replaces every field).
Future<ExpenseDraftResult> saveExpenseDraft(
  String id,
  ExpenseDraft draft,
) async {
  final json = await _api.patch('/expenses/$id/draft', draft.toJson());
  final validation = json['validation'];
  final warnings = <String>[
    ...jStrings(json['warnings']),
    if (validation is Map) ...jStrings(validation['warnings']),
  ];
  return ExpenseDraftResult(jStr(json['status']) ?? 'NEEDS_REVIEW', warnings);
}

/// POST /expenses/:id/approve (expense:approve).
Future<void> approveExpense(String id) => _api.post('/expenses/$id/approve');

/// POST /expenses/:id/reject {reason} (reason required).
Future<void> rejectExpense(String id, String reason) =>
    _api.post('/expenses/$id/reject', {'reason': reason.trim()});

/// POST /expenses/:id/duplicate {duplicateOfExpenseId}.
Future<void> markExpenseDuplicate(String id, String duplicateOfExpenseId) =>
    _api.post('/expenses/$id/duplicate', {
      'duplicateOfExpenseId': duplicateOfExpenseId,
    });

/// POST /expenses/:id/undo-duplicate → back to NEEDS_REVIEW ("לא, זו הוצאה אחרת").
Future<void> undoExpenseDuplicate(String id) =>
    _api.post('/expenses/$id/undo-duplicate');

/// GET /expenses/:id/source → the original image / PDF bytes.
Future<Uint8List> fetchExpenseSource(String id) =>
    _api.getBytes('/expenses/$id/source');

/// Approve a reviewed card: save the draft, then approve. Throws
/// ApiException EXPENSE_VALIDATION_FAILED when the server says it is not
/// complete (nothing is approved then).
Future<void> saveAndApproveExpense(String id, ExpenseDraft draft) async {
  final saved = await saveExpenseDraft(id, draft);
  if (!saved.readyToApprove) {
    throw ApiException(
      422,
      'EXPENSE_VALIDATION_FAILED',
      errorMessageHe('EXPENSE_VALIDATION_FAILED', status: 422),
    );
  }
  await approveExpense(id);
}

// ---- list, edit, delete (BE-44, P2) -------------------------------------------

/// One page of GET /expenses (BE-44).
class ExpensePage {
  const ExpensePage(this.expenses, {this.total});

  final List<ExpenseRow> expenses;
  final int? total;
}

/// GET /expenses?q=&mine=1&offset=&limit= (BE-44), or null when the server
/// has no such route yet (the list then falls back to the inbox).
Future<ExpensePage?> fetchExpenses({
  String q = '',
  bool mine = false,
  int offset = 0,
  int limit = 50,
}) async {
  try {
    final json = await _api.get(
      '/expenses',
      query: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        if (mine) 'mine': '1',
        if (offset > 0) 'offset': '$offset',
        'limit': '$limit',
      },
    );
    return ExpensePage([
      for (final e in (json['expenses'] as List? ?? const []))
        ExpenseRow.fromJson(Map<String, dynamic>.from(e as Map)),
    ], total: (json['total'] as num?)?.toInt());
  } on ApiException catch (e) {
    if (e.status == 404 && e.code == 'NOT_FOUND') return null;
    rethrow;
  }
}

/// PATCH /expenses/:id with the whole draft — also after APPROVED (BE-44, audited).
Future<void> updateExpense(String id, ExpenseDraft draft) =>
    _api.patch('/expenses/$id', draft.toJson());

/// DELETE /expenses/:id (BE-44, soft delete).
Future<void> deleteExpense(String id) => _api.delete('/expenses/$id');

/// Local search for the inbox fallback: supplier name, document number,
/// amount digits.
bool expenseMatches(ExpenseRow r, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if ((r.supplierName ?? '').toLowerCase().contains(q)) return true;
  if ((r.documentNumber ?? '').toLowerCase().contains(q)) return true;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 2) return false;
  final total = r.totalMinor;
  return total != null &&
      (total ~/ BigInt.from(100)).toString().contains(digits);
}

// ---- "mine" on this device (P0; BE-44 adds createdBy) ------------------------

String _mineKey(String? bid) => 'expenses_mine_$bid';

Future<Set<String>> readMyExpenseIds() async {
  try {
    final v = await AppCache.read(_mineKey(session.business?.businessId));
    return v is List ? {for (final e in v) '$e'} : <String>{};
  } on Object {
    return <String>{};
  }
}

/// Remember an expense captured on this device (newest first, ≤200).
Future<void> rememberMyExpense(String id) async {
  final bid = session.business?.businessId;
  final ids = [
    id,
    ...(await readMyExpenseIds()).where((e) => e != id),
  ].take(200).toList();
  try {
    await AppCache.write(_mineKey(bid), ids);
  } on Object {
    // best effort
  }
}

// ---- category memory (F8: default from history) -------------------------------

String _catKey(String? bid) => 'expense_last_category_$bid';

/// Last category used for [supplierName] on this device, else the last one at all.
Future<String?> lastExpenseCategory(String? supplierName) async {
  try {
    final v = await AppCache.read(_catKey(session.business?.businessId));
    if (v is! Map) return null;
    final bySupplier = v[(supplierName ?? '').trim()];
    return (bySupplier ?? v['']) as String?;
  } on Object {
    return null;
  }
}

Future<void> rememberExpenseCategory(
  String? supplierName,
  String categoryId,
) async {
  final bid = session.business?.businessId;
  try {
    final v = await AppCache.read(_catKey(bid));
    await AppCache.write(_catKey(bid), {
      if (v is Map) ...v,
      '': categoryId,
      if ((supplierName ?? '').trim().isNotEmpty)
        supplierName!.trim(): categoryId,
    });
  } on Object {
    // best effort
  }
}

// ---- pure helpers (tested) -------------------------------------------------

/// Cards for E (§6.E): reviewable + still processing, oldest first so the
/// count "3 מתוך 7" walks forward. Without expense.approve a member sees
/// only [mine] (P0: captured on this device; BE-44: createdBy == [userId]).
List<ExpenseRow> expenseReviewQueue(
  Iterable<ExpenseRow> rows, {
  required bool approver,
  Set<String> mine = const {},
  String? userId,
}) {
  bool own(ExpenseRow r) =>
      mine.contains(r.id) || (userId != null && r.createdBy == userId);
  return [
    for (final r in rows)
      if ((r.isReviewable || r.isProcessing || r.status == 'ERROR') &&
          (approver || own(r)))
        r,
  ].reversed.toList();
}

/// The list view (§6.E רשימה): everything visible to the member, newest first.
List<ExpenseRow> expenseListRows(
  Iterable<ExpenseRow> rows, {
  required bool approver,
  bool mineOnly = false,
  Set<String> mine = const {},
  String? userId,
}) {
  bool own(ExpenseRow r) =>
      mine.contains(r.id) || (userId != null && r.createdBy == userId);
  return [
    for (final r in rows)
      if ((approver && !mineOnly) || own(r)) r,
  ];
}
