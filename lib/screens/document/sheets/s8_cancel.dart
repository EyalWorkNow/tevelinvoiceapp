// S8 · בטל / זכה (SPEC-v2 §6 sheets, §8.3, J6). Owner: squad C.
// 305/320: opens on "זיכוי מלא ₪X" in an amount field that can be typed over
// (= partial) → red "הפק זיכוי". 300/100/500 (BE-36): "בטל מסמך" with a
// reason. J6 = ⋯ → "בטל / זכה" → (type) → "הפק זיכוי": the field has focus.

import 'package:flutter/material.dart';

import '../../../api/actions_api.dart';
import '../../../api/models/models.dart';
import '../../../state/business_context.dart';
import '../../../ui/ds.dart';
import '../../../util/cancel_policy.dart';
import '../../../util/labels/labels.dart';
import '../../../util/money.dart';
import '../dialogs.dart';

/// What S8 did (D shows the toast and reloads; a credit opens its own D).
class CancelResult {
  const CancelResult({this.credit, this.voided = false});

  final CreditOutcome? credit;
  final bool voided;
}

Future<CancelResult?> showCancelSheet(BuildContext context,
    {required String documentId, DocumentDetail? doc}) {
  return showAppSheet<CancelResult>(
    context,
    builder: (_) => CancelSheet(documentId: documentId, doc: doc),
  );
}

class CancelSheet extends StatefulWidget {
  const CancelSheet({super.key, required this.documentId, this.doc});

  final String documentId;
  final DocumentDetail? doc;

  @override
  State<CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<CancelSheet> {
  DocumentDetail? _doc;
  Object? _loadError;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _invalid;
  Object? _error;

  /// Server-confirmed maximum after CREDIT_LIMIT_EXCEEDED.
  BigInt? _max;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = widget.doc ?? await fetchDocumentDetail(widget.documentId);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loadError = null;
        _amount.text = agorotToKeypadText(creditableOf(doc));
      });
      // Typing over the amount = partial credit, without an extra tap (J6).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _action != CancelAction.credit) return;
        _focus.requestFocus();
        _amount.selection = TextSelection(baseOffset: 0, extentOffset: _amount.text.length);
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    _focus.dispose();
    super.dispose();
  }

  CancelAction get _action => cancelActionFor(_doc!.documentType, vatExempt: businessContext.isVatExempt);

  CancelFacts get _facts => CancelFacts(
        documentType: _doc!.documentType,
        status: _doc!.status,
        totalMinor: _doc!.totalMinor,
        creditedMinor: _doc!.creditedMinor,
        paidMinor: _doc!.paidTotalMinor,
        voidedAt: _doc!.voidedAt,
      );

  BigInt get _limit => _max ?? creditableOf(_doc!);

  Future<void> _credit() async {
    final amount = parseAmount(_amount.text) ?? BigInt.zero;
    if (amount <= BigInt.zero || amount > _limit) {
      setState(() => _invalid = DocumentHe.creditMax(moneyText(context, _limit)));
      return;
    }
    setState(() {
      _busy = true;
      _invalid = null;
      _error = null;
    });
    try {
      final out = await creditDocument(_doc!,
          amountMinor: amount, askPassphrase: () => askSigningPassphrase(context));
      if (mounted) Navigator.of(context).pop(CancelResult(credit: out));
    } on CreditLimitExceeded catch (e) {
      if (mounted) {
        setState(() {
          _max = e.maxMinor;
          _invalid = DocumentHe.creditMax(moneyText(context, e.maxMinor));
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _void() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _invalid = DocumentHe.reasonRequired);
      return;
    }
    setState(() {
      _busy = true;
      _invalid = null;
      _error = null;
    });
    try {
      await voidDocument(_doc!.id, _reason.text);
      if (mounted) Navigator.of(context).pop(const CancelResult(voided: true));
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) {
      return SizedBox(
        height: 240,
        child: _loadError == null ? const SkeletonList(rows: 3) : ErrorView(error: _loadError!, onRetry: _load),
      );
    }
    final p = context.palette;
    final action = _action;
    final note = Text.rich(
      TextSpan(text: _invalid ?? (_error == null ? null : errorTextHe(_error!))),
      key: const Key('s8-error'),
      style: AppText.body.copyWith(color: p.danger),
    );
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(DocumentHe.cancelTitle, subtitle: docTitle(doc.documentType, doc.documentNumber)),
          if (action == CancelAction.credit) ..._creditBody(doc, p),
          if (action == CancelAction.voidDocument) ..._voidBody(doc, p),
          if (action == CancelAction.none)
            Text(CommonHe.continueOnComputer, style: AppText.body.copyWith(color: p.muted)),
          if (_invalid != null || _error != null)
            Padding(padding: const EdgeInsets.only(bottom: Space.s), child: Semantics(liveRegion: true, child: note)),
          if (action == CancelAction.credit)
            PrimaryButton(
              key: const Key('s8-credit'),
              label: DocumentHe.issueCredit,
              destructive: true,
              offline: businessContext.offline,
              loadingText: _busy ? DocumentHe.issueCredit : null,
              onPressed: _credit,
            ),
          if (action == CancelAction.voidDocument && !voidBlockedByPayments(_facts))
            PrimaryButton(
              key: const Key('s8-void'),
              label: DocumentHe.voidDocument,
              destructive: true,
              offline: businessContext.offline,
              loadingText: _busy ? DocumentHe.voidDocument : null,
              onPressed: _void,
            ),
        ],
      ),
    );
  }

  List<Widget> _creditBody(DocumentDetail doc, AppPalette p) {
    final amount = parseAmount(_amount.text) ?? BigInt.zero;
    final full = amount == _limit;
    return [
      Text(
        full ? DocumentHe.fullCredit(moneyText(context, _limit)) : DocumentHe.partialCredit,
        key: const Key('s8-kind'),
        style: AppText.headline,
      ),
      const SizedBox(height: Space.s),
      TextField(
        key: const Key('s8-amount'),
        controller: _amount,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        style: AppText.amountCard,
        decoration: const InputDecoration(labelText: DocumentHe.creditAmount, prefixText: '₪ '),
        onChanged: (_) => setState(() => _invalid = null),
      ),
      const SizedBox(height: Space.m),
      Text(DocumentHe.creditEffect, style: AppText.secondary.copyWith(color: p.muted)),
      if (doc.documentType == 'TAX_INVOICE_RECEIPT')
        Text(DocumentHe.credit320Note, style: AppText.secondary.copyWith(color: p.muted)),
      if (doc.paidTotalMinor > BigInt.zero)
        Text(DocumentHe.creditPaidNote,
            key: const Key('s8-paid-note'), style: AppText.secondary.copyWith(color: p.muted)),
      const SizedBox(height: Space.l),
    ];
  }

  List<Widget> _voidBody(DocumentDetail doc, AppPalette p) {
    if (voidBlockedByPayments(_facts)) {
      return [
        Text(DocumentHe.voidHasPayments, key: const Key('s8-void-blocked'), style: AppText.body),
        const SizedBox(height: Space.l),
      ];
    }
    return [
      Text(DocumentHe.voidEffect, style: AppText.secondary.copyWith(color: p.muted)),
      const SizedBox(height: Space.s),
      TextField(
        key: const Key('s8-reason'),
        controller: _reason,
        maxLength: 300,
        decoration: const InputDecoration(labelText: DocumentHe.voidReason, counterText: ''),
      ),
      const SizedBox(height: Space.l),
    ];
  }
}
