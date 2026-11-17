// "מסמך לחתימה" (server 0116): model parsing + editor geometry, the photo →
// PDF writer, the /sign-request/:id route and push presentation, and the
// list / editor / send / detail screens against the fake backend.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invoice/api/sign_requests_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/document/sheets/s6_share.dart' show textSharer;
import 'package:invoice/screens/sign/sign_common.dart';
import 'package:invoice/screens/sign/sign_editor_screen.dart';
import 'package:invoice/screens/sign/sign_request_screen.dart';
import 'package:invoice/screens/sign/sign_requests_screen.dart';
import 'package:invoice/screens/sign/sign_send_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/system_notices.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/image_to_pdf.dart';
import 'package:invoice/util/labels/sign_he.dart';

import 'fakes/fake_api.dart';

Widget app(Widget home) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

const id = 'a1b2c3d4-0000-4000-8000-000000000001';

Map<String, dynamic> viewJson({
  String status = 'DRAFT',
  List<Map<String, dynamic>> fields = const [],
  List<Map<String, dynamic>> events = const [],
}) => {
  'id': id,
  'title': 'הסכם שירות',
  'status': status,
  'signerName': 'רונית לוי',
  'signerEmail': 'ronit@example.test',
  'signerPhone': '050-1234567',
  'customerId': null,
  'message': null,
  'createdAt': '2026-11-17T08:00:00.000Z',
  'sentAt': status == 'DRAFT' ? null : '2026-11-17T08:05:00.000Z',
  'viewedAt': null,
  'completedAt': status == 'COMPLETED' ? '2026-11-17T09:00:00.000Z' : null,
  'expiresOn': '2026-12-17',
  'pageCount': 2,
  'pages': [
    {'width': 595, 'height': 842},
    {'width': 842, 'height': 595},
  ],
  'originalSha256': 'ab' * 32,
  'completedSha256': status == 'COMPLETED' ? 'cd' * 32 : null,
  'sealed': status == 'COMPLETED' ? false : null,
  'sealNote': null,
  'notifyOnView': false,
  'fields': fields,
  'events': events,
};

Map<String, dynamic> fieldJson({
  String kind = 'SIGNATURE',
  bool filled = false,
}) => {
  'id': 'f1',
  'pageIndex': 0,
  'kind': kind,
  'x': 0.1,
  'y': 0.8,
  'width': 0.36,
  'height': 0.08,
  'required': true,
  'label': 'חתימת הלקוח',
  'placeholder': null,
  'value': null,
  'filled': filled,
};

