import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/state/cache.dart';

void main() {
  late Directory directory;
  final original = AppCache.directoryProvider;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('crm-queue-cache');
    AppCache.directoryProvider = () async => directory;
  });
  tearDownAll(() async {
    AppCache.directoryProvider = original;
    if (directory.existsSync()) await directory.delete(recursive: true);
  });
  test(
    'unsynced CRM activates the sign-out warning and survives session expiry',
    () async {
      await AppCache.writeUserData('customer_crm_user_business', {
        'customers': {},
        'pending': [
          {'mutationId': 'queued'},
        ],
      });
      expect(await AppCache.hasPending(), isTrue);
      await AppCache.clearAll(keepPending: true);
      expect(
        await AppCache.readUserData('customer_crm_user_business'),
        isNotNull,
      );
      expect(await AppCache.hasPending(), isTrue);
    },
  );
  test(
    'synced CRM and conflict backups are not mistaken for pending work',
    () async {
      await AppCache.writeUserData('customer_crm_user_business', {
        'customers': {},
        'pending': [],
      });
      await AppCache.writeUserData(
        'customer_crm_user_business_conflict_backup',
        {
          'pending': [
            {'mutationId': 'old'},
          ],
        },
      );
      expect(await AppCache.hasPending(), isFalse);
      await AppCache.clearAll();
      expect(await AppCache.readUserData('customer_crm_user_business'), isNull);
    },
  );
}
