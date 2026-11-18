import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
import '../api/documents_api.dart' show notifyDocumentsChanged;
import '../api/notifications_api.dart'
    show notifyNotificationsChanged, refreshNotificationsUnread;
import '../api/settings_api.dart' show appVersion;
import '../api/sign_requests_api.dart' show notifySignRequestsChanged;
import '../router.dart';
import '../util/errors_he.dart';
import '../ui/widgets/notch_notice.dart';
import '../util/labels/inbox_he.dart';
import 'session.dart';

const _channel = MethodChannel('tevel/system_notices');
const _events = EventChannel('tevel/system_notice_events');

/// Fixed, amount-free text for OS and foreground events.
(String, NoticeMotion)? systemNoticePresentation(String kind) => switch (kind) {
  'approved' => ('הלקוח אישר את הצעת המחיר!', NoticeMotion.approved),
  // Push catalogue (PUSH-001, /mobile/push/devices; packages/shared
  // push-catalogue.ts): `kind` + `link` instead of `tevelKind` + `route`.
  'QUOTE_SIGNED' => ('הלקוח אישר את הצעת המחיר', NoticeMotion.approved),
  'QUOTE_VIEWED' => ('הלקוח צפה בהצעת המחיר', NoticeMotion.sent),
  'ITA_ALLOCATION_APPROVED' => (
    'רשות המסים אישרה את המסמך',
    NoticeMotion.approved,
  ),
  'ITA_ALLOCATION_REJECTED' => ('רשות המסים דחתה את המסמך', NoticeMotion.error),
  'DOCUMENT_SEND_FAILED' => ('המסמך לא נשלח ללקוח', NoticeMotion.error),
  'PAYMENT_RECEIVED' => ('התקבל תשלום', NoticeMotion.payment),
  'PAYMENTS_OVERDUE' => (
    'חשבוניות שעבר מועד התשלום שלהן',
    NoticeMotion.reminder,
  ),
  'COLLECTION_REMINDERS_READY' => (
    'תזכורות גבייה מוכנות לשליחה',
    NoticeMotion.reminder,
  ),
  'TEAM_MEMBER_JOINED' => ('חבר צוות הצטרף', NoticeMotion.saved),
  'SUBSCRIPTION_RENEWS_SOON' => ('המנוי מתחדש בקרוב', NoticeMotion.reminder),
  'SUBSCRIPTION_PAYMENT_FAILED' => ('חידוש המנוי נכשל', NoticeMotion.error),
  'SUBSCRIPTION_EXPIRED' => ('המנוי הסתיים', NoticeMotion.error),
  'EXPORT_READY' => ('הקובץ מוכן', NoticeMotion.document),
  'EXPORT_FAILED' => ('הפקת הדוח נכשלה', NoticeMotion.error),
  'NEW_DEVICE_LOGIN' => ('כניסה מטלפון חדש', NoticeMotion.error),
  'UPLOAD_BLOCKED' => ('קובץ נחסם', NoticeMotion.error),
  'payment' => ('התקבל תשלום חדש', NoticeMotion.payment),
  'approvalNeeded' => ('מסמך חדש ממתין לאישור', NoticeMotion.document),
  'rejected' => ('המסמך הוחזר לתיקון', NoticeMotion.error),
  'viewed' => ('הלקוח צפה במסמך', NoticeMotion.sent),
  'expense' => ('ההוצאה מוכנה לבדיקה', NoticeMotion.document),
  'reminder' => ('זמן לחזור ללקוח', NoticeMotion.reminder),
  'visit' => ('הביקור שלך מתקרב', NoticeMotion.reminder),
  'collection' => ('תזכורת למעקב תשלום', NoticeMotion.reminder),
  'issued' => ('המסמך הופק', NoticeMotion.document),
  'sent' => ('המסמך נשלח', NoticeMotion.sent),
  'signed' => ('המסמך נחתם', NoticeMotion.signed),
  'recurringReady' => ('טיוטות חודשיות מוכנות לאישור', NoticeMotion.document),
  'bookingNew' => ('נקבעה פגישה חדשה', NoticeMotion.calendar),
  'bookingSoon' => ('הפגישה הבאה מתקרבת', NoticeMotion.calendar),
  // 0116 "מסמך לחתימה" (route /sign-request/:id).
  'signRequestCompleted' => ('המסמך נחתם', NoticeMotion.signed),
  'signRequestViewed' => ('המסמך לחתימה נצפה', NoticeMotion.sent),
  // 0119 "המסמכים של העסק" (route /business/vault).
  'vaultExpiring' => ('מסמך של העסק עומד לפוג', NoticeMotion.reminder),
  _ => null,
};

final systemNotices = SystemNotices();

/// A feature that shows its own, richer foreground notice for a kind (e.g.
/// "יומן" re-syncs and names the client). Returns true when it handled it.
typedef ForegroundNoticeHandler = bool Function(String kind);

