import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../util/errors_he.dart';
import 'client.dart';
import 'environment.dart';

/// Tokens are kept only for the exchange, never in preferences or Keychain.
Future<String> supabasePasswordToken(
  String email,
  String password, {
  required http.Client client,
  SupabaseAuthSettings settings = SupabaseAuthSettings.configured,
}) => SupabaseAuthApi(
  settings: settings,
  httpClient: client,
).passwordToken(email, password);

/// Supabase Auth refusal → app code. Only a real credentials answer says
/// "wrong password"; an unconfirmed e-mail, a blocked user or bad input say so.
/// [fallback] is the code of an unexplained 400/401 (the password grant:
/// INVALID_CREDENTIALS; a one-time code: SUPABASE_CODE_INVALID).
String supabaseErrorCode(
  int status,
  String body, {
  String fallback = 'INVALID_CREDENTIALS',
}) {
  if (status == 429) return 'RATE_LIMITED';
  if (status < 400 || status >= 500) return 'SUPABASE_AUTH_UNAVAILABLE';
  String? reason;
  try {
    final json = jsonDecode(body);
    if (json is Map<String, dynamic>) {
      final value = json['error_code'] ?? json['error'];
      if (value is String) reason = value;
    }
  } on FormatException {
    // Not JSON: decided by the status alone.
  }
  final known = switch (reason) {
    'invalid_credentials' || 'invalid_grant' => 'INVALID_CREDENTIALS',
    'email_not_confirmed' => 'SUPABASE_EMAIL_NOT_CONFIRMED',
    'user_banned' => 'SUPABASE_USER_BANNED',
    'email_address_invalid' => 'EMAIL_INVALID',
    'over_request_rate_limit' || 'over_email_send_rate_limit' => 'RATE_LIMITED',
    'otp_expired' || 'otp_disabled' => 'SUPABASE_CODE_INVALID',
    'user_already_exists' || 'email_exists' => 'SUPABASE_ACCOUNT_EXISTS',
    'weak_password' => 'SUPABASE_WEAK_PASSWORD',
    'same_password' => 'SUPABASE_SAME_PASSWORD',
    'signup_disabled' ||
    'email_provider_disabled' => 'SUPABASE_SIGNUP_DISABLED',
    'validation_failed' => 'SUPABASE_LOGIN_INVALID_INPUT',
    _ => null,
  };
  if (known != null) return known;
  if (status == 422) return 'SUPABASE_LOGIN_INVALID_INPUT';
  if (status == 400 || status == 401 || status == 403) return fallback;
  return 'SUPABASE_AUTH_UNAVAILABLE';
}

/// A Supabase sign-up: either signed in at once ("Confirm email" off) or
/// waiting for the 6-digit code that was e-mailed ("Confirm email" on).
class SupabaseSignUp {
  const SupabaseSignUp._(this.accessToken);

  final String? accessToken;

  bool get needsEmailCode => accessToken == null;
}

/// The Supabase Auth REST calls the app makes (GoTrue v2). Only the
/// publishable key is used; access tokens stay in memory for one exchange.
/// Responses and tokens are never logged.
class SupabaseAuthApi {
  SupabaseAuthApi({
    this.settings = SupabaseAuthSettings.configured,
    this.httpClient,
  });

  final SupabaseAuthSettings settings;

  /// Null: the app's HTTP client (tests then mock Supabase and Tevel at once).
  final http.Client? httpClient;

  http.Client get client => httpClient ?? ApiClient.instance.httpClient;

  bool get enabled => settings.enabled;

  /// e-mail + password → access token.
  Future<String> passwordToken(String email, String password) async {
    final body = await _send(
      'POST',
      '/auth/v1/token',
      query: {'grant_type': 'password'},
      body: {'email': email.trim(), 'password': password},
    );
    return _accessToken(body);
  }

