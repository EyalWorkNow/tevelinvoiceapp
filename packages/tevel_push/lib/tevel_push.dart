/// Dart side of the "tevel/push" channel (see ios/.../TevelPushPlugin.swift).
library;

import 'package:flutter/services.dart';

/// A push as the app sees it: routing keys + visible text. Never more.
class PushPayload {
  const PushPayload({this.link, this.kind, this.businessId, this.title, this.body});

  factory PushPayload.fromMap(Map<Object?, Object?> map) {
    String? s(String key) => map[key] is String ? map[key]! as String : null;
    return PushPayload(
      link: s('link'),
      kind: s('kind'),
      businessId: s('businessId'),
      title: s('title'),
      body: s('body'),
    );
  }

  final String? link;
  final String? kind;
  final String? businessId;
  final String? title;
  final String? body;
}

/// iOS notification permission states.
enum PushAuthorization { notDetermined, denied, authorized, provisional, unsupported }

/// Thin channel wrapper; replaceable in tests ([TevelPushPlatform.instance]).
class TevelPushPlatform {
  TevelPushPlatform({MethodChannel? channel}) : _channel = channel ?? const MethodChannel('tevel/push');

  static TevelPushPlatform instance = TevelPushPlatform();

  final MethodChannel _channel;
  void Function(String token)? onToken;
  void Function(String error)? onTokenError;
  void Function(PushPayload payload)? onMessage;
  void Function(PushPayload payload)? onTap;

  /// Starts listening; returns the push that launched the app (tap from a cold start), if any.
  Future<PushPayload?> start() async {
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'onToken':
          if (args is String) onToken?.call(args);
        case 'onTokenError':
          onTokenError?.call('$args');
        case 'onMessage':
          if (args is Map) onMessage?.call(PushPayload.fromMap(args));
        case 'onTap':
          if (args is Map) onTap?.call(PushPayload.fromMap(args));
      }
    });
    final initial = await _invoke<Map<Object?, Object?>>('initialNotification');
    return initial == null ? null : PushPayload.fromMap(initial);
  }

  Future<PushAuthorization> authorizationStatus() async {
    final name = await _invoke<String>('authorizationStatus');
    return PushAuthorization.values.firstWhere(
      (v) => v.name == name,
      orElse: () => PushAuthorization.unsupported,
    );
  }

  /// Shows the iOS permission dialog (once per install); true when allowed.
  Future<bool> requestPermission() async => await _invoke<bool>('requestPermission') ?? false;

  /// Re-registers with APNs when already allowed (a fresh token arrives via [onToken]).
  Future<bool> register() async => await _invoke<bool>('register') ?? false;

  Future<String> apnsEnvironment() async => await _invoke<String>('apnsEnvironment') ?? 'production';

  Future<void> setBadge(int count) => _invoke<void>('setBadge', count);

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // Android / tests without the plugin
    } on PlatformException {
      return null;
    }
  }
}
