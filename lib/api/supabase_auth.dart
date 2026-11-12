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
      http.Request(
          'POST',
          origin.replace(
            path: '/auth/v1/token',
            queryParameters: {'grant_type': 'password'},
          ),
        )
        ..followRedirects = false
        ..headers.addAll({
          'apikey': settings.publishableKey,
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({'email': email.trim(), 'password': password});
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
  if (response.statusCode != 200) {
    final code = supabaseErrorCode(response.statusCode, response.body);
    throw ApiException(response.statusCode, code, errorMessageHe(code));
  }
  try {
    final body = jsonDecode(response.body);
    final token = body is Map<String, dynamic> ? body['access_token'] : null;
    if (token is String && token.isNotEmpty) return token;
  } on FormatException {
    // Do not expose raw authentication responses to the UI or logs.
  }
  throw ApiException(502, 'BAD_RESPONSE', errorMessageHe('BAD_RESPONSE'));
}

/// Supabase Auth refusal → app code. Only a real credentials answer says
/// "wrong password"; an unconfirmed e-mail, a blocked user or bad input say so.
String supabaseErrorCode(int status, String body) {
  if (status == 429) return 'RATE_LIMITED';
  if (status != 400 && status != 401 && status != 422) {
    return 'SUPABASE_AUTH_UNAVAILABLE';
  }
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
  return switch (reason) {
    'invalid_credentials' || 'invalid_grant' => 'INVALID_CREDENTIALS',
    'email_not_confirmed' => 'SUPABASE_EMAIL_NOT_CONFIRMED',
    'user_banned' => 'SUPABASE_USER_BANNED',
    'email_address_invalid' => 'EMAIL_INVALID',
    'over_request_rate_limit' || 'over_email_send_rate_limit' => 'RATE_LIMITED',
    'validation_failed' => 'SUPABASE_LOGIN_INVALID_INPUT',
    _ when status == 422 => 'SUPABASE_LOGIN_INVALID_INPUT',
    _ => 'INVALID_CREDENTIALS',
  };
}
