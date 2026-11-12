// Business settings + account (B, S13 instances §13, B·חשבון) — squad E.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/business_context.dart';
import '../state/session.dart';
import '../util/allowed_urls.dart';
import 'actions_api.dart' show waTemplateKey, waTemplateStorage;
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

const String supportEmail = 'support@tevel.space';

/// Shown in B·חשבון "גרסה". Override at build time: --dart-define=APP_VERSION=2.0.0+1
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '2.0.0',
);

// ---- business profile (§13.1) ------------------------------------------------

/// PUT /business/profile with only the changed fields, then reloads
/// `session.profile` / `session.me` so every screen sees the new values.
Future<void> saveBusinessProfile(Map<String, dynamic> changes) async {
  if (changes.isEmpty) return;
  await _api.put('/business/profile', changes);
  await session.refreshBusiness();
  // The business list (/mobile/session) carries the legal name too.
  if (changes.containsKey('legalName')) await session.refreshAccount();
}

/// Same rule as the server (business-profile.ts `isHttpsLink`, migration 0051/0056):
/// https only, no whitespace, <= 2000 chars. Returns a Hebrew error or null.
String? paymentLinkError(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  if (v.length > 2000) return 'הקישור ארוך מדי';
  if (!RegExp(r'^https://[^\s]+$').hasMatch(v)) {
    return 'הקישור חייב להתחיל ב-https:// ובלי רווחים';
  }
  final uri = Uri.tryParse(v);
  if (uri == null || uri.host.isEmpty) return 'הקישור אינו תקין';
  return null;
}

/// Server rule `isValidIsraeliPhone` (packages/shared/src/israel.ts).
bool isValidIsraeliPhone(String raw) => RegExp(
  r'^(\+972|0)(5\d{8}|[2-4789]\d{7}|7[2-9]\d{7})$',
).hasMatch(raw.replaceAll(RegExp(r'[\s\-()]'), ''));

/// Server rule `isValidEmail`.
bool isValidEmail(String raw) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(raw.trim());

// ---- approvals (§13.6) --------------------------------------------------------

/// PUT /settings/approval. 422 APPROVAL_NO_OTHER_APPROVER when the self
/// switch is off and nobody else may approve (BE-37). Reloads /me.
Future<void> saveApprovalPolicy({
  required bool enabled,
  required BigInt thresholdMinor,
  required bool selfApprovalAllowed,
}) async {
  await _api.put('/settings/approval', {
    'mode': enabled ? 'THRESHOLD' : 'NONE',
    'thresholdMinor': (enabled ? thresholdMinor : BigInt.zero).toString(),
    'selfApprovalAllowed': selfApprovalAllowed,
  });
  await session.refreshBusiness();
}

// ---- numbering (§6.A step 3, §13.3) ------------------------------------------

/// Sets the next number of every untouched numbering scope (next_number = 1)
/// to [nextNumber]. Returns how many scopes changed.
Future<int> setStartingNumber(int nextNumber) async {
  final json = await _api.get('/sequences');
  var n = 0;
  for (final s in (json['sequences'] as List? ?? const [])) {
    final row = s as Map<String, dynamic>;
    if (row['next_number']?.toString() != '1') continue;
    await _api.put('/sequences/${row['numbering_scope_key']}/start', {
      'nextNumber': nextNumber,
    });
    n++;
  }
  return n;
}

// ---- continue on the computer (§13.9) ----------------------------------------

/// BE-35: POST /mobile/web-handoff {topic} → e-mail with the link. A server
/// without BE-35 (404) → a mailto: to the user's own address (P0, F6 (א)).
Future<void> sendWebHandoff(String topic, String topicLabel) async {
  try {
    await _api.post('/mobile/web-handoff', {'topic': topic});
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
    final to = session.account?.email ?? '';
    final subject = Uri.encodeComponent('תבל — להמשך במחשב: $topicLabel');
    final body = Uri.encodeComponent('https://invoice.crm.tevel.space/app/');
    await launchAllowed(Uri.parse('mailto:$to?subject=$subject&body=$body'));
  }
}

