import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/state/customer_crm_store.dart';
import 'package:invoice/state/customer_crm_job_budget.dart';

void main() {
  late Map<String, Object?> disk;
  late CustomerCrmStore store;
  CustomerCrmStore fresh() => CustomerCrmStore(
    read: (key) async => disk[key],
    write: (key, value) async {
      disk[key] = jsonDecode(jsonEncode(value));
    },
  );
  setUp(() {
    disk = {};
    store = fresh();
  });

  test(
    'pinned notes survive restart and can be unpinned without editing text',
    () async {
      await store.loadForBusiness('a');
      await store.addNote('c1', 'קוד לשער');
      final note = store.entryFor('c1').notes.single;
      await store.setNotePinned('c1', note.id, true);
      final restored = fresh();
      await restored.loadForBusiness('a');
      expect(restored.entryFor('c1').notes.single.pinned, isTrue);
      expect(restored.entryFor('c1').notes.single.text, 'קוד לשער');
      await restored.setNotePinned('c1', note.id, false);
      expect(restored.entryFor('c1').notes.single.pinned, isFalse);
      await expectLater(
        restored.setNotePinned('c1', 'missing', true),
        throwsStateError,
      );
    },
  );

  test(
    'rescheduling preserves checklist and money during concurrent changes',
    () async {
      await store.loadForBusiness('a');
      final job = CustomerCrmJob.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'שירות',
        scheduledAt: DateTime(2026, 11, 10, 14, 30),
        budget: const CustomerCrmJobBudget(priceMinor: 50000),
        checklist: const [CustomerCrmChecklistItem(id: 'one', text: 'ציוד')],
      );
      await store.addJob('c1', job);
      final date = DateTime(2026, 11, 11, 14, 30);
      await Future.wait([
        store.rescheduleJob('c1', job.id, date),
        store.setChecklistCompleted('c1', job.id, 'one', true),
      ]);
      final restored = fresh();
      await restored.loadForBusiness('a');
      expect(restored.jobs.single.scheduledAt, date);
      expect(restored.jobs.single.budget.priceMinor, 50000);
      expect(restored.jobs.single.checklist.single.done, isTrue);
      await restored.setJobStatus('c1', job.id, CustomerCrmJobStatus.completed);
      await expectLater(
        restored.rescheduleJob('c1', job.id, date),
        throwsStateError,
      );
    },
  );

  test(
    'budget and checklist persist, including concurrent checklist changes',
    () async {
      await store.loadForBusiness('a');
      final job = CustomerCrmJob.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'תיקון',
        scheduledAt: DateTime(2026, 11, 9),
        budget: CustomerCrmJobBudget(
          priceMinor: 125050,
          costMinor: 25025,
          paidMinor: 20000,
          workMinutes: 120,
          paymentDueAt: DateTime(2026, 11, 10),
        ),
        repeatEveryDays: 14,
        checklist: const [
          CustomerCrmChecklistItem(id: 'a', text: 'ברז'),
          CustomerCrmChecklistItem(id: 'b', text: 'לחץ מים'),
        ],
      );
      await store.addJob('c1', job);
      await Future.wait([
        store.setChecklistCompleted('c1', job.id, 'a', true),
        store.setChecklistCompleted('c1', job.id, 'b', true),
      ]);
      final restored = fresh();
      await restored.loadForBusiness('a');
      final saved = restored.jobs.single;
      expect(saved.checklist.every((item) => item.done), isTrue);
      expect(saved.repeatEveryDays, 14);
      expect(saved.budget.toJson(), job.budget.toJson());
      await restored.updateJob(
        'c1',
        saved.copyWith(budget: const CustomerCrmJobBudget()),
      );
      final cleared = fresh();
      await cleared.loadForBusiness('a');
      expect(cleared.jobs.single.budget.priceMinor, isNull);
      expect(cleared.jobs.single.budget.paymentDueAt, isNull);
    },
  );

  test(
    'legacy jobs load with unknown finances and no invented payment',
    () async {
      final job = CustomerCrmJob.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'legacy',
        scheduledAt: DateTime(2026, 11, 9),
      );
      final legacy = job.toJson()
        ..remove('budget')
        ..remove('repeatEveryDays')
        ..remove('checklist');
      disk['customer_crm_a'] = {
        'version': 2,
        'customers': {
          'c1': {
            'jobs': [legacy],
          },
        },
      };
      await store.loadForBusiness('a');
      expect(store.jobs.single.budget.priceMinor, isNull);
      expect(store.jobs.single.budget.paidMinor, 0);
      expect(store.jobs.single.checklist, isEmpty);
      expect(store.jobs.single.repeatEveryDays, 0);
      expect(store.loadError, isNull);
    },
  );

  test(
    'invalid finances and missing checklist targets never overwrite a job',
    () async {
      await store.loadForBusiness('a');
      final job = CustomerCrmJob.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'visit',
        scheduledAt: DateTime.now(),
      );
      await store.addJob('c1', job);
      await expectLater(
        store.updateJob(
          'c1',
          job.copyWith(
            budget: const CustomerCrmJobBudget(priceMinor: 100, paidMinor: 101),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.updateJob('c1', job.copyWith(repeatEveryDays: -1)),
        throwsArgumentError,
      );
      await expectLater(
        store.setChecklistCompleted('c1', job.id, 'missing', true),
        throwsStateError,
      );
      expect(store.jobs.single.budget.priceMinor, isNull);
      expect(store.jobs.single.repeatEveryDays, 0);
    },
  );

  test(
    'notes persist across new store instances, including edits and deletion',
    () async {
      await store.loadForBusiness('a');
      await store.addNote('c1', '  קוד לשער 1234  ');
      final note = store.entryFor('c1').notes.single;
      await store.updateNote('c1', note.id, 'קוד חדש');
      final restored = fresh();
      await restored.loadForBusiness('a');
      expect(restored.entryFor('c1').notes.single.text, 'קוד חדש');
      expect(restored.entryFor('c1').notes.single.updatedAt, isNotNull);
      await restored.deleteNote('c1', note.id);
      final empty = fresh();
      await empty.loadForBusiness('a');
      expect(empty.entryFor('c1').notes, isEmpty);
    },
  );

  test(
    'jobs, status, reminders and customer stage survive serialization',
    () async {
      await store.loadForBusiness('a');
      final job = CustomerCrmJob.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'גיזום גינה',
        address: 'הרצל 12',
        details: 'להיכנס מהשער הצדדי',
        scheduledAt: DateTime(2026, 11, 10, 9, 30),
      );
      await store.addJob('c1', job);
      await store.updateJob('c1', job.copyWith(address: 'הרצל 14'));
      await store.setJobStatus('c1', job.id, CustomerCrmJobStatus.active);
      await store.setJobStatus('c1', job.id, CustomerCrmJobStatus.completed);
      final reminder = CustomerCrmReminder.create(
        customerId: 'c1',
        customerName: 'דנה',
        title: 'לוודא שההשקיה עובדת',
        dueAt: DateTime(2026, 11, 11),
      );
      await store.addReminder('c1', reminder);
      await store.setReminderCompleted('c1', reminder.id, true);
      await store.setStage('c1', CustomerCrmStage.active);
      final restored = fresh();
      await restored.loadForBusiness('a');
      final entry = restored.entryFor('c1');
      expect(entry.stage, CustomerCrmStage.active);
      expect(entry.jobs.single.status, CustomerCrmJobStatus.completed);
      expect(entry.jobs.single.address, 'הרצל 14');
      expect(entry.jobs.single.scheduledAt, job.scheduledAt);
      expect(entry.reminders.single.completed, isTrue);
      await restored.deleteJob('c1', job.id);
      expect(restored.jobs, isEmpty);
    },
  );

  test(
    'parallel actions are serialized without overwriting one another',
    () async {
      await store.loadForBusiness('a');
      await Future.wait([
        store.addNote('c1', 'אחד'),
        store.addNote('c1', 'שניים'),
        store.addNote('c2', 'לקוח אחר'),
        store.setStage('c1', CustomerCrmStage.quoteSent),
      ]);
      final restored = fresh();
      await restored.loadForBusiness('a');
      expect(
        restored.entryFor('c1').notes.map((n) => n.text),
        containsAll(['אחד', 'שניים']),
      );
      expect(restored.entryFor('c1').stage, CustomerCrmStage.quoteSent);
      expect(restored.entryFor('c2').notes.single.text, 'לקוח אחר');
    },
  );

  test(
    'failed disk writes leave the UI unchanged and do not poison later saves',
    () async {
      var fail = true;
      store = CustomerCrmStore(
        read: (key) async => disk[key],
        write: (key, value) async {
          if (fail) throw FileSystemLikeFailure();
          disk[key] = value;
        },
      );
      await store.loadForBusiness('a');
      await expectLater(
        store.addNote('c1', 'not committed'),
        throwsA(isA<FileSystemLikeFailure>()),
      );
      expect(store.entryFor('c1').notes, isEmpty);
      fail = false;
      await store.addNote('c1', 'committed');
      expect(store.entryFor('c1').notes.single.text, 'committed');
    },
  );

  test(
    'a business switch never redirects a queued save to the new business',
    () async {
      final started = Completer<void>(), finish = Completer<void>();
      store = CustomerCrmStore(
        read: (key) async => disk[key],
        write: (key, value) async {
          started.complete();
          await finish.future;
          disk[key] = value;
        },
      );
      await store.loadForBusiness('a');
      final first = store.addNote('c1', 'belongs to a');
      await started.future;
      final queued = store.addNote('c1', 'cancel queued');
      final rejected = expectLater(queued, throwsStateError);
      final changed = store.loadForBusiness('b');
      finish.complete();
      await Future.wait([first, rejected, changed]);
      expect(store.isLoadedFor('b'), isTrue);
      expect(store.entryFor('c1').notes, isEmpty);
      expect(disk.containsKey('customer_crm_b'), isFalse);
      final restored = fresh();
      await restored.loadForBusiness('a');
      expect(restored.entryFor('c1').notes.single.text, 'belongs to a');
    },
  );

  test('A to B to A waits for A pending writes before reloading it', () async {
    final started = Completer<void>(), finish = Completer<void>();
    store = CustomerCrmStore(
      read: (key) async => disk[key],
      write: (key, value) async {
        started.complete();
        await finish.future;
        disk[key] = value;
      },
    );
    await store.loadForBusiness('a');
    final saving = store.addNote('c1', 'fresh value');
    await started.future;
    final b = store.loadForBusiness('b'), a = store.loadForBusiness('a');
    finish.complete();
    await Future.wait([saving, b, a]);
    expect(store.isLoadedFor('a'), isTrue);
    expect(store.entryFor('c1').notes.single.text, 'fresh value');
  });

  test(
    'corrupt records block writes and recover on retry without erasing data',
    () async {
      disk['customer_crm_a'] = {'customers': 'broken'};
      await store.loadForBusiness('a');
      expect(store.hasLoadErrorFor('a'), isTrue);
      await expectLater(store.addNote('c1', 'overwrite'), throwsStateError);
      expect(disk['customer_crm_a'], {'customers': 'broken'});
      disk['customer_crm_a'] = {
        'version': 1,
        'customers': {
          'c1': {
            'notes': [
              {
                'id': 'n1',
                'text': 'legacy note',
                'createdAt': '2026-11-01T09:00:00',
              },
            ],
          },
        },
      };
      await store.loadForBusiness('a');
      expect(store.entryFor('c1').notes.single.text, 'legacy note');
      expect(store.entryFor('c1').jobs, isEmpty);
      expect(store.loadError, isNull);
    },
  );

  test(
    'existing notes are not silently truncated when adding another note',
    () async {
      disk['customer_crm_a'] = {
        'version': 1,
        'customers': {
          'c1': {
            'notes': [
              for (var i = 0; i < 105; i++)
                {
                  'id': 'n$i',
                  'text': 'note $i',
                  'createdAt': '2026-11-01T09:00:00',
                },
            ],
          },
        },
      };
      await store.loadForBusiness('a');
      await store.addNote('c1', 'new note');
      expect(store.entryFor('c1').notes, hasLength(106));
    },
  );

  test(
    'empty notes and jobs for another customer are rejected before commit',
    () async {
      await store.loadForBusiness('a');
      await expectLater(store.addNote('c1', '   '), throwsArgumentError);
      final job = CustomerCrmJob.create(
        customerId: 'c2',
        customerName: 'other',
        title: 'visit',
        scheduledAt: DateTime.now(),
      );
      await expectLater(store.addJob('c1', job), throwsArgumentError);
      expect(disk, isEmpty);
    },
  );
}

class FileSystemLikeFailure implements Exception {}
