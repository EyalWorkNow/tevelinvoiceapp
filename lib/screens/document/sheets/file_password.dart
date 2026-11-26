// §7 "קובץ מוגן בסיסמה" (V2): the password card (big letters + "העתק"),
// sending the password as its own WhatsApp / SMS message, the document
// page's "נשלח מוגן · הצג סיסמה" row and its sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../api/client.dart';
import '../../../api/models/models.dart';
import '../../../api/protected_files_api.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/errors_he.dart';
import '../../../util/file_password.dart';
import '../../../util/labels/labels.dart';
import '../../../util/phone.dart';
import '../../../util/sms_composer.dart';
import '../../../util/still_here.dart';

/// The password in big letters with a copy button (haptic + "הועתק").
class FilePasswordCard extends StatefulWidget {
  const FilePasswordCard({super.key, required this.password, this.hint});

  final String password;

  /// Line under the password (null = none).
  final String? hint;

  @override
  State<FilePasswordCard> createState() => _FilePasswordCardState();
}

class _FilePasswordCardState extends State<FilePasswordCard> {
  bool _copied = false;
  Timer? _reset;

  @override
  void didUpdateWidget(FilePasswordCard old) {
    super.didUpdateWidget(old);
    if (old.password != widget.password) _copied = false;
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.password));
    unawaited(HapticFeedback.mediumImpact());
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      key: const Key('file-password-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Iconsax.lock_1, size: 18, color: p.muted),
              const SizedBox(width: Space.s),
              Text(
                ProtectedHe.passwordLabel,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: ProtectedHe.passwordLabel,
                  value: widget.password.split('').join(' '),
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      displayFilePassword(widget.password),
                      key: const Key('file-password-text'),
                      textDirection: TextDirection.ltr,
                      style: AppText.displayTitle.copyWith(
                        color: p.ink,
                        letterSpacing: 3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.m),
              Semantics(
                button: true,
                label: ProtectedHe.copySemantics,
                excludeSemantics: true,
                child: FilledButton.tonalIcon(
                  key: const Key('file-password-copy'),
                  onPressed: _copy,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, Hit.row),
                  ),
                  icon: Icon(
                    _copied ? Icons.check_rounded : Iconsax.copy,
                    size: 18,
                  ),
                  label: Text(
                    _copied ? ProtectedHe.copied : ProtectedHe.copy,
                    style: AppText.button,
                  ),
                ),
              ),
            ],
          ),
          if (widget.hint != null) ...[
            const SizedBox(height: Space.s),
            Text(
              widget.hint!,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "שלח סיסמה בוואטסאפ" / "שלח סיסמה ב־SMS": the password as its own
/// message, never with the file. Returns a done-message, or null.
Future<String?> sendPasswordWhatsApp(String password, {String? phone}) async {
  final text = ProtectedHe.passwordMessage(
    businessContext.displayName,
    password,
  );
  final opened = await launchAllowed(
    whatsAppUri(phone: waPhone(phone), text: text),
  );
  if (!opened) {
    throw ApiException(503, 'WHATSAPP_UNAVAILABLE', errorMessageHe('NETWORK'));
  }
  return '';
}

Future<String?> sendPasswordSms(String password, {String? phone}) async {
  final number = waPhone(phone);
  if (number == null) {
    throw ApiException(
      422,
      'CUSTOMER_PHONE_INVALID',
      BusinessHe.validPhoneRequired,
    );
  }
  final result = await smsComposer(
    '+$number',
    ProtectedHe.passwordMessage(businessContext.displayName, password),
  );
  if (result == 'SENT') return ProtectedHe.smsSent;
  if (result == 'UNAVAILABLE') {
    throw ApiException(503, 'SMS_UNAVAILABLE', BusinessHe.smsUnavailable);
  }
  if (result == 'FAILED') {
    throw ApiException(502, 'SMS_FAILED', BusinessHe.smsFailed);
  }
  return null; // cancelled: nothing was sent
}

/// The card + the two "send the password" actions (after a protected send,
/// and on the document page). [onDone] closes the surface.
class PasswordSendPanel extends StatefulWidget {
  const PasswordSendPanel({
    super.key,
    required this.password,
    this.phone,
    this.onDone,
    this.header,
  });

  final String password;
  final String? phone;
  final ValueChanged<String?>? onDone;
  final Widget? header;

  @override
  State<PasswordSendPanel> createState() => _PasswordSendPanelState();
}

class _PasswordSendPanelState extends State<PasswordSendPanel> {
  late final TextEditingController _phone = TextEditingController(
    text: widget.phone ?? '',
  );
  String? _busy;
  Object? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  bool get _needsPhone => waPhone(widget.phone) == null;

  Future<void> _run(String which, Future<String?> Function() work) async {
    if (_busy != null) return;
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      final done = await work();
      if (!mounted) return;
      if (done != null && done.isNotEmpty) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(done)));
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final offline = businessContext.offline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?widget.header,
        FilePasswordCard(password: widget.password),
        const SizedBox(height: Space.l),
        if (_needsPhone) ...[
          TextField(
            key: const Key('password-phone-field'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: ProtectedHe.phoneLabel,
            ),
          ),
          const SizedBox(height: Space.m),
        ],
        // Not a PrimaryButton: S6 turns into this panel in place, and the
        // sheet keeps one primary (F2) — the send it just made.
        FilledButton.icon(
          key: const Key('password-whatsapp'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(Hit.primary),
            backgroundColor: p.accent,
            foregroundColor: p.accentInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.button),
            ),
          ),
          onPressed: offline || _busy != null
              ? null
              : () => _run(
                  'wa',
                  () =>
                      sendPasswordWhatsApp(widget.password, phone: _phone.text),
                ),
          icon: _busy == 'wa'
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Iconsax.message, size: 20),
          label: const Text(ProtectedHe.sendWhatsApp, style: AppText.button),
        ),
        const SizedBox(height: Space.s),
        ListTile(
          key: const Key('password-sms'),
          minTileHeight: Hit.row,
          contentPadding: EdgeInsets.zero,
          leading: _busy == 'sms'
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Iconsax.sms, color: p.ink),
          title: Text(
            ProtectedHe.sendSms,
            style: AppText.body.copyWith(color: p.ink),
          ),
          onTap: offline || _busy != null
              ? null
              : () => _run(
                  'sms',
                  () => sendPasswordSms(widget.password, phone: _phone.text),
                ),
        ),
        if (widget.onDone != null)
          TextButton(
            key: const Key('password-done'),
            onPressed: _busy != null ? null : () => widget.onDone!(null),
            child: const Text(ProtectedHe.done),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorTextHe(_error!),
                style: AppText.body.copyWith(color: p.danger),
              ),
            ),
          ),
      ],
    );
  }
}

