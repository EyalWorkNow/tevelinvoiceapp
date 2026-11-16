// Stage C1 · "מי חייב לי" (server migration 0101).
//
//   GET    /debts                    who owes me, per customer, oldest first
//   POST   /debt-entries             "X owes me ₪Y for Z" — an internal note, NOT a document
//   PATCH  /debt-entries/:id         edit an open entry
//   DELETE /debt-entries/:id         soft delete
//   POST   /debt-entries/:id/close   {receiptDocumentId} the receipt issued for it
//   POST   /reminders/log            one reminder sent from this phone (any device sees it)
//   GET    /reminders/last?ids=      last reminder per document / entry

import 'client.dart';
import 'models/json.dart';

final _api = ApiClient.instance;

class DebtEntry {
  const DebtEntry({
    required this.id,
    required this.customerId,
    required this.amountMinor,
    required this.note,
    required this.debtDate,
    this.status = 'OPEN',
    this.receiptDocumentId,
    this.lastRemindedAt,
  });

  factory DebtEntry.fromJson(Map<String, dynamic> j) => DebtEntry(
    id: j['id'] as String,
    customerId: j['customerId'] as String,
    amountMinor: jBig(j['amountMinor']),
    note: jStr(j['note']) ?? '',
    debtDate: jStr(j['debtDate']) ?? '',
    status: jStr(j['status']) ?? 'OPEN',
    receiptDocumentId: jStr(j['receiptDocumentId']),
    lastRemindedAt: _time(j['lastRemindedAt']),
  );

  final String id;
  final String customerId;
  final BigInt amountMinor;
  final String note;

  /// YYYY-MM-DD.
  final String debtDate;
  final String status;
  final String? receiptDocumentId;
  final DateTime? lastRemindedAt;
}

class DebtDocument {
  const DebtDocument({
    required this.id,
    required this.documentType,
    this.documentNumber,
    required this.dueDate,
    required this.openMinor,
    required this.overdueDays,
    this.lastRemindedAt,
  });

  factory DebtDocument.fromJson(Map<String, dynamic> j) => DebtDocument(
    id: j['id'] as String,
    documentType: jStr(j['documentType']) ?? '',
    documentNumber: jStr(j['documentNumber']),
    dueDate: jStr(j['dueDate']) ?? '',
    openMinor: jBig(j['openMinor']),
    overdueDays: jIntOrNull(j['overdueDays']) ?? 0,
    lastRemindedAt: _time(j['lastRemindedAt']),
  );

  final String id;
  final String documentType;
  final String? documentNumber;
  final String dueDate;
  final BigInt openMinor;

  /// > 0 = days past the due date.
  final int overdueDays;
  final DateTime? lastRemindedAt;
}

class Debtor {
  const Debtor({
    this.customerId,
    required this.customerName,
    this.phone,
    required this.totalMinor,
    required this.documentsOpenMinor,
    required this.debtBookMinor,
    this.oldestOverdueDays,
    this.oldestEntryDays,
    this.lastRemindedAt,
    this.reminderCount = 0,
    this.documents = const [],
    this.debtEntries = const [],
  });

  factory Debtor.fromJson(Map<String, dynamic> j) => Debtor(
    customerId: jStr(j['customerId']),
    customerName: jStr(j['customerName']) ?? '',
    phone: jStr(j['phone']),
    totalMinor: jBig(j['totalMinor']),
    documentsOpenMinor: jBig(j['documentsOpenMinor']),
    debtBookMinor: jBig(j['debtBookMinor']),
    oldestOverdueDays: jIntOrNull(j['oldestOverdueDays']),
    oldestEntryDays: jIntOrNull(j['oldestEntryDays']),
    lastRemindedAt: _time(j['lastRemindedAt']),
    reminderCount: jIntOrNull(j['reminderCount']) ?? 0,
    documents: [
      for (final d in (j['documents'] as List? ?? const []))
        DebtDocument.fromJson(Map<String, dynamic>.from(d as Map)),
    ],
    debtEntries: [
      for (final e in (j['debtEntries'] as List? ?? const []))
        DebtEntry.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
  );

  /// null = open documents without a customer.
  final String? customerId;
  final String customerName;
  final String? phone;
  final BigInt totalMinor;
  final BigInt documentsOpenMinor;
  final BigInt debtBookMinor;
  final int? oldestOverdueDays;
  final int? oldestEntryDays;
  final DateTime? lastRemindedAt;

  /// Reminders already sent for what is open now (drives the tone).
  final int reminderCount;
  final List<DebtDocument> documents;
  final List<DebtEntry> debtEntries;
}

class WhoOwesMe {
  const WhoOwesMe({
    required this.documentsOpenMinor,
    required this.documentsOverdueMinor,
    required this.debtBookOpenMinor,
    required this.totalMinor,
    required this.customers,
  });

