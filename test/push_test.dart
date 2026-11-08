// PUSH-001: the app side of push notifications — token registration, the one-time permission
// question, tapping a push, and the settings screen built from the server's catalogue.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/push/push_service.dart';
import 'package:invoice/screens/profile/notification_settings_screen.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';
import 'package:tevel_push/tevel_push.dart';

class MemoryStore implements PushStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// The iOS side of "tevel/push", answered in Dart.
class FakeIos {
  FakeIos(this.channel) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'authorizationStatus' => status,
        'requestPermission' => (status = grant ? 'authorized' : 'denied') == 'authorized',
        'register' => status == 'authorized',
        'apnsEnvironment' => 'sandbox',
        'initialNotification' => initial,
        'setBadge' => null,
        _ => null,
      };
    });
  }

  final MethodChannel channel;
  final List<String> calls = [];
  String status = 'notDetermined';
  bool grant = true;
  Map<String, Object?>? initial;

  /// iOS → Dart (e.g. onToken).
  Future<void> emit(String method, Object? args) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }
}

Widget app(Widget child) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: child,
);

void main() {
  final api = ApiClient.instance;
  late List<http.Request> sent;
  late FakeIos ios;
  late MemoryStore store;
  late PushService push;

  void respond(Object? Function(http.Request) body) {
    api.httpClient = MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(body(request)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  setUp(() {
    sent = [];
    store = MemoryStore();
    const channel = MethodChannel('tevel/push');
    ios = FakeIos(channel);
    push = PushService(platform: TevelPushPlatform(channel: channel), store: store);
    session.status = SessionStatus.signedIn;
    api.deviceToken = 'inv_${'a' * 64}';
    respond((_) => {'status': 'ok'});
  });

  test('a payload keeps only routing keys and text', () {
    final p = PushPayload.fromMap({'link': '/doc/1', 'kind': 'ITA_ALLOCATION_APPROVED', 'businessId': 'b1', 'x': 1});
    expect([p.link, p.kind, p.businessId], ['/doc/1', 'ITA_ALLOCATION_APPROVED', 'b1']);
  });

  test('the install id is created once and kept', () async {
    final first = await push.deviceId();
    expect(first, matches(RegExp(r'^ios-[a-z0-9]{24}$')));
    expect(await push.deviceId(), first);
  });

  testWidgets('an APNs token is sent to the server once, with the environment', (tester) async {
    ios.status = 'authorized';
    await push.start();
    expect(ios.calls, containsAll(['initialNotification', 'authorizationStatus', 'register', 'setBadge']));
    await ios.emit('onToken', 'ab' * 32);
    await tester.pump();
    await ios.emit('onToken', 'ab' * 32);
    await tester.pump();
    final registrations = sent.where((r) => r.url.path == '/mobile/push/devices').toList();
    expect(registrations, hasLength(1));
    final body = jsonDecode(registrations.single.body) as Map<String, dynamic>;
    expect(body['token'], 'ab' * 32);
    expect(body['environment'], 'sandbox');
    expect(body['deviceId'], await push.deviceId());
  });

  testWidgets('a tap before home exists (cold start, Face ID lock) waits for the shell', (tester) async {
    ios.initial = {'link': '/activity?chip=unpaid', 'kind': 'PAYMENTS_OVERDUE'};
    await push.start();
    expect(push.lastTap.value, isNull); // routeSignedIn would wipe a screen pushed now
    push.shellReady();
    await tester.pump();
    expect(push.lastTap.value?.link, '/activity?chip=unpaid');
    await ios.emit('onTap', {'link': '/doc/1'}); // once home is up, taps open at once
    await tester.pump();
    expect(push.lastTap.value?.link, '/doc/1');
  });

  testWidgets('after the first document: our explanation, then iOS — and never again', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox));
    final asking = push.maybeAskAfterIssue(context, waitingForTaxAuthority: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-primer')), findsOneWidget);
    expect(find.textContaining('רשות המסים עוד לא החזירה'), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-primer-yes')));
    await tester.pumpAndSettle();
    await asking;
    expect(ios.calls, contains('requestPermission'));
    ios.calls.clear();
    ios.status = 'notDetermined'; // even if iOS forgot, we asked once already
    await push.maybeAskAfterIssue(context, waitingForTaxAuthority: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-primer')), findsNothing);
    expect(ios.calls, isNot(contains('requestPermission')));
  });

  testWidgets('"not now" never shows the iOS dialog', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: SizedBox())));
    final context = tester.element(find.byType(SizedBox));
    final asking = push.enable(context);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('push-primer-no')));
    await tester.pumpAndSettle();
    expect(await asking, isFalse);
    expect(ios.calls, isNot(contains('requestPermission')));
  });

  testWidgets('settings: built from the catalogue; security stays on; a switch saves', (tester) async {
    ios.status = 'denied';
    respond((request) {
      if (request.url.path == '/mobile/push/catalogue') {
        return {
          'categories': [
            {'id': 'DOCUMENTS', 'label': 'מסמכים ורשות המסים', 'description': 'd', 'canDisable': true},
            {'id': 'CUSTOMERS', 'label': 'לקוחות', 'description': 'c', 'canDisable': true},
            {'id': 'SECURITY', 'label': 'אבטחה', 'description': 's', 'canDisable': false},
          ],
          'kinds': [
            {'id': 'QUOTE_VIEWED', 'category': 'CUSTOMERS', 'title': 'הלקוח צפה בהצעת המחיר', 'defaultOn': false},
            {'id': 'ITA_ALLOCATION_APPROVED', 'category': 'DOCUMENTS', 'title': 't', 'defaultOn': true},
          ],
        };
      }
      if (request.url.path == '/mobile/push/preferences' && request.method == 'GET') {
        return {'disabledCategories': <String>[], 'enabledKinds': <String>[], 'quietHours': true};
      }
      return jsonDecode(request.body);
    });
    await tester.pumpWidget(app(NotificationSettingsScreen(push: push)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-permission-card')), findsOneWidget);
    expect(find.text('פתח הגדרות'), findsOneWidget); // denied → iOS settings
    final security = tester.widget<SwitchListTile>(find.byKey(const Key('push-cat-SECURITY')));
    expect(security.onChanged, isNull);
    expect(find.byKey(const Key('push-kind-QUOTE_VIEWED')), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-cat-DOCUMENTS')));
    await tester.pumpAndSettle();
    final put = sent.lastWhere((r) => r.method == 'PUT');
    expect(jsonDecode(put.body), {
      'disabledCategories': ['DOCUMENTS'],
      'enabledKinds': <String>[],
      'quietHours': true,
    });
  });
}
