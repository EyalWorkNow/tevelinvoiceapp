// F6 / AT-95 (INT). The app opens only these:
// * launchUrl: wa.me, fixed Apple Maps searches, mailto:, tel: ([isAllowedLaunch]);
// * in-app Safari (SFSafariViewController): the legal/support whitelist below.
// Hosted subscription checkout is separately pinned to Cardcom below.

import 'package:url_launcher/url_launcher.dart';

const String privacyUrl = 'https://www.tevel.space/legal/privacy';
const String termsUrl = 'https://www.tevel.space/legal/tevel-invoice';
const String supportUrl = 'https://www.tevel.space/contact';

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
