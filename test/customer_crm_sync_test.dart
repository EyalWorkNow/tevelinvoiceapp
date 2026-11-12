import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/customer_crm_api.dart';
import 'package:invoice/state/customer_crm_store.dart';

class Remote implements CustomerCrmRemote {
  final Map<String, CrmRemoteRecord> records = {};
  final Map<String, CrmRemoteRecord> acknowledged = {};
  bool offline = false;
  @override
  bool get enabled => true;
  String? identity;
  @override
  String? get userId => identity;
  @override
  Future<List<CrmRemoteRecord>> load(String businessId) async {
    if (offline) throw ApiException(0, 'NETWORK', 'offline');
    return records.values.toList();
  }

  @override
  Future<CrmRemoteRecord> write(
    String businessId,
    String customerId,
    Map<String, Object?> record,
    int expectedRevision,
    String mutationId, {
    bool importLocal = false,
  }) async {
    if (offline) throw ApiException(0, 'NETWORK', 'offline');
    if (acknowledged.containsKey(mutationId)) return acknowledged[mutationId]!;
    final old = records[customerId];
    if (!importLocal && (old?.revision ?? 0) != expectedRevision) {
      throw ApiException(409, 'CRM_CONFLICT', 'conflict');
    }
    final saved = CrmRemoteRecord(
      customerId: customerId,
      revision: (old?.revision ?? 0) + 1,
      record: Map<String, dynamic>.from(jsonDecode(jsonEncode(record)) as Map),
    );
    records[customerId] = saved;
    acknowledged[mutationId] = saved;
    return saved;
  }
}

void main() {
  late Map<String, Object?> disk;
  late Remote remote;
  CustomerCrmStore fresh() => CustomerCrmStore(
    remote: remote,
    read: (key) async => disk[key],
    write: (key, value) async {
      disk[key] = jsonDecode(jsonEncode(value));
    },
  );
  setUp(() {
    disk = {};
    remote = Remote();
  });
  test(
    'records upload to the server and restore into a new device with no local cache',
    () async {
      final store = fresh();
      await store.loadForBusiness('a');
      await store.addNote('c1', 'server note');
      await store.sync();
      expect(store.pendingCount, 0);
      expect(remote.records['c1']!.record['notes'], hasLength(1));
      disk = {};
      final newDevice = fresh();
      await newDevice.loadForBusiness('a');
      expect(newDevice.entryFor('c1').notes.single.text, 'server note');
    },
  );
  test(
    'offline mutations persist with stable keys and flush in order after restart',
    () async {
      final store = fresh();
      await store.loadForBusiness('a');
      remote.offline = true;
      await store.addNote('c1', 'one');
      await store.sync();
      await store.addNote('c1', 'two');
      await store.sync();
      expect(store.pendingCount, 2);
      expect(store.syncError, isA<ApiException>());
      final saved = Map<String, dynamic>.from(disk['customer_crm_a']! as Map);
      final ids = [
        for (final item in saved['pending'] as List)
          (item as Map)['mutationId'],
      ];
      final restored = fresh();
      await restored.loadForBusiness('a');
      await restored.sync();
      expect(restored.pendingCount, 2);
      remote.offline = false;
      await restored.sync();
      expect(restored.pendingCount, 0);
      expect(remote.acknowledged.keys, containsAll(ids));
      expect(remote.records['c1']!.record['notes'], hasLength(2));
    },
  );
  test(
    'a concurrent device edit becomes a visible conflict and preserves local work',
    () async {
      final first = fresh();
      await first.loadForBusiness('a');
      await first.addNote('c1', 'first');
      await first.sync();
      final second = fresh();
      await second.loadForBusiness('a');
      await first.addNote('c1', 'from first');
      await first.sync();
      await second.addNote('c1', 'from second');
      await second.sync();
      expect(second.hasConflict, isTrue);
      expect(second.pendingCount, 1);
      expect(second.entryFor('c1').notes.first.text, 'from second');
      expect(
        (remote.records['c1']!.record['notes'] as List).first['text'],
        'from first',
      );
      await second.resolveConflict(keepDeviceVersion: false);
      expect(second.pendingCount, 0);
      expect(second.entryFor('c1').notes.first.text, 'from first');
      expect(disk.containsKey('customer_crm_a_conflict_backup'), isTrue);
    },
  );
  test(
    'choosing local version only replaces customers that have local pending changes',
    () async {
      final store = fresh();
      await store.loadForBusiness('a');
      remote.offline = true;
      await store.addNote('c1', 'local');
      await store.sync();
      remote.offline = false;
      remote.records['c1'] = const CrmRemoteRecord(
        customerId: 'c1',
        revision: 3,
        record: {'stage': 'lead', 'notes': [], 'jobs': [], 'reminders': []},
      );
      remote.records['c2'] = const CrmRemoteRecord(
        customerId: 'c2',
        revision: 1,
        record: {'stage': 'active', 'notes': [], 'jobs': [], 'reminders': []},
      );
      await store.sync();
      expect(store.hasConflict, isTrue);
      await store.resolveConflict(keepDeviceVersion: true);
      expect(store.pendingCount, 0);
      expect(remote.records['c1']!.revision, 4);
      expect(remote.records['c2']!.record['stage'], 'active');
    },
  );
  test('an offline queue cannot cross into another signed-in user', () async {
    remote.identity = 'user-one';
    final first = fresh();
    await first.loadForBusiness('a');
    await first.addNote('c1', 'shared');
    await first.sync();
    remote.offline = true;
    await first.addNote('c1', 'not uploaded yet');
    await first.sync();
    expect(first.pendingCount, 1);
    remote.identity = 'user-two';
    remote.offline = false;
    await first.sync();
    expect(first.pendingCount, 1);
    final other = fresh();
    await other.loadForBusiness('a');
    expect(other.pendingCount, 0);
    expect(other.entryFor('c1').notes, hasLength(1));
    expect(disk.containsKey('customer_crm_user-one_a'), isTrue);
    expect(disk.containsKey('customer_crm_user-two_a'), isTrue);
    remote.identity = 'user-one';
    final restored = fresh();
    await restored.loadForBusiness('a');
    await restored.sync();
    expect(restored.pendingCount, 0);
    expect(restored.entryFor('c1').notes, hasLength(2));
  });

  test(
    'a missing backend is shown as an error and never silently becomes local-only',
    () async {
      final failing = _Unavailable();
      final store = CustomerCrmStore(
        remote: failing,
        read: (_) async => null,
        write: (_, _) async {},
      );
      await store.loadForBusiness('a');
      expect(store.hasLoadErrorFor('a'), isTrue);
      await expectLater(
        store.addNote('c1', 'no fake success'),
        throwsStateError,
      );
    },
  );
}

class _Unavailable extends Remote {
  @override
  Future<List<CrmRemoteRecord>> load(String businessId) async =>
      throw ApiException(404, 'NOT_FOUND', 'missing');
}
