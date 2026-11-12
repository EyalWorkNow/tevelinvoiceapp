// System dialogs of D / S5 / S6 / S8 (≤1 field each — not sheets, F4).
// Owner: squad C. B may import [askSigningPassphrase] for the Composer.

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/signing_api.dart' show PassphraseAnswer;
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';

/// "למה לדחות?" — one required field. Null = cancelled.
Future<String?> askReason(BuildContext context,
    {String title = DocumentHe.rejectTitle, String hint = DocumentHe.rejectHint, String? confirm}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _OneFieldDialog(
      title: title,
      hint: hint,
      confirm: confirm ?? DocumentHe.reject,
      required: DocumentHe.reasonRequired,
      fieldKey: const Key('reason-field'),
    ),
  );
}

/// "מספר הקצאה" — digits. Null = cancelled.
Future<String?> askManualAllocation(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _OneFieldDialog(
        title: DocumentHe.manualTitle,
        hint: DocumentHe.manualHint,
        confirm: CommonHe.save,
        required: DocumentHe.manualHint,
        digits: true,
        fieldKey: Key('allocation-field'),
      ),
    );

/// "סיסמת החתימה" with "שמור עם Face ID" (on by default, §6.C step 4).
Future<PassphraseAnswer?> askSigningPassphrase(BuildContext context) =>
    showDialog<PassphraseAnswer>(context: context, builder: (_) => const _PassphraseDialog());

/// CONSENT_REQUIRED on e-mail (S6): true = the customer agreed; false =
/// "שלח בווטסאפ במקום"; null = dismissed.
Future<bool?> askEmailConsent(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(DocumentHe.consentTitle),
        content: const Text(DocumentHe.consentBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(DocumentHe.consentNoWhatsApp)),
          TextButton(
              key: const Key('consent-yes'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text(DocumentHe.consentYes)),
        ],
      ),
    );

/// "המשך במחשב" (§13.9, P0): a mail to myself with the topic.
Future<void> continueOnComputer(BuildContext context, String topic) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(DocumentHe.continueOnComputerTitle),
      content: const Text(DocumentHe.continueOnComputerBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(CommonHe.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(context, true), child: const Text(DocumentHe.sendMeLink)),
      ],
    ),
  );
  if (ok != true) return;
  final email = session.account?.email ?? '';
  await launchAllowed(Uri(
    scheme: 'mailto',
    path: email,
    query: 'subject=${Uri.encodeComponent('תבל – $topic')}',
  ));
}

/// App-wide action feedback.
void toast(BuildContext context, String text, {NoticeMotion motion = NoticeMotion.saved}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m
    ?..hideCurrentNotchNotice()
    ..showNotchNotice(SnackBar(content: Text(text)), motion: motion);
}

class _OneFieldDialog extends StatefulWidget {
  const _OneFieldDialog({
    required this.title,
    required this.hint,
    required this.confirm,
    required this.required,
    required this.fieldKey,
    this.digits = false,
  });

  final String title;
  final String hint;
  final String confirm;
  final String required;
  final Key fieldKey;
  final bool digits;

  @override
  State<_OneFieldDialog> createState() => _OneFieldDialogState();
}

class _OneFieldDialogState extends State<_OneFieldDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    final bad = v.isEmpty || (widget.digits && !RegExp(r'^\d{9,}$').hasMatch(v));
    if (bad) {
      setState(() => _error = widget.required);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: widget.fieldKey,
          controller: _c,
          autofocus: true,
          maxLength: widget.digits ? 20 : 300,
          keyboardType: widget.digits ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(hintText: widget.hint, errorText: _error, counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(CommonHe.cancel)),
          TextButton(key: const Key('dialog-confirm'), onPressed: _submit, child: Text(widget.confirm)),
        ],
      );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _c = TextEditingController();
  bool _remember = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    if (_c.text.isEmpty) return;
    Navigator.pop(context, (passphrase: _c.text, remember: _remember));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text(DocumentHe.passphraseTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('passphrase-field'),
              controller: _c,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(hintText: DocumentHe.passphraseHint),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: const Text(DocumentHe.rememberWithFaceId, style: AppText.secondary),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text(CommonHe.cancel)),
          TextButton(
              key: const Key('passphrase-confirm'),
              onPressed: _submit,
              child: const Text(DocumentHe.saveWithFaceId)),
        ],
      );
}
