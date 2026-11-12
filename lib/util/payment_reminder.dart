// One-tap WhatsApp payment reminder (R1): who may see the button, and the
// device-local "last reminded at" per document. The server has no endpoint
// that records a WhatsApp reminder (docs/API-MOBILE.md: /reminders/send sends
// e-mail, /documents/:id/dispatch sends the document), so the hint that
// keeps the owner from spamming lives on this device only.

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

  /// When this device last opened a reminder for [documentId], or null.
  static Future<DateTime?> lastFor(String documentId) async {
    final raw = (await _all())[documentId];
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  /// Every known reminder time (the overdue list reads them at once).
  static Future<Map<String, DateTime>> all() async => {
    for (final e in (await _all()).entries)
      if (DateTime.tryParse(e.value) case final t?) e.key: t.toLocal(),
  };

  static Future<void> record(String documentId, {DateTime? at}) async {
    try {
      final all = await _all();
      all[documentId] = (at ?? DateTime.now()).toUtc().toIso8601String();
      await AppCache.write(_name, all);
    } on Object {
      // A hint only: never block the reminder over a disk error.
    }
  }
}
