// ADR-SHAAM-DEGRADATION (server item 3): while the Tax Authority is down the server fails fast
// with SHAAM_SERVICE_UNAVAILABLE and the document view carries a calm notice + the next
// automatic retry. "נסה שוב" must not surface that as an error of the document.

import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/actions_api.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';

import '../fakes/fake_api.dart';

const _notice = 'רשות המסים אינה זמינה כרגע — המסמך שמור וממתין למספר הקצאה';

void main() {
  late FakeBackend backend;
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('allocation_degradation_test');
    AppCache.directoryProvider = () async => tmp;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    resetSession();
    backend = FakeBackend()..install();
    installActionsFakes(backend);
    await signInAs(backend, Preset.owner);
    await AppCache.clearAll();
  });

  test(
    'the view parses the degradation notice and the next automatic retry',
    () {
      final s = AllocationState.fromJson({
        'state': 'RETRYABLE_FAILURE',
        'degradation': {
          'noticeHe': _notice,
          'serviceState': 'OPEN',
          'nextAutoRetryAt': '2026-11-01T12:05:00.000Z',
          'autoRetryAttempts': 2,
          'autoRetryExhausted': false,
        },
      });
      expect(s.serviceNoticeHe, _notice);
      expect(s.nextAutoRetryAt, DateTime.utc(2026, 11, 1, 12, 5));
      // An older server without the field: nothing changes.
      final old = AllocationState.fromJson({'state': 'READY'});
      expect(old.serviceNoticeHe, isNull);
      expect(old.nextAutoRetryAt, isNull);
    },
  );

  test(
    '"נסה שוב" while the authority is down: no error, the calm notice comes back',
    () async {
      backend.error(
        'POST',
        '/documents/:id/allocation/request',
        503,
        'SHAAM_SERVICE_UNAVAILABLE',
      );
      backend.json('GET', '/documents/:id/allocation', {
        'state': 'RETRYABLE_FAILURE',
        'degradation': {
          'noticeHe': _notice,
          'serviceState': 'OPEN',
          'nextAutoRetryAt': null,
        },
      });
      final s = await retryAllocation('doc-1');
      expect(s.serviceNoticeHe, _notice);
      expect(
        backend.calls('POST', '/documents/:id/allocation/request'),
        hasLength(1),
      );
    },
  );

  test('other refusals still surface as errors', () async {
    backend.error(
      'POST',
      '/documents/:id/allocation/request',
      409,
      'SHAAM_AUTHORIZATION_REQUIRED',
    );
    await expectLater(retryAllocation('doc-1'), throwsA(isA<ApiException>()));
  });
}
