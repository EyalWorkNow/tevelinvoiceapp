import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
import '../api/models/models.dart';
import 'cache.dart';

enum SessionStatus { unknown, signedOut, signedIn }

/// The one app-wide session: device token, selected business, /me + profile.
///
/// Flow: SplashScreen → `session.restore()`; LoginScreen (cookie session,
/// MFA) → `session.completeSignIn()`; any 401 on a business route →
/// signed out with [expired] = true.
class SessionController extends ChangeNotifier {
  SessionController({FlutterSecureStorage? storage, ApiClient? client})
      : _storage = storage ??
            const FlutterSecureStorage(
                iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)),
        _client = client ?? ApiClient.instance {
    _client.events.listen((event) {
      if (event == ApiEvent.sessionExpired && status == SessionStatus.signedIn) {
        unawaited(_signOutLocally(expired: true));
      }
    });
  }

  static const _kToken = 'device_token';
  static const _kBusiness = 'business_id';
  static const _kAccountCache = 'account';
  static const _kBusinessCache = 'me_';

  final FlutterSecureStorage _storage;
  final ApiClient _client;

  SessionStatus status = SessionStatus.unknown;

  /// True after an automatic sign-out caused by an expired/revoked token
  /// (LoginScreen shows "פג תוקף ההתחברות").
  bool expired = false;

  /// True when the last restore/refresh could not reach the server and the
  /// app is running from cache (writes are disabled).
  bool offline = false;

  MobileAccount? account;
  Business? business;
  Me? me;
  BusinessProfile? profile;

  /// When [me] was fetched (or read from the offline cache). Capabilities
  /// older than [maxCapsAge] are not used (SPEC-v2 §4.6).
  DateTime? meFetchedAt;
  static const Duration maxCapsAge = Duration(hours: 24);

  /// [me] when it is fresh enough to derive capabilities from.
  Me? get freshMe {
    final at = meFetchedAt;
    if (me == null || at == null) return null;
    return DateTime.now().difference(at) > maxCapsAge ? null : me;
  }

  List<Business> get businesses => account?.businesses ?? const [];
  /// Signed in to several businesses and none chosen yet → G2 picker.
  bool get needsBusinessPick => business == null && businesses.length > 1;

  /// Signed in without any business membership (nothing to scope /business
  /// routes to — the auth squad decides the screen; see ARCHITECTURE.md).
  bool get hasNoBusiness => account != null && businesses.isEmpty;

  /// Selected business has not finished onboarding → S2 (PUT /business/profile
  /// needs X-Business-Id, so onboarding always runs inside a business).
  bool get needsOnboarding => me != null && !me!.onboardingCompleted;

  /// Cold start. Reads the Keychain token; validates it with GET /mobile/session.
  /// Only a 401 signs out; offline / 5xx / 429 → stays signed in from the
  /// cached account (the token is kept).
  Future<void> restore() async {
    if (await AppCache.isFirstLaunch()) await _forgetTokenFromPreviousInstall();
    final token = await _storage.read(key: _kToken);
    if (token == null) {
      status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }
    _client.deviceToken = token;
    final storedBusiness = await _storage.read(key: _kBusiness);
    try {
      await _loadAccount(preferredBusinessId: storedBusiness);
      offline = false;
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _signOutLocally(expired: true);
        return;
      }
      offline = true;
      final cached = await AppCache.read(_kAccountCache);
      if (cached is! Map<String, dynamic>) {
        // Never been online with this token — nothing to show; keep the token
        // and let the UI offer a retry from the login screen.
        status = SessionStatus.signedOut;
        notifyListeners();
        return;
      }
      account = MobileAccount.fromJson(cached);
      _selectFromAccount(storedBusiness);
      await _readCachedBusiness();
    }
    // /me + profile before signalling signed-in, so the splash routes on them
    // (and does not fetch them a second time).
    if (business != null && !offline) {
      try {
        await refreshBusiness();
      } on ApiException catch (e) {
        if (e.isNetwork) {
          offline = true;
          await _readCachedBusiness();
        }
      }
    }
    status = SessionStatus.signedIn;
    notifyListeners();
  }

  /// After the cookie login (+ MFA if required) succeeded: get a device token,
  /// persist it, load the account. Returns the account so the caller can
  /// route: 0 businesses → onboarding, >1 → business picker, 1 → home.
  Future<MobileAccount> completeSignIn({String deviceName = 'iPhone'}) async {
    final token = await _client.exchangeSessionForDeviceToken(deviceName);
    await _storage.write(key: _kToken, value: token);
    await _loadAccount(preferredBusinessId: await _storage.read(key: _kBusiness));
    expired = false;
    offline = false;
    status = SessionStatus.signedIn;
    notifyListeners();
    if (business != null) await refreshBusiness();
    return account!;
  }

  /// Switch business (G2 / settings). Clears per-business state and reloads.
  Future<void> selectBusiness(Business selected) async {
    business = selected;
    _client.businessId = selected.businessId;
    me = null;
    profile = null;
    meFetchedAt = null;
    await _storage.write(key: _kBusiness, value: selected.businessId);
    notifyListeners();
    await refreshBusiness();
  }

  /// Reload /me + /business/profile for the selected business. A response
  /// that lands after a business switch is dropped.
  Future<void> refreshBusiness() async {
    final requested = business?.businessId;
    if (requested == null) return;
    final results = await Future.wait([
      _client.get('/me'),
      _client.get('/business/profile'),
    ]);
    if (business?.businessId != requested) return;
    me = Me.fromJson(results[0]);
    profile = BusinessProfile.fromJson(results[1]['profile'] as Map<String, dynamic>);
    meFetchedAt = DateTime.now();
    offline = false;
    notifyListeners();
    try {
      await AppCache.write('$_kBusinessCache$requested', {
        'fetchedAt': meFetchedAt!.toIso8601String(),
        'me': me!.toJson(),
        'profile': profile!.toJson(),
      });
    } on Object {
      // Offline start just shows less; never fails the refresh.
    }
  }

  /// Offline cold start: /me + profile from the last successful refresh.
  Future<void> _readCachedBusiness() async {
    final id = business?.businessId;
    if (id == null) return;
    final cached = await AppCache.read('$_kBusinessCache$id');
    if (cached is! Map<String, dynamic>) return;
    try {
      me = Me.fromJson(cached['me'] as Map<String, dynamic>);
      profile = BusinessProfile.fromJson(cached['profile'] as Map<String, dynamic>);
      meFetchedAt = DateTime.parse(cached['fetchedAt'] as String);
    } on Object {
      me = null;
      profile = null;
      meFetchedAt = null;
    }
  }

  /// Re-read GET /mobile/session (e.g. after onboarding created a business).
  Future<void> refreshAccount() async {
    await _loadAccount(preferredBusinessId: business?.businessId);
    notifyListeners();
  }

  /// Sign out on this device: revoke the token server-side (best effort),
  /// wipe Keychain + cache, including pending operations (the caller warns
  /// first when [AppCache.hasPending]).
  Future<void> signOut() async {
    if (_client.hasDeviceToken) {
      try {
        await _client.post('/mobile/logout');
      } on ApiException {
        // Offline or already revoked: local sign-out still proceeds.
      }
    }
    await _signOutLocally(expired: false);
  }

  /// Local-only wipe (account deleted, token revoked, expired). On expiry the
  /// pending issue / payment / credit state is kept, so after signing in again
  /// the resume banner continues it instead of issuing a duplicate.
  Future<void> _signOutLocally({required bool expired}) async {
    _client.clearCredentials();
    account = null;
    business = null;
    me = null;
    profile = null;
    meFetchedAt = null;
    offline = false;
    this.expired = expired;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kBusiness);
    try {
      await AppCache.clearAll(keepPending: expired);
    } on Object {
      // Cache wipe failure must not keep the user signed in.
    }
    status = SessionStatus.signedOut;
    notifyListeners();
  }

  /// Public wrapper for flows that already revoked server-side (delete account).
  Future<void> signOutLocally() => _signOutLocally(expired: false);

  /// The Keychain survives an uninstall; a token left by a previous install
  /// must not sign the next user of this app in. Revoked best effort.
  Future<void> _forgetTokenFromPreviousInstall() async {
    final old = await _storage.read(key: _kToken);
    if (old == null) return;
    await _storage.delete(key: _kToken);
    await _storage.delete(key: _kBusiness);
    _client.deviceToken = old;
    try {
      await _client.post('/mobile/logout').timeout(const Duration(seconds: 5));
    } on Object {
      // Offline / already revoked: the local delete is what matters.
    }
    _client.clearCredentials();
  }

  Future<void> _loadAccount({String? preferredBusinessId}) async {
    final json = await _client.get('/mobile/session');
    account = MobileAccount.fromJson(json);
    await AppCache.write(_kAccountCache, account!.toJson());
    _selectFromAccount(preferredBusinessId);
  }

  void _selectFromAccount(String? preferredBusinessId) {
    final list = businesses;
    Business? pick;
    for (final b in list) {
      if (b.businessId == preferredBusinessId) pick = b;
    }
    if (pick == null && list.length == 1) pick = list.first;
    business = pick;
    _client.businessId = pick?.businessId;
  }
}

/// The app-wide session instance.
final SessionController session = SessionController();
