import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/customer_crm_api.dart';
import 'package:invoice/state/customer_crm_store.dart';

class Remote implements CustomerCrmRemote {
  final Map<String, CrmRemoteRecord> records = {};
  final Map<String, CrmRemoteRecord> acknowledged = {};
  bool offline = false;
  ApiException? Function(String customerId)? rejectWrite;
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
    final rejected = rejectWrite?.call(customerId);
    if (rejected != null) throw rejected;
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

  test('resume refresh updates records in place without clearing the screen', () async {
    final store = fresh();
    await store.loadForBusiness('a');
    await store.addNote('c1', 'mine');
    await store.sync();
    remote.records['c2'] = const CrmRemoteRecord(
      customerId: 'c2',
      revision: 1,
      record: {'stage': 'active', 'notes': [], 'jobs': [], 'reminders': []},
    );
    final loadedAtEachNotify = <bool>[];
    store.addListener(() => loadedAtEachNotify.add(store.isLoadedFor('a')));
    await store.refresh();
    expect(loadedAtEachNotify, isNotEmpty);
    expect(loadedAtEachNotify, everyElement(isTrue));
    expect(store.entryFor('c2').stage, CustomerCrmStage.active);
    expect(store.entryFor('c1').notes.single.text, 'mine');
  });

  test('an edit made while a refresh is loading is never dropped', () async {
    final store = fresh();
    await store.loadForBusiness('a');
    final refreshing = store.refresh();
    final editing = store.addNote('c1', 'typed during refresh');
    await Future.wait([refreshing, editing]);
    await store.sync();
    expect(store.entryFor('c1').notes.single.text, 'typed during refresh');
    expect(remote.records['c1']!.record['notes'], hasLength(1));
  });

  test(
    'a change the server refuses (4xx) moves to a backup and unblocks the queue',
    () async {
      final store = fresh();
      await store.loadForBusiness('a');
      remote.rejectWrite = (id) =>
          id == 'c1' ? ApiException(422, 'VALIDATION', 'bad') : null;
      await store.addNote('c1', 'refused');
      await store.addNote('c2', 'accepted');
      await store.sync();
      await store.sync();
      expect(store.pendingCount, 0);
      expect(store.rejectedCount, 1);
      expect(remote.records['c2']!.record['notes'], hasLength(1));
      expect(store.entryFor('c1').notes, isEmpty);
      final backup = disk['customer_crm_a_rejected']! as Map;
      expect((backup['items'] as List).single['code'], 'VALIDATION');
      store.acknowledgeRejected();
      expect(store.rejectedCount, 0);
    },
  );

  test('409 and 429 stay queued instead of being discarded', () async {
    final store = fresh();
    await store.loadForBusiness('a');
    remote.rejectWrite = (_) => ApiException(429, 'RATE_LIMITED', 'slow');
    await store.addNote('c1', 'later');
    await store.sync();
    expect(store.pendingCount, 1);
    expect(store.rejectedCount, 0);
  });

  test('one unreadable customer is quarantined, the rest still loads', () async {
    remote.offline = true;
    disk['customer_crm_a'] = {
      'customers': {
        'c1': {
          'stage': 'active',
          'notes': [],
          'jobs': [],
          'reminders': [],
        },
        'c2': {
          'jobs': [
            {'id': 'j1'},
          ],
        },
      },
      'pending': [
        {'broken': true},
      ],
      'cloudInitialized': true,
    };
    final store = fresh();
    await store.loadForBusiness('a');
    expect(store.isLoadedFor('a'), isTrue);
    expect(store.entryFor('c1').stage, CustomerCrmStage.active);
    expect(store.isQuarantined('c2'), isTrue);
    final quarantine = disk['customer_crm_a_quarantine']! as Map;
    expect((quarantine['customers'] as Map).keys, ['c2']);
    expect(quarantine['mutations'], hasLength(1));
    await expectLater(store.addNote('c2', 'x'), throwsStateError);
  });

  test('the legacy device file is marked as migrated to the first user', () async {
    remote.identity = 'user-one';
    disk['customer_crm_a'] = {
      'customers': {
        'c1': {
          'stage': 'lead',
          'notes': [
            {'id': 'n1', 'text': 'old', 'createdAt': '2026-01-01T00:00:00Z'},
          ],
          'jobs': [],
          'reminders': [],
        },
      },
    };
    final store = fresh();
    await store.loadForBusiness('a');
    expect((disk['customer_crm_a']! as Map)['migratedToUser'], 'user-one');
    expect(remote.records['c1']!.record['notes'], hasLength(1));
    remote.identity = 'user-two';
    remote.records.clear();
    final other = fresh();
    await other.loadForBusiness('a');
    expect(other.entryFor('c1').notes, isEmpty);
    expect(remote.records, isEmpty);
  });
}

class _Unavailable extends Remote {
  @override
  Future<List<CrmRemoteRecord>> load(String businessId) async =>
      throw ApiException(404, 'NOT_FOUND', 'missing');
}