Uint8List tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 6, height: 8)));

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend()..install();
    loadSignPage = (_, _) async => tinyPng();
    loadSignRequests = fetchSignRequests;
    loadSignRequest = fetchSignRequest;
  });

  group('model', () {
    test('parses the view: status, pages, fields, events', () {
      final r = SignRequest.fromJson(
        viewJson(
          status: 'COMPLETED',
          fields: [fieldJson(filled: true)],
          events: [
            {
              'type': 'COMPLETED',
              'occurredAt': '2026-11-17T09:00:00.000Z',
              'ip': '203.0.113.9',
              'userAgent': 'Safari',
              'signerName': 'רונית לוי',
              'channel': null,
            },
          ],
        ),
      );
      expect(r.status, SignStatus.completed);
      expect(r.pageCount, 2);
      expect(r.page(1).aspect, closeTo(595 / 842, 1e-9));
      expect(r.page(9).aspect, closeTo(842 / 595, 1e-9)); // A4 fallback
      expect(r.fields.single.kind, SignFieldKind.signature);
      expect(r.fields.single.filled, isTrue);
      expect(r.events.single.ip, '203.0.113.9');
      expect(r.sealed, isFalse);
      expect(r.cancellable, isFalse);
    });

    test('every wire status / kind round-trips; unknown → safe default', () {
      for (final s in SignStatus.values) {
        expect(signStatusOf(signStatusWire(s)), s);
      }
      for (final k in SignFieldKind.values) {
        expect(signFieldKindOf(signFieldKindWire(k)), k);
      }
      expect(signStatusOf('WAT'), SignStatus.draft);
      expect(signFieldKindOf(null), SignFieldKind.signature);
    });

    test('placeAt centres on the tap and stays on the page', () {
      final f = SignField.placeAt(SignFieldKind.text, 0, 0.5, 0.5);
      expect(f.x + f.width / 2, closeTo(0.5, 1e-9));
      expect(f.y + f.height / 2, closeTo(0.5, 1e-9));
      // A tap in the bottom-right corner keeps the box inside.
      final c = SignField.placeAt(SignFieldKind.signature, 1, 0.99, 0.99);
      expect(c.x + c.width, lessThanOrEqualTo(1));
      expect(c.y + c.height, lessThanOrEqualTo(1));
      expect(c.pageIndex, 1);
      // Landscape page: the same field is taller in page-height units.
      final portrait = SignField.placeAt(SignFieldKind.signature, 0, .5, .5);
      final landscape = SignField.placeAt(
        SignFieldKind.signature,
        0,
        .5,
        .5,
        aspect: 595 / 842,
      );
      expect(landscape.height, greaterThan(portrait.height));
    });

    test('move / resize clamp to the page and the minimum size', () {
      const f = SignField(
        pageIndex: 0,
        kind: SignFieldKind.date,
        x: 0.7,
        y: 0.9,
        width: 0.2,
        height: 0.05,
      );
      final moved = f.moved(0.5, 0.5);
      expect(moved.x, closeTo(0.8, 1e-9));
      expect(moved.y, closeTo(0.95, 1e-9));
      expect(moved.width, 0.2);
      final left = f.moved(-5, -5);
      expect((left.x, left.y), (0.0, 0.0));
      final big = f.resized(1, 1);
      expect(big.x + big.width, closeTo(1, 1e-9));
      expect(big.y + big.height, closeTo(1, 1e-9));
      final tiny = f.resized(-1, -1);
      expect(tiny.width, minFieldSide);
      expect(tiny.height, minFieldSide);
    });

    test('normalized repairs NaN / out-of-range input', () {
      const bad = SignField(
        pageIndex: 0,
        kind: SignFieldKind.checkbox,
        x: double.nan,
        y: 2,
        width: 5,
        height: -1,
      );
      final n = bad.normalized();
      expect(n.width, 1);
      expect(n.height, minFieldSide);
      expect(n.x, 0);
      expect(n.y, closeTo(1 - minFieldSide, 1e-9));
    });

    test('toJson: wire kind, 4-decimal coords, trimmed labels', () {
      final j = const SignField(
        pageIndex: 2,
        kind: SignFieldKind.initials,
        x: 0.123456,
        y: 0.5,
        width: 0.14,
        height: 0.08,
        required: false,
        label: '  ',
        placeholder: 'ראשי תיבות',
      ).toJson();
      expect(j['kind'], 'INITIALS');
      expect(j['pageIndex'], 2);
      expect(j['x'], 0.1234);
      expect(j['required'], isFalse);
      expect(j['label'], isNull);
      expect(j['placeholder'], 'ראשי תיבות');
    });
  });

  group('photo → PDF', () {
    test('one page per JPEG, a valid xref', () {
      final jpeg = normalizeToJpeg(
        Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 400))),
      )!;
      expect(jpegSize(jpeg), (300, 400, 3));
      final pdf = jpegsToPdf([jpeg, jpeg]);
      final text = latin1.decode(pdf);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text, contains('/Count 2'));
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      final xref = int.parse(
        RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
      );
      expect(text.substring(xref, xref + 4), 'xref');
      final offsets = RegExp(
        r'(\d{10}) 00000 n',
      ).allMatches(text).map((m) => int.parse(m.group(1)!)).toList();
      expect(offsets, hasLength(2 + 3 * 2));
      for (var i = 0; i < offsets.length; i++) {
        expect(text.substring(offsets[i]), startsWith('${i + 1} 0 obj'));
      }
    });

    test('large photos shrink to maxScanSide; non-images are refused', () {
      final big = normalizeToJpeg(
        Uint8List.fromList(img.encodeJpg(img.Image(width: 4000, height: 1000))),
      )!;
      expect(jpegSize(big)!.$1, maxScanSide);
      expect(normalizeToJpeg(Uint8List.fromList([1, 2, 3])), isNull);
      expect(
        imagesToPdf([
          Uint8List.fromList([1, 2, 3]),
        ]),
        isNull,
      );
      expect(() => jpegsToPdf([Uint8List(4)]), throwsArgumentError);
    });
  });

  group('route + push', () {
    test('/sign-request/:id is a D view for document viewers', () {
      final r = AppRoute.parse('/sign-request/$id')!;
      expect(r.pattern, '/sign-request/:id');
      expect(r.screen, ScreenId.d);
      expect(r.requiredCap, Cap.docView);
      expect(screenFor(r), isA<SignRequestScreen>());
      expect(AppRoute.parse('tevel://sign-request/$id')?.params['id'], id);
      expect(AppRoute.parse('/sign-request/..%2Fx'), isNull);
    });

    test('both push kinds have a foreground notice', () {
      expect(
        systemNoticePresentation('signRequestCompleted')?.$1,
        'המסמך נחתם',
      );
      expect(systemNoticePresentation('signRequestViewed'), isNotNull);
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view
        ..physicalSize = const Size(1000, 2400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(home));
      await tester.pumpAndSettle();
    }

    testWidgets('list: rows, chips filter, empty state', (tester) async {
      backend.json('GET', '/sign-requests', {
        'items': [
          viewJson(status: 'COMPLETED'),
          {...viewJson(status: 'SENT'), 'id': 'b2', 'title': 'טופס הצטרפות'},
        ],
        'total': 2,
      });
      await pump(tester, const SignRequestsScreen());
      expect(find.text('הסכם שירות'), findsOneWidget);
      expect(find.text('טופס הצטרפות'), findsOneWidget);
      expect(find.text(SignHe.status(SignStatus.completed)), findsOneWidget);
      await tester.tap(find.byKey(const Key('sign-chip-waiting')));
      await tester.pumpAndSettle();
      expect(find.text('הסכם שירות'), findsNothing);
      expect(find.text('טופס הצטרפות'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sign-chip-drafts')));
      await tester.pumpAndSettle();
      expect(find.text(SignHe.emptyTitle), findsOneWidget);
    });

    testWidgets('new request: pick → title → upload → editor', (tester) async {
      backend.json('GET', '/sign-requests', {'items': [], 'total': 0});
      backend.json('POST', '/sign-requests', {
        'signRequest': viewJson(),
      }, status: 201);
      pickSignDocument = (_) async =>
          Uint8List.fromList(latin1.encode('%PDF-1.4\n%%EOF\n'));
      addTearDown(() => pickSignDocument = (_) async => null);
      await pump(tester, const SignRequestsScreen());
      await tester.tap(find.byKey(const Key('sign-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-source-pdf')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sign-title')), 'הסכם');
      await tester.tap(find.byKey(const Key('sign-title-ok')));
      await tester.pumpAndSettle();
      final post = backend.last('POST', '/sign-requests')!;
      expect(post.query['title'], 'הסכם');
      expect(post.headers['Content-Type'], 'application/pdf');
      expect(find.byType(SignEditorScreen), findsOneWidget);
    });

    testWidgets('editor: tap adds a field, drag moves it, save PUTs '
        'normalized fields and opens the send screen', (tester) async {
      backend.on('PUT', '/sign-requests/:id', (r) {
        return FakeResponse(200, {
          'signRequest': viewJson(
            fields: [
              for (final f in r.body['fields'] as List)
                {...(f as Map<String, dynamic>), 'id': 'f1', 'filled': false},
            ],
          ),
        });
      });
      await pump(
        tester,
        SignEditorScreen(request: SignRequest.fromJson(viewJson())),
      );
      await tester.tap(find.byKey(const Key('sign-kind-date')));
      await tester.pump();
      final page = find.byKey(const Key('sign-page-tap-0'));
      final box = tester.getRect(page);
      await tester.tapAt(box.center);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-field-0')), findsOneWidget);
      // Drag it 10% of the page width to the right.
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('sign-field-0'))),
      );
      for (var k = 0; k < 10; k++) {
        await g.moveBy(Offset(box.width * 0.01 + 4, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-editor-save')));
      await tester.pumpAndSettle();
      final sent = backend.last('PUT', '/sign-requests/:id')!.body;
      final f = (sent['fields'] as List).single as Map<String, dynamic>;
      expect(f['kind'], 'DATE');
      expect(f['pageIndex'], 0);
      final x = (f['x'] as num).toDouble();
      final w = (f['width'] as num).toDouble();
      expect(x + w / 2, closeTo(0.6, 0.03));
      expect(x + w, lessThanOrEqualTo(1));
      expect(find.byType(SignSendScreen), findsOneWidget);
    });

    testWidgets('editor: settings sheet deletes the selected field', (
      tester,
    ) async {
      await pump(
        tester,
        SignEditorScreen(
          request: SignRequest.fromJson(viewJson(fields: [fieldJson()])),
        ),
      );
      await tester.tap(find.byKey(const Key('sign-field-0'))); // select
      await tester.pump();
      await tester.tap(find.byKey(const Key('sign-field-0'))); // settings
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-field-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sign-field-0')), findsNothing);
    });

    testWidgets('send by WhatsApp: details PUT, send, wa.me 972…', (
      tester,
    ) async {
      final launcher = FakeLauncher()..install();
      backend.on(
        'PUT',
        '/sign-requests/:id',
        (_) => FakeResponse(200, {'signRequest': viewJson()}),
      );
      backend.json('POST', '/sign-requests/:id/send', {
        'url': 'https://app.example/s/tok',
        'signRequest': viewJson(status: 'SENT'),
      });
      backend.json('GET', '/sign-requests/:id', {
        'signRequest': viewJson(status: 'SENT'),
      });
      await pump(
        tester,
        SignSendScreen(
          request: SignRequest.fromJson(viewJson()),
          today: () => DateTime(2026, 11, 17),
        ),
      );
      await tester.tap(find.byKey(const Key('sign-notify-view')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sign-send-whatsapp')));
      await tester.pumpAndSettle();
      final put = backend.last('PUT', '/sign-requests/:id')!.body;
      expect(put['signerName'], 'רונית לוי');
      expect(put['expiresOn'], '2026-12-17');
      expect(put['notifyOnView'], isTrue);
      final send = backend.last('POST', '/sign-requests/:id/send')!.body;
      expect(send, {'channel': 'WHATSAPP', 'notifyOnView': true});
      expect(launcher.last!.host, 'wa.me');
      expect(launcher.last!.path, '/972501234567');
      expect(launcher.last!.queryParameters['text'], contains('/s/tok'));
      expect(find.byType(SignRequestScreen), findsOneWidget);
    });

    testWidgets('e-mail that did not go out falls back to sharing the link', (
      tester,
    ) async {
      final shared = <String>[];
      textSharer = (t) async => shared.add(t);
      backend.on(
        'PUT',
        '/sign-requests/:id',
        (_) => FakeResponse(200, {'signRequest': viewJson()}),
      );
      backend.json('POST', '/sign-requests/:id/send', {
        'url': 'https://app.example/s/tok',
        'emailed': false,
        'signRequest': viewJson(status: 'SENT'),
      });
      backend.json('GET', '/sign-requests/:id', {
        'signRequest': viewJson(status: 'SENT'),
      });
      await pump(
        tester,
        SignSendScreen(request: SignRequest.fromJson(viewJson())),
      );
      await tester.tap(find.byKey(const Key('sign-send-email')));
      await tester.pumpAndSettle();
      expect(
        backend.last('POST', '/sign-requests/:id/send')!.body['channel'],
        'EMAIL',
      );
      expect(shared.single, contains('/s/tok'));
      expect(find.byType(SignRequestScreen), findsOneWidget);
    });

    testWidgets('send by e-mail without an address is stopped on the phone', (
      tester,
    ) async {
      await pump(
        tester,
        SignSendScreen(
          request: SignRequest.fromJson({...viewJson(), 'signerEmail': null}),
        ),
      );
      await tester.tap(find.byKey(const Key('sign-send-email')));
      await tester.pumpAndSettle();
      expect(find.text(SignHe.emailRequired), findsOneWidget);
      expect(backend.calls('POST', '/sign-requests/:id/send'), isEmpty);
    });

    testWidgets('detail: audit trail, remind by share, cancel', (tester) async {
      final shared = <String>[];
      textSharer = (t) async => shared.add(t);
      backend.json('GET', '/sign-requests/:id', {
        'signRequest': viewJson(
          status: 'VIEWED',
          fields: [fieldJson()],
          events: [
            {
              'type': 'SENT',
              'occurredAt': '2026-11-17T08:05:00.000Z',
              'channel': 'EMAIL',
            },
            {
              'type': 'VIEWED',
              'occurredAt': '2026-11-17T08:30:00.000Z',
              'ip': '203.0.113.9',
            },
          ],
        ),
      });
      backend.json('POST', '/sign-requests/:id/remind', {
        'url': 'https://app.example/s/new',
        'emailed': false,
      });
      backend.on('POST', '/sign-requests/:id/cancel', (_) {
        final cancelled = {'signRequest': viewJson(status: 'CANCELLED')};
        backend.json('GET', '/sign-requests/:id', cancelled);
        return FakeResponse(200, cancelled);
      });
      await pump(tester, const SignRequestScreen(id: id));
      expect(find.text('${SignHe.event('SENT')} באימייל'), findsOneWidget);
      expect(find.textContaining('IP 203.0.113.9'), findsOneWidget);
      expect(find.text(SignHe.filledOf(0, 1)), findsOneWidget);
      await tester.tap(find.byKey(const Key('sign-remind')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-remind-share')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('/s/new'));
      await tester.tap(find.byKey(const Key('sign-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sign-cancel-yes')));
      await tester.pumpAndSettle();
      expect(backend.calls('POST', '/sign-requests/:id/cancel'), hasLength(1));
      expect(find.byKey(const Key('sign-cancel')), findsNothing);
      expect(find.text(SignHe.status(SignStatus.cancelled)), findsOneWidget);
    });

    testWidgets('a sign-request push refreshes the open detail', (
      tester,
    ) async {
      var status = 'SENT';
      backend.on(
        'GET',
        '/sign-requests/:id',
        (_) => FakeResponse(200, {'signRequest': viewJson(status: status)}),
      );
      await pump(tester, const SignRequestScreen(id: id));
      expect(find.text(SignHe.status(SignStatus.sent)), findsOneWidget);
      status = 'COMPLETED';
      notifySignRequestsChanged();
      await tester.pumpAndSettle();
      expect(find.text(SignHe.status(SignStatus.completed)), findsOneWidget);
      expect(find.byKey(const Key('sign-view-signed')), findsOneWidget);
    });
  });
}
