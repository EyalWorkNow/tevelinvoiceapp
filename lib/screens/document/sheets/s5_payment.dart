// S5 · תשלום (SPEC-v2 §6 sheets, §9.1, J3). Owner: squad C.
// Amount (default = the open balance) · method chips (§9.1) · cheque fields ·
// "+ תשלום נוסף" · date (today) → "רשום". J3: D "קיבלתי תשלום" → S5 already
// filled → "רשום" (1 tap here).

import 'package:flutter/material.dart';

import '../../../api/actions_api.dart' show fetchDocumentDetail;
import '../../../api/models/models.dart';
import '../../../api/payments_api.dart';
import '../../../state/business_context.dart';
import '../../../state/cache.dart';
import '../../../ui/ds.dart';
import '../../../util/labels/labels.dart';
import '../../../util/money.dart';
import '../dialogs.dart';

/// Opens S5 for an open document. Returns the outcome after "רשום", or null.
Future<PaymentsOutcome?> showPaymentSheet(
  BuildContext context, {
  required String documentId,
  DocumentDetail? doc,
}) {
  return showAppSheet<PaymentsOutcome>(
    context,
    builder: (_) => PaymentSheet(documentId: documentId, doc: doc),
  );
}

String _lastMethodKey() =>
    'last_payment_method_${businessContext.business?.businessId ?? 'none'}';

