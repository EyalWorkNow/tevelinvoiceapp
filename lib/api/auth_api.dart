// Auth & onboarding API calls (auth squad). Cookie phase only: sign-in, MFA,
// password reset. The device-token exchange itself lives in
// session.completeSignIn(); onboarding writes go through the bearer token.

import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

/// Answer of /auth/login, /auth/apple, /auth/google.
class SignInResult {
  const SignInResult({required this.mfaRequired, required this.businesses});

  factory SignInResult.fromJson(Map<String, dynamic> json) => SignInResult(
    mfaRequired: json['mfaRequired'] == true || json['status'] == 'MFA_REQUIRED',
    businesses: [
      for (final b in (json['businesses'] as List? ?? const [])) Business.fromJson(b as Map<String, dynamic>),
    ],
  );

  final bool mfaRequired;

  /// Empty when MFA is still required (read /mobile/session afterwards).
  final List<Business> businesses;
}

/// Every sign-in starts clean: a half-finished earlier attempt may have left a
/// device token in memory, which would make the client send Bearer instead of
/// the new cookie.
void _freshCookiePhase() => _api.clearCredentials();

Future<SignInResult> signInWithPassword(String email, String password) async {
  _freshCookiePhase();
  final json = await _api.post('/auth/login', {'email': email.trim(), 'password': password});
  return SignInResult.fromJson(json);
}

/// CONTRACT A. [fullName] only exists on the very first Apple authorisation.
Future<SignInResult> signInWithApple(String identityToken, {String? fullName}) async {
  _freshCookiePhase();
  final json = await _api.post('/auth/apple', {
    'identityToken': identityToken,
    if (fullName != null && fullName.trim().isNotEmpty) 'fullName': fullName.trim(),
  });
  return SignInResult.fromJson(json);
}

/// POST /auth/google. NOTE: the server verifies a *Firebase* ID token
/// (iss `securetoken.google.com/<project>`); see the auth squad report.
Future<SignInResult> signInWithGoogle(String idToken) async {
  _freshCookiePhase();
  final json = await _api.post('/auth/google', {'idToken': idToken});
  return SignInResult.fromJson(json);
}

/// Always "ok" (no account enumeration). The reset link opens the web app.
Future<void> requestPasswordReset(String email) async {
  await _api.post('/auth/password/forgot', {'email': email.trim()});
}

/// GET /auth/mfa/methods (readable while half-authenticated).
class MfaMethods {
  const MfaMethods({
    required this.totp,
    required this.email,
    required this.emailAvailable,
    required this.recoveryCodesRemaining,
  });

  factory MfaMethods.fromJson(Map<String, dynamic> json) => MfaMethods(
    totp: json['totp'] == true,
    email: (json['email'] as Map<String, dynamic>?)?['enabled'] == true,
    emailAvailable: json['emailAvailable'] != false,
    recoveryCodesRemaining: (json['recoveryCodesRemaining'] as num?)?.toInt() ?? 0,
  );

  final bool totp;
  final bool email;
  final bool emailAvailable;
  final int recoveryCodesRemaining;

  /// E-mail codes are the default when they work; TOTP otherwise.
  bool get useEmail => email && emailAvailable;
}

Future<MfaMethods> fetchMfaMethods() async => MfaMethods.fromJson(await _api.get('/auth/mfa/methods'));

/// LOGIN (verify an enrolled e-mail method) or ENROLL (first-time setup).
enum MfaPurpose { login, enroll }

String _purpose(MfaPurpose p) => p == MfaPurpose.enroll ? 'ENROLL' : 'LOGIN';

class EmailCodeSent {
  const EmailCodeSent({required this.sentTo, required this.resendAfterSeconds});

  factory EmailCodeSent.fromJson(Map<String, dynamic> json) => EmailCodeSent(
    sentTo: json['sentTo']?.toString() ?? '',
    resendAfterSeconds: (json['resendAfterSeconds'] as num?)?.toInt() ?? 30,
  );

  /// Masked address, e.g. "mo***@tevel.test".
  final String sentTo;
  final int resendAfterSeconds;
}

Future<EmailCodeSent> sendEmailCode(MfaPurpose purpose) async =>
    EmailCodeSent.fromJson(await _api.post('/auth/mfa/email/send', {'purpose': _purpose(purpose)}));

/// Verifies an e-mail code. Returns recovery codes when the server issued
/// them (show once), else null. Cookie + csrf rotate inside ApiClient.
Future<List<String>?> verifyEmailCode(String code, MfaPurpose purpose) async {
  final json = await _api.post('/auth/mfa/email/verify', {
    'code': code,
    if (purpose == MfaPurpose.enroll) 'purpose': 'ENROLL',
  });
  final codes = json['recoveryCodes'];
  return codes is List && codes.isNotEmpty ? [for (final c in codes) c.toString()] : null;
}