class SystemNotices extends ChangeNotifier with WidgetsBindingObserver {
  static const _storage = FlutterSecureStorage();
  StreamSubscription<dynamic>? _subscription;
  final Map<String, Map<String, Object?>> _tokens = {};
  final Set<String> _uploaded = {};
  final Set<String> _seen = {};
  String? _business;
  bool enabled = false;
  bool deliveryConfigured = false;
  bool liveActivities = false;
  Object? syncError;
  bool _installed = false;
  int _generation = 0;
  Future<void>? _registration;
  bool _registrationPending = false;
  bool _askedThisLaunch = false;

  /// Per-kind foreground handlers (see [ForegroundNoticeHandler]).
  final Map<String, ForegroundNoticeHandler> foregroundHandlers = {};

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  String get _preferenceKey =>
      'system_notices_${session.account?.userId}_${session.business?.businessId}';

  void install() {
    if (!supported || _installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_onSession);
    session.beforeSignOut.add(unregisterForSignOut);
    _subscription = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: _failure,
    );
    _onSession();
  }

  void _failure(Object error) {
    syncError = error;
    notifyListeners();
  }

  void _onSession() {
    final next = session.status == SessionStatus.signedIn
        ? session.business?.businessId
        : null;
    if (_business == next) return;
    _business = next;
    _generation++;
    syncError = null;
    _uploaded.clear();
    _seen.clear();
    enabled = false;
    deliveryConfigured = false;
    if (next == null) {
      _tokens.clear();
      unawaited(_channel.invokeMethod<void>('disable').catchError(_failure));
    } else {
      unawaited(refresh().catchError(_failure));
    }
  }

  /// The push setting cannot work for this sign-in (no MFA on the device
  /// token); retrying is pointless, the text says what to do.
  bool get mfaRequired =>
      syncError is ApiException &&
      (syncError as ApiException).code == 'PUSH_MFA_REQUIRED';

  /// Hebrew text for [syncError] when it is more specific than "connection".
  String? get problemHe =>
      mfaRequired ? (syncError as ApiException).messageHe : null;

  /// Explicit sign-out: remove this device's push rows in every business it
  /// registered for, while the bearer is still valid (SessionController hook).
  Future<void> unregisterForSignOut() async {
    if (!supported) return;
    final user = session.account?.userId;
    for (final business in session.businesses) {
      final id = business.businessId;
      try {
        final opted =
            await _storage.read(key: 'system_notices_${user}_$id') != '0';
        if (opted) {
          await ApiClient.instance.deleteForBusiness(id, '/mobile/push-tokens');
        }
      } on Object {
        // Best effort per business; sign-out continues.
      }
    }
    _uploaded.clear();
    // /mobile/logout also stops it (bound to the bearer); explicit anyway.
    await _unregisterCatalogueDevice();
  }

  Future<void> refresh() async {
    if (!supported || session.status != SessionStatus.signedIn) return;
    final generation = _generation;
    final stored = await _storage.read(key: _preferenceKey);
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    if (generation != _generation) return;
    final startup = pushStartup(
      stored: stored,
      osAuthorized: status?['notifications'] == true,
      // Older native builds do not report it: never prompt on their behalf.
      osDetermined: status?['determined'] != false,
    );
    if (startup == PushStartup.ask && !_askedThisLaunch) {
      // Fresh install / first sign-in: ask the OS once, so the quote-accepted
      // push can arrive without a trip to ניהול → התראות (tester 2026-11-18).
      _askedThisLaunch = true;
      try {
        await enable();
      } on Object {
        // Declined: iOS remembers; the switch in ניהול stays available.
      }
      return;
    }
    enabled = startup == PushStartup.on;
    liveActivities = status?['liveActivities'] == true;
    notifyListeners();
    if (enabled) {
      await _channel.invokeMethod<void>('resume');
      await _uploadTokens();
      if (generation != _generation || _business == null) return;
      final businessId = _business!;
      final backend = await ApiClient.instance.getForBusiness(
        businessId,
        '/mobile/push-status',
      );
      if (generation != _generation) return;
      deliveryConfigured = backend['deliveryConfigured'] == true;
      if (!deliveryConfigured) throw StateError('PUSH_SERVICE_NOT_CONFIGURED');
      notifyListeners();
    }
  }

  Future<void> enable() async {
    if (!supported || session.status != SessionStatus.signedIn) return;
    syncError = null;
    final generation = _generation;
    final preference = _preferenceKey;
    final allowed = await _channel.invokeMethod<bool>('enable') ?? false;
    if (generation != _generation) return;
    if (!allowed) throw StateError('NOTIFICATION_PERMISSION_DENIED');
    await _storage.write(key: preference, value: '1');
    enabled = true;
    await refresh();
  }

  Future<void> disable() async {
    if (!supported) return;
    // Remove this business/device registration while its bearer is still valid.
    await ApiClient.instance.delete('/mobile/push-tokens');
    // '0' = switched off on purpose (no preference = on while iOS allows it).
    await _storage.write(key: _preferenceKey, value: '0');
    enabled = false;
    _uploaded.clear();
    // The catalogue device is per user: kept while another business is on.
    if (!await _optedInAnywhere()) await _unregisterCatalogueDevice();
    await _channel.invokeMethod<void>('endAll');
    notifyListeners();
  }

  /// Push kinds whose arrival means a quote/document changed on the server.
  static bool refreshesDocuments(String kind, String route) =>
      kind == 'approved' ||
      kind == 'QUOTE_SIGNED' ||
      route.startsWith('/quote/') ||
      route.startsWith('/doc/');

  @visibleForTesting
  void debugEvent(Map<Object?, Object?> raw) => _onEvent(raw);

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    if (raw['type'] == 'registrationError') {
      _failure(StateError('APNS_REGISTRATION_FAILED'));
      return;
    }
    if (raw['type'] == 'token') {
      final kind = raw['tokenType'];
      final token = raw['token'];
      final environment = raw['environment'];
      if (kind is! String || token is! String || environment is! String) {
        return;
      }
      final eventID = raw['eventID'];
      final business = raw['businessId'];
      _tokens['$kind:${eventID ?? ''}'] = {
        'tokenType': kind,
        'token': token,
        'environment': environment,
        if (eventID is String) 'eventID': eventID,
        if (business is String) 'businessId': business,
      };
      unawaited(_uploadTokens().catchError(_failure));
      return;
    }
    final kind = raw['kind'];
    final route = raw['route'];
    final business = raw['businessId'];
    // Account-level catalogue pushes (subscription, new device) carry no
    // business: they open in the current one.
    if (kind is! String ||
        route is! String ||
        business is! String ||
        AppRoute.parse(route) == null ||
        (business.isNotEmpty && !isSafeId(business))) {
      return;
    }
    final presentation = systemNoticePresentation(kind);
    if (presentation == null) return;
    // A quote accepted / a document changed elsewhere: the open quote screen
    // and the lists reload (ACCEPTED, the signed PDF).
    if (refreshesDocuments(kind, route)) notifyDocumentsChanged();
    // Open lists / the detail reload on any sign-request push; Home's
    // "מסמכים אחרונים" shows the signed document too (tester 2026-11-18).
    if (kind.startsWith('signRequest')) {
      notifySignRequestsChanged();
      if (kind == 'signRequestCompleted') notifyDocumentsChanged();
    }
    // Every push is also an item in the Home bell: badge + open list reload.
    notifyNotificationsChanged();
    unawaited(refreshNotificationsUnread());
    if (raw['type'] == 'opened') {
      final uri = Uri.parse(route);
      final query = {
        ...uri.queryParameters,
        if (business.isNotEmpty) 'businessId': business,
      };
      final link = Uri(
        path: uri.path,
        queryParameters: query.isEmpty ? null : query,
      ).toString();
      unawaited(AppRouter.instance.openDeepLink(link).catchError(_failure));
      return;
    }
    if (session.status != SessionStatus.signedIn ||
        (business.isNotEmpty && business != _business)) {
      return;
    }
    if (raw['type'] != 'notice') return;
    final id = raw['eventID'];
    if (id is String && id.isNotEmpty) {
      if (!_seen.add(id)) return;
      if (_seen.length > 100) _seen.remove(_seen.first);
    }
    if (foregroundHandlers[kind]?.call(kind) ?? false) return;
    // 1.11: a notice that arrives in the foreground opens its screen on tap.
    notchNoticeKey.currentState?.show(
      SnackBar(
        content: Text(presentation.$1),
        action: SnackBarAction(
          label: InboxHe.actOpen,
          onPressed: () => unawaited(go(route)),
        ),
      ),
      motion: presentation.$2,
    );
  }

  Future<void> _uploadTokens() {
    _registrationPending = true;
    return _registration ??= _drainRegistrations().whenComplete(
      () => _registration = null,
    );
  }

  Future<void> _drainRegistrations() async {
    while (_registrationPending) {
      _registrationPending = false;
      await _uploadTokensOnce();
    }
  }

  Future<void> _uploadTokensOnce() async {
    if (session.status != SessionStatus.signedIn) return;
    final generation = _generation;
    for (final token in _tokens.values.toList()) {
      if (generation != _generation) return;
      final target = token['businessId'] as String? ?? _business;
      if (target == null ||
          !(session.account?.businesses.any((b) => b.businessId == target) ??
              false)) {
        continue;
      }
      final optedIn = target == _business
          ? enabled
          : await _storage.read(
                  key: 'system_notices_${session.account?.userId}_$target',
                ) !=
                '0';
      if (generation != _generation) return;
      if (!optedIn) continue;
      final key = '$target:${token['tokenType']}:${token['token']}';
      if (_uploaded.contains(key)) continue;
      final Map<String, dynamic> result;
      try {
        result = await ApiClient.instance
            .postForBusiness(target, '/mobile/push-tokens', {
              for (final entry in token.entries)
                if (entry.key != 'businessId') entry.key: entry.value,
              'liveActivities': liveActivities,
            });
      } on ApiException catch (e) {
        throw pushRegistrationError(e);
      }
      if (generation != _generation) return;
      deliveryConfigured = result['deliveryConfigured'] == true;
      if (result['deliveryConfigured'] == false) {
        throw StateError('PUSH_SERVICE_NOT_CONFIGURED');
      }
      _uploaded.add(key);
    }
    if (generation == _generation && enabled) await _registerCatalogueDevice();
    syncError = null;
    notifyListeners();
  }

  // ---- PUSH-001 catalogue device (/mobile/push/devices) ----------------------
  // The server's audit fan-out (payments, ITA, export, subscription, security
  // …) only reaches devices in push_devices: per user, bound to this bearer.

  static const _deviceIdKey = 'push_catalogue_device_id';
  String? _catalogueRegistered;

  Future<String> _deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null &&
        RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(existing)) {
      return existing;
    }
    final r = Random.secure();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final id = List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  /// POST /mobile/push/devices with this device's alert token (best effort:
  /// the business notices keep working without it).
  Future<void> _registerCatalogueDevice() async {
    final alert = _tokens.values
        .where((t) => t['tokenType'] == 'alert')
        .firstOrNull;
    final token = alert?['token'] as String?;
    if (token == null) return;
    final key = '${session.account?.userId}:$token';
    if (_catalogueRegistered == key) return;
    try {
      await ApiClient.instance.post('/mobile/push/devices', {
        'deviceId': await _deviceId(),
        'token': token,
        'environment': alert!['environment'],
        'locale': 'he',
        'appVersion': appVersion,
      });
      _catalogueRegistered = key;
    } on Object {
      // Older server / offline: retried on the next resume.
    }
  }

  Future<void> _unregisterCatalogueDevice() async {
    _catalogueRegistered = null;
    try {
      final id = await _storage.read(key: _deviceIdKey);
      if (id == null) return;
      await ApiClient.instance.post('/mobile/push/devices/unregister', {
        'deviceId': id,
      });
    } on Object {
      // Best effort.
    }
  }

  Future<bool> _optedInAnywhere() async {
    final user = session.account?.userId;
    for (final b in session.businesses) {
      if (await _storage.read(key: 'system_notices_${user}_${b.businessId}') !=
          '0') {
        return true;
      }
    }
    return false;
  }

  @visibleForTesting
  Future<void> debugRegisterCatalogue(Map<String, Object?> alertToken) {
    _tokens['alert:'] = alertToken;
    return _registerCatalogueDevice();
  }

  @visibleForTesting
  Future<void> debugDisableCatalogue() => _unregisterCatalogueDevice();

  /// The server refuses push for a device token without MFA with a plain
  /// VALIDATION; that is not a connection problem and "retry" never helps.
  static ApiException pushRegistrationError(ApiException e) {
    if (e.code == 'VALIDATION' &&
        (e.serverMessage ?? '').contains('device credential')) {
      return ApiException(
        e.status,
        'PUSH_MFA_REQUIRED',
        errorMessageHe('PUSH_MFA_REQUIRED'),
        serverMessage: e.serverMessage,
      );
    }
    return e;
  }

  Future<String?> preview() => _channel.invokeMethod<String>('preview');
  Future<void> testLocal() => _channel.invokeMethod<void>('testLocal');
  Future<void> endAll() => _channel.invokeMethod<void>('endAll');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Also renew server registration TTL after returning to the app.
      _uploaded.clear();
      unawaited(refresh().catchError(_failure));
    }
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// Push on/off at start-up for one business (tester 2026-11-18: the
/// quote-accepted push never arrived because a fresh install/sign-in never
/// registered a token until the user found ניהול → התראות).
enum PushStartup { on, off, ask }

/// [stored]: '1' switched on, '0' switched off on purpose, null never chosen.
PushStartup pushStartup({
  required String? stored,
  required bool osAuthorized,
  required bool osDetermined,
}) {
  if (stored == '0') return PushStartup.off;
  if (osAuthorized) return PushStartup.on;
  // Never asked yet → ask once; asked and declined (or switched off in iOS
  // Settings) → off: the in-app switch explains how to turn it back on.
  return stored == null && !osDetermined ? PushStartup.ask : PushStartup.off;
}