  factory WhoOwesMe.fromJson(Map<String, dynamic> j) => WhoOwesMe(
    documentsOpenMinor: jBig(j['documentsOpenMinor']),
    documentsOverdueMinor: jBig(j['documentsOverdueMinor']),
    debtBookOpenMinor: jBig(j['debtBookOpenMinor']),
    totalMinor: jBig(j['totalMinor']),
    customers: [
      for (final c in (j['customers'] as List? ?? const []))
        Debtor.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
  );

  /// Σ open documents — the same server figure as Home's "מגיע לך".
  final BigInt documentsOpenMinor;
  final BigInt documentsOverdueMinor;

  /// Σ open debt-book entries (internal notes, not documents).
  final BigInt debtBookOpenMinor;
  final BigInt totalMinor;
  final List<Debtor> customers;
}

DateTime? _time(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

Future<WhoOwesMe> fetchWhoOwesMe() async =>
    WhoOwesMe.fromJson(await _api.get('/debts'));

Future<DebtEntry> createDebtEntry({
  required String customerId,
  required BigInt amountMinor,
  required String note,
  String? debtDate,
  String? idempotencyKey,
}) async {
  final json = await _api.post('/debt-entries', {
    'customerId': customerId,
    'amountMinor': amountMinor.toString(),
    'note': note,
    'debtDate': ?debtDate,
  }, idempotencyKey);
  return DebtEntry.fromJson(
    Map<String, dynamic>.from(json['debtEntry'] as Map),
  );
}

Future<DebtEntry> updateDebtEntry(
  String id, {
  BigInt? amountMinor,
  String? note,
  String? debtDate,
}) async {
  final json = await _api.patch('/debt-entries/$id', {
    'amountMinor': ?amountMinor?.toString(),
    'note': ?note,
    'debtDate': ?debtDate,
  });
  return DebtEntry.fromJson(
    Map<String, dynamic>.from(json['debtEntry'] as Map),
  );
}

Future<void> deleteDebtEntry(String id) async {
  await _api.delete('/debt-entries/$id');
}

Future<DebtEntry> closeDebtEntry(String id, String receiptDocumentId) async {
  final json = await _api.post('/debt-entries/$id/close', {
    'receiptDocumentId': receiptDocumentId,
  });
  return DebtEntry.fromJson(
    Map<String, dynamic>.from(json['debtEntry'] as Map),
  );
}

/// One reminder that left this phone. [channel]: WHATSAPP | SHARE.
Future<void> logReminder({
  List<String> documentIds = const [],
  List<String> debtEntryIds = const [],
  String channel = 'WHATSAPP',
}) async {
  await _api.post('/reminders/log', {
    'documentIds': documentIds,
    'debtEntryIds': debtEntryIds,
    'channel': channel,
  });
}

/// Last reminder per id, from the server (every device and team member).
Future<Map<String, DateTime>> fetchLastReminded(List<String> ids) async {
  if (ids.isEmpty) return const {};
  final json = await _api.get('/reminders/last', query: {'ids': ids.join(',')});
  final last = json['last'];
  if (last is! Map) return const {};
  return {for (final e in last.entries) e.key.toString(): ?_time(e.value)};
}
