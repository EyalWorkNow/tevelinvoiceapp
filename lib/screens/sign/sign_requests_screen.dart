// "מסמכים לחתימה": the list of sign requests (status chips) and the "+" that
// creates one — a PDF from Files, a camera scan or gallery photos (→ PDF on
// the phone) → upload → the field editor.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/sign_requests_api.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/image_to_pdf.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/sign_he.dart';
import 'sign_common.dart';

enum SignSource { pdf, camera, gallery }

const _pdfChannel = MethodChannel('tevel/pdf_picker');

/// Picks the document bytes (a PDF) for [source]; null = the user backed
/// out. Tests replace it.
Future<Uint8List?> Function(SignSource source) pickSignDocument = _pick;

/// Loads the list. Tests replace it.
Future<List<SignRequest>> Function() loadSignRequests = fetchSignRequests;

Future<Uint8List?> _pick(SignSource source) async {
  switch (source) {
    case SignSource.pdf:
      return _pdfChannel.invokeMethod<Uint8List>('pickPdf');
    case SignSource.camera:
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: maxScanSide.toDouble(),
        maxHeight: maxScanSide.toDouble(),
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (f == null) return null;
      return _toPdf([await f.readAsBytes()]);
    case SignSource.gallery:
      final files = await ImagePicker().pickMultiImage(
        maxWidth: maxScanSide.toDouble(),
        maxHeight: maxScanSide.toDouble(),
        imageQuality: 85,
        requestFullMetadata: false,
        limit: 20,
      );
      if (files.isEmpty) return null;
      return _toPdf([for (final f in files) await f.readAsBytes()]);
  }
}

Future<Uint8List> _toPdf(List<Uint8List> images) async {
  final pdf = await compute(imagesToPdf, images);
  if (pdf == null) throw const FormatException('images');
  return pdf;
}

enum _Chip { all, waiting, signed, drafts }

bool _inChip(SignRequest r, _Chip c) => switch (c) {
  _Chip.all => true,
  _Chip.waiting => r.waiting,
  _Chip.signed => r.status == SignStatus.completed,
  _Chip.drafts => r.status == SignStatus.draft,
};

class SignRequestsScreen extends StatefulWidget {
  const SignRequestsScreen({super.key});

  @override
  State<SignRequestsScreen> createState() => _SignRequestsScreenState();
}

