// 0119 "המסמכים של העסק" (tester 2026-11-18: "אין מקום להכניס מסמכים שלי כמו
// תעודת עוסק מורשה, תיק ניכויים וכו'"). The business's own certificates:
// upload (PDF / photo, ≤ 15 MB, scanned on the server), category, title, issue /
// expiry date with a reminder N days before, view, send one or several to a
// customer (share sheet → mail / WhatsApp), edit, remove (soft, audited).
// Owner / partner manage; whoever holds business_documents:read views + sends.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/client.dart' show ApiException;
import '../../api/expenses_api.dart' show isPdf, prepareExpenseJpeg;
import '../../api/reports_api.dart' show ExportFile;
import '../../api/vault_api.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/israel_date.dart';
import '../../util/labels/labels.dart';
import '../../util/still_here.dart';
import '../document/pdf_viewer_screen.dart';
import 'team_editors.dart' show confirmDanger;

enum VaultSource { pdf, camera, gallery }

/// A picked file before upload.
class VaultFile {
  const VaultFile(this.bytes, this.mimeType, this.filename);
  final Uint8List bytes;
  final String mimeType;
  final String filename;
}

class VaultInputException implements Exception {
  const VaultInputException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Picks the file for [source]; null = the user backed out. Tests replace it.
Future<VaultFile?> Function(VaultSource source) pickVaultFile = _pick;

/// Loads the list. Tests replace it.
Future<VaultList> Function() loadVault = fetchVault;

/// Shares [files] through the system share sheet. Tests replace it.
Future<void> Function(List<ExportFile> files, {String? text}) vaultSharer =
    _shareFiles;

/// Downloads one file. Tests replace it.
Future<ExportFile> Function(VaultDocument d) downloadVault =
    downloadVaultDocument;

Future<VaultFile?> _pick(VaultSource source) async {
  if (source == VaultSource.pdf) {
    final bytes = await const MethodChannel(
      'tevel/pdf_picker',
    ).invokeMethod<Uint8List>('pickPdf');
    if (bytes == null) return null;
    if (!isPdf(bytes)) throw const VaultInputException(VaultHe.notPdf);
    return VaultFile(bytes, 'application/pdf', 'document.pdf');
  }
  final image = await ImagePicker().pickImage(
    source: source == VaultSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
    requestFullMetadata: false,
  );
  if (image == null) return null;
  return VaultFile(
    await prepareExpenseJpeg(await image.readAsBytes()),
    'image/jpeg',
    'document.jpg',
  );
}

Future<void> _shareFiles(List<ExportFile> files, {String? text}) async {
  final dir = await getTemporaryDirectory();
  final out = <XFile>[];
  for (final f in files) {
    final path = '${dir.path}/${f.name}';
    await XFile.fromData(
      f.bytes,
      mimeType: f.mimeType,
      name: f.name,
    ).saveTo(path);
    out.add(XFile(path, mimeType: f.mimeType));
  }
  await SharePlus.instance.share(ShareParams(files: out, text: text));
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  VaultList? _data;
  Object? _error;
  bool _busy = false;
  bool _selecting = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    vaultVersion.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    vaultVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final data = await loadVault();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
          _selected.removeWhere((id) => !data.items.any((d) => d.id == id));
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(
    context,
  ).showNotchNotice(SnackBar(content: Text(text)));

  Future<void> _add() async {
    final source = await showAppSheet<VaultSource>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(VaultHe.sourceTitle),
          for (final (s, icon, label) in [
            (VaultSource.pdf, Iconsax.document_upload, VaultHe.sourcePdf),
            (VaultSource.camera, Iconsax.camera, VaultHe.sourceCamera),
            (VaultSource.gallery, Iconsax.gallery, VaultHe.sourceGallery),
          ])
            ListTile(
              key: Key('vault-source-${s.name}'),
              leading: Icon(icon),
              title: Text(label, style: AppText.body),
              minTileHeight: Hit.min + 8,
              onTap: () => Navigator.of(context).pop(s),
            ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    VaultFile? file;
    try {
      file = await pickVaultFile(source);
    } on VaultInputException catch (e) {
      if (mounted) _notice(e.message);
      return;
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    if (file == null || !mounted) return;
    if (file.bytes.length > vaultMaxBytes) {
      _notice(VaultHe.tooLarge);
      return;
    }
    final meta = await showVaultDetails(context);
    if (meta == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await uploadVaultDocument(
        meta,
        bytes: file.bytes,
        mimeType: file.mimeType,
        filename: file.filename,
      );
      if (mounted) _notice(VaultHe.uploaded);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'SCANNER_INFECTED') {
        _notice(VaultHe.infected);
      } else if (e.code == 'FILE_TOO_LARGE') {
        _notice(VaultHe.tooLarge);
      } else {
        showErrorSnack(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(VaultDocument d) async {
    try {
      final file = await downloadVault(d);
      if (!mounted || !stillHere(context)) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => d.isPdf
              ? PdfViewerScreen(bytes: file.bytes, title: d.title)
              : _ImageViewer(bytes: file.bytes, title: d.title),
        ),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _share(List<VaultDocument> docs) async {
    if (docs.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final files = [for (final d in docs) await downloadVault(d)];
      if (!mounted || !stillHere(context)) return;
      await vaultSharer(
        files,
        text: VaultHe.shareText(businessContext.displayName),
      );
      unawaited(recordVaultShare([for (final d in docs) d.id], 'SHARE'));
      if (mounted) {
        setState(() {
          _selecting = false;
          _selected.clear();
        });
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(VaultDocument d) async {
    final meta = await showVaultDetails(context, initial: d);
    if (meta == null || !mounted) return;
    try {
      await updateVaultDocument(d.id, meta);
      if (mounted) _notice(VaultHe.saved);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _delete(VaultDocument d) async {
    final ok = await confirmDanger(
      context,
      VaultHe.deleteTitle,
      VaultHe.deleteBody,
      VaultHe.delete,
    );
    if (!ok || !mounted) return;
    try {
      await deleteVaultDocument(d.id);
      if (mounted) _notice(VaultHe.deleted);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  Future<void> _actions(VaultDocument d) async {
    final manage = _data?.canManage ?? false;
    final action = await showAppSheet<String>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(d.title, subtitle: d.categoryLabel),
          for (final (key, icon, label) in [
            ('view', Iconsax.eye, VaultHe.view),
            ('share', Iconsax.send_2, VaultHe.share),
            if (manage) ('edit', Iconsax.edit_2, VaultHe.edit),
            if (manage) ('delete', Iconsax.trash, VaultHe.delete),
          ])
            ListTile(
              key: Key('vault-action-$key'),
              leading: Icon(
                icon,
                color: key == 'delete' ? context.palette.danger : null,
              ),
              title: Text(
                label,
                style: AppText.body.copyWith(
                  color: key == 'delete' ? context.palette.danger : null,
                ),
              ),
              minTileHeight: Hit.min + 8,
              onTap: () => Navigator.of(context).pop(key),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'view':
        await _view(d);
      case 'share':
        await _share([d]);
      case 'edit':
        await _edit(d);
      case 'delete':
        await _delete(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final manage = data?.canManage ?? false;
    final items = data?.items ?? const <VaultDocument>[];
    final Widget body;
    if (_error != null && data == null) {
      body = ErrorView(error: _error!, onRetry: _reload);
    } else if (data == null) {
      body = const SkeletonList(rows: 4);
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Iconsax.folder_open,
        title: VaultHe.empty,
        message: VaultHe.emptyHint,
        actionLabel: manage ? VaultHe.add : null,
        onAction: manage ? () => unawaited(_add()) : null,
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.page,
            Space.s,
            Space.page,
            MediaQuery.paddingOf(context).bottom + Space.xl,
          ),
          children: [
            Text(
              manage ? VaultHe.intro : VaultHe.viewOnly,
              style: AppText.secondary.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: Space.m),
            for (final d in items)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: _VaultRow(
                  doc: d,
                  selecting: _selecting,
                  selected: _selected.contains(d.id),
                  onTap: () {
                    if (_selecting) {
                      setState(() {
                        _selected.contains(d.id)
                            ? _selected.remove(d.id)
                            : _selected.add(d.id);
                      });
                    } else {
                      unawaited(_actions(d));
                    }
                  },
                ),
              ),
          ],
        ),
      );
    }
    final chosen = [
      for (final d in items)
        if (_selected.contains(d.id)) d,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(VaultHe.title),
        actions: [
          if (items.length > 1)
            TextButton(
              key: const Key('vault-select'),
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _selected.clear();
              }),
              child: Text(_selecting ? VaultHe.cancelSelect : VaultHe.select),
            ),
        ],
      ),
      body: SafeArea(bottom: false, child: body),
      // One PrimaryButton per screen (F2): the same button changes role.
      bottomNavigationBar: _selecting || (manage && items.isNotEmpty)
          ? BottomActionArea(
              key: const Key('vault-bottom'),
              child: PrimaryButton(
                label: _selecting
                    ? VaultHe.sendSelected(chosen.length)
                    : VaultHe.add,
                icon: _selecting ? Iconsax.send_2 : Iconsax.add,
                loadingText: _busy ? VaultHe.uploading : null,
                onPressed: () =>
                    unawaited(_selecting ? _share(chosen) : _add()),
              ),
            )
          : null,
    );
  }
}

class _VaultRow extends StatelessWidget {
  const _VaultRow({
    required this.doc,
    required this.selecting,
    required this.selected,
    required this.onTap,
  });

  final VaultDocument doc;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (expiryText, expiryColor) = _expiry(doc, p);
    return AppCard(
      key: Key('vault-row-${doc.id}'),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.tint(p.info),
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Icon(
              doc.isPdf ? Iconsax.document_text : Iconsax.gallery,
              color: p.info,
              size: 21,
            ),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: AppText.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  doc.categoryLabel,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  expiryText,
                  key: Key('vault-expiry-${doc.id}'),
                  style: AppText.secondary.copyWith(
                    color: expiryColor,
                    fontWeight: expiryColor == p.muted ? null : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (selecting)
            Icon(
              selected ? Iconsax.tick_circle : Iconsax.record,
              color: selected ? p.accent : p.muted,
            ),
        ],
      ),
    );
  }

  static (String, Color) _expiry(VaultDocument d, AppPalette p) {
    final days = d.daysToExpiry;
    return switch (d.expiry) {
      VaultExpiry.none => (VaultHe.noExpiry, p.muted),
      VaultExpiry.expired => (VaultHe.expiredAgo(-(days ?? 0)), p.danger),
      VaultExpiry.expiring => (VaultHe.expiresIn(days ?? 0), p.warn),
      VaultExpiry.valid => (
        VaultHe.validUntil(formatDateHe(d.expiresOn)),
        p.muted,
      ),
    };
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    backgroundColor: context.palette.canvas,
    body: InteractiveViewer(
      maxScale: 5,
      child: Center(child: Image.memory(bytes)),
    ),
  );
}

/// The details sheet (upload / edit): category, title, issue + expiry date,
/// reminder lead time. Null = cancelled.
Future<VaultMeta?> showVaultDetails(
  BuildContext context, {
  VaultDocument? initial,
}) => showAppSheet<VaultMeta>(
  context,
  builder: (context) => _VaultDetails(initial: initial),
);

const List<int> _remindChoices = [0, 7, 14, 30, 60, 90];

class _VaultDetails extends StatefulWidget {
  const _VaultDetails({this.initial});
  final VaultDocument? initial;

  @override
  State<_VaultDetails> createState() => _VaultDetailsState();
}

class _VaultDetailsState extends State<_VaultDetails> {
  late String _category = widget.initial?.category ?? 'DEALER_CERTIFICATE';
  late final TextEditingController _title = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late String? _issued = widget.initial?.issuedOn;
  late String? _expires = widget.initial?.expiresOn;
  late int _remind = widget.initial?.remindDaysBefore ?? 30;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool expiry) async {
    final today = israelTodayDate();
    final current = DateTime.tryParse((expiry ? _expires : _issued) ?? '');
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(today.year - 30),
      lastDate: DateTime(today.year + 30),
      initialDate:
          current ??
          (expiry ? DateTime(today.year + 1, today.month, today.day) : today),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expiry) {
        _expires = isoDate(picked);
      } else {
        _issued = isoDate(picked);
      }
    });
  }

  Widget _dateRow(String key, String label, String? value, bool expiry) =>
      ListTile(
        key: Key('vault-$key'),
        contentPadding: EdgeInsets.zero,
        minTileHeight: Hit.row,
        title: Text(label, style: AppText.body),
        subtitle: Text(
          value == null ? VaultHe.noDate : formatDateHe(value),
          style: AppText.secondary,
        ),
        trailing: value == null
            ? const Icon(Iconsax.calendar_1)
            : IconButton(
                tooltip: VaultHe.clearDate,
                icon: const Icon(Iconsax.close_circle),
                onPressed: () => setState(() {
                  if (expiry) {
                    _expires = null;
                  } else {
                    _issued = null;
                  }
                }),
              ),
        onTap: () => unawaited(_pickDate(expiry)),
      );

  @override
  Widget build(BuildContext context) {
    final label = vaultCategoryLabel(_category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          widget.initial == null ? VaultHe.detailsTitle : VaultHe.editTitle,
        ),
        DropdownButtonFormField<String>(
          key: const Key('vault-category'),
          initialValue: _category,
          isExpanded: true,
          decoration: const InputDecoration(labelText: VaultHe.category),
          items: [
            for (final (k, l) in vaultCategories)
              DropdownMenuItem(value: k, child: Text(l)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('vault-title'),
          controller: _title,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: VaultHe.docTitle,
            hintText: label,
          ),
        ),
        _dateRow('issued', VaultHe.issuedOn, _issued, false),
        _dateRow('expires', VaultHe.expiresOn, _expires, true),
        if (_expires != null) ...[
          const SizedBox(height: Space.s),
          Text(VaultHe.remind, style: AppText.secondary),
          const SizedBox(height: Space.s),
          ChipRow<int>(
            key: const Key('vault-remind'),
            padding: EdgeInsets.zero,
            options: [
              for (final d in _remindChoices)
                ChipOption(d, VaultHe.remindDays(d)),
            ],
            selected: _remind,
            onSelected: (d) => setState(() => _remind = d),
          ),
        ],
        const SizedBox(height: Space.l),
        PrimaryButton(
          key: const Key('vault-save'),
          label: VaultHe.save,
          onPressed: () => Navigator.of(context).pop(
            VaultMeta(
              category: _category,
              title: _title.text.trim().isEmpty ? label : _title.text,
              issuedOn: _issued,
              expiresOn: _expires,
              remindDaysBefore: _remind,
            ),
          ),
        ),
      ],
    );
  }
}
