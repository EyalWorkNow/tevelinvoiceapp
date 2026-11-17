// Shared pieces of "מסמך לחתימה": status pill, page image, toast, header.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/sign_requests_api.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/sign_he.dart';
import '../../util/labels/status_he.dart' show Tone;

/// Loads a page PNG. Tests replace it (no server).
Future<Uint8List> Function(String id, int page) loadSignPage = fetchSignPage;

class SignStatusPill extends StatelessWidget {
  const SignStatusPill(this.status, {super.key});
  final SignStatus status;

  static Tone toneOf(SignStatus s) => switch (s) {
    SignStatus.completed => Tone.ok,
    SignStatus.sent || SignStatus.viewed => Tone.info,
    SignStatus.expired || SignStatus.cancelled => Tone.danger,
    SignStatus.draft => Tone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.tone(toneOf(status));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s + 2, vertical: 2),
      decoration: BoxDecoration(
        color: p.tint(color),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        SignHe.status(status),
        maxLines: 1,
        style: AppText.secondary.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Screen title row: big title + back button (the app's header pattern).
class SignHeader extends StatelessWidget {
  const SignHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.page,
      Space.m,
      Space.page,
      Space.s,
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: AppText.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        ?trailing,
        if (ModalRoute.of(context)?.canPop ?? false) const DesignBackButton(),
      ],
    ),
  );
}

void signToast(
  BuildContext context,
  String text, {
  NoticeMotion motion = NoticeMotion.saved,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showNotchNotice(SnackBar(content: Text(text)), motion: motion);
}

String signErrorText(Object e, String fallback) {
  if (e is ApiException) {
    return switch (e.code) {
      'NOT_A_PDF' => SignHe.notPdf,
      'FILE_TOO_LARGE' => SignHe.tooLarge,
      'TOO_MANY_PAGES' => SignHe.tooManyPages,
      'SIGNER_EMAIL_MISSING' => SignHe.emailRequired,
      _ => e.messageHe.isNotEmpty ? e.messageHe : fallback,
    };
  }
  return fallback;
}

/// One page of the request as an image; keeps the page aspect while loading.
class SignPageImage extends StatefulWidget {
  const SignPageImage({
    super.key,
    required this.requestId,
    required this.index,
    required this.aspect,
    required this.cache,
  });
  final String requestId;
  final int index;
  final double aspect;
  final Map<int, Uint8List> cache;

  @override
  State<SignPageImage> createState() => _SignPageImageState();
}

class _SignPageImageState extends State<SignPageImage> {
  Future<Uint8List>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final cached = widget.cache[widget.index];
    _future = cached != null
        ? Future.value(cached)
        : loadSignPage(widget.requestId, widget.index).then((b) {
            widget.cache[widget.index] = b;
            return b;
          });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
        }
        if (snap.hasError) {
          return InkWell(
            onTap: () => setState(_load),
            child: Center(
              child: Text(
                SignHe.pageFailed,
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          );
        }
        return ColoredBox(
          color: p.surface,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
