// Quote signatures: the hand-drawn signature pad + PNG export, /me/signature,
// the quote's "פרטי חתימה" parsing and section, the first-send prompt, and
// the QUOTE_SIGNED push (wording, routing, refresh).

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/documents_api.dart' show documentsVersion;
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/signature_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/document/quote_signature_section.dart';
import 'package:invoice/screens/signature/signature_screen.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

/// 1×1 transparent PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Map<String, dynamic> _quoteJson({Map<String, dynamic>? signature}) => {
  'quote': {
    'id': 'q1',
    'status': signature?['acceptance'] == null ? 'SENT' : 'ACCEPTED',
    'customerName': 'דנה',
    'totalMinor': '11800',
    'netMinor': '10000',
    'taxMinor': '1800',
    'currency': 'ILS',
  },
  'lines': const [],
  'signature': ?signature,
};

void main() {
  group('signature export', () {
    test('empty pad exports nothing', () async {
      expect(await exportSignaturePng(const []), isNull);
    });

    test(
      'strokes become a trimmed 600×200 PNG well under 200 KB with ink',
      () async {
        // A small scribble in the corner of a big pad: trimmed + scaled.
        final strokes = [
          [
            for (var i = 0; i <= 40; i++)
              Offset(300 + i * 2.0, 400 + 15 * (i.isEven ? 1 : -1)),
          ],
          [const Offset(310, 380)], // a dot
        ];
        final png = (await exportSignaturePng(strokes))!;
        expect(png.length, lessThan(maxSignaturePngBytes));
        expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 600);
        expect(image.height, 200);
        final rgba = (await image.toByteData())!;
        var inked = 0, minX = 600, maxX = 0;
        for (var y = 0; y < 200; y++) {
          for (var x = 0; x < 600; x++) {
            if (rgba.getUint8((y * 600 + x) * 4 + 3) > 0) {
              inked++;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
            }
          }
        }
        // Background transparent, ink present and spread over the width.
        expect(rgba.getUint8(3), 0);
        expect(inked, greaterThan(500));
        expect(maxX - minX, greaterThan(250));
      },
    );
  });

  group('quote signature parsing', () {
    test('older server: no signature', () {
      final q = Quote.fromJson(_quoteJson());
      expect(q.signature, isNull);
      expect(quoteSignedApproved(q), isFalse);
    });

    test('full signature with the customer drawing', () {
      final q = Quote.fromJson(
        _quoteJson(
          signature: {
            'sentBy': {'fullName': 'אייל כהן'},
            'sentAt': '2026-11-17T10:00:00Z',
            'handwritten': true,
            'digital': {
              'level': 'CERTIFIED',
              'certSubject': 'תבל בע״מ',
              'certSerial': '0A1B',
              'signedAt': '2026-11-17T10:00:01Z',
            },
            'acceptance': {
              'fullName': 'דנה לוי',
              'acceptedAt': '2026-11-17T12:30:00Z',
              'drawnSignaturePngBase64': _png,
            },
          },
        ),
      );
      final s = q.signature!;
      expect(s.sentByName, 'אייל כהן');
      expect(s.handwritten, isTrue);
      expect(s.digital!.level, 'CERTIFIED');
      expect(s.digital!.certSerial, '0A1B');
      expect(s.acceptance!.fullName, 'דנה לוי');
      expect(s.acceptance!.drawnSignaturePng, base64Decode(_png));
      expect(quoteSignedApproved(q), isTrue);
    });

    test('nulls and a missing customer drawing are tolerated', () {
      final q = Quote.fromJson(
        _quoteJson(
          signature: {
            'sentBy': null,
            'sentAt': null,
            'handwritten': false,
            'digital': null,
            'acceptance': {
              'fullName': 'דנה',
              'acceptedAt': '2026-11-17T12:30:00Z',
            },
          },
        ),
      );
      final s = q.signature!;
      expect(s.sentByName, isNull);
      expect(s.digital, isNull);
      expect(s.acceptance!.drawnSignaturePng, isNull);
      final bad = QuoteSignature.tryParse({
        'acceptance': {'fullName': 'x', 'drawnSignaturePngBase64': '%%%'},
      })!;
      expect(bad.acceptance!.drawnSignaturePng, isNull);
      expect(QuoteSignature.tryParse('nope'), isNull);
    });
  });

  group('screens', () {
    late FakeBackend backend;
    setUp(() async {
      backend = await eSetUp();
      final seen = <String>{};
      signaturePromptSeen = (name) async => seen.contains(name);
      markSignaturePromptSeen = (name) async => seen.add(name);
    });

    testWidgets('פרטי חתימה: waiting, then signed & approved', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(
          const Scaffold(
            body: QuoteSignatureSection(
              signature: QuoteSignature(
                sentByName: 'אייל כהן',
                sentAt: '2026-11-17T10:00:00Z',
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('אייל כהן'), findsOneWidget);
      expect(find.textContaining('לא נוספה'), findsOneWidget);
      expect(find.textContaining('לא נחתם דיגיטלית'), findsOneWidget);
      expect(find.textContaining('ממתין לאישור'), findsOneWidget);
      expect(find.byKey(const Key('sig-customer-drawn')), findsNothing);

      await tester.pumpWidget(
        eApp(
          Scaffold(
            body: QuoteSignatureSection(
              signature: QuoteSignature(
                sentByName: 'אייל כהן',
                sentAt: '2026-11-17T10:00:00Z',
                handwritten: true,
                digital: const QuoteDigitalSignature(
                  level: 'SECURE',
                  certSubject: 'תבל',
                  certSerial: '0A1B',
                  signedAt: '2026-11-17T10:00:01Z',
                ),
                acceptance: QuoteAcceptance(
                  fullName: 'דנה לוי',
                  acceptedAt: '2026-11-17T12:30:00Z',
                  drawnSignaturePng: base64Decode(_png),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('כלולה בהצעה'), findsOneWidget);
      expect(find.textContaining('מאובטחת'), findsOneWidget);
      expect(find.textContaining('0A1B'), findsOneWidget);
      expect(find.textContaining('דנה לוי'), findsOneWidget);
      expect(find.textContaining('ממתין לאישור'), findsNothing);
      expect(find.byKey(const Key('sig-customer-drawn')), findsOneWidget);
    });

    testWidgets('draw, save (PUT PNG), delete', (tester) async {
      phone(tester);
      backend.on(
        'GET',
        '/me/signature',
        (_) => FakeResponse.error(404, 'SIGNATURE_NOT_SET'),
      );
      backend.on(
        'PUT',
        '/me/signature',
        (r) => FakeResponse(200, {
          'imagePngBase64': r.body['imagePngBase64'],
          'updatedAt': '2026-11-17T10:00:00Z',
        }),
      );
      backend.on('DELETE', '/me/signature', (_) => const FakeResponse(204));
      await tester.pumpWidget(eApp(const SignatureScreen()));
      await settle(tester);
      expect(find.byKey(const Key('signature-none')), findsOneWidget);

      // Saving an empty pad sends nothing.
      await tester.tap(find.byKey(const Key('signature-save')));
      await settle(tester);
      expect(backend.calls('PUT', '/me/signature'), isEmpty);
      await tester.pump(const Duration(seconds: 6)); // the notice leaves
      await settle(tester);

      final pad = tester.getRect(find.byKey(const Key('signature-pad')));
      final g = await tester.startGesture(pad.center - const Offset(80, 0));
      for (var i = 1; i <= 16; i++) {
        await g.moveBy(Offset(10, i.isEven ? 12 : -12));
      }
      await g.up();
      await tester.pump();
      expect(find.text('חתמו כאן עם האצבע'), findsNothing);

      await tester.tap(find.byKey(const Key('signature-save')));
      await settle(tester);
      final sent = backend.last('PUT', '/me/signature')!.body;
      final bytes = base64Decode(sent['imagePngBase64'] as String);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(bytes.length, lessThan(maxSignaturePngBytes));
      expect(find.byKey(const Key('signature-saved')), findsOneWidget);

      await tester.tap(find.byKey(const Key('signature-delete')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('signature-delete-yes')));
      await settle(tester);
      expect(backend.calls('DELETE', '/me/signature'), hasLength(1));
      expect(find.byKey(const Key('signature-none')), findsOneWidget);
    });

    Future<bool?> runPrompt(WidgetTester tester) async {
      bool? result;
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await ensureSignatureBeforeSend(context),
                child: const Text('send'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('send'));
      await settle(tester);
      return result;
    }

    testWidgets('first send without a signature asks once', (tester) async {
      phone(tester);
      backend.on(
        'GET',
        '/me/signature',
        (_) => FakeResponse.error(404, 'SIGNATURE_NOT_SET'),
      );
      await runPrompt(tester);
      expect(find.text('הוסף חתימה'), findsOneWidget);
      await tester.tap(find.byKey(const Key('signature-prompt-skip')));
      await settle(tester);
      // Asked once: the next send goes straight through.
      final again = await runPrompt(tester);
      expect(find.text('הוסף חתימה'), findsNothing);
      expect(again, isTrue);
    });

    testWidgets('"הוסף חתימה" opens the pad, then the send continues', (
      tester,
    ) async {
      phone(tester);
      backend.on(
        'GET',
        '/me/signature',
        (_) => FakeResponse.error(404, 'SIGNATURE_NOT_SET'),
      );
      bool? result;
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await ensureSignatureBeforeSend(context),
                child: const Text('send'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('send'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('signature-prompt-add')));
      await settle(tester);
      expect(find.byType(SignatureScreen), findsOneWidget);
      navigatorKey.currentState!.pop();
      await settle(tester);
      expect(result, isTrue);
    });

    testWidgets('a saved signature or an older server never asks', (
      tester,
    ) async {
      phone(tester);
      backend.json('GET', '/me/signature', {
        'imagePngBase64': _png,
        'updatedAt': '2026-11-17T10:00:00Z',
      });
      expect(await runPrompt(tester), isTrue);
      expect(find.text('הוסף חתימה'), findsNothing);
      backend.on(
        'GET',
        '/me/signature',
        (_) => FakeResponse.error(404, 'NOT_FOUND'),
      );
      expect(await runPrompt(tester), isTrue);
      expect(find.text('הוסף חתימה'), findsNothing);
    });

    test('/me/signature client', () async {
      backend.on(
        'GET',
        '/me/signature',
        (_) => FakeResponse.error(404, 'SIGNATURE_NOT_SET'),
      );
      expect(await fetchMySignature(), isNull);
      backend.json('GET', '/me/signature', {
        'imagePngBase64': _png,
        'updatedAt': '2026-11-17T10:00:00Z',
      });
      expect((await fetchMySignature())!.png, base64Decode(_png));
      expect(
        () => saveMySignature(Uint8List(maxSignaturePngBytes + 1)),
        throwsArgumentError,
      );
    });
  });

  group('QUOTE_SIGNED push', () {
    test('says the customer approved (אישר), not signed', () {
      for (final kind in ['QUOTE_SIGNED', 'approved']) {
        final (text, motion) = systemNoticePresentation(kind)!;
        expect(text, contains('אישר'));
        expect(text, isNot(contains('חתם')));
        expect(motion, NoticeMotion.approved);
      }
    });

    test('its link opens the quote detail', () {
      final route = AppRoute.parse(
        '/quote/9f1c2d3e-aaaa-bbbb-cccc-000000000001',
      );
      expect(route, isNotNull);
      final screen = screenFor(route!) as DocumentScreen;
      expect(screen.isQuote, isTrue);
      expect(screen.id, '9f1c2d3e-aaaa-bbbb-cccc-000000000001');
    });

    test('arrival refreshes the quote list and the open quote', () {
      expect(
        SystemNotices.refreshesDocuments('QUOTE_SIGNED', '/quote/q1'),
        isTrue,
      );
      expect(SystemNotices.refreshesDocuments('approved', '/quote/q1'), isTrue);
      expect(
        SystemNotices.refreshesDocuments('bookingNew', '/calendar'),
        isFalse,
      );
      final before = documentsVersion.value;
      SystemNotices().debugEvent({
        'type': 'notice',
        'kind': 'QUOTE_SIGNED',
        'route': '/quote/q1',
        'businessId': 'b1',
      });
      expect(documentsVersion.value, before + 1);
      // Unknown kinds are ignored.
      SystemNotices().debugEvent({
        'type': 'notice',
        'kind': 'SOMETHING_NEW',
        'route': '/quote/q1',
        'businessId': 'b1',
      });
      expect(documentsVersion.value, before + 1);
    });
  });

  group('push catalogue (/mobile/push/devices)', () {
    late FakeBackend backend;
    setUp(() async => backend = await eSetUp());

    test('every catalogue kind has an amount-free in-app notice', () {
      for (final kind in const [
        'ITA_ALLOCATION_APPROVED',
        'ITA_ALLOCATION_REJECTED',
        'DOCUMENT_SEND_FAILED',
        'PAYMENT_RECEIVED',
        'PAYMENTS_OVERDUE',
        'COLLECTION_REMINDERS_READY',
        'QUOTE_SIGNED',
        'QUOTE_VIEWED',
        'TEAM_MEMBER_JOINED',
        'SUBSCRIPTION_RENEWS_SOON',
        'SUBSCRIPTION_PAYMENT_FAILED',
        'SUBSCRIPTION_EXPIRED',
        'EXPORT_READY',
        'EXPORT_FAILED',
        'NEW_DEVICE_LOGIN',
        'UPLOAD_BLOCKED',
      ]) {
        final p = systemNoticePresentation(kind);
        expect(p, isNotNull, reason: kind);
        expect(p!.$1, isNot(contains('₪')));
      }
    });

    test('catalogue links are app routes', () {
      for (final link in const [
        '/doc/d1',
        '/quote/q1',
        '/activity?chip=unpaid',
        '/debts?batch=1',
        '/business/team',
        '/business/account',
        '/reports',
        '/expenses',
      ]) {
        expect(AppRoute.parse(link), isNotNull, reason: link);
      }
    });

    test('a tapped catalogue push opens its link in its business', () {
      SystemNotices().debugEvent({
        'type': 'opened',
        'kind': 'PAYMENTS_OVERDUE',
        'route': '/activity?chip=unpaid',
        'businessId': 'b2',
      });
      expect(debugPendingDeepLink, '/activity?chip=unpaid&businessId=b2');
      // Account-level (no business): the current business.
      SystemNotices().debugEvent({
        'type': 'opened',
        'kind': 'NEW_DEVICE_LOGIN',
        'route': '/business/account',
        'businessId': '',
      });
      expect(debugPendingDeepLink, '/business/account');
    });

    test('registers the alert token once; unregisters by device id', () async {
      backend.json('POST', '/mobile/push/devices', {'status': 'ok', 'id': 'x'});
      backend.json('POST', '/mobile/push/devices/unregister', {
        'status': 'ok',
        'removed': true,
      });
      final notices = SystemNotices();
      final token = {
        'tokenType': 'alert',
        'token': 'ab' * 32,
        'environment': 'sandbox',
      };
      await notices.debugRegisterCatalogue(token);
      await notices.debugRegisterCatalogue(token);
      final calls = backend.calls('POST', '/mobile/push/devices');
      expect(calls, hasLength(1));
      final body = calls.single.body;
      expect(body['token'], 'ab' * 32);
      expect(body['environment'], 'sandbox');
      expect(body['deviceId'], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      // User-level route: no business header.
      expect(calls.single.raw.headers['X-Business-Id'], isNull);
      await notices.debugDisableCatalogue();
      expect(backend.last('POST', '/mobile/push/devices/unregister')!.body, {
        'deviceId': body['deviceId'],
      });
    });
  });
}