/// F8: the last method used in S5 (else cash).
Future<String> lastPaymentMethod() async {
  final v = await AppCache.read(_lastMethodKey());
  return v is String && paymentMethodLabels.containsKey(v) ? v : 'CASH';
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({super.key, required this.documentId, this.doc});

  final String documentId;
  final DocumentDetail? doc;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

/// One payment's editable fields.
class _Draft {
  _Draft({required this.method, required String amount, required this.date})
    : amount = TextEditingController(text: amount);

  String method;
  final TextEditingController amount;
  String date;
  bool showMore = false;
  final bank = TextEditingController();
  final branch = TextEditingController();
  final account = TextEditingController();
  final check = TextEditingController();

  PaymentEntry toEntry() => PaymentEntry(
    method: method,
    amountMinor: parseAmount(amount.text) ?? BigInt.zero,
    paymentDate: date,
    reference: method == 'CHECK' ? check.text.trim() : null,
    bankNumber: method == 'CHECK' ? bank.text.trim() : null,
    branchNumber: method == 'CHECK' ? branch.text.trim() : null,
    accountNumber: method == 'CHECK' ? account.text.trim() : null,
  );

  void dispose() {
    for (final c in [amount, bank, branch, account, check]) {
      c.dispose();
    }
  }
}

class _PaymentSheetState extends State<PaymentSheet> {
  DocumentDetail? _doc;
  Object? _loadError;
  final List<_Draft> _drafts = [];
  String? _busy;
  Object? _error;
  String? _invalid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = widget.doc ?? await fetchDocumentDetail(widget.documentId);
      final method = await lastPaymentMethod();
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loadError = null;
        if (_drafts.isEmpty) {
          _drafts.add(
            _Draft(
              method: method,
              amount: agorotToKeypadText(doc.balanceMinor),
              date: isoDay(DateTime.now()),
            ),
          );
        }
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  BigInt get _sum => _drafts.fold(
    BigInt.zero,
    (a, d) => a + (parseAmount(d.amount.text) ?? BigInt.zero),
  );

  /// Local checks before the server: amount > 0, total ≤ balance
  /// (PAYMENT_OVERALLOCATED), cheque details complete (0037: digits).
  String? _validate() {
    for (final d in _drafts) {
      if ((parseAmount(d.amount.text) ?? BigInt.zero) <= BigInt.zero) {
        return PaymentHe.amountRequired;
      }
      if (d.method == 'CHECK') {
        final parts = [
          d.bank.text,
          d.branch.text,
          d.account.text,
          d.check.text,
        ].map((s) => s.trim());
        if (parts.any((s) => s.isEmpty)) return PaymentHe.checkDetailsRequired;
        if (parts.any((s) => !RegExp(r'^\d+$').hasMatch(s))) {
          return PaymentHe.digitsOnly;
        }
      }
    }
    if (_sum > _doc!.balanceMinor) {
      return '${PaymentHe.overBalance} (${moneyText(context, _doc!.balanceMinor)})';
    }
    return null;
  }

  Future<void> _record() async {
    final invalid = _validate();
    setState(() {
      _invalid = invalid;
      _error = null;
    });
    if (invalid != null) return;
    setState(
      () => _busy = paymentNeedsReceipt(_doc!.documentType)
          ? PaymentHe.issuingReceipt
          : PaymentHe.recording,
    );
    try {
      final outcome = await recordPayments(_doc!, [
        for (final d in _drafts) d.toEntry(),
      ], askPassphrase: () => askSigningPassphrase(context));
      await AppCache.write(_lastMethodKey(), _drafts.last.method);
      if (mounted) Navigator.of(context).pop(outcome);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _addPayment() {
    final last = _drafts.last;
    final left = _doc!.balanceMinor - _sum;
    final next = _Draft(
      method: last.method,
      amount: left > BigInt.zero ? agorotToKeypadText(left) : '',
      date: last.date,
    );
    if (last.method == 'CHECK') {
      // §9.1 "+ צ'ק נוסף": same bank, number + 1, a month later, same amount.
      final e = last.toEntry().nextCheck();
      next
        ..amount.text = last.amount.text
        ..date = e.paymentDate
        ..bank.text = e.bankNumber ?? ''
        ..branch.text = e.branchNumber ?? ''
        ..account.text = e.accountNumber ?? ''
        ..check.text = e.reference ?? '';
    }
    setState(() => _drafts.add(next));
  }

  Future<void> _pickDate(_Draft d) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(d.date) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(
        now.year + 2,
      ), // a post-dated cheque carries its own date (§9.1)
    );
    if (picked != null) setState(() => d.date = isoDay(picked));
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) {
      return SizedBox(
        height: 240,
        child: _loadError == null
            ? const SkeletonList(rows: 3)
            : ErrorView(error: _loadError!, onRetry: _load),
      );
    }
    final p = context.palette;
    return PopScope(
      canPop: _busy == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(
            PaymentHe.title,
            subtitle:
                '${PaymentHe.balance}: ${moneyText(context, doc.balanceMinor)}',
          ),
          for (var i = 0; i < _drafts.length; i++) _paymentBlock(i),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('s5-add'),
              onPressed: _busy == null ? _addPayment : null,
              child: Text(
                _drafts.last.method == 'CHECK'
                    ? PaymentHe.addCheck
                    : PaymentHe.addPayment,
              ),
            ),
          ),
          if (_invalid != null || _error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _invalid ?? errorTextHe(_error!),
                  key: const Key('s5-error'),
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ),
          PrimaryButton(
            key: const Key('s5-record'),
            label: PaymentHe.record,
            offline: businessContext.offline,
            loadingText: _busy,
            onPressed: _record,
          ),
        ],
      ),
    );
  }

  Widget _paymentBlock(int i) {
    final d = _drafts[i];
    final p = context.palette;
    final chips = [
      for (final m in primaryPaymentMethods)
        ChipOption(m, paymentMethodLabel(m)),
      if (d.showMore || morePaymentMethods.contains(d.method))
        for (final m in morePaymentMethods) ChipOption(m, paymentMethodLabel(m))
      else
        const ChipOption('_more', PaymentHe.more),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_drafts.length > 1)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${PaymentHe.paymentN} ${i + 1}',
                    style: AppText.headline,
                  ),
                ),
                if (i > 0)
                  TextButton(
                    onPressed: _busy == null
                        ? () => setState(() => _drafts.removeAt(i).dispose())
                        : null,
                    child: const Text(PaymentHe.remove),
                  ),
              ],
            ),
          TextField(
            key: Key('s5-amount-$i'),
            controller: d.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            style: AppText.amountCard,
            decoration: const InputDecoration(
              labelText: PaymentHe.amount,
              prefixText: '₪ ',
            ),
            onChanged: (_) => setState(() => _invalid = null),
          ),
          const SizedBox(height: Space.s),
          ChipRow<String>(
            options: chips,
            selected: d.method,
            onSelected: (m) => setState(() {
              if (m == '_more') {
                d.showMore = true;
              } else {
                d.method = m;
              }
            }),
          ),
          if (d.method == 'CHECK') ...[
            Row(
              children: [
                Expanded(
                  child: _digits(d.bank, PaymentHe.bank, Key('s5-bank-$i')),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: _digits(
                    d.branch,
                    PaymentHe.branch,
                    Key('s5-branch-$i'),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _digits(
                    d.account,
                    PaymentHe.account,
                    Key('s5-account-$i'),
                  ),
                ),
                const SizedBox(width: Space.s),
                Expanded(
                  child: _digits(
                    d.check,
                    PaymentHe.checkNumber,
                    Key('s5-check-$i'),
                  ),
                ),
              ],
            ),
          ],
          ListTile(
            key: Key('s5-date-$i'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: Hit.min,
            title: Text(
              d.method == 'CHECK' ? PaymentHe.checkDate : PaymentHe.date,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            trailing: Text(relativeDateHe(d.date), style: AppText.body),
            onTap: _busy == null ? () => _pickDate(d) : null,
          ),
        ],
      ),
    );
  }

  Widget _digits(TextEditingController c, String label, Key key) => TextField(
    key: key,
    controller: c,
    keyboardType: TextInputType.number,
    textDirection: TextDirection.ltr,
    decoration: InputDecoration(labelText: label),
  );
}
