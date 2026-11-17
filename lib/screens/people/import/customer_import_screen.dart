// ייבוא לקוחות (customer import) — from the לקוחות tab (header ⋯ and the empty state).
// Owner / partner only (Cap.customerImport; the server enforces the same rule).
//
//   source → (contacts: multi-select | file: column mapping) → review (validation +
//   duplicates, skip / fill-empty / create anyway, fix a row) → import in chunks → summary
//   (נוספו · עודכנו · דולגו · שגיאות + shareable error list).
//
// The file is parsed by the server (UTF-8 / Windows-1255 CSV, xlsx); the app only maps
// columns. Chunks carry one import id, so "נסה שוב" after a dropped connection resumes
// without duplicating anyone.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/client.dart';
import '../../../api/customer_import_api.dart';
import '../../../api/customers_api.dart';
import '../../../ui/ds.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/errors_he.dart';
import '../../../util/labels/common_he.dart';
import '../../../util/labels/customer_import_he.dart';
import '../../../util/phone.dart';

/// A picked file (name keeps the extension the server needs).
class PickedImportFile {
  const PickedImportFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// The system document picker (Files, iCloud Drive, files saved from WhatsApp / mail).
/// Tests replace it.
Future<PickedImportFile?> Function() pickImportFile = _nativePickFile;

Future<PickedImportFile?> _nativePickFile() async {
  final r = await const MethodChannel(
    'tevel/pdf_picker',
  ).invokeMethod<Map<Object?, Object?>>('pickSpreadsheet');
  if (r == null) return null;
  return PickedImportFile('${r['name']}', r['bytes']! as Uint8List);
}

/// All contacts the user shares with the app; null = permission denied. Tests replace it.
Future<List<DeviceContact>?> Function() loadDeviceContacts = _nativeContacts;

Future<List<DeviceContact>?> _nativeContacts() async {
  const channel = MethodChannel('tevel/contacts_permission');
  final allowed = await channel.invokeMethod<bool>('requestAccess') ?? false;
  if (!allowed) return null;
  final list =
      await channel.invokeMethod<List<Object?>>('fetchAll') ?? const [];
  return [
    for (final m in list)
      if (m is Map) DeviceContact.fromMap(m),
  ];
}

/// Shares a generated file (error list). Tests replace it.
Future<void> Function(Uint8List bytes, String name, String mime)
shareImportFile = _shareFile;

Future<void> _shareFile(Uint8List bytes, String name, String mime) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path, mimeType: mime)]),
  );
}

enum _Step { source, contacts, mapping, review, running, summary }

enum _Filter { fresh, duplicates, errors }

class CustomerImportScreen extends StatefulWidget {
  const CustomerImportScreen({super.key});

  @override
  State<CustomerImportScreen> createState() => _CustomerImportScreenState();
}

class _CustomerImportScreenState extends State<CustomerImportScreen> {
  _Step _step = _Step.source;
  String? _busy;
  String? _error;
  bool _contactsDenied = false;

  // File
  ImportTable? _table;
  String _source = 'GENERIC';

  // Contacts
  List<DeviceContact>? _contacts;
  final Set<String> _picked = {};
  Set<String> _customerPhones = const {};
  final _contactSearch = TextEditingController();

  // Review
  final Map<int, Map<String, Object?>> _records = {};
  List<ImportRowResult> _preview = const [];
  _Filter _filter = _Filter.fresh;
  String _policy = 'SKIP';
  final Map<int, String> _rowPolicy = {};

