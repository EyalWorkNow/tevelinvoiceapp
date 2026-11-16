// C6 · "בקש תיקון/זיכוי" (QA 2026-11-16, persona 06 idea 3). Owner: C6.
// The accountant (who never issues or cancels) asks the owner to correct an
// issued document: a reason and, optionally, the amount to credit. The owner
// gets a CORRECTION_REQUESTED inbox card that opens S8 prefilled.
// POST /documents/:id/correction-requests {reason, amountMinor?}.

import 'package:flutter/material.dart';

import '../../api/actions_api.dart' show creditableOf;
import '../../api/documents_api.dart' show issuedStatuses;
import '../../api/models/models.dart';
import '../../api/readiness_api.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../../util/money.dart';

/// The menu item shows for the accountant presets on an issued, not
/// cancelled document that is not itself a credit note.
bool canRequestCorrection(DocumentDetail d) =>
    businessContext.caps.homeIsReports &&
    issuedStatuses.contains(d.status) &&
    d.voidedAt == null &&
    d.documentType != 'CREDIT_DOCUMENT';

/// True when the request was sent.
Future<bool> showCorrectionRequestSheet(
  BuildContext context,
  DocumentDetail doc,
) async {
  final sent = await showAppSheet<bool>(
    context,
    builder: (_) => CorrectionRequestSheet(doc: doc),
  );
  if (sent == true && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(ReadinessHe.sent)));
  }
  return sent == true;
}

class CorrectionRequestSheet extends StatefulWidget {
  const CorrectionRequestSheet({super.key, required this.doc});

  final DocumentDetail doc;

  @override
  State<CorrectionRequestSheet> createState() => _CorrectionRequestSheetState();
}

class _CorrectionRequestSheetState extends State<CorrectionRequestSheet> {
  final _reason = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  String? _invalid;
  Object? _error;

  bool get _creditable => const {
    'TAX_INVOICE',
    'TAX_INVOICE_RECEIPT',
  }.contains(widget.doc.documentType);

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.length < 2) {
      setState(() => _invalid = ReadinessHe.reasonRequired);
      return;
    }
    BigInt? amount;
    if (_creditable && _amount.text.trim().isNotEmpty) {
      amount = parseAmount(_amount.text);
      final max = creditableOf(widget.doc);
      if (amount == null || amount <= BigInt.zero || amount > max) {
        setState(
          () => _invalid = DocumentHe.creditMax(moneyText(context, max)),
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _invalid = null;
      _error = null;
    });
    try {
      await requestCorrection(
        widget.doc.id,
        reason: reason,
        amountMinor: amount,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final doc = widget.doc;
    final problem = _invalid ?? (_error == null ? null : errorTextHe(_error!));
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(
            ReadinessHe.requestTitle,
            subtitle: docTitle(doc.documentType, doc.documentNumber),
          ),
          Text(
            ReadinessHe.requestBody,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.m),
          TextField(
            key: const Key('correction-reason'),
            controller: _reason,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: ReadinessHe.reasonLabel,
              hintText: ReadinessHe.reasonHint,
              counterText: '',
            ),
            onChanged: (_) => setState(() => _invalid = null),
          ),
          if (_creditable) ...[
            const SizedBox(height: Space.s),
            TextField(
              key: const Key('correction-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: ReadinessHe.amountLabel,
                hintText: ReadinessHe.amountHint,
                prefixText: '₪ ',
              ),
              onChanged: (_) => setState(() => _invalid = null),
            ),
          ],
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  problem,
                  key: const Key('correction-error'),
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ),
          const SizedBox(height: Space.l),
          PrimaryButton(
            key: const Key('correction-send'),
            label: ReadinessHe.send,
            offline: businessContext.offline,
            loadingText: _busy ? ReadinessHe.send : null,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}
