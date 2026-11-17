// "המסמכים של העסק" (server 0119, apps/api/src/routes/v2/business-vault.ts).
//
//   GET    /business/vault                    {items, canManage, categories, maxBytes}
//   POST   /business/vault?category=&title=&issuedOn=&expiresOn=&remindDaysBefore=
//          raw file (pdf | jpeg | png | webp, ≤ 15 MB, X-Filename) → 201 {item}
//   PATCH  /business/vault/:id                {category?, title?, issuedOn?, expiresOn?, remindDaysBefore?}
//   DELETE /business/vault/:id                soft delete (audited)
//   GET    /business/vault/:id/file           bytes
//   POST   /business/vault/share {ids, channel}  audit of a share from the phone

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models/json.dart';
import 'reports_api.dart' show ExportFile;

final ApiClient _api = ApiClient.instance;

const int vaultMaxBytes = 15 * 1024 * 1024;

/// The server's categories, in its order (labels mirror VAULT_CATEGORY_LABELS).
const List<(String, String)> vaultCategories = [
  ('DEALER_CERTIFICATE', 'תעודת עוסק מורשה / פטור'),
  ('BOOKKEEPING_APPROVAL', 'אישור ניהול ספרים'),
  ('WITHHOLDING_APPROVAL', 'אישור ניכוי במקור'),
  ('INCORPORATION', 'תעודת התאגדות'),
  ('BANK_CONFIRMATION', "אישור בנק / צ'ק מבוטל"),
  ('INSURANCE', 'ביטוח'),
  ('BUSINESS_LICENSE', 'רישיון עסק'),
  ('CONTRACT', 'חוזה'),
  ('OTHER', 'אחר'),
];

String vaultCategoryLabel(String key) =>
    vaultCategories.firstWhere((c) => c.$1 == key, orElse: () => (key, key)).$2;

/// Bumped after every change, so the list reloads.
final ValueNotifier<int> vaultVersion = ValueNotifier(0);

enum VaultExpiry { valid, expiring, expired, none }

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.category,
    required this.title,
    required this.mimeType,
    required this.byteSize,
    required this.filename,
    this.issuedOn,
    this.expiresOn,
    this.remindDaysBefore = 30,
    this.expiry = VaultExpiry.none,
    this.daysToExpiry,
  });

  factory VaultDocument.fromJson(Map<String, dynamic> j) => VaultDocument(
    id: jStr(j['id']) ?? '',
    category: jStr(j['category']) ?? 'OTHER',
    title: jStr(j['title']) ?? '',
    issuedOn: jStr(j['issuedOn']),
    expiresOn: jStr(j['expiresOn']),
    remindDaysBefore: jIntOrNull(j['remindDaysBefore']) ?? 30,
    expiry: switch (jStr(j['expiryStatus'])) {
      'VALID' => VaultExpiry.valid,
      'EXPIRING' => VaultExpiry.expiring,
      'EXPIRED' => VaultExpiry.expired,
      _ => VaultExpiry.none,
    },
    daysToExpiry: jIntOrNull(j['daysToExpiry']),
    mimeType: jStr(j['mimeType']) ?? 'application/pdf',
    byteSize: jIntOrNull(j['byteSize']) ?? 0,
    filename: jStr(j['filename']) ?? 'document',
  );

  final String id;
  final String category;
  final String title;
  final String? issuedOn;
  final String? expiresOn;
  final int remindDaysBefore;
  final VaultExpiry expiry;
  final int? daysToExpiry;
  final String mimeType;
  final int byteSize;
  final String filename;

  bool get isPdf => mimeType == 'application/pdf';
  String get categoryLabel => vaultCategoryLabel(category);
}

class VaultList {
  const VaultList(this.items, {required this.canManage});
  final List<VaultDocument> items;
  final bool canManage;
}

/// What the user fills in before upload / on edit.
class VaultMeta {
  const VaultMeta({
    required this.category,
    required this.title,
    this.issuedOn,
    this.expiresOn,
    this.remindDaysBefore = 30,
  });

  final String category;
  final String title;
  final String? issuedOn;
  final String? expiresOn;
  final int remindDaysBefore;

  Map<String, String> get query => {
    'category': category,
    if (title.trim().isNotEmpty) 'title': title.trim(),
    'issuedOn': ?issuedOn,
    'expiresOn': ?expiresOn,
    'remindDaysBefore': '$remindDaysBefore',
  };

  Map<String, Object?> get patch => {
    'category': category,
    'title': title.trim(),
    'issuedOn': issuedOn,
    'expiresOn': expiresOn,
    'remindDaysBefore': remindDaysBefore,
  };
}

Future<VaultList> fetchVault() async {
  final json = await _api.get('/business/vault');
  return VaultList([
    for (final i in (json['items'] as List? ?? const []))
      VaultDocument.fromJson(jMap(i)),
  ], canManage: jBool(json['canManage']));
}

Future<VaultDocument> uploadVaultDocument(
  VaultMeta meta, {
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) async {
  final json = await _api.postRaw(
    '/business/vault',
    bytes,
    mimeType,
    query: meta.query,
    filename: filename,
  );
  vaultVersion.value++;
  return VaultDocument.fromJson(jMap(json['item']));
}

Future<VaultDocument> updateVaultDocument(String id, VaultMeta meta) async {
  final json = await _api.patch('/business/vault/$id', meta.patch);
  vaultVersion.value++;
  return VaultDocument.fromJson(jMap(json['item']));
}

Future<void> deleteVaultDocument(String id) async {
  await _api.delete('/business/vault/$id');
  vaultVersion.value++;
}

Future<ExportFile> downloadVaultDocument(VaultDocument d) async => ExportFile(
  await _api.getBytes('/business/vault/${d.id}/file'),
  vaultShareName(d),
  d.mimeType,
);

/// The file name the customer sees: the title + the right extension.
String vaultShareName(VaultDocument d) {
  final ext = switch (d.mimeType) {
    'application/pdf' => 'pdf',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
  final base = d.title.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), ' ').trim();
  return '${base.isEmpty ? 'document' : base}.$ext';
}

/// Audit of a share that happened on the phone (never blocks the share).
Future<void> recordVaultShare(List<String> ids, String channel) async {
  try {
    await _api.post('/business/vault/share', {'ids': ids, 'channel': channel});
  } on Object {
    // The share itself already happened; the audit line is best-effort.
  }
}
