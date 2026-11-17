// One sign request (/sign-request/:id, also the push target): status, who
// signs, the audit trail (sent / viewed / completed with time, IP and the
// signer's name), the signed PDF (view / share), remind and cancel.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/sign_requests_api.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/sign_he.dart';
import '../../util/phone.dart';
import '../document/pdf_viewer_screen.dart';
import '../document/sheets/s6_share.dart' show pdfSharer, textSharer;
import 'sign_common.dart';

/// Loads one request. Tests replace it.
Future<SignRequest> Function(String id) loadSignRequest = fetchSignRequest;

/// 'YYYY-MM-DDTHH:MM…' (UTC) → '17.11.2026 14:05' in the phone's zone.
String signTimeHe(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return iso;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day}.${t.month}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

class SignRequestScreen extends StatefulWidget {
  const SignRequestScreen({super.key, required this.id});
  final String id;

  @override
  State<SignRequestScreen> createState() => _SignRequestScreenState();
}

class _SignRequestScreenState extends State<SignRequestScreen> {
  SignRequest? _r;
  Object? _error;
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
      final r = await loadSignRequest(widget.id);
      if (mounted) {
        setState(() {
          _r = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _pdf({required bool completed, bool share = false}) =>
      _run(() async {
        final r = _r!;
        final bytes = await fetchSignPdf(r.id, completed: completed);
        if (!mounted) return;
        if (share) {
          await pdfSharer(bytes, r.title);
          return;
        }
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PdfViewerScreen(bytes: bytes, title: r.title),
            fullscreenDialog: true,
          ),
        );
      });

  Future<void> _remind() async {
    final r = _r!;
    final channel = await showAppSheet<SignChannel>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(SignHe.remindTitle),
          for (final (ch, icon, label, ok) in [
            (
              SignChannel.email,
              Iconsax.sms,
              SignHe.sendEmail,
              (r.signerEmail ?? '').isNotEmpty,
            ),
            (
              SignChannel.whatsapp,
              Iconsax.message,
              SignHe.sendWhatsApp,
              waPhone(r.signerPhone) != null,
            ),
            (SignChannel.share, Iconsax.share, SignHe.sendShare, true),
          ])
            if (ok)
              ListTile(
                key: Key('sign-remind-${ch.name}'),
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(ch),
              ),
        ],
      ),
    );
    if (channel == null || !mounted) return;
    await _run(() async {
      final sent = await remindSignRequest(r.id, channel);
      final text = SignHe.shareText(r.title, sent.url);
      if (channel == SignChannel.email && !sent.emailed) {
        if (mounted) {
          signToast(context, SignHe.emailFailed, motion: NoticeMotion.error);
        }
        await textSharer(text);
        return;
      }
      if (channel == SignChannel.whatsapp) {
        await launchAllowed(
          whatsAppUri(phone: waPhone(r.signerPhone), text: text),
        );
      } else if (channel == SignChannel.share) {
        await textSharer(text);
      }
      if (mounted) {
        signToast(context, SignHe.reminded, motion: NoticeMotion.sent);
      }
    });
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(SignHe.cancelConfirmTitle),
        content: const Text(SignHe.cancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text(SignHe.cancelNo),
          ),
          TextButton(
            key: const Key('sign-cancel-yes'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text(SignHe.cancelYes),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await cancelSignRequest(widget.id);
      if (!mounted) return;
      setState(() => _r = r);
      signToast(context, SignHe.cancelled);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SignHeader(SignHe.detailTitle),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: r == null
                    ? ListView(
                        children: [
                          if (_error != null)
                            ErrorView(error: _error!, onRetry: _reload)
                          else
                            const SkeletonList(rows: 4),
                        ],
                      )
                    : _body(context, r),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SignRequest r) {
    final p = context.palette;
    final filled = r.fields.where((f) => f.filled).length;
    final muted = AppText.secondary.copyWith(color: p.muted);
    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool primary = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: SizedBox(
        width: double.infinity,
        height: Hit.primary,
        child: primary
            ? FilledButton.icon(
                key: Key(key),
                onPressed: _busy ? null : onTap,
                icon: Icon(icon),
                label: Text(label),
              )
            : OutlinedButton.icon(
                key: Key(key),
                onPressed: _busy ? null : onTap,
                icon: Icon(icon, color: color),
                label: Text(label, style: TextStyle(color: color)),
              ),
      ),
    );
    return ListView(
      key: const Key('sign-detail'),
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        Space.xl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(r.title, style: AppText.title, maxLines: 3),
                  ),
                  SignStatusPill(r.status),
                ],
              ),
              const SizedBox(height: Space.s),
              Text(
                '${SignHe.signer}: ${r.signerName ?? '—'}',
                style: AppText.body,
              ),
              if ((r.signerEmail ?? '').isNotEmpty)
                Text(
                  r.signerEmail!,
                  style: muted,
                  textDirection: TextDirection.ltr,
                ),
              if ((r.signerPhone ?? '').isNotEmpty)
                Text(formatPhoneHe(r.signerPhone), style: muted),
              if (r.fields.isNotEmpty) ...[
                const SizedBox(height: Space.s),
                Text(SignHe.filledOf(filled, r.fields.length), style: muted),
              ],
              if (r.expiresOn != null && r.waiting)
                Text(
                  '${SignHe.expiry} ${SignHe.expiryOn(formatDateHe(r.expiresOn))}',
                  style: muted,
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        if (r.status == SignStatus.completed) ...[
          action(
            'sign-view-signed',
            Iconsax.document_text,
            SignHe.viewSigned,
            () => unawaited(_pdf(completed: true)),
            primary: true,
          ),
          action(
            'sign-share-signed',
            Iconsax.share,
            SignHe.shareSigned,
            () => unawaited(_pdf(completed: true, share: true)),
          ),
          if (r.sealed != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                r.sealed! ? SignHe.sealedYes : SignHe.sealedNo,
                style: muted,
              ),
            ),
        ],
        if (r.editable)
          action(
            'sign-edit',
            Iconsax.edit,
            SignHe.editFields,
            () => unawaited(openSignEditor(context, r)),
            primary: true,
          ),
        if (r.waiting)
          action(
            'sign-remind',
            Iconsax.notification,
            SignHe.remind,
            () => unawaited(_remind()),
            primary: true,
          ),
        action(
          'sign-view-original',
          Iconsax.document,
          SignHe.viewOriginal,
          () => unawaited(_pdf(completed: false)),
        ),
        if (r.cancellable)
          action(
            'sign-cancel',
            Iconsax.close_circle,
            SignHe.cancel,
            () => unawaited(_cancel()),
            color: p.danger,
          ),
        const SizedBox(height: Space.l),
        if (r.events.isNotEmpty) ...[
          Text(SignHe.timeline, style: AppText.title),
          const SizedBox(height: Space.s),
          for (final e in r.events)
            Padding(
              key: Key('sign-event-${e.type}'),
              padding: const EdgeInsets.only(bottom: Space.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 10, color: p.muted),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            SignHe.event(e.type),
                            SignHe.channel(e.channel),
                          ].where((s) => s.isNotEmpty).join(' '),
                          style: AppText.body,
                        ),
                        Text(
                          [
                            signTimeHe(e.occurredAt),
                            if ((e.signerName ?? '').isNotEmpty) e.signerName!,
                            if ((e.ip ?? '').isNotEmpty) SignHe.ip(e.ip!),
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (r.completedSha256 != null || r.originalSha256 != null)
          Text(
            SignHe.sha(r.completedSha256 ?? r.originalSha256!),
            style: muted,
            textDirection: TextDirection.rtl,
          ),
      ],
    );
  }
}