/// Document page row: "נשלח מוגן · הצג סיסמה" when this document went out
/// protected. Only for who may see the document (`document:read`); hidden
/// while loading, offline or on an older server.
class ProtectedSendTile extends StatefulWidget {
  const ProtectedSendTile({super.key, required this.documentId, this.customer});

  final String documentId;
  final Customer? customer;

  @override
  State<ProtectedSendTile> createState() => _ProtectedSendTileState();
}

class _ProtectedSendTileState extends State<ProtectedSendTile> {
  DocumentProtection? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (businessContext.can(Cap.docView)) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final s = await fetchDocumentProtection(widget.documentId);
      if (mounted) setState(() => _state = s);
    } on Object {
      // Older server / offline: the row stays hidden.
    }
  }

  Future<void> _open() async {
    final send = _state!.sends.first;
    setState(() => _busy = true);
    try {
      final password = await revealProtectedPassword(
        widget.documentId,
        send.id,
      );
      if (!mounted) return;
      await showAppSheet<void>(
        context,
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle(ProtectedHe.sheetTitle),
            PasswordSendPanel(
              password: password,
              phone: widget.customer?.phone,
              onDone: (_) {
                if (stillHere(sheet)) Navigator.of(sheet).pop();
              },
            ),
          ],
        ),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null || s.sends.isEmpty) return const SizedBox.shrink();
    final last = s.sends.first;
    final p = context.palette;
    return ListTile(
      key: const Key('doc-protected'),
      contentPadding: EdgeInsets.zero,
      minTileHeight: Hit.row,
      leading: _busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Iconsax.lock_1),
      title: const Text(ProtectedHe.showRow, style: AppText.body),
      subtitle: Text(
        ProtectedHe.lastSent(
          relativeDateHe(
            DateTime.tryParse(last.createdAt)?.toLocal().toIso8601String() ??
                last.createdAt,
          ),
          link: last.channel == 'LINK',
        ),
        style: AppText.secondary.copyWith(color: p.muted),
      ),
      trailing: const Icon(Iconsax.arrow_left_2),
      onTap: _busy ? null : _open,
    );
  }
}