  /// Creates the Supabase account of an invited e-mail. An address that
  /// already has a confirmed account answers SUPABASE_ACCOUNT_EXISTS (with
  /// "Confirm email" on, Supabase hides that behind an empty identity list).
  Future<SupabaseSignUp> signUp(String email, String password) async {
    final body = await _send(
      'POST',
      '/auth/v1/signup',
      body: {'email': email.trim(), 'password': password},
    );
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) return SupabaseSignUp._(token);
    final user = body['user'] is Map<String, dynamic>
        ? body['user'] as Map<String, dynamic>
        : body;
    final identities = user['identities'];
    if (identities is List && identities.isEmpty) {
      throw ApiException(
        409,
        'SUPABASE_ACCOUNT_EXISTS',
        errorMessageHe('SUPABASE_ACCOUNT_EXISTS'),
      );
    }
    if (user['id'] is! String) {
      throw ApiException(502, 'BAD_RESPONSE', errorMessageHe('BAD_RESPONSE'));
    }
    return const SupabaseSignUp._(null);
  }

  /// Sends the sign-up confirmation code again.
  Future<void> resendSignUpCode(String email) => _send(
    'POST',
    '/auth/v1/resend',
    body: {'type': 'signup', 'email': email.trim()},
  );

  /// "שכחתי סיסמה": e-mails a recovery code. Supabase answers the same for
  /// unknown addresses (no account enumeration); so does the app.
  Future<void> sendRecoveryCode(String email) =>
      _send('POST', '/auth/v1/recover', body: {'email': email.trim()});

  /// The e-mailed code → a session (sign-up confirmation or recovery).
  Future<String> verifyCode(
    String email,
    String code, {
    required bool recovery,
  }) async {
    final body = await _send(
      'POST',
      '/auth/v1/verify',
      body: {
        'type': recovery ? 'recovery' : 'signup',
        'email': email.trim(),
        'token': code.trim(),
      },
      fallback: 'SUPABASE_CODE_INVALID',
    );
    return _accessToken(body);
  }

  /// Sets a new password with the recovery session's access token.
  Future<void> updatePassword(String accessToken, String password) => _send(
    'PUT',
    '/auth/v1/user',
    body: {'password': password},
    bearer: accessToken,
    fallback: 'SUPABASE_TOKEN_INVALID',
  );

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    required Map<String, Object> body,
    String? bearer,
    String fallback = 'INVALID_CREDENTIALS',
  }) async {
    final Uri origin;
    try {
      origin = settings.origin;
    } on FormatException {
      throw ApiException(
        503,
        'SUPABASE_AUTH_DISABLED',
        errorMessageHe('SUPABASE_AUTH_DISABLED'),
      );
    }
    final request =
        http.Request(method, origin.replace(path: path, queryParameters: query))
          ..followRedirects = false
          ..headers.addAll({
            'apikey': settings.publishableKey,
            'Content-Type': 'application/json',
            if (bearer != null) 'Authorization': 'Bearer $bearer',
          })
          ..body = jsonEncode(body);
    final http.Response response;
    try {
      response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(ApiClient.timeout);
    } on TimeoutException {
      throw ApiException(0, 'TIMEOUT', errorMessageHe('TIMEOUT'));
    } on http.ClientException {
      throw ApiException(0, 'NETWORK', errorMessageHe('NETWORK'));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = supabaseErrorCode(
        response.statusCode,
        response.body,
        fallback: fallback,
      );
      throw ApiException(response.statusCode, code, errorMessageHe(code));
    }
    if (response.body.trim().isEmpty) return const {};
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Do not expose raw authentication responses to the UI or logs.
    }
    throw ApiException(502, 'BAD_RESPONSE', errorMessageHe('BAD_RESPONSE'));
  }

  static String _accessToken(Map<String, dynamic> body) {
    final token = body['access_token'];
    if (token is String && token.isNotEmpty) return token;
    throw ApiException(502, 'BAD_RESPONSE', errorMessageHe('BAD_RESPONSE'));
  }
}

/// The app's Supabase Auth (build-time settings). Tests replace it.
SupabaseAuthApi supabaseAuth = SupabaseAuthApi();
