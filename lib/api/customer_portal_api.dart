// "האזור האישי של הלקוח" (server 0135: apps/api/src/routes/v2/customer-portal.ts).
//
//   GET    /customers/:id/portal-link             {link: PortalLink | null}
//   POST   /customers/:id/portal-link             the live link (created on first use)
//   POST   /customers/:id/portal-link/regenerate  the old link dies, a new one
//   DELETE /customers/:id/portal-link             {revoked}
//
// The customer opens the link and signs in with a one-time code sent to the
// e-mail on file; 422 CUSTOMER_EMAIL_MISSING when the customer has none.

import 'client.dart';
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

class PortalLink {
  const PortalLink({
    required this.url,
    required this.createdAt,
    this.lastLoginAt,
    this.whatsappText,
  });

  factory PortalLink.fromJson(Map<String, dynamic> j) => PortalLink(
    url: jStr(j['url']) ?? '',
    createdAt: jStr(j['createdAt']) ?? '',
    lastLoginAt: jStr(j['lastLoginAt']),
    whatsappText: jStr(j['whatsappText']),
  );

  final String url;

  /// ISO-8601 UTC.
  final String createdAt;

  /// When the customer last signed in (ISO-8601 UTC), null = never.
  final String? lastLoginAt;

  /// The ready WhatsApp message (POST answers only).
  final String? whatsappText;
}

Future<PortalLink?> fetchPortalLink(String customerId) async {
  final j = await _api.get('/customers/$customerId/portal-link');
  final link = j['link'];
  return link is Map<String, dynamic> ? PortalLink.fromJson(link) : null;
}

Future<PortalLink> ensurePortalLink(String customerId) async =>
    PortalLink.fromJson(await _api.post('/customers/$customerId/portal-link'));

Future<PortalLink> regeneratePortalLink(String customerId) async =>
    PortalLink.fromJson(
      await _api.post('/customers/$customerId/portal-link/regenerate'),
    );

Future<void> revokePortalLink(String customerId) =>
    _api.delete('/customers/$customerId/portal-link');
