// §7 "קובץ מוגן בסיסמה" (V2): password logic, the card (copy + haptic +
// "הועתק"), the S6 toggle / "תמיד ללקוח הזה" / protected sends / the separate
// password message, and the document page's "נשלח מוגן · הצג סיסמה".

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/sheets/file_password.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/util/file_password.dart';
import 'package:invoice/util/sms_composer.dart';

import '../fakes/fake_api.dart';

Map<String, dynamic> protectionJson({
  bool available = true,
  bool always = false,
  List<Map<String, dynamic>> sends = const [],
}) => {
  'available': available,
  'customerId': 'cust-1',
  'customerAlwaysProtect': always,
  'sends': sends,
};

void main() {
  group('file password (pure logic)', () {
    test('8 characters from the unambiguous alphabet, never 0/O/1/I/L', () {
      final r = Random(7);
      for (var i = 0; i < 2000; i++) {
        final p = generateFilePassword(r);
        expect(p, hasLength(8));
        expect(isValidFilePassword(p), isTrue, reason: p);
        expect(p, isNot(matches(RegExp('[01OIL]'))));
      }
      expect(filePasswordAlphabet, isNot(contains('O')));
      expect(filePasswordAlphabet.length, 31);
    });

    test('a new password each time (secure random by default)', () {
      final seen = {for (var i = 0; i < 200; i++) generateFilePassword()};
      expect(seen.length, 200);
    });

    test('validation and the big-letters display', () {
      expect(isValidFilePassword('K7M4Q9P2'), isTrue);
      expect(isValidFilePassword('k7m4q9p2'), isFalse);
      expect(isValidFilePassword('K7M4Q9P'), isFalse);
      expect(isValidFilePassword('K7M4Q9P0'), isFalse);
      expect(displayFilePassword('K7M4Q9P2'), 'K7M4 Q9P2');
    });
  });

  late FakeBackend backend;
  late FakeLauncher launcher;
  late Directory tmp;
  final haptics = <String>[];

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('protected_file_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    installActionsFakes(backend);
    launcher = FakeLauncher()..install();
    haptics.clear();
    pdfSharer = (Uint8List bytes, String name, {String? text}) async {};
    backend.json('GET', '/tax-rates', {
      'rates': [
        {'tax_code': 'VAT', 'rate_basis_points': 1800},
      ],
    });
    await AppCache.clearAll();
  });

  tearDown(FakeLauncher.uninstall);

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(f);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await settle(tester);
  }

  void captureClipboardAndHaptics(WidgetTester tester, List<String> clip) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  Future<void> pumpDoc(
    WidgetTester tester, {
    Preset preset = Preset.owner,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => signInAs(backend, preset));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        home: const DocumentScreen(id: 'doc-1'),
      ),
    );
    await settle(tester);
  }

  Future<void> openShare(WidgetTester tester) async {
    await tap(tester, find.byTooltip('עוד'));
    await tap(tester, find.text('שתף'));
  }

  String cardPassword(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('file-password-text')))
      .data!
      .replaceAll(' ', '');

  testWidgets('FilePasswordCard: copy → clipboard, haptic, "הועתק"', (
    tester,
  ) async {
    final clip = <String>[];
    captureClipboardAndHaptics(tester, clip);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: FilePasswordCard(password: 'K7M4Q9P2')),
        ),
      ),
    );
    expect(find.text('K7M4 Q9P2'), findsOneWidget);
    expect(find.text('העתק'), findsOneWidget);
    await tester.tap(find.byKey(const Key('file-password-copy')));
    await tester.pump();
    expect(clip, ['K7M4Q9P2']);
    expect(haptics, isNotEmpty);
    expect(find.text('הועתק'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('העתק'), findsOneWidget);
  });

  testWidgets('S6 without server support: no toggle, sending unchanged', (
    tester,
  ) async {
    await pumpDoc(tester);
    await openShare(tester);
    expect(find.byKey(const Key('s6-whatsapp')), findsOneWidget);
    expect(find.byKey(const Key('s6-protect')), findsNothing);
  });

  testWidgets(
    'S6 toggle → card → copy link sends the same password → the password goes separately in WhatsApp',
    (tester) async {
      backend.json('GET', '/documents/:id/protection', protectionJson());
      await pumpDoc(tester);
      await openShare(tester);
      expect(find.byKey(const Key('s6-protect')), findsOneWidget);
      expect(find.byKey(const Key('file-password-card')), findsNothing);
      await tap(tester, find.byKey(const Key('s6-protect')));
      expect(find.byKey(const Key('file-password-card')), findsOneWidget);
      final password = cardPassword(tester);
      expect(isValidFilePassword(password), isTrue);
      // While protected: the automatic send and the "העתק נאמן" copy are not offered.
      await tap(tester, find.byKey(const Key('s6-more')));
      expect(find.byKey(const Key('s6-automatic')), findsNothing);
      expect(find.byKey(const Key('s6-pdf-copy')), findsNothing);

      await tap(tester, find.byKey(const Key('s6-copy')));
      final call = backend.last('POST', '/documents/:id/share-link')!;
      expect(call.body, {'protect': true, 'password': password});
      // The sheet stays: "send the password in a separate message".
      expect(find.byKey(const Key('s6-protected-sent')), findsOneWidget);
      expect(find.byKey(const Key('s6-password-panel')), findsOneWidget);
      expect(cardPassword(tester), password);

      await tap(tester, find.byKey(const Key('password-whatsapp')));
      final url = Uri.decodeFull(launcher.last.toString());
      expect(url, startsWith('https://wa.me/972501234567'));
      expect(url, contains(password));
      expect(url, isNot(contains('/d/'))); // never with the link

      await tap(tester, find.byKey(const Key('password-done')));
      expect(find.byKey(const Key('s6-password-panel')), findsNothing);
    },
  );

  testWidgets('S6 protected WhatsApp send: the link message has no password', (
    tester,
  ) async {
    backend.json('GET', '/documents/:id/protection', protectionJson());
    await pumpDoc(tester);
    await openShare(tester);
    await tap(tester, find.byKey(const Key('s6-protect')));
    final password = cardPassword(tester);
    await tap(tester, find.byKey(const Key('s6-whatsapp')));
    expect(
      backend.last('POST', '/documents/:id/share-link')!.body['password'],
      password,
    );
    final first = Uri.decodeFull(launcher.last.toString());
    expect(first, contains('/d/tok123'));
    expect(first, isNot(contains(password)));
    expect(find.byKey(const Key('password-whatsapp')), findsOneWidget);
  });

  testWidgets(
    'S6 protected e-mail carries protect + password; SMS sends it apart',
    (tester) async {
      final original = smsComposer;
      addTearDown(() => smsComposer = original);
      String? smsBody;
      smsComposer = (to, text) async {
        smsBody = text;
        return 'SENT';
      };
      backend.json('GET', '/documents/:id/protection', protectionJson());
      await pumpDoc(tester);
      await openShare(tester);
      await tap(tester, find.byKey(const Key('s6-protect')));
      final password = cardPassword(tester);
      await tap(tester, find.byKey(const Key('s6-more')));
      await tap(tester, find.byKey(const Key('s6-email')));
      await tap(tester, find.byKey(const Key('s6-email-send')));
      final body = backend.last('POST', '/documents/:id/send')!.body;
      expect(body['protect'], true);
      expect(body['password'], password);
      expect(find.text('המייל נשלח ✓'), findsOneWidget);
      await tap(tester, find.byKey(const Key('password-sms')));
      expect(smsBody, contains(password));
    },
  );

  testWidgets(
    '"תמיד ללקוח הזה": starts on, and the checkbox saves the setting',
    (tester) async {
      backend
        ..json('GET', '/documents/:id/protection', protectionJson(always: true))
        ..json('PUT', '/customers/:id/file-protection', {'always': false});
      await pumpDoc(tester);
      await openShare(tester);
      expect(find.byKey(const Key('file-password-card')), findsOneWidget);
      final box = find.byKey(const Key('s6-protect-always'));
      expect(tester.widget<CheckboxListTile>(box).value, isTrue);
      await tap(tester, box);
      final put = backend.last('PUT', '/customers/:id/file-protection')!;
      expect(put.params['id'], 'cust-1');
      expect(put.body, {'always': false});
      expect(tester.widget<CheckboxListTile>(box).value, isFalse);
      // Off → no password at all on the next send.
      await tap(tester, find.byKey(const Key('s6-protect')));
      expect(find.byKey(const Key('file-password-card')), findsNothing);
      await tap(tester, find.byKey(const Key('s6-copy')));
      expect(backend.last('POST', '/documents/:id/share-link')!.body, isEmpty);
    },
  );

  testWidgets('a new password each time the toggle is switched on', (
    tester,
  ) async {
    backend.json('GET', '/documents/:id/protection', protectionJson());
    await pumpDoc(tester);
    await openShare(tester);
    final seen = <String>{};
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byKey(const Key('s6-protect')));
      seen.add(cardPassword(tester));
      await tap(tester, find.byKey(const Key('s6-protect')));
    }
    expect(seen, hasLength(3));
  });

  testWidgets(
    'D: "נשלח מוגן · הצג סיסמה" reveals and offers the separate message',
    (tester) async {
      backend
        ..json(
          'GET',
          '/documents/:id/protection',
          protectionJson(
            sends: [
              {
                'id': 'ps-2',
                'channel': 'LINK',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'createdBy': 'u1',
                'recipient': null,
              },
            ],
          ),
        )
        ..json('POST', '/documents/:id/protection/:sendId/reveal', {
          'password': 'ABCD2345',
        });
      await pumpDoc(tester);
      expect(backend.calls('GET', '/documents/:id/protection'), isNotEmpty);
      await tester.scrollUntilVisible(
        find.byKey(const Key('doc-protected')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('doc-protected')), findsOneWidget);
      expect(find.text('נשלח מוגן · הצג סיסמה'), findsOneWidget);
      expect(find.textContaining('קישור מוגן · היום'), findsOneWidget);
      await tap(tester, find.byKey(const Key('doc-protected')));
      final reveal = backend.last(
        'POST',
        '/documents/:id/protection/:sendId/reveal',
      )!;
      expect(reveal.params['sendId'], 'ps-2');
      expect(find.text('ABCD 2345'), findsOneWidget);
      await tap(tester, find.byKey(const Key('password-whatsapp')));
      expect(Uri.decodeFull(launcher.last.toString()), contains('ABCD2345'));
    },
  );

  testWidgets('D: no protected sends → no row', (tester) async {
    backend.json('GET', '/documents/:id/protection', protectionJson());
    await pumpDoc(tester);
    expect(find.byKey(const Key('doc-protected')), findsNothing);
  });
}