  // Run
  String _importId = newImportId();
  int _nextChunk = 0;
  List<List<Map<String, Object?>>> _chunks = const [];
  final List<ImportRowResult> _results = [];
  bool _retrying = false;
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    _contactSearch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _contactSearch.dispose();
    super.dispose();
  }

  /// IMPORT_* answers carry a Hebrew message from the server (e.g. "save as xlsx").
  String _message(Object e) => e is ApiException
      ? (e.code.startsWith('IMPORT_') && e.serverMessage != null
            ? e.serverMessage!
            : e.messageHe)
      : errorMessageHe('UNKNOWN');

  bool get _canLeave =>
      _step == _Step.source || _step == _Step.summary || _busy == null;

  void _back() {
    if (_step == _Step.running) return;
    if (_step == _Step.summary || _step == _Step.source) {
      Navigator.of(context).pop(_step == _Step.summary);
      return;
    }
    setState(() {
      _error = null;
      _step = switch (_step) {
        _Step.review => _table != null ? _Step.mapping : _Step.contacts,
        _ => _Step.source,
      };
    });
  }

  // ---------------------------------------------------------------- source

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final PickedImportFile? file;
    try {
      file = await pickImportFile();
    } on PlatformException {
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _busy = ImportHe.readingFile);
    try {
      final table = await parseImportFile(file.name, file.bytes);
      if (!mounted) return;
      setState(() {
        _table = table;
        _contacts = null;
        _source = table.source;
        _busy = null;
        _step = _Step.mapping;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _openContacts() async {
    setState(() {
      _error = null;
      _contactsDenied = false;
      _busy = ImportHe.loadingContacts;
    });
    try {
      final contacts = await loadDeviceContacts();
      Set<String> phones = const {};
      try {
        final list = await fetchCustomerList();
        phones = {
          for (final c in list.active)
            if (_phoneKey(c.phone) != null) _phoneKey(c.phone)!,
        };
      } on Object {
        // The "כבר לקוח" hint is optional; the server still finds duplicates.
      }
      if (!mounted) return;
      if (contacts == null) {
        setState(() {
          _busy = null;
          _contactsDenied = true;
        });
        return;
      }
      final named = [
        for (final c in contacts)
          if (c.displayName.isNotEmpty) c,
      ]..sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() {
        _contacts = named;
        _table = null;
        _source = 'CONTACTS';
        _customerPhones = phones;
        _picked.clear();
        _busy = null;
        _step = _Step.contacts;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = e is PlatformException
              ? ImportHe.contactsDenied
              : _message(e);
        });
      }
    }
  }

  static String? _phoneKey(String? raw) => waPhone(raw);

  bool _isCustomer(DeviceContact c) =>
      c.phones.any((p) => _customerPhones.contains(_phoneKey(p)));

  // ---------------------------------------------------------------- review

  Future<void> _check(List<Map<String, Object?>> records) async {
    setState(() {
      _busy = ImportHe.checking;
      _error = null;
    });
    try {
      final preview = await previewImport(records);
      if (!mounted) return;
      setState(() {
        _records
          ..clear()
          ..addEntries(records.map((r) => MapEntry(r['row']! as int, r)));
        _preview = preview;
        _rowPolicy.clear();
        _importId = newImportId(); // a new selection is a new import
        _filter = _count('NEW') > 0
            ? _Filter.fresh
            : _count('DUPLICATE') > 0
            ? _Filter.duplicates
            : _Filter.errors;
        _busy = null;
        _step = _Step.review;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _message(e);
        });
      }
    }
  }

  int _count(String status) => _preview.where((r) => r.status == status).length;

  String _policyOf(ImportRowResult r) => _rowPolicy[r.row] ?? _policy;

  /// Rows that will create or change a customer.
  int get _toImport => _preview
      .where(
        (r) =>
            r.status == 'NEW' ||
            (r.status == 'DUPLICATE' && _policyOf(r) != 'SKIP'),
      )
      .length;

  String _nameOf(int row) => '${_records[row]?['name'] ?? ''}'.trim().isEmpty
      ? ImportHe.rowLabel(row)
      : '${_records[row]!['name']}';

  Future<void> _fixRow(ImportRowResult r) async {
    final record = Map<String, Object?>.from(_records[r.row] ?? {'row': r.row});
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _FixRowDialog(
        errors: [for (final e in r.errors) e.message],
        initial: {
          'name': '${record['name'] ?? ''}',
          'taxId': '${record['taxId'] ?? ''}',
          'phone': '${record['mobile'] ?? record['phone'] ?? ''}',
          'email': '${record['email'] ?? ''}',
        },
      ),
    );
    if (values == null || !mounted) return;
    record
      ..remove('phone')
      ..remove('mobile');
    for (final e in values.entries) {
      final key = e.key == 'phone' ? 'mobile' : e.key;
      if (e.value.isEmpty) {
        record.remove(key);
      } else {
        record[key] = e.value;
      }
    }
    setState(() => _busy = ImportHe.checking);
    try {
      final fixed = (await previewImport([record])).single;
      if (!mounted) return;
      setState(() {
        _records[r.row] = record;
        _preview = [for (final p in _preview) p.row == r.row ? fixed : p];
        _busy = null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _rowPolicySheet(ImportRowResult r) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(_nameOf(r.row), style: AppText.headline),
              subtitle: const Text(ImportHe.rowPolicyTitle),
            ),
            for (final (value, label) in [
              ('', ImportHe.useDefault),
              ('SKIP', ImportHe.policySkip),
              ('MERGE', ImportHe.policyMerge),
              ('CREATE', ImportHe.policyCreate),
            ])
              ListTile(
                key: Key('import-row-policy-$value'),
                title: Text(label),
                trailing: (_rowPolicy[r.row] ?? '') == value
                    ? const Icon(Iconsax.tick_circle)
                    : null,
                onTap: () => Navigator.pop(context, value),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() {
      if (choice.isEmpty) {
        _rowPolicy.remove(r.row);
      } else {
        _rowPolicy[r.row] = choice;
      }
    });
  }

  // ---------------------------------------------------------------- run

  void _start() {
    final rows = [
      for (final r in _preview)
        if (r.status != 'ERROR')
          {
            ..._records[r.row]!,
            if (_rowPolicy[r.row] != null) 'onDuplicate': _rowPolicy[r.row],
          },
    ];
    _chunks = [
      for (var i = 0; i < rows.length; i += importChunkSize)
        rows.sublist(
          i,
          i + importChunkSize > rows.length ? rows.length : i + importChunkSize,
        ),
    ];
    _nextChunk = 0;
    _results.clear();
    setState(() {
      _step = _Step.running;
      _stopped = false;
    });
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _stopped = false;
      _error = null;
    });
    while (_nextChunk < _chunks.length) {
      try {
        final results = await commitImportChunk(
          importId: _importId,
          chunkIndex: _nextChunk,
          source: _source,
          onDuplicate: _policy,
          records: _chunks[_nextChunk],
          onRetry: () {
            if (mounted) setState(() => _retrying = true);
          },
        );
        if (!mounted) return;
        setState(() {
          _results.addAll(results);
          _nextChunk++;
          _retrying = false;
        });
      } on Object catch (e) {
        if (!mounted) return;
        setState(() {
          _retrying = false;
          _stopped = true;
          _error = _message(e);
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() => _step = _Step.summary);
  }

  List<ImportRowResult> get _allResults => [
    ..._results,
    ..._preview.where((r) => r.status == 'ERROR'),
  ];

  Future<void> _shareErrors() async {
    final bytes = errorsCsv(
      _allResults,
      ImportHe.errorsCsvHeader,
      (f) => (ImportHe.fieldLabels[f] ?? f).replaceAll(' *', ''),
      _nameOf,
    );
    await shareImportFile(bytes, ImportHe.errorsFileName, 'text/csv');
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canLeave && _step == _Step.source,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(switch (_step) {
            _Step.contacts => ImportHe.contactsTitle,
            _Step.mapping => ImportHe.mappingTitle,
            _Step.review => ImportHe.reviewTitle,
            _Step.summary => ImportHe.summaryTitle,
            _ => ImportHe.title,
          }),
          automaticallyImplyLeading: false,
          leading: _step == _Step.running
              ? null
              : IconButton(
                  key: const Key('import-back'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _back,
                  icon: Icon(
                    _step == _Step.source || _step == _Step.summary
                        ? Iconsax.close_circle
                        : Iconsax.arrow_right_3,
                  ),
                ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.page,
                    Space.s,
                    Space.page,
                    0,
                  ),
                  child: Text(
                    _error!,
                    key: const Key('import-error'),
                    style: AppText.secondary.copyWith(
                      color: context.palette.danger,
                    ),
                  ),
                ),
              Expanded(
                child: _busy != null && _step != _Step.running
                    ? _Busy(_busy!)
                    : switch (_step) {
                        _Step.source => _sourceStep(context),
                        _Step.contacts => _contactsStep(context),
                        _Step.mapping => _mappingStep(context),
                        _Step.review => _reviewStep(context),
                        _Step.running => _runningStep(context),
                        _Step.summary => _summaryStep(context),
                      },
              ),
              // One scope per step: the old step's button never overlaps the new one (F2).
              if (_busy == null && _bottom(context) != null)
                PrimaryScope(key: ValueKey(_step), child: _bottom(context)!),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _bottom(BuildContext context) => switch (_step) {
    _Step.contacts when _picked.isNotEmpty => BottomActionArea(
      child: PrimaryButton(
        key: const Key('import-contacts-continue'),
        label: ImportHe.continueWith(_picked.length),
        onPressed: () {
          final chosen = [
            for (final c in _contacts!)
              if (_picked.contains(c.id)) c,
          ];
          _check([
            for (var i = 0; i < chosen.length; i++) chosen[i].toRecord(i + 1),
          ]);
        },
      ),
    ),
    _Step.mapping => BottomActionArea(
      child: PrimaryButton(
        key: const Key('import-check'),
        label: ImportHe.checkRows,
        onPressed: () {
          if (_table!.mapping['name'] == null) {
            setState(() => _error = ImportHe.nameRequired);
            return;
          }
          _check(_table!.records());
        },
      ),
    ),
    _Step.review when _toImport > 0 || _count('DUPLICATE') > 0 =>
      BottomActionArea(
        note: _count('ERROR') > 0 ? ImportHe.fixHint : null,
        child: PrimaryButton(
          key: const Key('import-start'),
          label: ImportHe.importN(_toImport),
          onPressed: _start,
        ),
      ),
    _Step.running when _stopped => BottomActionArea(
      note: ImportHe.failedMidway,
      child: PrimaryButton(
        key: const Key('import-retry'),
        label: ImportHe.tryAgain,
        onPressed: () => unawaited(_run()),
      ),
    ),
    _Step.summary => BottomActionArea(
      child: PrimaryButton(
        key: const Key('import-done'),
        label: ImportHe.done,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ),
    _ => null,
  };

  Widget _sourceStep(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(Space.page),
      children: [
        Text(ImportHe.sourceIntro, style: AppText.body.copyWith(color: p.ink)),
        const SizedBox(height: Space.xl),
        _SourceTile(
          key: const Key('import-source-file'),
          icon: Iconsax.document_text,
          title: ImportHe.sourceFile,
          subtitle: ImportHe.sourceFileSub,
          onTap: _pickFile,
        ),
        const SizedBox(height: Space.m),
        _SourceTile(
          key: const Key('import-source-contacts'),
          icon: Iconsax.profile_2user,
          title: ImportHe.sourceContacts,
          subtitle: ImportHe.sourceContactsSub,
          onTap: _openContacts,
        ),
        const SizedBox(height: Space.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Iconsax.info_circle, size: 18, color: p.muted),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                ImportHe.whatsappHint,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          ],
        ),
        if (_contactsDenied) ...[
          const SizedBox(height: Space.xl),
          Text(
            ImportHe.contactsDenied,
            key: const Key('import-contacts-denied'),
            style: AppText.secondary.copyWith(color: p.danger),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => launchAllowed(Uri.parse('app-settings:')),
              child: const Text(ImportHe.openSettings),
            ),
          ),
        ],
      ],
    );
  }

  Widget _contactsStep(BuildContext context) {
    final p = context.palette;
    final q = _contactSearch.text.trim().toLowerCase();
    final all = _contacts ?? const <DeviceContact>[];
    if (all.isEmpty) {
      return const EmptyState(
        icon: Iconsax.profile_2user,
        title: ImportHe.noContacts,
      );
    }
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final rows = [
      for (final c in all)
        if (q.isEmpty ||
            c.displayName.toLowerCase().contains(q) ||
            (digits.length >= 3 &&
                c.phones.any(
                  (ph) => ph.replaceAll(RegExp(r'\D'), '').contains(digits),
                )))
          c,
    ];
    final allPicked =
        rows.isNotEmpty && rows.every((c) => _picked.contains(c.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.s,
            Space.page,
            0,
          ),
          child: TextField(
            key: const Key('import-contacts-search'),
            controller: _contactSearch,
            decoration: const InputDecoration(
              hintText: ImportHe.contactsSearch,
              prefixIcon: Icon(Iconsax.search_normal_1),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ImportHe.selectedCount(_picked.length),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ),
              TextButton(
                key: const Key('import-contacts-all'),
                onPressed: () => setState(() {
                  if (allPicked) {
                    _picked.removeAll(rows.map((c) => c.id));
                  } else {
                    _picked.addAll(rows.map((c) => c.id));
                  }
                }),
                child: Text(allPicked ? ImportHe.clearAll : ImportHe.selectAll),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('import-contacts-list'),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final c = rows[i];
              final phone = c.sortedPhones.isEmpty
                  ? (c.emails.isEmpty ? '' : c.emails.first)
                  : formatPhoneHe(normalizePhoneInput(c.sortedPhones.first));
              final known = _isCustomer(c);
              return CheckboxListTile(
                key: Key('import-contact-${c.id}'),
                value: _picked.contains(c.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _picked.add(c.id);
                  } else {
                    _picked.remove(c.id);
                  }
                }),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(c.displayName, style: AppText.body),
                subtitle: Text(
                  [
                    if (phone.isNotEmpty) phone,
                    if (c.name.isNotEmpty && c.organization.isNotEmpty)
                      c.organization,
                  ].join(' · '),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
                secondary: known
                    ? Text(
                        ImportHe.alreadyCustomer,
                        key: Key('import-known-${c.id}'),
                        style: AppText.secondary.copyWith(color: p.warn),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _mappingStep(BuildContext context) {
    final p = context.palette;
    final t = _table!;
    final used = t.mapping.values.toSet();
    return ListView(
      key: const Key('import-mapping'),
      padding: const EdgeInsets.all(Space.page),
      children: [
        Text(
          ImportHe.detected(t.sourceLabel, t.rows.length),
          style: AppText.headline,
        ),
        const SizedBox(height: Space.xs),
        Text(
          t.hasHeader ? ImportHe.mappingIntro : ImportHe.noHeaderNote,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.l),
        for (final field in importFields)
          _MappingRow(
            key: Key('import-map-$field'),
            label: ImportHe.fieldLabels[field]!,
            headers: t.headers,
            column: t.mapping[field],
            used: used,
            sample: t.mapping[field] == null ? '' : t.sample(t.mapping[field]!),
            onChanged: (col) => setState(() {
              _error = null;
              if (col == null) {
                t.mapping.remove(field);
              } else {
                t.mapping.removeWhere((_, v) => v == col);
                t.mapping[field] = col;
              }
            }),
          ),
        const SizedBox(height: Space.xl),
        Text(ImportHe.previewTable, style: AppText.headline),
        const SizedBox(height: Space.s),
        _PreviewTable(table: t),
      ],
    );
  }

  Widget _reviewStep(BuildContext context) {
    final p = context.palette;
    final fresh = _count('NEW'),
        dups = _count('DUPLICATE'),
        errs = _count('ERROR');
    final rows = _preview
        .where(
          (r) => switch (_filter) {
            _Filter.fresh => r.status == 'NEW',
            _Filter.duplicates => r.status == 'DUPLICATE',
            _Filter.errors => r.status == 'ERROR',
          },
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s),
        ChipRow<_Filter>(
          options: [
            ChipOption(_Filter.fresh, ImportHe.newCount(fresh)),
            ChipOption(_Filter.duplicates, ImportHe.dupCount(dups)),
            ChipOption(_Filter.errors, ImportHe.errCount(errs)),
          ],
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
        if (_filter == _Filter.duplicates && dups > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              Space.m,
              Space.page,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(ImportHe.duplicatesQuestion, style: AppText.body),
                const SizedBox(height: Space.s),
                SegmentedButton<String>(
                  key: const Key('import-policy'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'SKIP',
                      label: Text(ImportHe.policySkip),
                    ),
                    ButtonSegment(
                      value: 'MERGE',
                      label: Text(ImportHe.policyMerge),
                    ),
                    ButtonSegment(
                      value: 'CREATE',
                      label: Text(ImportHe.policyCreate),
                    ),
                  ],
                  selected: {_policy},
                  onSelectionChanged: (s) => setState(() => _policy = s.first),
                ),
                const SizedBox(height: Space.xs),
                Text(switch (_policy) {
                  'MERGE' => ImportHe.policyMergeHelp,
                  'CREATE' => ImportHe.policyCreateHelp,
                  _ => ImportHe.policySkipHelp,
                }, style: AppText.secondary.copyWith(color: p.muted)),
              ],
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const EmptyState(
                  icon: Iconsax.tick_circle,
                  title: ImportHe.nothingToImport,
                )
              : ListView.separated(
                  key: const Key('import-review-list'),
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: p.line),
                  itemBuilder: (context, i) => _reviewRow(context, rows[i]),
                ),
        ),
      ],
    );
  }

  Widget _reviewRow(BuildContext context, ImportRowResult r) {
    final p = context.palette;
    final c = r.customer;
    final details = <String>[
      if (c?['phone'] != null) formatPhoneHe('${c!['phone']}'),
      if (c?['taxId'] != null) '${c!['taxId']}',
      if (c?['email'] != null) '${c!['email']}',
      if ((c?['address'] as Map?)?['city'] != null)
        '${(c!['address'] as Map)['city']}',
    ];
    final lines = <Widget>[
      if (details.isNotEmpty)
        Text(
          details.join(' · '),
          style: AppText.secondary.copyWith(color: p.muted),
        ),
      if (r.duplicateName != null)
        Text(
          ImportHe.existing(r.duplicateName!, switch (r.duplicateBy) {
            'TAX_ID' => ImportHe.byTaxId,
            'PHONE' => ImportHe.byPhone,
            _ => ImportHe.byEmail,
          }),
          style: AppText.secondary.copyWith(color: p.warn),
        ),
      if (r.duplicateOfRow != null && r.duplicateName == null)
        Text(
          ImportHe.sameAsRow(r.duplicateOfRow!),
          style: AppText.secondary.copyWith(color: p.warn),
        ),
      for (final e in r.errors)
        Text(e.message, style: AppText.secondary.copyWith(color: p.danger)),
      for (final w in r.warnings)
        Text(w.message, style: AppText.secondary.copyWith(color: p.muted)),
    ];
    final rowPolicy = _rowPolicy[r.row];
    return ListTile(
      key: Key('import-row-${r.row}'),
      title: Text(_nameOf(r.row), style: AppText.body),
      subtitle: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
      trailing: switch (r.status) {
        'ERROR' => const Icon(Iconsax.edit_2),
        'DUPLICATE' => Text(
          switch (rowPolicy ?? _policy) {
            'MERGE' => ImportHe.policyMerge,
            'CREATE' => ImportHe.policyCreate,
            _ => ImportHe.policySkip,
          },
          style: AppText.secondary.copyWith(
            color: rowPolicy == null ? p.muted : p.ink,
          ),
        ),
        _ => null,
      },
      onTap: switch (r.status) {
        'ERROR' => () => _fixRow(r),
        'DUPLICATE' => () => _rowPolicySheet(r),
        _ => null,
      },
    );
  }

  Widget _runningStep(BuildContext context) {
    final total = _chunks.fold<int>(0, (n, c) => n + c.length);
    final done = _results.length;
    return Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          const SizedBox(height: Space.l),
          Text(
            _retrying ? ImportHe.retrying : ImportHe.importing(done, total),
            key: const Key('import-progress'),
            style: AppText.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _summaryStep(BuildContext context) {
    final p = context.palette;
    final s = ImportSummary.of(_allResults);
    return ListView(
      key: const Key('import-summary'),
      padding: const EdgeInsets.all(Space.page),
      children: [
        Icon(Iconsax.tick_circle, size: 56, color: p.ok),
        const SizedBox(height: Space.l),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.m,
          runSpacing: Space.m,
          children: [
            _Stat(
              ImportHe.added(s.created),
              p.ok,
              const Key('import-sum-created'),
            ),
            _Stat(
              ImportHe.updated(s.updated),
              p.ink,
              const Key('import-sum-updated'),
            ),
            _Stat(
              ImportHe.skipped(s.skipped),
              p.muted,
              const Key('import-sum-skipped'),
            ),
            _Stat(
              ImportHe.errors(s.errors),
              s.errors > 0 ? p.danger : p.muted,
              const Key('import-sum-errors'),
            ),
          ],
        ),
        if (s.errors > 0) ...[
          const SizedBox(height: Space.xl),
          OutlinedButton.icon(
            key: const Key('import-share-errors'),
            onPressed: _shareErrors,
            icon: const Icon(Iconsax.export_1),
            label: const Text(ImportHe.shareErrors),
          ),
          const SizedBox(height: Space.m),
          for (final r in _allResults.where((r) => r.status == 'ERROR'))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                '${_nameOf(r.row)} — ${r.errors.map((e) => e.message).join(' · ')}',
                style: AppText.secondary.copyWith(color: p.danger),
              ),
            ),
        ],
      ],
    );
  }
}

