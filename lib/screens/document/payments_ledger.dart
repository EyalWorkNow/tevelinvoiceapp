// "תקבולים" (SPEC-v2 §3.3, BE-11): the payments ledger, embedded by R (squad
// E) as a report body — not a screen of its own (F4). Owner: squad C.
//
// Row: method · customer, date · receipt number (or "בוטל"), amount. Tap a
// row with a receipt → its D. ⋯ "בטל תשלום" only on a payment that is in no
// receipt, for who may record payments (the server also refuses a payment
// allocated to an issued document → PAYMENT_LOCKED_IN_DOCUMENT, in Hebrew).

import 'package:flutter/material.dart';

import '../../api/models/models.dart';
import '../../api/payments_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import 'dialogs.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class PaymentsLedger extends StatefulWidget {
  const PaymentsLedger({super.key, this.from, this.to, this.pageSize = 50});

  /// 'YYYY-MM-DD' period (R's period chips).
  final String? from;
  final String? to;
  final int pageSize;

  @override
  State<PaymentsLedger> createState() => _PaymentsLedgerState();
}

class _PaymentsLedgerState extends State<PaymentsLedger> {
  final List<PaymentRow> _rows = [];
  int _total = 0;
  bool _loading = true;
  bool _more = false;
  Object? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(PaymentsLedger old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await fetchPaymentsPage(
        from: widget.from,
        to: widget.to,
        offset: reset ? 0 : _rows.length,
        limit: widget.pageSize,
        includeVoided: true,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _rows.clear();
        _rows.addAll(page.rows);
        _total = page.total;
        _more = page.hasMore;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _void(PaymentRow row) async {
    final reason = await askReason(
      context,
      title: DocumentHe.voidPaymentTitle,
      hint: DocumentHe.voidReason,
      confirm: DocumentHe.voidPayment,
    );
    if (reason == null || !mounted) return;
    setState(() => _busyId = row.id);
    try {
      await voidPayment(row.id, reason);
      if (!mounted) return;
      toast(context, DocumentHe.paymentVoided);
      await _load(reset: true);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty && _loading) return const SkeletonList(rows: 4);
    if (_rows.isEmpty && _error != null)
      return ErrorView(error: _error!, onRetry: () => _load(reset: true));
    if (_rows.isEmpty) {
      return const EmptyState(
        icon: Iconsax.moneys,
        title: DocumentHe.ledgerEmpty,
      );
    }
    final canVoid =
        businessContext.can(Cap.paymentRecord) && !businessContext.offline;
    return Column(
      key: const Key('payments-ledger'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in _rows) _row(context, r, canVoid: canVoid),
        if (_more)
          TextButton(
            key: const Key('ledger-more'),
            onPressed: _loading ? null : () => _load(),
            child: Text('${DocumentHe.ledgerMore} (${_total - _rows.length})'),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, PaymentRow r, {required bool canVoid}) {
    final p = context.palette;
    final muted = r.isVoided;
    final sub = [
      if (r.paymentDate != null) formatDateHe(r.paymentDate),
      if (r.isVoided)
        DocumentHe.voidedPayment
      else if (r.receiptDocumentNumber != null)
        DocumentHe.receiptNo(r.receiptDocumentNumber!),
    ].join(' · ');
    return ListTile(
      key: Key('ledger-${r.id}'),
      minTileHeight: Hit.row,
      contentPadding: EdgeInsets.zero,
      title: Text(
        [
          paymentMethodLabel(r.method),
          if (r.customerName != null) r.customerName!,
        ].join(' · '),
        style: AppText.body.copyWith(color: muted ? p.muted : p.ink),
      ),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, style: AppText.secondary.copyWith(color: p.muted)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AmountText(r.amountMinor),
          if (canVoid && r.mayVoid)
            _busyId == r.id
                ? const Padding(
                    padding: EdgeInsets.all(Space.s),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : MoreMenu(
                    items: [
                      MoreMenuItem(
                        label: DocumentHe.voidPayment,
                        destructive: true,
                        onSelected: () => _void(r),
                      ),
                    ],
                  ),
        ],
      ),
      onTap: r.receiptDocumentId == null
          ? null
          : () => openDocument(context, r.receiptDocumentId!),
    );
  }
}
