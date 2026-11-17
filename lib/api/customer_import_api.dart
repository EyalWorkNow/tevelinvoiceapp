// Customer import / export (ייבוא לקוחות). Server: apps/api/src/routes/v2/customer-import.ts.
//
//   POST /customers/import/parse    {fileName, contentBase64} → table + auto mapping
//   POST /customers/import/preview  {records}                 → validation + duplicates
//   POST /customers/import          {importId, chunkIndex, …} → one idempotent chunk
//   GET  /customers/export.xlsx
//
// Files are parsed on the server (encodings, xlsx), so the app needs no Excel dependency.
// A chunk retried with the same importId + chunkIndex is answered from the server's
// idempotency record: a dropped connection never duplicates customers.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'client.dart';

final _api = ApiClient.instance;

/// Fields the importer knows (server IMPORT_FIELDS minus the ignored customer number).
const importFields = [
  'name',
  'taxId',
  'phone',
  'mobile',
  'email',
  'address',
  'street',
  'houseNumber',
  'city',
  'postalCode',
  'contactPerson',
  'notes',
  'paymentTerms',
  'country',
];

/// Rows per commit request (server cap 200) and per preview request (cap 2000).
const importChunkSize = 100;
const importPreviewMax = 2000;

class ImportTable {
  ImportTable({
    required this.source,
    required this.sourceLabel,
    required this.headers,
    required this.rows,
    required this.mapping,
    required this.firstRowNumber,
    required this.hasHeader,
  });

  factory ImportTable.fromJson(Map<String, dynamic> j) {
    final mapping = <String, int>{};
    (j['mapping'] as Map? ?? const {}).forEach((k, v) {
      if (importFields.contains(k) && v is num) {
        mapping[k as String] = v.toInt();
      }
    });
    return ImportTable(
      source: j['source'] as String? ?? 'GENERIC',
      sourceLabel: j['sourceLabel'] as String? ?? '',
      headers: [for (final h in j['headers'] as List? ?? const []) '$h'],
      rows: [
        for (final r in j['rows'] as List? ?? const [])
          [for (final c in r as List) '$c'],
      ],
      mapping: mapping,
      firstRowNumber: (j['firstRowNumber'] as num?)?.toInt() ?? 1,
      hasHeader: ((j['headerRow'] as num?)?.toInt() ?? -1) >= 0,
    );
  }

  final String source;
  final String sourceLabel;
  final List<String> headers;
  final List<List<String>> rows;

  /// field → column index (editable in the mapping step).
  final Map<String, int> mapping;
  final int firstRowNumber;
  final bool hasHeader;

  /// First non-empty value of [column] (the "לדוגמה" hint).
  String sample(int column) {
    for (final r in rows) {
      if (column < r.length && r[column].trim().isNotEmpty) return r[column];
    }
    return '';
  }

  /// Raw records as the server expects them; `row` = the row number in the file.
  List<Map<String, Object?>> records() => [
    for (var i = 0; i < rows.length; i++)
      {
        'row': firstRowNumber + i,
        for (final e in mapping.entries)
          if (e.value < rows[i].length && rows[i][e.value].trim().isNotEmpty)
            e.key: rows[i][e.value],
      },
  ];
}

/// One phone contact as the native side returns it.
class DeviceContact {
  DeviceContact({
    required this.id,
    required this.name,
    this.organization = '',
    this.phones = const [],
    this.emails = const [],
    this.street = '',
    this.city = '',
    this.postalCode = '',
  });

  factory DeviceContact.fromMap(Map<dynamic, dynamic> m) => DeviceContact(
    id: '${m['id'] ?? ''}',
    name: '${m['name'] ?? ''}'.trim(),
    organization: '${m['organization'] ?? ''}'.trim(),
    phones: [for (final p in m['phones'] as List? ?? const []) '$p'],
    emails: [for (final e in m['emails'] as List? ?? const []) '$e'],
    street: '${m['street'] ?? ''}',
    city: '${m['city'] ?? ''}',
    postalCode: '${m['postalCode'] ?? ''}',
  );

  final String id;
  final String name;
  final String organization;
  final List<String> phones;
  final List<String> emails;
  final String street;
  final String city;
  final String postalCode;

  /// The person's name, or the company's when the card has only that.
  String get displayName => name.isNotEmpty ? name : organization;

  /// Israeli mobiles first (WhatsApp works on them).
  List<String> get sortedPhones {
    bool mobile(String p) =>
        RegExp(r'^(\+?972|0)5').hasMatch(p.replaceAll(RegExp(r'[^\d+]'), ''));
    return [...phones.where(mobile), ...phones.where((p) => !mobile(p))];
  }

  Map<String, Object?> toRecord(int row) {
    final phones = sortedPhones;
    return {
      'row': row,
      'name': displayName,
      if (phones.isNotEmpty) 'mobile': phones.first,
      if (phones.length > 1) 'phone': phones[1],
      if (emails.isNotEmpty) 'email': emails.first,
      if (street.trim().isNotEmpty) 'street': street,
      if (city.trim().isNotEmpty) 'city': city,
      if (postalCode.trim().isNotEmpty) 'postalCode': postalCode,
      if (name.isNotEmpty && organization.isNotEmpty) 'contactPerson': name,
    };
  }
}

