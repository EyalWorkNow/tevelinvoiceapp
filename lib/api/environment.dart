import 'dart:io';

/// Release builds must never send credentials to a development endpoint.
Uri productionApiUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      (uri.hasPort && uri.port != 443)) {
    throw const FormatException('API_BASE must be a public HTTPS origin');
  }
  final host = uri.host.toLowerCase();
  if (InternetAddress.tryParse(host) != null ||
      !host.contains('.') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal')) {
    throw const FormatException('API_BASE must use a public DNS name');
  }
  return uri.replace(path: '');
}

/// Supabase is used only for primary authentication. Tevel still issues the
/// device token and enforces business permissions and its MFA challenge.
class SupabaseAuthSettings {
  const SupabaseAuthSettings({required this.url, required this.publishableKey});

  static const configured = SupabaseAuthSettings(
    url: String.fromEnvironment('SUPABASE_AUTH_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_AUTH_PUBLISHABLE_KEY'),
  );

  final String url;
  final String publishableKey;

  bool get enabled => url.isNotEmpty || publishableKey.isNotEmpty;

  Uri get origin {
    final uri = productionApiUri(url);
    if (!RegExp(r'^[a-z0-9]+\.supabase\.co$').hasMatch(uri.host) ||
        !publishableKey.startsWith('sb_publishable_')) {
      throw const FormatException(
        'Supabase Auth requires a hosted origin and publishable key',
      );
    }
    return uri;
  }
}
