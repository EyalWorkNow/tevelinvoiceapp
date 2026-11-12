import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/client.dart';
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
  _ => null,
};

final systemNotices = SystemNotices();

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
  String? get problemHe => mfaRequired ? (syncError as ApiException).messageHe : null;

  /// Explicit sign-out: remove this device's push rows in every business it
  /// registered for, while the bearer is still valid (SessionController hook).
  Future<void> unregisterForSignOut() async {
    if (!supported) return;
    final user = session.account?.userId;
    for (final business in session.businesses) {
      final id = business.businessId;
      try {
        final opted =
            await _storage.read(key: 'system_notices_${user}_$id') == '1';
        if (opted) {
          await ApiClient.instance.deleteForBusiness(id, '/mobile/push-tokens');
        }
      } on Object {
        // Best effort per business; sign-out continues.
      }
    }
    _uploaded.clear();
  }

  Future<void> refresh() async {
    if (!supported || session.status != SessionStatus.signedIn) return;
    final generation = _generation;
    final optedIn = await _storage.read(key: _preferenceKey) == '1';
    final status = await _channel.invokeMapMethod<String, Object?>('status');
    if (generation != _generation) return;
    enabled = optedIn && status?['notifications'] == true;
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
    await _storage.delete(key: _preferenceKey);
    enabled = false;
    _uploaded.clear();
    await _channel.invokeMethod<void>('endAll');
    notifyListeners();
  }

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
    if (kind is! String ||
        route is! String ||
        business is! String ||
        AppRoute.parse(route) == null ||
        !isSafeId(business)) {
      return;
    }
    final presentation = systemNoticePresentation(kind);
    if (presentation == null) return;
    if (raw['type'] == 'opened') {
      final link = Uri(
        path: route,
        queryParameters: {'businessId': business},
      ).toString();
      unawaited(AppRouter.instance.openDeepLink(link).catchError(_failure));
      return;
    }
    if (session.status != SessionStatus.signedIn || business != _business) {
      return;
    }
    if (raw['type'] != 'notice') return;
    final id = raw['eventID'];
    if (id is String && id.isNotEmpty) {
      if (!_seen.add(id)) return;
      if (_seen.length > 100) _seen.remove(_seen.first);
    }
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
                ) ==
                '1';
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
    syncError = null;
    notifyListeners();
  }

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
