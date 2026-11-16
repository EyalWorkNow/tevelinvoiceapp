// One-tap WhatsApp payment reminder (R1): who may see the button, and the
// "last reminded at" per document / debt entry.
//
// C1 (server 0101): a reminder is recorded on the server (POST /reminders/log),
// so every device and team member sees "נשלחה תזכורת לפני X ימים", and the
// tone escalates by the server's count. This device keeps its own copy as the
// fallback (offline, an older server without the route).

import '../api/debts_api.dart';
import '../screens/document/next_action.dart';
import '../state/business_context.dart';
import '../state/cache.dart';
import '../state/caps.dart';

/// Unpaid issued invoice (300/305, open > 0, not voided / credited, the
/// amounts visible to this viewer) + `doc.send`. Drafts, quotes, receipts,
/// paid or cancelled documents never get the button.
bool mayRemindOnWhatsApp({
  required String documentType,
  required String status,
  required BigInt totalMinor,
  BigInt? openMinor,
  BigInt? creditedMinor,
  String? voidedAt,
  bool amountHidden = false,
  required Caps caps,
}) {
  if (amountHidden || !caps.can(Cap.docSend)) return false;
  return isOpenReceivable(
    DocFacts(
      status: status,
      documentType: documentType,
      totalMinor: totalMinor,
      openMinor: openMinor,
      creditedMinor: creditedMinor,
      voidedAt: voidedAt,
    ),
  );
}

/// Whole calendar days from [at] to [now] (local time, DST-safe).
int daysSince(DateTime at, DateTime now) {
  final a = DateTime(at.year, at.month, at.day);
  final b = DateTime(now.year, now.month, now.day);
  return (b.difference(a).inHours / 24).round();
}

/// "Last reminded at" per document, per business, per signed-in user
/// (AppCache user data: survives cache eviction, wiped on sign-out).
abstract final class ReminderLog {
  static const prefix = 'wa_reminded_';

  static String get _name =>
      '$prefix${businessContext.business?.businessId ?? 'none'}';

  static Future<Map<String, String>> _all() async {
    final json = await AppCache.read(_name);
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }

  /// When a reminder for [documentId] was last sent: the later of the
  /// server's record (any device / member) and this device's copy.
  static Future<DateTime?> lastFor(String documentId) async {
    final raw = (await _all())[documentId];
    final local = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    DateTime? server;
    try {
      server = (await fetchLastReminded([documentId]))[documentId];
    } on Object {
      // Offline / no such route: this device's copy only.
    }
    if (server == null) return local;
    if (local == null) return server;
    return server.isAfter(local) ? server : local;
  }

  /// Every reminder time this device knows (the offline fallback).
  static Future<Map<String, DateTime>> all() async => {
    for (final e in (await _all()).entries)
      if (DateTime.tryParse(e.value) case final t?) e.key: t.toLocal(),
  };

  /// "Last reminded at" for [ids] at once (the "באיחור" list): the server's
  /// record (C1: any device / member, 100 ids per read) merged with this
  /// device's copy, the later wins. Offline or an older server: device only.
  static Future<Map<String, DateTime>> forIds(List<String> ids) async {
    final merged = <String, DateTime>{
      for (final e in (await all()).entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    try {
      for (var i = 0; i < ids.length; i += 100) {
        final chunk = ids.sublist(
          i,
          i + 100 > ids.length ? ids.length : i + 100,
        );
        for (final e in (await fetchLastReminded(chunk)).entries) {
          final local = merged[e.key];
          if (local == null || e.value.isAfter(local)) merged[e.key] = e.value;
        }
      }
    } on Object {
      // Offline / no such route: this device's copy only.
    }
    return merged;
  }

  /// Records a reminder for a document ([documentId]) or, with [debtEntry],
  /// a debt-book entry: on this device and on the server ([channel] WHATSAPP
  /// when the chat opened, SHARE for the share sheet). Never throws.
  static Future<void> record(
    String documentId, {
    DateTime? at,
    String channel = 'WHATSAPP',
    bool debtEntry = false,
  }) => recordMany(
    documentIds: debtEntry ? const [] : [documentId],
    debtEntryIds: debtEntry ? [documentId] : const [],
    at: at,
    channel: channel,
  );

  /// One reminder that covered several documents / entries (one tap).
  static Future<void> recordMany({
    List<String> documentIds = const [],
    List<String> debtEntryIds = const [],
    DateTime? at,
    String channel = 'WHATSAPP',
  }) async {
    try {
      final all = await _all();
      final when = (at ?? DateTime.now()).toUtc().toIso8601String();
      for (final id in [...documentIds, ...debtEntryIds]) {
        all[id] = when;
      }
      await AppCache.write(_name, all);
    } on Object {
      // A hint only: never block the reminder over a disk error.
    }
    try {
      await logReminder(
        documentIds: documentIds,
        debtEntryIds: debtEntryIds,
        channel: channel,
      );
    } on Object {
      // Offline / older server: the local copy stays the hint.
    }
  }
}