/// TOTP (6 digits) or a recovery code.
Future<void> verifyMfaCode(String code) async {
  await _api.post('/auth/mfa', {'code': code.trim()});
}

// ---- invitations (§6.A, public preview + accept on the cookie phase) -------

/// GET /auth/invite/:token. 410 INVITATION_EXPIRED / INVITATION_REVOKED /
/// INVITATION_INVALID when it can no longer be used.
Future<InvitationPreview> fetchInvitation(String token) async {
  _freshCookiePhase();
  return InvitationPreview.fromJson(await _api.get('/auth/invite/$token'));
}

/// POST /auth/invite/:token/accept {password, displayName?} → a cookie session
/// (not MFA-satisfied yet). The caller continues with finishSignIn.
/// Errors: INVALID_CREDENTIALS (existing account, wrong password),
/// PASSWORD_POLICY (new account), MEMBER_EXISTS, INVITATION_*.
Future<void> acceptInvitation(String token, {required String password, String? displayName}) async {
  _freshCookiePhase();
  await _api.post('/auth/invite/$token/accept', {
    'password': password,
    if (displayName != null && displayName.trim().isNotEmpty) 'displayName': displayName.trim(),
  });
}

// ---- onboarding (S2, bearer + X-Business-Id) ------------------------------

/// PUT /business/profile with only the setup fields (§6.A step 2).
/// Identity fields are frozen once documents exist; never resent then.
Future<BusinessProfile> saveOnboardingProfile({
  required String legalName,
  required String businessType,
  required String taxId,
  String? defaultLineDescription,
  bool includeIdentity = true,
}) async {
  final description = (defaultLineDescription ?? '').trim();
  final json = await _api.put('/business/profile', {
    'legalName': legalName.trim(),
    if (includeIdentity) 'businessType': businessType,
    if (includeIdentity) 'taxId': taxId.replaceAll(RegExp(r'\D'), ''),
    if (description.isNotEmpty) 'defaultLineDescription': description,
  });
  return BusinessProfile.fromJson(json['profile'] as Map<String, dynamic>);
}

Future<void> completeOnboarding() async {
  await _api.put('/business/onboarding', {'completed': true});
}

// ---- local validation (same rules as packages/shared/src/israel.ts) -------

/// Israeli 9-digit id checksum (ת.ז. / ע.מ. / ח.פ.).
bool isValidIsraeliId(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty || digits.length > 9) return false;
  final id = digits.padLeft(9, '0');
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    final n = int.parse(id[i]) * (i.isEven ? 1 : 2);
    sum += n > 9 ? n - 9 : n;
  }
  return sum % 10 == 0;
}

/// 05x mobile, 0x landline or +972.
bool isValidIsraeliPhone(String raw) => RegExp(
  r'^(\+972|0)(5\d{8}|[2-4789]\d{7}|7[2-9]\d{7})$',
).hasMatch(raw.replaceAll(RegExp(r'[\s\-()]'), ''));

bool isValidEmail(String raw) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(raw.trim());

// ---- business list (S14, BE-24) and another business (BE-40) --------------

/// One page of GET /mobile/businesses?q=&offset=&limit= (bearer, no
/// X-Business-Id). Null = a server without BE-24: S14 filters the session's
/// list locally.
Future<({int total, List<Business> businesses})?> searchBusinesses(
  String query, {
  int offset = 0,
  int limit = 50,
}) async {
  try {
    final json = await _api.get(
      '/mobile/businesses',
      query: {if (query.trim().isNotEmpty) 'q': query.trim(), 'offset': '$offset', 'limit': '$limit'},
    );
    final rows = [
      for (final b in (json['businesses'] as List? ?? const [])) Business.fromJson(b as Map<String, dynamic>),
    ];
    return (total: (json['total'] as num?)?.toInt() ?? rows.length, businesses: rows);
  } on ApiException catch (e) {
    if (e.status == 404 && e.code == 'NOT_FOUND') return null;
    rethrow;
  }
}

/// BE-40: POST /businesses {businessType, legalName, taxId} → the caller is
/// OWNER of a new business. Returns its id.
Future<String> createBusiness({
  required String businessType,
  required String legalName,
  required String taxId,
}) async {
  final json = await _api.post('/businesses', {
    'businessType': businessType,
    'legalName': legalName.trim(),
    'taxId': taxId.replaceAll(RegExp(r'\D'), ''),
  });
  final nested = json['business'];
  final id =
      json['businessId'] ?? json['id'] ?? (nested is Map ? nested['businessId'] ?? nested['id'] : null);
  if (id is! String) throw const FormatException('POST /businesses: no business id');
  return id;
}
