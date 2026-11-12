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
    final code = response.statusCode == 429
        ? 'RATE_LIMITED'
        : response.statusCode == 400 ||
              response.statusCode == 401 ||
              response.statusCode == 422
        ? 'INVALID_CREDENTIALS'
        : 'SUPABASE_AUTH_UNAVAILABLE';
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
