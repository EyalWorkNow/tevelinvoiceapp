// SA2 · D for a document in WAITING_FOR_ALLOCATION: what is happening, what
// the user can do (wait · enter the number by hand · cancel the request), and
// the money that waits with it on the server ("תשלום ממתין: ₪X ביט, יירשם
// כשיתקבל מספר ההקצאה"), editable and cancellable while it waits.

import 'package:flutter/material.dart';

import '../../api/issue_api.dart' show PendingPayment;
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../../util/money.dart';

class WaitingAllocationCard extends StatelessWidget {
  const WaitingAllocationCard({
    super.key,
    required this.pending,
    this.onManual,
    this.onCancelRequest,
    this.onEditPayment,
    this.onCancelPayment,
    this.amountHidden = false,
  });

  /// The PENDING payments of the document (server copy).
  final List<PendingPayment> pending;

  /// Null = not offered (no permission, manual entry off, busy or offline).
  final VoidCallback? onManual;
  final VoidCallback? onCancelRequest;
  final void Function(PendingPayment p)? onEditPayment;
  final void Function(PendingPayment p)? onCancelPayment;

  /// No money:read for this viewer: amounts are not shown.
  final bool amountHidden;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final muted = AppText.secondary.copyWith(color: p.muted);
    final options = <String>[
      PendingPaymentHe.optionWait,
      if (onManual != null) PendingPaymentHe.optionManual,
      if (onCancelRequest != null)
        pending.isEmpty
            ? PendingPaymentHe.optionCancel
            : PendingPaymentHe.optionCancelWithPayment,
    ];
    return AppCard(
      key: const Key('doc-waiting-allocation'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(PendingPaymentHe.waitingTitle, style: AppText.title),
          ),
          const SizedBox(height: Space.s),
          Text(PendingPaymentHe.waitingWhy, style: AppText.body),
          if (!amountHidden)
            for (final pay in pending)
              Padding(
                key: Key('doc-pending-payment-${pay.id}'),
                padding: const EdgeInsets.only(top: Space.m),
                child: Container(
                  padding: const EdgeInsets.all(Space.m),
                  decoration: BoxDecoration(
                    color: p.tint(p.ok),
                    borderRadius: BorderRadius.circular(Radii.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        PendingPaymentHe.pendingLine(
                          pay.amountMinor,
                          pay.method,
                        ),
                        style: AppText.body.copyWith(color: p.ink),
                      ),
                      if (onEditPayment != null || onCancelPayment != null)
                        Wrap(
                          spacing: Space.s,
                          children: [
                            if (onEditPayment != null)
                              TextButton(
                                key: Key('pending-edit-${pay.id}'),
                                onPressed: () => onEditPayment!(pay),
                                child: const Text(PendingPaymentHe.edit),
                              ),
                            if (onCancelPayment != null)
                              TextButton(
                                key: Key('pending-cancel-${pay.id}'),
                                onPressed: () => onCancelPayment!(pay),
                                child: const Text(
                                  PendingPaymentHe.cancelPayment,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: Space.m),
          Text(PendingPaymentHe.whatNow, style: AppText.body),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('• $o', style: muted),
            ),
          if (onManual != null || onCancelRequest != null)
            Wrap(
              spacing: Space.s,
              children: [
                if (onManual != null)
                  TextButton(
                    key: const Key('doc-waiting-manual'),
                    onPressed: onManual,
                    child: const Text(PendingPaymentHe.enterNumber),
                  ),
                if (onCancelRequest != null)
                  TextButton(
                    key: const Key('doc-waiting-cancel'),
                    onPressed: onCancelRequest,
                    child: const Text(PendingPaymentHe.cancelRequest),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "עריכת התשלום הממתין": the amount (₪). Null = cancelled.
Future<BigInt?> askPendingAmount(BuildContext context, BigInt current) =>
    showDialog<BigInt>(
      context: context,
      builder: (_) => _AmountDialog(current: current),
    );

/// "לבטל את התשלום הממתין?" → true = cancel it.
Future<bool> confirmCancelPendingPayment(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(PendingPaymentHe.cancelTitle),
        content: const Text(PendingPaymentHe.cancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(PendingPaymentHe.keep),
          ),
          TextButton(
            key: const Key('pending-cancel-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(PendingPaymentHe.cancelPayment),
          ),
        ],
      ),
    ) ==
    true;

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.current});

  final BigInt current;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _c = TextEditingController(
    text: agorotToKeypadText(widget.current),
  );
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = parseAmount(_c.text);
    if (v == null || v <= BigInt.zero) {
      setState(() => _error = PendingPaymentHe.amountInvalid);
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(PendingPaymentHe.editTitle),
    content: TextField(
      key: const Key('pending-amount-field'),
      controller: _c,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        hintText: PendingPaymentHe.amountHint,
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(CommonHe.cancel),
      ),
      TextButton(
        key: const Key('pending-amount-save'),
        onPressed: _submit,
        child: const Text(CommonHe.save),
      ),
    ],
  );
}