class _SignRequestsScreenState extends State<SignRequestsScreen> {
  List<SignRequest>? _items;
  Object? _error;
  _Chip _chip = _Chip.all;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    signRequestsVersion.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    signRequestsVersion.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final items = await loadSignRequests();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    final source = await showAppSheet<SignSource>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(SignHe.sourceTitle),
          for (final (s, icon, label) in [
            (SignSource.pdf, Iconsax.document_upload, SignHe.sourcePdf),
            (SignSource.camera, Iconsax.camera, SignHe.sourceCamera),
            (SignSource.gallery, Iconsax.gallery, SignHe.sourceGallery),
          ])
            ListTile(
              key: Key('sign-source-${s.name}'),
              leading: Icon(icon),
              title: Text(label, style: AppText.body),
              minTileHeight: Hit.min + 8,
              onTap: () => Navigator.of(context).pop(s),
            ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    Uint8List? pdf;
    try {
      pdf = await pickSignDocument(source);
    } on FormatException {
      if (mounted) {
        signToast(context, SignHe.imagesFailed, motion: NoticeMotion.error);
      }
      return;
    } catch (_) {
      if (mounted) {
        signToast(context, SignHe.pickFailed, motion: NoticeMotion.error);
      }
      return;
    }
    if (pdf == null || !mounted) return;
    if (pdf.length > 10 * 1024 * 1024) {
      signToast(context, SignHe.tooLarge, motion: NoticeMotion.error);
      return;
    }
    final title = await askSignTitle(context);
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final created = await createSignRequest(pdf, title);
      if (!mounted) return;
      await openSignEditor(context, created);
    } catch (e) {
      if (mounted) {
        signToast(
          context,
          signErrorText(e, SignHe.uploadFailed),
          motion: NoticeMotion.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final items = _items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SignHeader(
              SignHe.listTitle,
              trailing: Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.s),
                child: IconButton.filled(
                  key: const Key('sign-new'),
                  tooltip: SignHe.newRequest,
                  onPressed: _busy ? null : () => unawaited(_create()),
                  icon: const Icon(Iconsax.add),
                ),
              ),
            ),
            if (_busy)
              Padding(
                padding: const EdgeInsets.all(Space.s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Space.s),
                    Text(SignHe.uploading, style: AppText.secondary),
                  ],
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: Row(
                children: [
                  for (final (c, label) in [
                    (_Chip.all, SignHe.chipAll),
                    (_Chip.waiting, SignHe.chipWaiting),
                    (_Chip.signed, SignHe.chipSigned),
                    (_Chip.drafts, SignHe.chipDrafts),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.s),
                      child: ChoiceChip(
                        key: Key('sign-chip-${c.name}'),
                        label: Text(label),
                        selected: _chip == c,
                        onSelected: (_) => setState(() => _chip = c),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: () {
                  if (items == null) {
                    if (_error != null) {
                      return ListView(
                        children: [ErrorView(error: _error!, onRetry: _reload)],
                      );
                    }
                    return const SingleChildScrollView(
                      child: SkeletonList(rows: 5),
                    );
                  }
                  final shown = [
                    for (final r in items)
                      if (_inChip(r, _chip)) r,
                  ];
                  if (shown.isEmpty) {
                    return ListView(
                      children: [
                        EmptyState(
                          icon: Iconsax.edit,
                          title: SignHe.emptyTitle,
                          message: SignHe.emptyBody,
                          actionLabel: SignHe.newRequest,
                          onAction: _busy ? null : () => unawaited(_create()),
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    key: const Key('sign-list'),
                    padding: const EdgeInsets.fromLTRB(
                      Space.page,
                      0,
                      Space.page,
                      Space.xl,
                    ),
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.s),
                    itemBuilder: (context, i) {
                      final r = shown[i];
                      final when =
                          r.completedAt ??
                          r.viewedAt ??
                          r.sentAt ??
                          r.createdAt;
                      return AppCard(
                        key: Key('sign-row-${r.id}'),
                        onTap: () => unawaited(
                          r.editable
                              ? openSignEditor(context, r)
                              : openSignRequest(context, r.id),
                        ),
                        child: Row(
                          children: [
                            Icon(Iconsax.document_text, color: p.muted),
                            const SizedBox(width: Space.m),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.title,
                                    style: AppText.headline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    [
                                      if ((r.signerName ?? '').isNotEmpty)
                                        r.signerName!,
                                      if (when != null)
                                        formatDateHe(when.substring(0, 10)),
                                    ].join(' · '),
                                    style: AppText.secondary.copyWith(
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SignStatusPill(r.status),
                          ],
                        ),
                      );
                    },
                  );
                }(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The title sheet after picking a file. Null = backed out.
Future<String?> askSignTitle(BuildContext context, {String? initial}) {
  final controller = TextEditingController(text: initial ?? '');
  return showAppSheet<String>(
    context,
    builder: (context) {
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle(SignHe.titleLabel),
            TextField(
              key: const Key('sign-title'),
              controller: controller,
              autofocus: true,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: SignHe.titleHint,
                errorText: error,
              ),
            ),
            const SizedBox(height: Space.m),
            FilledButton(
              key: const Key('sign-title-ok'),
              onPressed: () {
                final t = controller.text.trim();
                if (t.isEmpty) {
                  setState(() => error = SignHe.titleRequired);
                  return;
                }
                Navigator.of(context).pop(t);
              },
              child: const Text(SignHe.next),
            ),
          ],
        ),
      );
    },
  );
}
