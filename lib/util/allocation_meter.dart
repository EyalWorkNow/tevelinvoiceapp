// R7 · "מד הקצאה": when does a document need an Israel Invoices allocation
// number (מספר הקצאה, שע״ם)? Pure — unit-tested in test/allocation_meter_test.dart.
//
// The schedule MIRRORS the server (source of truth):
//   ~/inv-wt/A10 packages/shaam/src/rules.ts ISRAEL_INVOICE_RULES
//   + migration 0031_shaam_israel_invoices.sql (israel_invoice_rules).
// "עולה על 5,000 ₪ לפני מע״מ" = strictly greater (S1 FAQ Q48, rule R-STRICT-GT).
// The server decides on finalize; this only predicts it for the UI.

/// One effective-dated threshold row (dates inclusive, 'YYYY-MM-DD').
class AllocationThreshold {
  const AllocationThreshold({
    required this.ruleId,
    required this.effectiveFrom,
    required this.effectiveUntil,
    required this.thresholdMinor,
  });

  final String ruleId;
  final String effectiveFrom;

  /// Null = open-ended.
  final String? effectiveUntil;

  /// Amount BEFORE VAT in agorot; the obligation starts strictly above it.
  final int thresholdMinor;
}

/// Server rules R-THRESH-2026-01 / R-THRESH-2026-06. Before 2026-01-01 the
/// server has no verified rule (REGULATORY_RULE_UNKNOWN) — neither do we.
const List<AllocationThreshold> allocationThresholds = [
  AllocationThreshold(
    ruleId: 'R-THRESH-2026-01',
    effectiveFrom: '2026-01-01',
    effectiveUntil: '2026-05-31',
    thresholdMinor: 1000000, // ₪10,000
  ),
  AllocationThreshold(
    ruleId: 'R-THRESH-2026-06',
    effectiveFrom: '2026-06-01',
    effectiveUntil: null,
    thresholdMinor: 500000, // ₪5,000
  ),
];

/// Document types (server names) the obligation can apply to in this app
/// (305 / 320; the server also lists 310/340/345/348 which the app never issues).
const Set<String> allocationDocumentTypes = {
  'TAX_INVOICE',
  'TAX_INVOICE_RECEIPT',
};

final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// The threshold in effect on [isoDate] ('YYYY-MM-DD'), or null.
AllocationThreshold? thresholdOn(
  String isoDate, [
  List<AllocationThreshold> rules = allocationThresholds,
]) {
  if (!_isoDay.hasMatch(isoDate)) return null;
  for (final r in rules) {
    if (r.effectiveFrom.compareTo(isoDate) <= 0 &&
        (r.effectiveUntil == null ||
            isoDate.compareTo(r.effectiveUntil!) <= 0)) {
      return r;
    }
  }
  return null;
}

/// The lowest threshold that applies to any day from [fromIso] on (a safe
/// pre-filter on totals for the missing-numbers scan). Null = none.
int? lowestThresholdSince(
  String fromIso, [
  List<AllocationThreshold> rules = allocationThresholds,
]) {
  int? low;
  for (final r in rules) {
    if (r.effectiveUntil != null && r.effectiveUntil!.compareTo(fromIso) < 0) {
      continue;
    }
    if (low == null || r.thresholdMinor < low) low = r.thresholdMinor;
  }
  return low;
}

/// True when the server would make the allocation number MANDATORY:
/// 305/320 ∧ customer is עוסק מורשה ∧ VAT ≠ 0 ∧ amount before VAT is strictly
/// above the threshold in effect on [issueDate]. An עוסק פטור / private /
/// unknown customer → false (the server asks about UNKNOWN in the issue flow).
bool allocationRequired({
  required String documentType,
  required String? customerVatDealerStatus,
  required BigInt amountBeforeVatMinor,
  required BigInt vatMinor,
  required String issueDate,
}) {
  if (!allocationDocumentTypes.contains(documentType)) return false;
  if (customerVatDealerStatus != 'AUTHORIZED_DEALER') return false;
  if (vatMinor == BigInt.zero) return false;
  final rule = thresholdOn(issueDate);
  if (rule == null) return false;
  return amountBeforeVatMinor > BigInt.from(rule.thresholdMinor);
}

/// What the Composer shows under the amount.
enum AllocationHint {
  /// Below the threshold / not applicable: nothing.
  none,

  /// "המסמך יקבל מספר הקצאה מרשות המסים".
  willAllocate,

  /// "נדרש חיבור לרשות המסים" + link to the ShaamPage.
  needsConnection,
}

/// [shaamStatus] is `/me.shaam.status` (CONNECTED | EXPIRED | … | DISABLED);
/// null = the server did not say (older server) → no connection warning.
AllocationHint allocationHint({
  required bool required,
  required String? shaamStatus,
}) {
  if (!required) return AllocationHint.none;
  if (shaamStatus == null || shaamStatus == 'CONNECTED') {
    return AllocationHint.willAllocate;
  }
  return AllocationHint.needsConnection;
}