// ---- hide amounts (§13.12, F12) -----------------------------------------------

const _hideAmountsKey = 'hide_amounts';
const _prefs = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// "הסתר סכומים" (default off). INT wraps the app root in
/// `AmountPrivacy(hidden: hideAmounts.value)`.
final ValueNotifier<bool> hideAmounts = ValueNotifier<bool>(false);

Future<void> loadHideAmounts() async {
  try {
    hideAmounts.value = await _prefs.read(key: _hideAmountsKey) == '1';
  } on Object {
    hideAmounts.value = false;
  }
}

Future<void> setHideAmounts(bool hidden) async {
  hideAmounts.value = hidden;
  try {
    await _prefs.write(key: _hideAmountsKey, value: hidden ? '1' : '0');
  } on Object {
    // The switch still works for this run.
  }
}

// ---- account (§13.11, §13.15) -------------------------------------------------

/// Bearer "log out on all devices": revokes every session and device token,
/// this one included.
Future<void> logoutAllDevices() async {
  await _api.post('/mobile/logout-all');
}

const _appleSignInKey = 'apple_sign_in_used';

/// Remembers on this device that the account signed in with Apple, so account
/// deletion asks for an Apple authorization code (token revocation, 5.1.1(v)).
Future<void> rememberAppleSignIn() async {
  try {
    await _prefs.write(key: _appleSignInKey, value: '1');
  } on Object {
    // Best effort: deletion still offers the Apple step.
  }
}

/// True when this device signed in with Apple at least once.
Future<bool> usedAppleSignIn() async {
  try {
    return await _prefs.read(key: _appleSignInKey) == '1';
  } on Object {
    return false;
  }
}

/// POST /mobile/account/delete with exactly one fresh proof of identity
/// (password or Apple identity token) plus, for an Apple account, the one-time
/// [appleAuthorizationCode] the server revokes at appleid.apple.com.
/// Throws ApiException (CONFIRMATION_REQUIRED / REAUTH_REQUIRED / REAUTH_FAILED…).
Future<void> deleteAccount({
  String? password,
  String? appleIdentityToken,
  String? appleAuthorizationCode,
}) async {
  final usePassword = password != null && password.isNotEmpty;
  await _api.post('/mobile/account/delete', {
    'confirm': 'DELETE',
    if (usePassword)
      'password': password
    else
      'appleIdentityToken': ?appleIdentityToken,
    if (appleAuthorizationCode != null && appleAuthorizationCode.isNotEmpty)
      'appleAuthorizationCode': appleAuthorizationCode,
  });
  try {
    // A V1 install may still hold a custom WhatsApp wording; the account is gone.
    await waTemplateStorage.delete(key: waTemplateKey);
  } on Object {
    // A Keychain failure must not undo a completed deletion.
  }
}

/// Hebrew for the codes only account deletion can return.
String deleteAccountErrorHe(ApiException e) => switch (e.code) {
  'CONFIRMATION_REQUIRED' => 'יש להקליד את מילת האישור כדי למחוק את החשבון',
  'REAUTH_REQUIRED' =>
    'כדי למחוק את החשבון יש לאמת שוב את הזהות (סיסמה או Apple)',
  'REAUTH_FAILED' => 'לא הצלחנו לאמת את הזהות — בדוק את הסיסמה ונסה שוב',
  _ => e.messageHe,
};

/// Header title of the selected business.
String businessTitle(BusinessProfile? profile, Business? business) =>
    profile?.displayName ?? business?.legalName ?? '';

// ---- server features that may not be deployed yet (P1/P2) ---------------------
//
// A route the server does not have answers 404 with code NOT_FOUND (the
// router's fallback; domain 404s carry their own code). Rows/fields of such a
// feature are hidden (F5), never shown as "בקרוב". Answers are remembered per
// business for the run.

final Map<String, bool> _probes = {};

/// Test hook / business switch: forget every feature probe.
void resetFeatureProbes() => _probes.clear();

bool isMissingRoute(Object e) =>
    e is ApiException && e.status == 404 && e.code == 'NOT_FOUND';

