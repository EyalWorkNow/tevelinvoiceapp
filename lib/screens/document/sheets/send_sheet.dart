// "שלח" from the documents list (owner 2026-11-17: "מתוך דף מסמכים לשלוח את
// כל סוגי המסמכים שלנו"). A swipe on a row, or a long press, opens:
// * an issued document (every type: 305 · 320 · 300 · 400 · 405 · 330 ·
//   100 · 500) → S6 (WhatsApp with the /d/ link, e-mail with the original
//   PDF through POST /documents/:id/send, copy link, PDF through the share
//   sheet; without doc.send the PDF only);
// * a quote (DRAFT / SENT / ACCEPTED) → the quote send path: WhatsApp with
//   its /d/ page (a DRAFT becomes SENT), POST /quotes/:id/send-email, PDF.
// Drafts, documents waiting for approval / an allocation number / a
// signature, and rows whose amounts are hidden are never offered: only an
// issued original leaves the business (the server refuses the rest too).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../api/actions_api.dart';
import '../../../api/models/models.dart';
import '../../../api/quotes_api.dart'
    show emailQuote, fetchQuote, fetchQuotePdf, setQuoteStatus;
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/labels/labels.dart';
import '../../../util/phone.dart';
import '../dialogs.dart' show toast;
import 's6_share.dart';

/// Statuses of an issued original (the list's "שלח" is offered on these).
const Set<String> sendableDocumentStatuses = {
  'FINALIZED',
  'SIGNED',
  'ARCHIVED',
  'SENT',
};

/// Quotes that can still go to the customer.
const Set<String> sendableQuoteStatuses = {'DRAFT', 'SENT', 'ACCEPTED'};

/// The row may be sent (or, without doc.send, shared as a PDF).
bool canSendFromList(DocumentSummary d, Caps caps) =>
    caps.can(Cap.docView) &&
    !d.amountHidden &&
    sendableDocumentStatuses.contains(d.status);

bool canSendQuoteFromList(QuoteRow q, Caps caps) =>
    caps.can(Cap.docView) &&
    !q.amountHidden &&
    !q.expired &&
    sendableQuoteStatuses.contains(q.status);

/// S6 for a list row; the done-message as a toast. [onSent]: reload the list.
Future<void> sendDocumentFromList(
  BuildContext context,
  DocumentSummary d, {
  VoidCallback? onSent,
}) async {
  final message = await showShareSheet(context, documentId: d.id);
  if (!context.mounted) return;
  if (message != null && message.isNotEmpty) toast(context, message);
  onSent?.call();
}

Future<void> sendQuoteFromList(
  BuildContext context,
  String quoteId, {
  VoidCallback? onSent,
}) async {
  final message = await showAppSheet<String>(
    context,
    builder: (_) => QuoteSendSheet(quoteId: quoteId),
  );
  if (!context.mounted) return;
  if (message != null && message.isNotEmpty) toast(context, message);
  onSent?.call();
}

enum _QuoteBusy { whatsapp, email, pdf }

class QuoteSendSheet extends StatefulWidget {
  const QuoteSendSheet({super.key, required this.quoteId});

  final String quoteId;

  @override
  State<QuoteSendSheet> createState() => _QuoteSendSheetState();
}

class _QuoteSendSheetState extends State<QuoteSendSheet> {
  Quote? _quote;
  Customer? _customer;
  Object? _loadError;
  Object? _error;
  _QuoteBusy? _busy;

  bool get _canSend => businessContext.can(Cap.docSend);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await fetchQuote(widget.quoteId);
      if (q == null) throw StateError('quote ${widget.quoteId} not found');
      Customer? c;
      if (q.customerId != null) {
        try {
          c = await fetchCustomerById(q.customerId!);
        } on Object {
          c = null; // the text just goes without the phone
        }
      }
      if (!mounted) return;
      setState(() {
        _quote = q;
        _customer = c;
        _loadError = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _run(_QuoteBusy b, Future<String?> Function() work) async {
    if (_busy != null) return;
    setState(() {
      _busy = b;
      _error = null;
    });
    try {
      final done = await work();
      if (mounted && done != null) Navigator.of(context).pop(done);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// §8.2.4 text: with the quote's /d/ page when it has lines (BE-06).
  Future<String> _text(Quote q) async {
    String? link;
    if (quoteHasLines(q)) link = await quoteShareUrl(q.id);
    return quoteWhatsAppMessage(
      customerName: q.customerName ?? _customer?.name,
      totalMinor: q.totalMinor,
      validUntil: q.validUntil,
      businessName: businessContext.displayName,
      link: link,
    );
  }

  Future<String?> _whatsApp() async {
    final q = _quote!;
    final text = await _text(q);
    if (!mounted) return null;
    final phone = waPhone(_customer?.phone);
    final opened =
        phone != null &&
        await launchAllowed(whatsAppUri(phone: phone, text: text));
    if (!opened) await textSharer(text);
    if (q.status == 'DRAFT') await setQuoteStatus(q.id, 'SENT');
    return '';
  }

  Future<String?> _pdf() async {
    final q = _quote!;
    final bytes = await fetchQuotePdf(q.id);
    final text = _canSend ? await _text(q) : null;
    if (!mounted) return null;
    await pdfSharer(bytes, DocumentHe.quoteTitle, text: text);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    if (q == null) {
      return SizedBox(
        height: 240,
        child: _loadError == null
            ? const SkeletonList(rows: 3)
            : ErrorView(error: _loadError!, onRetry: _load),
      );
    }
    final p = context.palette;
    final offline = businessContext.offline;
    final hasEmail = (_customer?.email ?? '').trim().isNotEmpty;
    return PopScope(
      canPop: _busy == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(
            DocumentHe.send,
            subtitle:
                '${DocumentHe.quoteTitleNumbered(q.quoteNumber)} · ${moneyText(context, q.totalMinor)}',
          ),
          if (_canSend)
            PrimaryButton(
              key: const Key('send-quote-whatsapp'),
              label: DocumentHe.sendWhatsApp,
              icon: Iconsax.message,
              offline: offline,
              loadingText: _busy == _QuoteBusy.whatsapp
                  ? DocumentHe.sendWhatsApp
                  : null,
              onPressed: () => _run(_QuoteBusy.whatsapp, _whatsApp),
            ),
          if (_canSend && hasEmail)
            _row(
              Iconsax.sms,
              DocumentHe.emailQuote,
              const Key('send-quote-email'),
              _QuoteBusy.email,
              () async => DocumentHe.quoteEmailed(await emailQuote(q.id)),
            ),
          _row(
            Iconsax.document_text,
            DocumentHe.pdf,
            const Key('send-quote-pdf'),
            _QuoteBusy.pdf,
            _pdf,
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
      ),
    );
  }

  Widget _row(
    IconData icon,
    String label,
    Key key,
    _QuoteBusy busy,
    Future<String?> Function() work,
  ) {
    final p = context.palette;
    return ListTile(
      key: key,
      minTileHeight: Hit.row,
      contentPadding: EdgeInsets.zero,
      leading: _busy == busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: p.ink),
      title: Text(label, style: AppText.body.copyWith(color: p.ink)),
      onTap: businessContext.offline || _busy != null
          ? null
          : () => _run(busy, work),
    );
  }
}
