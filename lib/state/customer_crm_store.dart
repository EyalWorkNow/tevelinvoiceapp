import 'dart:async';

import 'package:flutter/widgets.dart';
import '../api/client.dart';
import '../api/customer_crm_api.dart';
import 'package:flutter/foundation.dart';

import 'cache.dart';
import 'customer_crm_job_budget.dart';

enum CustomerCrmStage {
  lead('ליד חדש'),
  quoteSent('הצעת מחיר נשלחה'),
  orderApproved('הזמנה אושרה'),
  active('לקוח פעיל');

  const CustomerCrmStage(this.label);

  final String label;

  static CustomerCrmStage fromJson(Object? value) =>
      CustomerCrmStage.values.firstWhere(
        (stage) => stage.name == value,
        orElse: () => CustomerCrmStage.lead,
      );
}

@immutable
class CustomerCrmNote {
  const CustomerCrmNote({
    required this.id,
    required this.text,
    required this.createdAt,
    this.updatedAt,
    this.pinned = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool pinned;

  factory CustomerCrmNote.create(String text) => CustomerCrmNote(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    text: text.trim(),
    createdAt: DateTime.now(),
  );

  CustomerCrmNote copyWith({String? text, DateTime? updatedAt, bool? pinned}) =>
      CustomerCrmNote(
        id: id,
        text: text ?? this.text,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
      );

  factory CustomerCrmNote.fromJson(Object? json) {
    final value = Map<String, dynamic>.from(json! as Map);
    return CustomerCrmNote(
      id:
          value['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      text: value['text'] as String? ?? '',
      createdAt:
          (DateTime.tryParse(value['createdAt'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .toLocal(),
      updatedAt: DateTime.tryParse(
        value['updatedAt'] as String? ?? '',
      )?.toLocal(),
      pinned: value['pinned'] as bool? ?? false,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'pinned': pinned,
    'createdAt': createdAt.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };
}

@immutable
class CustomerCrmReminder {
  const CustomerCrmReminder({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.title,
    required this.dueAt,
    this.completed = false,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String title;
  final DateTime dueAt;
  final bool completed;

  factory CustomerCrmReminder.create({
    required String customerId,
    required String customerName,
    required String title,
    required DateTime dueAt,
  }) => CustomerCrmReminder(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    customerId: customerId,
    customerName: customerName,
    title: title,
    dueAt: dueAt,
  );

  factory CustomerCrmReminder.fromJson(Object? json) {
    final value = Map<String, dynamic>.from(json! as Map);
    return CustomerCrmReminder(
      id: value['id'] as String? ?? '',
      customerId: value['customerId'] as String? ?? '',
      customerName: value['customerName'] as String? ?? '',
      title: value['title'] as String? ?? '',
      dueAt:
          (DateTime.tryParse(value['dueAt'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .toLocal(),
      completed: value['completed'] as bool? ?? false,
    );
  }

  CustomerCrmReminder copyWith({
    String? title,
    DateTime? dueAt,
    bool? completed,
  }) => CustomerCrmReminder(
    id: id,
    customerId: customerId,
    customerName: customerName,
    title: title ?? this.title,
    dueAt: dueAt ?? this.dueAt,
    completed: completed ?? this.completed,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'customerId': customerId,
    'customerName': customerName,
    'title': title,
    'dueAt': dueAt.toIso8601String(),
    'completed': completed,
  };
}

enum CustomerCrmJobStatus {
  scheduled('נקבעה'),
  active('בטיפול'),
  completed('הושלמה'),
  cancelled('בוטלה');

  const CustomerCrmJobStatus(this.label);
  final String label;
  bool get isOpen => this == scheduled || this == active;
}

@immutable
class CustomerCrmJob {
  const CustomerCrmJob({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.title,
    required this.scheduledAt,
    required this.createdAt,
    this.address = '',
    this.details = '',
    this.status = CustomerCrmJobStatus.scheduled,
    this.budget = const CustomerCrmJobBudget(),
    this.repeatEveryDays = 0,
    this.checklist = const [],
  });
  final String id;
  final String customerId;
  final String customerName;
  final String title;
  final String address;
  final String details;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final CustomerCrmJobStatus status;
  final CustomerCrmJobBudget budget;
  final int repeatEveryDays;
  final List<CustomerCrmChecklistItem> checklist;

  DateTime nextVisitAt(DateTime now) {
    final base = scheduledAt.isAfter(now) ? scheduledAt : now;
    return DateTime(
      base.year,
      base.month,
      base.day + (repeatEveryDays == 0 ? 7 : repeatEveryDays),
      scheduledAt.hour,
      scheduledAt.minute,
    );
  }

  factory CustomerCrmJob.create({
    required String customerId,
    required String customerName,
    required String title,
    required DateTime scheduledAt,
    String address = '',
    String details = '',
    CustomerCrmJobBudget budget = const CustomerCrmJobBudget(),
    int repeatEveryDays = 0,
    List<CustomerCrmChecklistItem> checklist = const [],
  }) => CustomerCrmJob(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    customerId: customerId,
    customerName: customerName,
    title: title.trim(),
    address: address.trim(),
    details: details.trim(),
    scheduledAt: scheduledAt,
    createdAt: DateTime.now(),
    budget: budget,
    repeatEveryDays: repeatEveryDays,
    checklist: List.unmodifiable(checklist),
  );

  CustomerCrmJob copyWith({
    String? title,
    String? address,
    String? details,
    DateTime? scheduledAt,
    CustomerCrmJobStatus? status,
    CustomerCrmJobBudget? budget,
    int? repeatEveryDays,
    List<CustomerCrmChecklistItem>? checklist,
  }) => CustomerCrmJob(
    id: id,
    customerId: customerId,
    customerName: customerName,
    title: title ?? this.title,
    address: address ?? this.address,
    details: details ?? this.details,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    createdAt: createdAt,
    status: status ?? this.status,
    budget: budget ?? this.budget,
    repeatEveryDays: repeatEveryDays ?? this.repeatEveryDays,
    checklist: List.unmodifiable(checklist ?? this.checklist),
  );

  factory CustomerCrmJob.fromJson(Object? json) {
    final value = Map<String, dynamic>.from(json! as Map);
    return CustomerCrmJob(
      id: value['id'] as String,
      customerId: value['customerId'] as String,
      customerName: value['customerName'] as String,
      title: value['title'] as String,
      address: value['address'] as String? ?? '',
      details: value['details'] as String? ?? '',
      scheduledAt: DateTime.parse(value['scheduledAt'] as String).toLocal(),
      createdAt: DateTime.parse(value['createdAt'] as String).toLocal(),
      budget: value['budget'] == null
          ? const CustomerCrmJobBudget()
          : CustomerCrmJobBudget.fromJson(value['budget'] as Map),
      repeatEveryDays: value['repeatEveryDays'] as int? ?? 0,
      checklist: value['checklist'] == null
          ? const []
          : List.unmodifiable(
              (value['checklist'] as List).map(
                (item) => CustomerCrmChecklistItem.fromJson(item as Map),
              ),
            ),
      status: CustomerCrmJobStatus.values.firstWhere(
        (status) => status.name == value['status'],
        orElse: () => CustomerCrmJobStatus.scheduled,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'customerId': customerId,
    'customerName': customerName,
    'title': title,
    'address': address,
    'details': details,
    'scheduledAt': scheduledAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'budget': budget.toJson(),
    'repeatEveryDays': repeatEveryDays,
    'checklist': checklist.map((item) => item.toJson()).toList(),
  };
}

@immutable
class CustomerCrmEntry {
  const CustomerCrmEntry({
    this.stage = CustomerCrmStage.lead,
    this.notes = const [],
    this.reminders = const [],
    this.jobs = const [],
  });

  final CustomerCrmStage stage;
  final List<CustomerCrmNote> notes;
  final List<CustomerCrmReminder> reminders;
  final List<CustomerCrmJob> jobs;

  factory CustomerCrmEntry.fromJson(Object? json) {
    final value = Map<String, dynamic>.from(json! as Map);
    final rawNotes = value['notes'];
    final rawReminders = value['reminders'];
    final rawJobs = value['jobs'];
    return CustomerCrmEntry(
      stage: CustomerCrmStage.fromJson(value['stage']),
      jobs: rawJobs is List
          ? rawJobs.map(CustomerCrmJob.fromJson).toList(growable: false)
          : const [],
      notes: rawNotes is List
          ? rawNotes
                .whereType<Map>()
                .map(CustomerCrmNote.fromJson)
                .toList(growable: false)
          : const [],
      reminders: rawReminders is List
          ? rawReminders
                .whereType<Map>()
                .map(CustomerCrmReminder.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  CustomerCrmEntry copyWith({
    CustomerCrmStage? stage,
    List<CustomerCrmNote>? notes,
    List<CustomerCrmReminder>? reminders,
    List<CustomerCrmJob>? jobs,
  }) => CustomerCrmEntry(
    stage: stage ?? this.stage,
    notes: notes ?? this.notes,
    reminders: reminders ?? this.reminders,
    jobs: jobs ?? this.jobs,
  );

  Map<String, Object?> toJson() => {
    'stage': stage.name,
    'notes': notes.map((note) => note.toJson()).toList(),
    'reminders': reminders.map((reminder) => reminder.toJson()).toList(),
    'jobs': jobs.map((job) => job.toJson()).toList(),
  };
}

/// Device-local CRM records. Writes commit to durable storage before updating UI.
class CustomerCrmStore extends ChangeNotifier with WidgetsBindingObserver {
  CustomerCrmStore({
    this.remote,
    Future<Object?> Function(String)? read,
    Future<void> Function(String, Object?)? write,
  }) : _read = read ?? _readLocal,
       _write = write ?? AppCache.writeUserData;

  static final CustomerCrmStore instance = CustomerCrmStore(
    remote: CustomerCrmApi(),
  );
  static Future<Object?> _readLocal(String name) =>
      AppCache.readUserData(name, strict: true);
  final Future<Object?> Function(String) _read;
  final Future<void> Function(String, Object?) _write;
  String? _businessId;
  Map<String, CustomerCrmEntry> _entries = {};
  bool _loaded = false;
  String? _loadingBusiness;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();
  int _generation = 0;
  Object? loadError;
  final CustomerCrmRemote? remote;
  Map<String, int> _revisions = {};
  List<_PendingCrmMutation> _pending = [];
  bool _cloudInitialized = false;
  bool _remoteWasEnabled = false;
  String? _credentialAtLoad;
  String? _loadedUserId;
  String? _storageKey;
  bool _previewLocal = false;
  bool _installed = false;
  Future<void>? _syncFuture;
  Set<String> _quarantined = {};
  int _rejectedCount = 0;
  int _localEdits = 0;
  Object? syncError;
  bool syncing = false;
  bool get remoteActive => !_previewLocal && (remote?.enabled ?? false);
  int get pendingCount => _pending.length;
  bool get readyForEdits => !remoteActive || _cloudInitialized;

  /// A stored record that could not be read is kept aside in
  /// `<key>_quarantine` and stays read-only, so it never overwrites the server.
  bool isQuarantined(String customerId) => _quarantined.contains(customerId);

  /// Changes the server refused for good (4xx), moved to `<key>_rejected`.
  int get rejectedCount => _rejectedCount;
  void acknowledgeRejected() {
    if (_rejectedCount == 0) return;
    _rejectedCount = 0;
    notifyListeners();
  }

  bool get hasConflict =>
      syncError is ApiException &&
      (syncError as ApiException).code == 'CRM_CONFLICT';

  /// Explicitly isolated showcase only. Production never falls back on a missing API route.
  void useDeviceLocalPreview() {
    assert(!kReleaseMode);
    if (kReleaseMode) throw StateError('Preview mode unavailable');
    _previewLocal = true;
  }

  void install() {
    if (_installed) return;
    _installed = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        remoteActive &&
        _businessId != null &&
        loadedForCurrentCredential) {
      unawaited(refresh());
    }
  }

  /// The loaded business belongs to the device token and user now signed in.
  /// After another member signs in on this device (no app restart) the store
  /// still holds the previous member's business; refreshing it on resume sent
  /// that business with the new token → 401 → the new member was signed out
  /// (business E2E AT-29 → AT-46). The screens load the current business.
  bool get loadedForCurrentCredential =>
      _credentialAtLoad == ApiClient.instance.deviceToken &&
      _loadedUserId == (remoteActive ? remote?.userId : null);

  /// Flushes the queue, then replaces records in place from the server. The
  /// loaded state is never cleared, and an edit made meanwhile always wins.
  Future<void> refresh() async {
    final business = _businessId;
    if (business == null || !remoteActive) return;
    if (!_loaded) {
      if (loadError != null) await loadForBusiness(business, force: true);
      return;
    }
    await sync();
    if (_businessId == business && _loaded && _pending.isEmpty) {
      await _reloadInPlace();
    }
  }

  /// Server records over the loaded ones: all of them, or only [only]
  /// (customers whose rejected changes must be undone on screen).
  Future<void> _reloadInPlace({Set<String>? only}) async {
    final business = _businessId, storageKey = _storageKey;
    if (business == null || storageKey == null || remote == null) return;
    final identity = _loadedUserId, generation = _generation;
    final edits = _localEdits;
    try {
      final server = await remote!.load(business);
      final result = _writes.then((_) async {
        if (_generation != generation ||
            remote?.userId != identity ||
            (only == null && (_localEdits != edits || _pending.isNotEmpty))) {
          return;
        }
        final quarantine = <String, Object?>{};
        final decoded = _decodeCustomers(
          server.map((item) => MapEntry(item.customerId, item.record)),
          quarantine,
        );
        final serverRevisions = {
          for (final item in server) item.customerId: item.revision,
        };
        final entries = Map<String, CustomerCrmEntry>.of(_entries);
        final revisions = Map<String, int>.of(_revisions);
        final quarantined = Set<String>.of(_quarantined);
        final ids = only ?? {...entries.keys, ...serverRevisions.keys};
        for (final id in ids) {
          if (_pending.any((item) => item.customerId == id)) continue;
          final entry = decoded[id];
          entry == null ? entries.remove(id) : entries[id] = entry;
          final revision = serverRevisions[id];
          revision == null ? revisions.remove(id) : revisions[id] = revision;
          quarantine.containsKey(id)
              ? quarantined.add(id)
              : quarantined.remove(id);
        }
        await _saveQuarantine(storageKey, quarantine, const []);
        await _write(
          storageKey,
          _snapshot(entries, revisions, _pending, _cloudInitialized),
        );
        if (_generation != generation) return;
        _entries = entries;
        _revisions = revisions;
        _quarantined = quarantined;
        if (only == null) syncError = null;
        notifyListeners();
      });
      _writes = result.catchError((Object _) {});
      await result;
    } on Object catch (error) {
      if (_generation == generation) {
        syncError = error;
        notifyListeners();
      }
    }
  }

  /// One unreadable customer must not block the whole CRM: it is skipped and
  /// returned in [quarantine] (raw), everything else loads.
  static Map<String, CustomerCrmEntry> _decodeCustomers(
    Iterable<MapEntry<Object?, Object?>> items,
    Map<String, Object?> quarantine,
  ) {
    final decoded = <String, CustomerCrmEntry>{};
    for (final item in items) {
      final key = item.key;
      try {
        if (key is! String || item.value is! Map) {
          throw const FormatException('Invalid CRM customer');
        }
        final entry = CustomerCrmEntry.fromJson(item.value);
        for (final job in entry.jobs) {
          _validateJob(key, job);
        }
        decoded[key] = entry;
      } on Object {
        quarantine['$key'] = item.value;
      }
    }
    return decoded;
  }

  Future<void> _saveQuarantine(
    String storageKey,
    Map<String, Object?> customers,
    List<Object?> pending,
  ) async {
    if (customers.isEmpty && pending.isEmpty) return;
    try {
      final name = '${storageKey}_quarantine';
      final old = await _read(name);
      final previous = old is Map && old['customers'] is Map
          ? Map<String, Object?>.from(old['customers'] as Map)
          : <String, Object?>{};
      final previousQueue = old is Map && old['mutations'] is List
          ? old['mutations'] as List
          : const <Object?>[];
      await _write(name, {
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'customers': {...previous, ...customers},
        'mutations': [...previousQueue, ...pending],
      });
    } on Object {
      // The copy is a courtesy; loading the readable records matters more.
    }
  }

  bool isLoadedFor(String businessId) => _businessId == businessId && _loaded;
  bool hasLoadErrorFor(String businessId) =>
      _businessId == businessId && loadError != null;

  /// Load failures are exposed through [loadError]; edits stay disabled until retry succeeds.
  Future<void> loadForBusiness(String businessId, {bool force = false}) {
    if (!force &&
        isLoadedFor(businessId) &&
        _remoteWasEnabled == remoteActive &&
        _credentialAtLoad == ApiClient.instance.deviceToken &&
        _loadedUserId == (remoteActive ? remote?.userId : null)) {
      return Future<void>.value();
    }
    if (_loadingBusiness == businessId && _loading != null) return _loading!;
    final generation = ++_generation;
    _businessId = businessId;
    _entries = {};
    _loaded = false;
    loadError = null;
    syncError = null;
    _loadingBusiness = businessId;
    notifyListeners();
    return _loading = _readBusiness(businessId, generation);
  }

  Future<void> _readBusiness(String businessId, int generation) async {
    final useRemote = remoteActive;
    final credential = ApiClient.instance.deviceToken;
    final userId = useRemote ? remote?.userId : null;
    final storageKey = _cacheKey(businessId, userId);
    try {
      await _writes;
      var raw = await _read(storageKey);
      Map? legacyRaw;
      if (raw == null && useRemote && userId != null) {
        final legacy = await _read(_cacheKey(businessId));
        if (legacy is Map &&
            legacy['migratedToUser'] == null &&
            (legacy['pending'] is! List ||
                (legacy['pending'] as List).isEmpty)) {
          raw = legacyRaw = legacy;
        }
      }
      var decoded = <String, CustomerCrmEntry>{};
      var revisions = <String, int>{};
      var pending = <_PendingCrmMutation>[];
      var initialized = false;
      final quarantine = <String, Object?>{};
      final badPending = <Object?>[];
      if (raw != null) {
        // A file that is not a CRM file at all stays a load error (edits
        // blocked, nothing overwritten); only single records are skipped.
        if (raw is! Map || raw['customers'] is! Map) {
          throw const FormatException('Invalid CRM records');
        } else {
          decoded = _decodeCustomers(
            (raw['customers'] as Map).entries,
            quarantine,
          );
          if (raw['revisions'] is Map) {
            revisions = {
              for (final item in (raw['revisions'] as Map).entries)
                if (item.key is String && item.value is int)
                  item.key as String: item.value as int,
            };
          }
          if (raw['pending'] is List) {
            for (final item in raw['pending'] as List) {
              try {
                pending.add(_PendingCrmMutation.fromJson(item));
              } on Object {
                badPending.add(item);
              }
            }
          }
          initialized = raw['cloudInitialized'] == true;
        }
      }
      await _saveQuarantine(storageKey, quarantine, badPending);
      var quarantined = quarantine.keys.toSet();
      if (useRemote && pending.isEmpty) {
        try {
          var server = await remote!.load(businessId);
          if (!initialized && decoded.isNotEmpty) {
            // Import is a merge by stable item id, never a blind overwrite of another device.
            for (final item in decoded.entries) {
              await remote!.write(
                businessId,
                item.key,
                item.value.toJson(),
                0,
                ApiClient.newIdempotencyKey(),
                importLocal: true,
              );
            }
            server = await remote!.load(businessId);
          }
          final serverQuarantine = <String, Object?>{};
          decoded = _decodeCustomers(
            server.map((item) => MapEntry(item.customerId, item.record)),
            serverQuarantine,
          );
          await _saveQuarantine(storageKey, serverQuarantine, const []);
          quarantined = serverQuarantine.keys.toSet();
          revisions = {
            for (final item in server) item.customerId: item.revision,
          };
          initialized = true;
          await _write(
            storageKey,
            _snapshot(decoded, revisions, pending, initialized),
          );
          // The unscoped pre-account file now belongs to this user only.
          if (legacyRaw != null) {
            await _write(_cacheKey(businessId), {
              ...legacyRaw,
              'migratedToUser': userId,
            });
          }
        } on ApiException catch (error) {
          // Only a network outage may use an existing cache; a missing/forbidden API is visible.
          if (!error.isNetwork || raw == null) rethrow;
          if (_generation == generation) syncError = error;
        }
      }
      if (_generation != generation) return;
      _entries = decoded;
      _revisions = revisions;
      _pending = pending;
      _quarantined = quarantined;
      _cloudInitialized = initialized;
      _remoteWasEnabled = useRemote;
      _credentialAtLoad = credential;
      _loadedUserId = userId;
      _storageKey = storageKey;
      _loaded = true;
    } on Object catch (error) {
      if (_generation != generation) return;
      loadError = error;
    }
    if (_generation != generation) return;
    _loadingBusiness = null;
    _loading = null;
    notifyListeners();
    if (_loaded && useRemote && _pending.isNotEmpty) unawaited(sync());
  }

  static Map<String, Object?> _snapshot(
    Map<String, CustomerCrmEntry> entries,
    Map<String, int> revisions,
    List<_PendingCrmMutation> pending,
    bool initialized,
  ) => {
    'version': 3,
    'customers': {
      for (final item in entries.entries) item.key: item.value.toJson(),
    },
    'revisions': revisions,
    'pending': pending.map((item) => item.toJson()).toList(),
    'cloudInitialized': initialized,
  };

  Future<void> sync() {
    if (!remoteActive || !_loaded || _businessId == null || _pending.isEmpty) {
      return Future.value();
    }
    return _syncFuture ??= _sync().whenComplete(() => _syncFuture = null);
  }

  Future<void> _sync() {
    final businessId = _businessId!;
    final storageKey = _storageKey!;
    final identity = _loadedUserId;
    final generation = _generation;
    final dropped = <String>{};
    final result = _writes.then((_) async {
      if (_generation != generation) return;
      syncing = true;
      syncError = null;
      notifyListeners();
      try {
        while (_pending.isNotEmpty &&
            _generation == generation &&
            remoteActive) {
          if (remote?.userId != identity) {
            throw StateError('CRM_ACCOUNT_CHANGED');
          }
          final pending = _pending.first;
          final CrmRemoteRecord saved;
          try {
            saved = await remote!.write(
              businessId,
              pending.customerId,
              pending.record,
              pending.expectedRevision,
              pending.mutationId,
            );
          } on ApiException catch (error) {
            if (!_isRejected(error)) rethrow;
            // A change the server refuses for good must not block the queue
            // forever: it (and later changes built on it) goes to a backup file.
            final rejected = [
              for (final item in _pending)
                if (item.customerId == pending.customerId) item,
            ];
            final remaining = [
              for (final item in _pending)
                if (item.customerId != pending.customerId) item,
            ];
            await _backupRejected(storageKey, rejected, error);
            await _write(
              storageKey,
              _snapshot(_entries, _revisions, remaining, true),
            );
            if (_generation != generation) return;
            _pending = remaining;
            _rejectedCount += rejected.length;
            dropped.add(pending.customerId);
            notifyListeners();
            continue;
          }
          if (_generation != generation || remote?.userId != identity) return;
          final remaining = _pending.skip(1).toList();
          final revisions = {..._revisions, pending.customerId: saved.revision};
          final entries = Map<String, CustomerCrmEntry>.of(_entries);
          if (!remaining.any((item) => item.customerId == pending.customerId)) {
            entries[pending.customerId] = CustomerCrmEntry.fromJson(
              saved.record,
            );
          }
          await _write(
            storageKey,
            _snapshot(entries, revisions, remaining, true),
          );
          if (_generation != generation) return;
          _entries = entries;
          _revisions = revisions;
          _pending = remaining;
          _cloudInitialized = true;
          notifyListeners();
        }
      } on Object catch (error) {
        if (_generation == generation) syncError = error;
      } finally {
        if (_generation == generation) {
          syncing = false;
          notifyListeners();
        }
      }
    });
    _writes = result.catchError((Object _) {});
    return result.then((_) async {
      if (dropped.isNotEmpty && _generation == generation) {
        await _reloadInPlace(only: dropped);
      }
    });
  }

  /// 4xx that no retry can fix. 401 (session), 408, 409 (conflict, the user
  /// chooses) and 429 stay queued.
  static bool _isRejected(ApiException error) =>
      error.status >= 400 &&
      error.status < 500 &&
      !const {401, 408, 409, 429}.contains(error.status);

  Future<void> _backupRejected(
    String storageKey,
    List<_PendingCrmMutation> rejected,
    ApiException error,
  ) async {
    final name = '${storageKey}_rejected';
    Object? old;
    try {
      old = await _read(name);
    } on Object {
      old = null;
    }
    final items = old is Map && old['items'] is List
        ? [...old['items'] as List]
        : <Object?>[];
    final at = DateTime.now().toUtc().toIso8601String();
    for (final item in rejected) {
      items.add({
        ...item.toJson(),
        'rejectedAt': at,
        'status': error.status,
        'code': error.code,
      });
    }
    await _write(name, {'items': items});
  }

  /// Explicit user choice after a conflict; only locally changed customer records are replaced.
  Future<void> resolveConflict({required bool keepDeviceVersion}) async {
    if (!remoteActive || _businessId == null || !hasConflict) return;
    final business = _businessId!, generation = _generation;
    final storageKey = _storageKey!;
    final identity = _loadedUserId;
    final result = _writes.then((_) async {
      if (remote?.userId != identity) throw StateError('CRM_ACCOUNT_CHANGED');
      final server = await remote!.load(business);
      if (_generation != generation) return;
      final entries = {
        for (final item in server)
          item.customerId: CustomerCrmEntry.fromJson(item.record),
      };
      final revisions = {
        for (final item in server) item.customerId: item.revision,
      };
      final affected = _pending.map((item) => item.customerId).toSet();
      final pending = <_PendingCrmMutation>[];
      if (keepDeviceVersion) {
        for (final id in affected) {
          final local = _entries[id]!;
          entries[id] = local;
          pending.add(
            _PendingCrmMutation(
              customerId: id,
              expectedRevision: revisions[id] ?? 0,
              mutationId: ApiClient.newIdempotencyKey(),
              record: local.toJson(),
            ),
          );
        }
      }
      // Preserve a local recovery snapshot before the user-selected version is applied.
      await _write(
        '${storageKey}_conflict_backup',
        _snapshot(_entries, _revisions, _pending, _cloudInitialized),
      );
      await _write(storageKey, _snapshot(entries, revisions, pending, true));
      if (_generation != generation) return;
      _entries = entries;
      _revisions = revisions;
      _pending = pending;
      _cloudInitialized = true;
      syncError = null;
      notifyListeners();
    });
    _writes = result.catchError((Object _) {});
    await result;
    await sync();
  }

  List<CustomerCrmJob> get jobs =>
      _entries.values.expand((entry) => entry.jobs).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  Future<void> setStage(String customerId, CustomerCrmStage stage) =>
      _updateEntry(customerId, (entry) => entry.copyWith(stage: stage));

  Future<void> addJob(String customerId, CustomerCrmJob job) =>
      _updateEntry(customerId, (entry) {
        _validateJob(customerId, job);
        return entry.copyWith(jobs: [...entry.jobs, job]);
      });

  Future<void> updateJob(String customerId, CustomerCrmJob job) =>
      _updateEntry(customerId, (entry) {
        _validateJob(customerId, job);
        if (!entry.jobs.any((value) => value.id == job.id)) {
          throw StateError('Job no longer exists');
        }
        return entry.copyWith(
          jobs: [
            for (final value in entry.jobs) value.id == job.id ? job : value,
          ],
        );
      });

  Future<void> setJobStatus(
    String customerId,
    String jobId,
    CustomerCrmJobStatus status,
  ) => _updateEntry(customerId, (entry) {
    if (!entry.jobs.any((job) => job.id == jobId)) {
      throw StateError('Job no longer exists');
    }
    return entry.copyWith(
      jobs: [
        for (final job in entry.jobs)
          job.id == jobId ? job.copyWith(status: status) : job,
      ],
    );
  });

  Future<void> deleteJob(String customerId, String jobId) => _updateEntry(
    customerId,
    (entry) => entry.copyWith(
      jobs: entry.jobs.where((job) => job.id != jobId).toList(),
    ),
  );

  Future<void> setChecklistCompleted(
    String customerId,
    String jobId,
    String itemId,
    bool done,
  ) => _updateEntry(customerId, (entry) {
    final index = entry.jobs.indexWhere((job) => job.id == jobId);
    if (index < 0 ||
        !entry.jobs[index].checklist.any((item) => item.id == itemId)) {
      throw StateError('Checklist item no longer exists');
    }
    final job = entry.jobs[index];
    final updated = job.copyWith(
      checklist: [
        for (final item in job.checklist)
          item.id == itemId
              ? CustomerCrmChecklistItem(
                  id: item.id,
                  text: item.text,
                  done: done,
                )
              : item,
      ],
    );
    return entry.copyWith(
      jobs: [
        for (final value in entry.jobs) value.id == jobId ? updated : value,
      ],
    );
  });

  static void _validateJob(String customerId, CustomerCrmJob job) {
    if (job.customerId != customerId ||
        job.title.trim().isEmpty ||
        job.title.length > 120 ||
        job.details.length > 1000 ||
        job.address.length > 250 ||
        !job.budget.isValid ||
        !const {0, 7, 14, 30, 90}.contains(job.repeatEveryDays) ||
        job.checklist.length > 20 ||
        job.checklist.map((item) => item.id).toSet().length !=
            job.checklist.length ||
        job.checklist.any(
          (item) =>
              item.id.isEmpty ||
              item.text.trim().isEmpty ||
              item.text.length > 120,
        )) {
      throw ArgumentError('Invalid CRM job');
    }
  }

  CustomerCrmEntry entryFor(String customerId) =>
      _entries[customerId] ?? const CustomerCrmEntry();

  List<CustomerCrmReminder> get reminders =>
      _entries.values.expand((entry) => entry.reminders).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  List<CustomerCrmReminder> remindersForCustomer(
    String customerId, {
    bool includeCompleted = true,
  }) {
    final values = entryFor(customerId).reminders;
    final filtered = includeCompleted
        ? values.toList()
        : values.where((reminder) => !reminder.completed).toList();
    filtered.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return filtered;
  }

  Future<void> addNote(String customerId, String text) {
    if (text.trim().isEmpty || text.trim().length > 2000) {
      return Future.error(ArgumentError('Invalid note'));
    }
    final note = CustomerCrmNote.create(text);
    return _updateEntry(customerId, (entry) {
      final notes = [note, ...entry.notes];
      return entry.copyWith(notes: notes);
    });
  }

  Future<void> updateNote(String customerId, String noteId, String text) =>
      _updateEntry(customerId, (entry) {
        if (text.trim().isEmpty || text.trim().length > 2000) {
          throw ArgumentError('Invalid note');
        }
        final notes = entry.notes
            .map(
              (note) => note.id == noteId
                  ? note.copyWith(text: text.trim(), updatedAt: DateTime.now())
                  : note,
            )
            .toList(growable: false);
        return entry.copyWith(notes: notes);
      });

  Future<void> deleteNote(String customerId, String noteId) => _updateEntry(
    customerId,
    (entry) => entry.copyWith(
      notes: entry.notes
          .where((note) => note.id != noteId)
          .toList(growable: false),
    ),
  );

  Future<void> setNotePinned(String customerId, String noteId, bool pinned) =>
      _updateEntry(customerId, (entry) {
        if (!entry.notes.any((note) => note.id == noteId)) {
          throw StateError('Note no longer exists');
        }
        return entry.copyWith(
          notes: [
            for (final note in entry.notes)
              note.id == noteId ? note.copyWith(pinned: pinned) : note,
          ],
        );
      });

  Future<void> rescheduleJob(String customerId, String jobId, DateTime date) =>
      _updateEntry(customerId, (entry) {
        final index = entry.jobs.indexWhere((job) => job.id == jobId);
        if (index < 0 || !entry.jobs[index].status.isOpen) {
          throw StateError('Only open jobs can be rescheduled');
        }
        return entry.copyWith(
          jobs: [
            for (final job in entry.jobs)
              job.id == jobId ? job.copyWith(scheduledAt: date) : job,
          ],
        );
      });

  Future<void> addReminder(String customerId, CustomerCrmReminder reminder) =>
      _updateEntry(
        customerId,
        (entry) => entry.copyWith(reminders: [...entry.reminders, reminder]),
      );

  Future<void> setReminderCompleted(
    String customerId,
    String reminderId,
    bool completed,
  ) => _updateEntry(customerId, (entry) {
    final reminders = entry.reminders
        .map(
          (reminder) => reminder.id == reminderId
              ? reminder.copyWith(completed: completed)
              : reminder,
        )
        .toList(growable: false);
    return entry.copyWith(reminders: reminders);
  });

  Future<void> updateReminder(
    String customerId,
    CustomerCrmReminder reminder,
  ) => _updateEntry(customerId, (entry) {
    final reminders = entry.reminders
        .map((item) => item.id == reminder.id ? reminder : item)
        .toList(growable: false);
    return entry.copyWith(reminders: reminders);
  });

  Future<void> deleteReminder(String customerId, String reminderId) =>
      _updateEntry(
        customerId,
        (entry) => entry.copyWith(
          reminders: entry.reminders
              .where((reminder) => reminder.id != reminderId)
              .toList(growable: false),
        ),
      );

  Future<void> _updateEntry(
    String customerId,
    CustomerCrmEntry Function(CustomerCrmEntry entry) update,
  ) {
    final businessId = _businessId;
    final storageKey = _storageKey;
    final generation = _generation;
    if (businessId == null || !_loaded) {
      return Future.error(StateError('CRM data is not loaded'));
    }
    final result = _writes.then((_) async {
      // Capture scope at enqueue time; never write a customer's data into a new business.
      if (_generation != generation || !_loaded) {
        throw StateError('CRM business changed before saving');
      }
      if (remoteActive && remote?.userId != _loadedUserId) {
        throw StateError('CRM_ACCOUNT_CHANGED');
      }
      if (remoteActive && !_cloudInitialized) {
        throw StateError('CRM_INITIAL_SYNC_REQUIRED');
      }
      if (_quarantined.contains(customerId)) {
        throw StateError('CRM_RECORD_QUARANTINED');
      }
      final next = Map<String, CustomerCrmEntry>.of(_entries)
        ..[customerId] = update(entryFor(customerId));
      final pending = [..._pending];
      if (remoteActive) {
        pending.add(
          _PendingCrmMutation(
            customerId: customerId,
            expectedRevision:
                (_revisions[customerId] ?? 0) +
                pending.where((item) => item.customerId == customerId).length,
            mutationId: ApiClient.newIdempotencyKey(),
            record: next[customerId]!.toJson(),
          ),
        );
      }
      await _write(
        storageKey!,
        _snapshot(next, _revisions, pending, _cloudInitialized),
      );
      if (_generation != generation) return;
      _entries = next;
      _pending = pending;
      _localEdits++;
      notifyListeners();
    });
    // Queue recovery only: the caller still receives and displays the failed save.
    _writes = result.catchError((Object _) {});
    unawaited(result.then((_) => sync()).catchError((Object _) {}));
    return result;
  }

  @override
  void dispose() {
    if (_installed) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static String _cacheKey(String businessId, [String? userId]) => userId == null
      ? 'customer_crm_$businessId'
      : 'customer_crm_${userId}_$businessId';
}

class _PendingCrmMutation {
  const _PendingCrmMutation({
    required this.customerId,
    required this.expectedRevision,
    required this.mutationId,
    required this.record,
  });
  final String customerId, mutationId;
  final int expectedRevision;
  final Map<String, Object?> record;
  factory _PendingCrmMutation.fromJson(Object? value) {
    final json = Map<String, dynamic>.from(value! as Map);
    return _PendingCrmMutation(
      customerId: json['customerId'] as String,
      expectedRevision: json['expectedRevision'] as int,
      mutationId: json['mutationId'] as String,
      record: Map<String, Object?>.from(json['record'] as Map),
    );
  }
  Map<String, Object?> toJson() => {
    'customerId': customerId,
    'expectedRevision': expectedRevision,
    'mutationId': mutationId,
    'record': record,
  };
}
