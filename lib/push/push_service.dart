// Push notifications (PUSH-001) — the app side. docs/PUSH-NOTIFICATIONS-he.md has the catalogue.
//
// * Permission is never asked on first launch: after the first issued document (or one that waits
//   for the Tax Authority) a short sheet explains what the notifications are for, then iOS asks.
//   Settings › התראות can ask too.
// * The APNs token goes to POST /mobile/push/devices with a per-install id (Keychain), the APNs
//   environment (sandbox for Xcode/simulator builds, production for TestFlight/App Store) and the
//   locale. The server binds it to this device's bearer token, so signing out stops the pushes.
// * A tap opens the push's `link` (a §5 route) — in the push's business, switching to it first.
// * The badge is cleared whenever the app comes to the foreground.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tevel_push/tevel_push.dart';

import '../api/client.dart';
import '../router.dart';
import '../state/session.dart';
import '../ui/theme.dart';
import '../util/labels/labels.dart';

/// Where a push may be registered and opened from: replaceable in tests.
abstract class PushStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class _KeychainStore implements PushStore {
  const _KeychainStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
}

const String _kDeviceId = 'push_device_id';
const String _kAsked = 'push_permission_asked';
const String _kLastToken = 'push_last_token';

class PushService with WidgetsBindingObserver {
  PushService({TevelPushPlatform? platform, ApiClient? api, PushStore? store, Random? random})
    : _platform = platform ?? TevelPushPlatform.instance,
      _api = api ?? ApiClient.instance,
      _store = store ?? const _KeychainStore(),
      _random = random ?? Random.secure();

  static PushService instance = PushService();

  final TevelPushPlatform _platform;
  final ApiClient _api;
  final PushStore _store;
  final Random _random;
  bool _started = false;
  String? _registeredToken;
  // A tap that arrives before the home shell exists (cold start, splash, Face ID lock) waits here:
  // routeSignedIn resets the stack, which would drop a screen pushed earlier.
  bool _shellReady = false;
  PushPayload? _pending;

  /// Last tap opened (tests and diagnostics).
  final ValueNotifier<PushPayload?> lastTap = ValueNotifier(null);

  /// Called once the user is signed in with a business.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _platform.onToken = (token) {
      unawaited(_register(token));
    };
    _platform.onTokenError = (error) {
      debugPrint('push: APNs registration failed: $error');
    };
    _platform.onTap = (payload) {
      unawaited(_openWhenReady(payload));
    };
    final initial = await _platform.start();
    unawaited(_platform.setBadge(0));
    final status = await _platform.authorizationStatus();
    if (status == PushAuthorization.authorized || status == PushAuthorization.provisional) {
      await _platform.register(); // a fresh token arrives via onToken
    }
    if (initial != null) await _openWhenReady(initial);
  }

  /// routeSignedIn calls this once home is on screen.
  void shellReady() {
    _shellReady = true;
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(openPayload(pending));
  }

  Future<void> _openWhenReady(PushPayload payload) async {
    if (_shellReady) return openPayload(payload);
    _pending = payload;
  }

  /// Sign-out: forget what was registered (the server already stopped this device's pushes).
  void reset() {
    _registeredToken = null;
    _shellReady = false;
    _pending = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_platform.setBadge(0));
  }

  Future<PushAuthorization> status() => _platform.authorizationStatus();

  Future<String> deviceId() async {
    final existing = await _store.read(_kDeviceId);
    if (existing != null && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(existing)) return existing;
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final id = 'ios-${List.generate(24, (_) => alphabet[_random.nextInt(alphabet.length)]).join()}';
    await _store.write(_kDeviceId, id);
    return id;
  }

  Future<void> _register(String token) async {
    if (session.status != SessionStatus.signedIn) return;
    if (_registeredToken == token) return;
    try {
      await _api.post('/mobile/push/devices', {
        'deviceId': await deviceId(),
        'token': token,
        'environment': await _platform.apnsEnvironment(),
        'locale': 'he-IL',
      });
      _registeredToken = token;
      await _store.write(_kLastToken, token);
    } on ApiException catch (e) {
      debugPrint('push: registration refused (${e.code})');
    }
  }

  /// Asks iOS (after our own explanation when iOS has not asked yet). True when allowed.
  Future<bool> enable(BuildContext context, {String? reason}) async {
    final status = await _platform.authorizationStatus();
    if (status == PushAuthorization.authorized || status == PushAuthorization.provisional) {
      await _platform.register();
      return true;
    }
    if (status == PushAuthorization.denied || status == PushAuthorization.unsupported) return false;
    if (!context.mounted) return false;
    final go = await showPushPrimer(context, reason: reason);
    await _store.write(_kAsked, 'true');
    if (go != true) return false;
    return _platform.requestPermission();
  }

  /// After a document was issued (or is waiting for the Tax Authority): ask once per install.
  Future<void> maybeAskAfterIssue(BuildContext context, {required bool waitingForTaxAuthority}) async {
    if (await _store.read(_kAsked) == 'true') return;
    if (await _platform.authorizationStatus() != PushAuthorization.notDetermined) return;
    if (!context.mounted) return;
    await enable(
      context,
      reason: waitingForTaxAuthority
          ? PushHe.primerWaitingAllocation
          : null,
    );
  }

  /// Opens a tapped push: switches to its business when needed, then goes to its link.
  Future<void> openPayload(PushPayload payload) async {
    lastTap.value = payload;
    if (session.status != SessionStatus.signedIn) return;
    final businessId = payload.businessId;
    if (businessId != null && session.business?.businessId != businessId) {
      final target = session.businesses.where((b) => b.businessId == businessId).firstOrNull;
      if (target == null) return; // not a member any more: open nothing
      await session.selectBusiness(target);
    }
    final link = payload.link;
    if (link != null && link.isNotEmpty) await go(link);
  }
}

/// Our explanation before the one-time iOS dialog. Returns true to continue to iOS.
Future<bool?> showPushPrimer(BuildContext context, {String? reason}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          key: const Key('push-primer'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(PushHe.primerTitle, style: AppText.title),
            const SizedBox(height: 8),
            Text(
              reason ?? PushHe.primerBody,
              style: AppText.body,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('push-primer-yes'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(PushHe.primerYes),
            ),
            TextButton(
              key: const Key('push-primer-no'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(PushHe.primerNo),
            ),
          ],
        ),
      ),
    ),
  );
}
