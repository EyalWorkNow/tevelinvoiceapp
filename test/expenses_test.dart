import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:invoice/api/client.dart';
import 'package:invoice/api/expenses_api.dart';

Uint8List _noise(int w, int h) {
  final r = Random(7);
  final image = img.Image(width: w, height: h);
  for (final px in image) {
    px.setRgb(r.nextInt(256), r.nextInt(256), r.nextInt(256));
  }
  return img.encodePng(image);
}

bool _isJpeg(Uint8List b) => b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

void main() {
  group('prepareExpenseJpeg', () {
    test('a small JPEG passes through untouched', () async {
      final jpeg = img.encodeJpg(img.Image(width: 40, height: 30));
      final out = await prepareExpenseJpeg(jpeg);
      expect(identical(out, jpeg), isTrue);
    });

    test(
      'PNG becomes JPEG (server rejects HEIC; we always send JPEG)',
      () async {
        final out = await prepareExpenseJpeg(_noise(64, 48));
        expect(_isJpeg(out), isTrue);
        final decoded = img.decodeJpg(out)!;
        expect((decoded.width, decoded.height), (64, 48));
      },
    );

    test('too big: resized and recompressed under the byte budget', () async {
      final out = await prepareExpenseJpeg(
        _noise(900, 600),
        maxBytes: 300 * 1024,
        maxSide: 800,
      );
      expect(_isJpeg(out), isTrue);
      expect(out.length, lessThanOrEqualTo(300 * 1024));
      final decoded = img.decodeJpg(out)!;
      expect(
        max(decoded.width, decoded.height),
        600,
      ); // 800 did not fit even at q55
    });

    test('undecodable bytes (e.g. HEIC) → ExpenseFileUnsupported', () async {
      final heicLike = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...ascii.encode('ftypheic'),
        1,
        2,
        3,
        4,
      ]);
      expect(
        () => prepareExpenseJpeg(heicLike),
        throwsA(isA<ExpenseFileUnsupported>()),
      );
    });
  });

  test('sha256Hex matches the standard vector', () {
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  group('uploadExpense', () {
    final api = ApiClient.instance;
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    late List<http.Request> sent;

    void serve(Map<String, http.Response Function(http.Request)> routes) {
      api.httpClient = MockClient((request) async {
        sent.add(request);
        final key = '${request.method} ${request.url.path}';
        final handler = routes[key];
        if (handler == null) fail('unexpected $key');
        return handler(request);
      });
    }

    http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    setUp(() {
      sent = [];
      api.clearCredentials();
      api.deviceToken = 'inv_tok';
      api.businessId = 'biz-1';
    });

    final initiateApi = json(201, {
      'uploadId': 'u1',
      'status': 'SCAN_PENDING',
      'expiresAt': '2026-10-30T05:00:00Z',
      'upload': {
        'kind': 'api',
        'method': 'PUT',
        'url': '/expenses/uploads/u1/bytes',
        'headers': {'Content-Type': 'image/jpeg'},
      },
    });

    test('initiate → PUT bytes → complete 202 → poll CLEAN', () async {
      var polls = 0;
      final stages = <ExpenseUploadStage>[];
      serve({
        'POST /expenses/uploads/initiate': (_) => initiateApi,
        'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
        'POST /expenses/uploads/u1/complete': (_) =>
            json(202, {'uploadId': 'u1', 'status': 'SCAN_PENDING'}),
        'GET /expenses/uploads/u1': (_) => ++polls < 2
            ? json(200, {'uploadId': 'u1', 'status': 'SCAN_PENDING'})
            : json(200, {
                'uploadId': 'u1',
                'status': 'CLEAN',
                'expenseId': 'e1',
              }),
      });
      final r = await uploadExpense(
        jpeg,
        filename: 'r.jpg',
        onStage: stages.add,
        pollEvery: Duration.zero,
      );
      expect(r.expenseId, 'e1');
      expect(r.duplicate, isFalse);
      expect(r.stillScanning, isFalse);
      expect(stages, [
        ExpenseUploadStage.uploading,
        ExpenseUploadStage.scanning,
      ]);

      final init = jsonDecode(sent.first.body) as Map<String, dynamic>;
      expect(init, {
        'filename': 'r.jpg',
        'contentType': 'image/jpeg',
        'sizeBytes': jpeg.length,
        'sha256': sha256Hex(jpeg),
      });
      final put = sent[1];
      expect(put.bodyBytes, jpeg);
      expect(put.headers['Content-Type'], 'image/jpeg');
      expect(put.headers['Authorization'], 'Bearer inv_tok');
      expect(put.headers['X-Business-Id'], 'biz-1');
    });

    test(
      'complete 201 with duplicate → done at once, duplicate flagged',
      () async {
        serve({
          'POST /expenses/uploads/initiate': (_) => initiateApi,
          'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
          'POST /expenses/uploads/u1/complete': (_) => json(201, {
            'expenseId': 'e2',
            'status': 'NEEDS_REVIEW',
            'duplicateOfExpenseId': 'e1',
            'uploadId': 'u1',
          }),
        });
        final r = await uploadExpense(jpeg, filename: 'r.jpg');
        expect(r.expenseId, 'e2');
        expect(r.duplicate, isTrue);
        expect(sent.length, 3);
      },
    );

    test(
      'malware: 422 SCANNER_INFECTED on complete, and REJECTED_MALWARE on poll',
      () async {
        serve({
          'POST /expenses/uploads/initiate': (_) => initiateApi,
          'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
          'POST /expenses/uploads/u1/complete': (_) =>
              json(422, {'error': 'SCANNER_INFECTED', 'message': 'x'}),
        });
        await expectLater(
          uploadExpense(jpeg, filename: 'r.jpg'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', 'SCANNER_INFECTED')
                .having((e) => e.messageHe, 'he', contains('נחסם')),
          ),
        );

        serve({
          'POST /expenses/uploads/initiate': (_) => initiateApi,
          'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
          'POST /expenses/uploads/u1/complete': (_) =>
              json(202, {'uploadId': 'u1', 'status': 'SCAN_PENDING'}),
          'GET /expenses/uploads/u1': (_) =>
              json(200, {'uploadId': 'u1', 'status': 'REJECTED_MALWARE'}),
        });
        await expectLater(
          uploadExpense(jpeg, filename: 'r.jpg', pollEvery: Duration.zero),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'SCANNER_INFECTED',
            ),
          ),
        );
      },
    );

    test(
      'scan still pending after the poll window → stillScanning (not an error)',
      () async {
        serve({
          'POST /expenses/uploads/initiate': (_) => initiateApi,
          'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
          'POST /expenses/uploads/u1/complete': (_) =>
              json(202, {'uploadId': 'u1', 'status': 'SCAN_PENDING'}),
          'GET /expenses/uploads/u1': (_) =>
              json(200, {'uploadId': 'u1', 'status': 'SCAN_PENDING'}),
        });
        final r = await uploadExpense(
          jpeg,
          filename: 'r.jpg',
          pollEvery: const Duration(milliseconds: 5),
          pollTimeout: const Duration(milliseconds: 30),
        );
        expect(r.stillScanning, isTrue);
      },
    );

    test('PDF: sent as-is with application/pdf', () async {
      final pdf = Uint8List.fromList([...ascii.encode('%PDF-1.7'), 1, 2, 3]);
      expect(isPdf(pdf), isTrue);
      expect(isPdf(jpeg), isFalse);
      serve({
        'POST /expenses/uploads/initiate': (_) => json(201, {
          'uploadId': 'u1',
          'status': 'SCAN_PENDING',
          'upload': {
            'kind': 'api',
            'method': 'PUT',
            'url': '/expenses/uploads/u1/bytes',
          },
        }),
        'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
        'POST /expenses/uploads/u1/complete': (_) => json(201, {
          'expenseId': 'e4',
          'status': 'NEEDS_REVIEW',
          'uploadId': 'u1',
        }),
      });
      final r = await uploadExpense(
        pdf,
        filename: 'r.pdf',
        contentType: 'application/pdf',
      );
      expect(r.expenseId, 'e4');
      final init = jsonDecode(sent.first.body) as Map<String, dynamic>;
      expect(init['contentType'], 'application/pdf');
      expect(init['sha256'], sha256Hex(pdf));
      expect(sent[1].bodyBytes, pdf);
      expect(sent[1].headers['Content-Type'], 'application/pdf');
    });

    test(
      'cancelled (screen closed) → polling stops, no more requests',
      () async {
        var polls = 0;
        var closed = false;
        serve({
          'POST /expenses/uploads/initiate': (_) => initiateApi,
          'PUT /expenses/uploads/u1/bytes': (_) => http.Response('', 204),
          'POST /expenses/uploads/u1/complete': (_) =>
              json(202, {'uploadId': 'u1', 'status': 'SCAN_PENDING'}),
          'GET /expenses/uploads/u1': (_) {
            polls++;
            closed = true;
            return json(200, {'uploadId': 'u1', 'status': 'SCAN_PENDING'});
          },
        });
        final r = await uploadExpense(
          jpeg,
          filename: 'r.jpg',
          cancelled: () => closed,
          pollEvery: Duration.zero,
        );
        expect(r.stillScanning, isTrue);
        expect(polls, 1);
      },
    );

    test(
      'signed upload target: plain PUT to storage, no app credentials',
      () async {
        serve({
          'POST /expenses/uploads/initiate': (_) => json(201, {
            'uploadId': 'u1',
            'status': 'SCAN_PENDING',
            'upload': {
              'kind': 'signed',
              'method': 'PUT',
              'url': 'https://storage.example/q/u1?sig=1',
              'headers': {'Content-Type': 'image/jpeg', 'x-upsert': 'false'},
            },
          }),
          'PUT /q/u1': (_) => http.Response('', 200),
          'POST /expenses/uploads/u1/complete': (_) => json(201, {
            'expenseId': 'e3',
            'status': 'NEEDS_REVIEW',
            'uploadId': 'u1',
          }),
        });
        final r = await uploadExpense(jpeg, filename: 'r.jpg');
        expect(r.expenseId, 'e3');
        final put = sent[1];
        expect(put.url.host, 'storage.example');
        expect(put.headers['x-upsert'], 'false');
        expect(put.headers.containsKey('Authorization'), isFalse);
        expect(put.headers.containsKey('X-Business-Id'), isFalse);
      },
    );
  });
}