/// "תקן שורה": the four fields that can fail validation; answers the edited values.
class _FixRowDialog extends StatefulWidget {
  const _FixRowDialog({required this.errors, required this.initial});

  final List<String> errors;
  final Map<String, String> initial;

  @override
  State<_FixRowDialog> createState() => _FixRowDialogState();
}

class _FixRowDialogState extends State<_FixRowDialog> {
  late final Map<String, TextEditingController> _fields = {
    for (final e in widget.initial.entries)
      e.key: TextEditingController(text: e.value),
  };

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(ImportHe.fixRow),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final message in widget.errors)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                message,
                style: AppText.secondary.copyWith(
                  color: context.palette.danger,
                ),
              ),
            ),
          for (final e in _fields.entries)
            TextField(
              key: Key('import-fix-${e.key}'),
              controller: e.value,
              keyboardType: switch (e.key) {
                'phone' => TextInputType.phone,
                'email' => TextInputType.emailAddress,
                'taxId' => TextInputType.number,
                _ => TextInputType.text,
              },
              decoration: InputDecoration(
                labelText: ImportHe.fieldLabels[e.key],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(CommonHe.cancel),
      ),
      TextButton(
        key: const Key('import-fix-save'),
        onPressed: () => Navigator.pop(context, {
          for (final e in _fields.entries) e.key: e.value.text.trim(),
        }),
        child: const Text(ImportHe.save),
      ),
    ],
  );
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: Space.l),
        Text(text, key: const Key('import-busy'), style: AppText.body),
      ],
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 28, color: p.ink),
          const SizedBox(width: Space.l),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.headline),
                const SizedBox(height: Space.xs),
                Text(
                  subtitle,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          Icon(Iconsax.arrow_left_2, size: 18, color: p.muted),
        ],
      ),
    );
  }
}

