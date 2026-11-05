// System dialogs of the issue flow (≤1 field each, not counted as sheets – F4).
// Owner: squad B.

import 'package:flutter/material.dart';

import '../../api/issue_api.dart' show VatStatusAnswer;
import '../../util/labels/labels.dart';

/// ≥ ₪50,000 → one confirmation (§6.C edge). True = continue.
Future<bool> confirmBigAmount(BuildContext context, BigInt totalMinor) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const Key('big-amount-dialog'),
      title: Text(ComposeHe.bigAmountTitle(totalMinor)),
      content: const Text(ComposeHe.bigAmountBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text(CommonHe.cancel)),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text(CommonHe.issue)),
      ],
    ),
  );
  return ok == true;
}

/// §4.9 "{לקוח} הוא עוסק מורשה?" – כן (+ the VAT number field when it is
/// missing) / לא, לקוח פרטי. Null = closed.
Future<VatStatusAnswer?> askVatDealer(BuildContext context,
    {required String customerName, required bool needsNumber}) {
  final number = TextEditingController();
  var missing = false;
  return showDialog<VatStatusAnswer>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        key: const Key('vat-dealer-dialog'),
        title: Text(ComposeHe.vatDealerQuestion(customerName)),
        content: needsNumber
            ? TextField(
                controller: number,
                autofocus: true,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                    labelText: ComposeHe.vatNumber,
                    errorText: missing ? ComposeHe.vatNumber : null),
              )
            : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, const VatStatusAnswer(authorizedDealer: false)),
            child: const Text(ComposeHe.vatDealerNo),
          ),
          TextButton(
            key: const Key('vat-dealer-yes'),
            onPressed: () {
              if (needsNumber && number.text.trim().isEmpty) {
                setState(() => missing = true);
                return;
              }
              Navigator.pop(c, VatStatusAnswer(authorizedDealer: true, taxId: number.text.trim()));
            },
            child: const Text(ComposeHe.vatDealerYes),
          ),
        ],
      ),
    ),
  );
}

/// What the passphrase dialog returns.
class PassphraseEntry {
  const PassphraseEntry(this.passphrase, {required this.save});
  final String passphrase;
  final bool save;
}

/// One field: the signing passphrase. "שמור עם Face ID" keeps it on the
/// device (squad C's signing_api asks Face ID before saving). Null = cancelled.
Future<PassphraseEntry?> askSigningPassphrase(BuildContext context) {
  final field = TextEditingController();
  void submit(BuildContext c) {
    if (field.text.isNotEmpty) Navigator.pop(c, PassphraseEntry(field.text, save: true));
  }

  return showDialog<PassphraseEntry>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      key: const Key('signing-dialog'),
      title: const Text(ComposeHe.signingTitle),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(ComposeHe.signingBody),
        TextField(
          key: const Key('signing-passphrase'),
          controller: field,
          autofocus: true,
          obscureText: true,
          onSubmitted: (_) => submit(c),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text(CommonHe.cancel)),
        TextButton(
          key: const Key('signing-save'),
          onPressed: () => submit(c),
          child: const Text(ComposeHe.signingSaveFaceId),
        ),
      ],
    ),
  );
}