// ---- document screen: the allocation state in words ------------------------

enum AllocationTone { ok, waiting, failed, neutral }

/// Server allocation states (packages/shaam/src/state-machine.ts) grouped.
const Set<String> allocationWaitingStates = {
  'REQUIRED',
  'READY',
  'REQUESTING',
  'OUTCOME_UNKNOWN',
  'HELD',
  'HEARING_PENDING',
};
const Set<String> allocationFailedStates = {
  'NOT_APPROVED',
  'TECHNICAL_FAILURE',
  'RETRYABLE_FAILURE',
  'USER_ACTION_REQUIRED',
  'AUTHORIZATION_REQUIRED',
  'DISABLED',
  'CONTINUED_WITHOUT_ALLOCATION',
};
const Set<String> allocationNotRequiredStates = {
  'NOT_REQUIRED',
  'NOT_ELIGIBLE',
  'OPTIONAL',
};

/// A required number that is still missing (the scan lists these).
bool allocationMissing(String state, String? allocationNumber) =>
    (allocationNumber == null || allocationNumber.isEmpty) &&
    (allocationWaitingStates.contains(state) ||
        allocationFailedStates.contains(state));

/// "נסה שוב" on an ISSUED document (WAITING_FOR_ALLOCATION keeps row 4 of
/// next_action). States from which the server accepts request/reconcile.
bool allocationRetryable(String state, String? allocationNumber) =>
    (allocationNumber == null || allocationNumber.isEmpty) &&
    const {
      'REQUIRED',
      'READY',
      'REQUESTING',
      'OUTCOME_UNKNOWN',
      'HELD',
      'TECHNICAL_FAILURE',
      'RETRYABLE_FAILURE',
      'CONTINUED_WITHOUT_ALLOCATION',
    }.contains(state);

/// (Hebrew status, tone) for the document screen; null = say nothing
/// (NOT_EVALUATED and the like on a server without SHAAM).
(String, AllocationTone)? allocationStatusHe(
  String state,
  String? allocationNumber,
) {
  if (allocationNumber != null && allocationNumber.isNotEmpty) {
    return (AllocationHe.number(allocationNumber), AllocationTone.ok);
  }
  if (allocationNotRequiredStates.contains(state)) {
    return (AllocationHe.notRequired, AllocationTone.neutral);
  }
  if (state == 'AUTHORIZATION_REQUIRED' || state == 'DISABLED') {
    return (AllocationHe.needsConnection, AllocationTone.failed);
  }
  if (state == 'CONTINUED_WITHOUT_ALLOCATION') {
    return (AllocationHe.continuedWithout, AllocationTone.failed);
  }
  if (allocationFailedStates.contains(state)) {
    return (AllocationHe.failed, AllocationTone.failed);
  }
  if (allocationWaitingStates.contains(state)) {
    return (AllocationHe.waiting, AllocationTone.waiting);
  }
  if (state == 'CANCELLED') {
    return (AllocationHe.cancelled, AllocationTone.neutral);
  }
  return null;
}

/// Hebrew strings of the feature (kept here so the pure tests see them).
abstract final class AllocationHe {
  static const willAllocate = 'המסמך יקבל מספר הקצאה מרשות המסים';
  static const needsConnection = 'נדרש חיבור לרשות המסים';
  static const connect = 'לחיבור';
  static const title = 'מספר הקצאה';
  static String number(String n) => 'מספר הקצאה: \u2066$n\u2069';
  static const waiting = 'ממתין למספר הקצאה';
  static const failed = 'בקשת מספר ההקצאה נכשלה';
  static const notRequired = 'לא נדרש מספר הקצאה';
  static const continuedWithout = 'הופק בלי מספר הקצאה';
  static const cancelled = 'בקשת המספר בוטלה';
  static const retry = 'נסה שוב';

  // Missing-numbers scan (Reports).
  static const scanTitle = 'מספרי הקצאה חסרים';
  static const scanHint =
      'חשבוניות מ-12 החודשים האחרונים שחייבות מספר ואין להן';
  static const scanIntro =
      'חשבוניות מס ללקוח עוסק מורשה מעל הסף, בלי מספר הקצאה. '
      'אפשר לבקש מספר בדיעבד מתוך המסמך.';
  static const scanEmpty = 'אין חשבוניות שחסר להן מספר הקצאה';
  static String scanCount(int n) =>
      n == 1 ? 'חשבונית אחת חסרה מספר' : '$n חשבוניות חסרות מספר';
  static const scanPartial = 'חלק מהמסמכים לא נבדקו (יותר מדי תוצאות)';
  static const scanLocal = 'לפי חישוב באפליקציה';
}