class _MappingRow extends StatelessWidget {
  const _MappingRow({
    super.key,
    required this.label,
    required this.headers,
    required this.column,
    required this.used,
    required this.sample,
    required this.onChanged,
  });

  final String label;
  final List<String> headers;
  final int? column;
  final Set<int> used;
  final String sample;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Text(label, style: AppText.body),
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<int?>(
                  initialValue: column,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text(ImportHe.notMapped),
                    ),
                    for (var i = 0; i < headers.length; i++)
                      DropdownMenuItem<int?>(
                        value: i,
                        child: Text(
                          headers[i],
                          overflow: TextOverflow.ellipsis,
                          style: used.contains(i) && i != column
                              ? TextStyle(color: p.muted)
                              : null,
                        ),
                      ),
                  ],
                  onChanged: onChanged,
                ),
                if (sample.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      '${ImportHe.sample}: $sample',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The first rows with the mapped fields only (horizontal scroll for wide files).
class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.table});
  final ImportTable table;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fields = [
      for (final f in importFields)
        if (table.mapping[f] != null) f,
    ];
    if (fields.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const Key('import-preview-table'),
        headingTextStyle: AppText.secondary.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: AppText.secondary.copyWith(color: p.ink),
        columnSpacing: Space.l,
        horizontalMargin: Space.s,
        columns: [
          for (final f in fields)
            DataColumn(
              label: Text(ImportHe.fieldLabels[f]!.replaceAll(' *', '')),
            ),
        ],
        rows: [
          for (final r in table.rows.take(5))
            DataRow(
              cells: [
                for (final f in fields)
                  DataCell(
                    Text(
                      table.mapping[f]! < r.length ? r[table.mapping[f]!] : '',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.text, this.color, Key key) : super(key: key);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
    decoration: BoxDecoration(
      border: Border.all(color: context.palette.line),
      borderRadius: BorderRadius.circular(Radii.button),
    ),
    child: Text(text, style: AppText.headline.copyWith(color: color)),
  );
}