/// Write routes that ship with the V2 server (BE-40, BE-43, BE-49).
const Set<String> v2PostRoutes = {
  '/businesses',
  '/business/type-change',
  '/business/ownership/transfer',
};

/// True when the server routes `POST [path]`.
///
/// A V2 /me (enforcement.readGating, BE-03) means the V2 server, which has
/// every route in [v2PostRoutes]: answered without a request, so a screen
/// opening never POSTs to a mutating endpoint. Only an older server (none of
/// these routes: the empty POST meets the 404 fallback) is still probed.
Future<bool> serverHasPost(String path) async {
  if (v2PostRoutes.contains(path) && (businessContext.me?.readGating ?? false))
    return true;
  final key = '${session.business?.businessId}|POST $path';
  final known = _probes[key];
  if (known != null) return known;
  try {
    await _api.post(path, const <String, dynamic>{});
    return _probes[key] = true;
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return _probes[key] = !isMissingRoute(e);
  }
}

/// GET [path] → body, or null when the server has no such route.
Future<Map<String, dynamic>?> _getOptional(String path) async {
  try {
    return await _api.get(path);
  } on ApiException catch (e) {
    if (isMissingRoute(e)) return null;
    rethrow;
  }
}

// ---- BE-13: copy of every document e-mail to the owner (§13.1) ----------------

/// GET /settings/document-email → ccOwnerEmail; null = not on this server.
Future<bool?> fetchCcOwnerEmail() async {
  final json = await _getOptional('/settings/document-email');
  return json == null ? null : json['ccOwnerEmail'] == true;
}

Future<void> saveCcOwnerEmail(bool on) async {
  await _api.put('/settings/document-email', {'ccOwnerEmail': on});
}

// ---- BE-19: automatic reminders (B row 7, §9.3) -------------------------------

/// GET /settings/reminders → enabled; null = not on this server (row hidden).
Future<bool?> fetchRemindersEnabled() async {
  final json = await _getOptional('/settings/reminders');
  return json == null ? null : json['enabled'] == true;
}

Future<void> saveRemindersEnabled(bool enabled) async {
  await _api.put('/settings/reminders', {'enabled': enabled});
}

// ---- BE-22: accountant automation (§13.1 → רואה החשבון) -----------------------

/// GET /settings/accountant-automation; null = not on this server.
Future<AccountantAutomation?> fetchAccountantAutomation() async {
  final json = await _getOptional('/settings/accountant-automation');
  return json == null ? null : AccountantAutomation.fromJson(json);
}

Future<void> saveAccountantAutomation(AccountantAutomation a) async {
  await _api.put('/settings/accountant-automation', a.toJson());
}

/// `{sendReports:{every:"MONTH|BIMONTH", dayOfMonth}|null, forwardEveryDocument}`.
class AccountantAutomation {
  const AccountantAutomation({
    this.every,
    this.dayOfMonth = 10,
    this.forwardEveryDocument = false,
  });

  factory AccountantAutomation.fromJson(Map<String, dynamic> json) {
    final s = json['sendReports'];
    return AccountantAutomation(
      every: s is Map ? s['every'] as String? : null,
      dayOfMonth: s is Map ? int.tryParse('${s['dayOfMonth']}') ?? 10 : 10,
      forwardEveryDocument: json['forwardEveryDocument'] == true,
    );
  }

  /// MONTH | BIMONTH; null = reports are not sent automatically.
  final String? every;
  final int dayOfMonth;
  final bool forwardEveryDocument;

  Map<String, dynamic> toJson() => {
    'sendReports': every == null
        ? null
        : {'every': every, 'dayOfMonth': dayOfMonth},
    'forwardEveryDocument': forwardEveryDocument,
  };
}

// ---- BE-43: business type change with an effective date (§13.1) ---------------

/// פטור → מורשה from [effectiveDate] (yyyy-mm-dd). Reloads the profile.
Future<void> requestBusinessTypeChange(
  String newType,
  String effectiveDate,
) async {
  await _api.post('/business/type-change', {
    'newType': newType,
    'effectiveDate': effectiveDate,
  });
  await session.refreshBusiness();
}
