// F6 / AT-95 (INT). The app opens only these:
// * launchUrl: wa.me, fixed Apple Maps searches, mailto:, tel:, sms: ([isAllowedLaunch]);
// * in-app Safari (SFSafariViewController): the legal/support whitelist below.
// Hosted subscription checkout is separately pinned to Cardcom below.

import 'package:url_launcher/url_launcher.dart';

const String privacyUrl = 'https://www.tevel.space/legal/privacy';
const String termsUrl = 'https://www.tevel.space/legal/tevel-invoice';
const String supportUrl = 'https://www.tevel.space/contact';

/// Tevel's own contact details (websitetry src/lib/site.ts `company`).
const String tevelEmail = 'help@tevel.space';
const String tevelPhone = '053-932-8311';
const String tevelPhoneE164 = '+972539328311';

/// "אין לך חשבון? דברו איתנו": WhatsApp with a prefilled Hebrew message.
Uri tevelWhatsAppUri([String text = accountRequestText]) =>
    Uri.https('wa.me', '/${tevelPhoneE164.substring(1)}', {'text': text});

/// The same request by e-mail.
Uri tevelEmailUri([String text = accountRequestText]) => Uri(
  scheme: 'mailto',
  path: tevelEmail,
  query:
      'subject=${Uri.encodeComponent('פתיחת חשבון בתבל')}'
      '&body=${Uri.encodeComponent(text)}',
);

const String accountRequestText =
    'היי, אשמח לפתוח חשבון באפליקציית תבל להפקת חשבוניות וקבלות.';

/// Pages allowed in SFSafariViewController.
const Set<String> safariWhitelist = {privacyUrl, termsUrl, supportUrl};

bool isAllowedSafariUrl(Uri uri) => safariWhitelist.contains(uri.toString());

/// Apple's own "manage subscriptions" page (cancel an App Store plan).
final Uri appleSubscriptionsUri = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);

/// External launches: fixed map searches, WhatsApp, mail, phone, and iOS Settings (camera
/// permission denied → "פתח הגדרות" on expense capture).
bool isAllowedLaunch(Uri uri) =>
    (uri.scheme == 'https' && uri.host == 'wa.me') ||
    uri == appleSubscriptionsUri ||
    (uri.scheme == 'https' &&
        uri.host == 'maps.apple.com' &&
        uri.path == '/' &&
        uri.userInfo.isEmpty &&
        (!uri.hasPort || uri.port == 443) &&
        uri.queryParametersAll.length == 1 &&
        uri.queryParametersAll['q']?.length == 1 &&
        uri.queryParameters['q']!.trim().isNotEmpty &&
        uri.fragment.isEmpty) ||
    uri.scheme == 'mailto' ||
    uri.scheme == 'tel' ||
    // 0134 טופס 101: the one-time code by SMS (the owner's own composer).
    uri.scheme == 'sms' ||
    uri.toString() == 'app-settings:';

/// The one door to url_launcher. Tests replace it (test/fakes FakeLauncher
/// records every URL — AT-10 checks `wa.me/972…/d/…` without WhatsApp).
typedef UrlOpener = Future<bool> Function(Uri uri, {bool inApp});

UrlOpener urlOpener = defaultUrlOpener;

Future<bool> defaultUrlOpener(Uri uri, {bool inApp = false}) => launchUrl(
  uri,
  mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication,
);

/// Fixed map searches, WhatsApp, mail and phone only. Anything else throws.
Future<bool> launchAllowed(Uri uri) {
  if (!isAllowedLaunch(uri)) {
    throw ArgumentError.value(uri, 'uri', 'not an allowed launch target');
  }
  return urlOpener(uri);
}

/// Legal / support pages in SFSafariViewController (F6 (ב)). Anything else throws.
Future<bool> openSafari(Uri uri) {
  if (!isAllowedSafariUrl(uri)) {
    throw ArgumentError.value(uri, 'uri', 'not on the whitelist');
  }
  return urlOpener(uri, inApp: true);
}

/// Hosted Cardcom checkout: card details are entered only on the provider's page.
Future<bool> openPaymentPage(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host != 'secure.cardcom.solutions' ||
      (uri.hasPort && uri.port != 443) ||
      uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(uri, 'uri', 'not a Cardcom checkout');
  }
  return urlOpener(uri, inApp: true);
}

/// 0136 וואטסאפ עסקי: the server's one-time Embedded Signup page
/// (`/wa/connect/<token>`) in SFSafariViewController — only on the Tevel API
/// host ([waConnectHost], or the configured API origin in dev builds).
const String waConnectHost = 'invoice.crm.tevel.space';

bool isWaConnectUrl(Uri uri, {String? apiOrigin}) {
  if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) return false;
  final segments = uri.pathSegments;
  if (segments.length != 3 ||
      segments[0] != 'wa' ||
      segments[1] != 'connect' ||
      segments[2].isEmpty) {
    return false;
  }
  if (uri.scheme == 'https' &&
      uri.host == waConnectHost &&
      (!uri.hasPort || uri.port == 443)) {
    return true;
  }
  final origin = apiOrigin == null ? null : Uri.tryParse(apiOrigin);
  return origin != null &&
      origin.host.isNotEmpty &&
      uri.scheme == origin.scheme &&
      uri.host == origin.host &&
      uri.port == origin.port;
}

Future<bool> openWaConnectPage(Uri uri, {String? apiOrigin}) {
  if (!isWaConnectUrl(uri, apiOrigin: apiOrigin)) {
    throw ArgumentError.value(uri, 'uri', 'not a WhatsApp connect page');
  }
  return urlOpener(uri, inApp: true);
}