class ImportIssue {
  const ImportIssue(this.field, this.message);
  final String field;
  final String message;
}

class ImportRowResult {
  ImportRowResult({
    required this.row,
    required this.status,
    this.customerId,
    this.duplicateId,
    this.duplicateName,
    this.duplicateBy,
    this.duplicateOfRow,
    this.errors = const [],
    this.warnings = const [],
    this.customer,
  });

  factory ImportRowResult.fromJson(Map<String, dynamic> j) {
    List<ImportIssue> issues(Object? list) => [
      for (final i in list as List? ?? const [])
        ImportIssue('${(i as Map)['field']}', '${i['message']}'),
    ];
    final dup = j['duplicate'] as Map?;
    return ImportRowResult(
      row: (j['row'] as num).toInt(),
      status: j['status'] as String,
      customerId: j['customerId'] as String?,
      duplicateId: dup?['customerId'] as String?,
      duplicateName: dup?['name'] as String?,
      duplicateBy: dup?['by'] as String?,
      duplicateOfRow: (j['duplicateOfRow'] as num?)?.toInt(),
      errors: issues(j['errors']),
      warnings: issues(j['warnings']),
      customer: (j['customer'] as Map?)?.cast<String, dynamic>(),
    );
  }

  final int row;

  /// NEW | DUPLICATE (preview) · CREATED | UPDATED | SKIPPED | ERROR.
  final String status;
  final String? customerId;
  final String? duplicateId;
  final String? duplicateName;

  /// TAX_ID | PHONE | EMAIL.
  final String? duplicateBy;
  final int? duplicateOfRow;
  final List<ImportIssue> errors;
  final List<ImportIssue> warnings;

  /// The normalised customer (preview).
  final Map<String, dynamic>? customer;

  String get name => '${customer?['name'] ?? ''}';
}

class ImportSummary {
  const ImportSummary({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
  });

  factory ImportSummary.of(Iterable<ImportRowResult> results) {
    var c = 0, u = 0, s = 0, e = 0;
    for (final r in results) {
      switch (r.status) {
        case 'CREATED':
          c++;
        case 'UPDATED':
          u++;
        case 'SKIPPED':
          s++;
        case 'ERROR':
          e++;
      }
    }
    return ImportSummary(created: c, updated: u, skipped: s, errors: e);
  }

  final int created;
  final int updated;
  final int skipped;
  final int errors;
}

Future<ImportTable> parseImportFile(String fileName, Uint8List bytes) async {
  final json = await _api.post('/customers/import/parse', {
    'fileName': fileName,
    'contentBase64': base64Encode(bytes),
  });
  return ImportTable.fromJson(json);
}

/// Dry run (validation + duplicates), in requests of ≤ [importPreviewMax] rows.
Future<List<ImportRowResult>> previewImport(
  List<Map<String, Object?>> records,
) async {
  final out = <ImportRowResult>[];
  for (var i = 0; i < records.length; i += importPreviewMax) {
    final json = await _api.post('/customers/import/preview', {
      'records': records.sublist(i, min(i + importPreviewMax, records.length)),
    });
    out.addAll([
      for (final r in json['results'] as List? ?? const [])
        ImportRowResult.fromJson(Map<String, dynamic>.from(r as Map)),
    ]);
  }
  return out;
}

/// One commit chunk. Network failures are retried with the SAME body (idempotent).
Future<List<ImportRowResult>> commitImportChunk({
  required String importId,
  required int chunkIndex,
  required String source,
  required String onDuplicate,
  required List<Map<String, Object?>> records,
  int attempts = 3,
  void Function()? onRetry,
}) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final json = await _api.post('/customers/import', {
        'importId': importId,
        'chunkIndex': chunkIndex,
        'source': source,
        'onDuplicate': onDuplicate,
        'records': records,
      });
      return [
        for (final r in json['results'] as List? ?? const [])
          ImportRowResult.fromJson(Map<String, dynamic>.from(r as Map)),
      ];
    } on ApiException catch (e) {
      if (!e.isNetwork || attempt >= attempts) rethrow;
      onRetry?.call();
      await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
    }
  }
}

Future<Uint8List> exportCustomersXlsx() =>
    _api.getBytes('/customers/export.xlsx');

/// A random v4 UUID (the import id; no extra dependency).
String newImportId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// The downloadable error list: UTF-8 with BOM (Excel shows Hebrew), one line per issue.
Uint8List errorsCsv(
  Iterable<ImportRowResult> results,
  String header,
  String Function(String field) fieldLabel,
  String Function(int row) nameOf,
) {
  String cell(String v) =>
      RegExp(r'[",\n\r]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
  final lines = <String>[header];
  for (final r in results.where((r) => r.status == 'ERROR')) {
    for (final e in r.errors) {
      lines.add(
        [
          '${r.row}',
          r.name.isEmpty ? nameOf(r.row) : r.name,
          fieldLabel(e.field),
          e.message,
        ].map(cell).join(','),
      );
    }
  }
  return Uint8List.fromList([
    0xef,
    0xbb,
    0xbf,
    ...utf8.encode('${lines.join('\r\n')}\r\n'),
  ]);
}
