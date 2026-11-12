// Pieces of D (squad C): PDF preview, status line + P0 timeline, banners.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../api/models/models.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../../util/status_map.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Embedded PDF (pinch-zoomable) — replaced in widget tests (no platform view).
Widget Function(Uint8List bytes) pdfPreviewBuilder = (bytes) => _PdfPreview(bytes: bytes);

class _PdfPreview extends StatefulWidget {
  const _PdfPreview({required this.bytes});

  final Uint8List bytes;

  @override
  State<_PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<_PdfPreview> {
  late final PdfControllerPinch _c = PdfControllerPinch(document: PdfDocument.openData(widget.bytes));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PdfViewPinch(
        controller: _c,
        backgroundDecoration: BoxDecoration(color: context.palette.canvas),
      );
}

/// §15.5 list state of [doc] ([extras]: BE-12 sent / viewed, BE-36 open;
/// [row]: BE-10a for an older server; [sentAt]: D's own answer, which also
/// counts a WhatsApp dispatch).
DocListState docStateOf(DocumentDetail doc,
        {DocumentSummary? row, DocumentExtras extras = DocumentExtras.empty, String? sentAt}) =>
    docListState(
      status: doc.status,
      documentType: doc.documentType,
      totalMinor: doc.totalMinor,
      // Hidden amounts (BE-03) arrive as null: never read them as ₪0 / paid.
      openMinor: doc.amountHidden ? null : extras.openMinor ?? row?.openMinor ?? doc.openMinor,
      creditedMinor: doc.amountHidden ? null : doc.creditedMinor ?? row?.creditedMinor,
      voidedAt: doc.voidedAt ?? row?.voidedAt,
      dueDate: doc.dueDate ?? row?.dueDate,
      issueDate: doc.issueDate,
      sentAt: sentAt ?? extras.sentAt ?? row?.sentAt,
      viewedAt: extras.viewedAt,
    );

/// "ממתין לתשלום ₪1,180 · נשלח" + "✓ אושר ברשות המסים"; tap → timeline.
class DocStatusLine extends StatelessWidget {
  const DocStatusLine({
    super.key,
    required this.state,
    this.openMinor,
    this.dueDate,
    this.allocationNumber,
    required this.expanded,
    required this.onTap,
  });

  final DocListState state;
  final BigInt? openMinor;

  /// BE-07: shown as "לתשלום עד …" while the document is open.
  final String? dueDate;
  final String? allocationNumber;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final open = state.status == DocStatus.awaitingPayment || state.status == DocStatus.overdue;
    final words = [
      for (final a in state.attributes) docAttributeLabels[a]!,
    ].join(' · ');
    return Semantics(
      button: true,
      hint: DocumentHe.showTimeline,
      child: InkWell(
        key: const Key('doc-status-line'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Row(
              children: [
                StatusPill.doc(state.status),
                if (open && openMinor != null) ...[
                  const SizedBox(width: Space.s),
                  AmountText(openMinor!),
                ],
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    [
                      if (open && dueDate != null) DocumentHe.dueBy(formatDateHe(dueDate)),
                      if (words.isNotEmpty) words,
                      if (allocationNumber != null) '${DocumentHe.taxAuthorityOk} (\u2066$allocationNumber\u2069)',
                    ].join(' · '),
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ),
                Icon(expanded ? Iconsax.arrow_up_2 : Iconsax.arrow_down_1, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// P0 timeline (BE-12 adds the full one): created / submitted / issued /
/// paid / credited / voided / sent — what the document itself tells.
List<(String, String)> timelineOf(DocumentDetail doc, {DocumentSummary? row, BuildContext? context}) {
  String money(BigInt m) => context == null ? m.toString() : moneyText(context, m);
  return [
    (DocumentHe.timelineCreated, ''),
    if (doc.submittedBy != null) (DocumentHe.timelineSubmitted, ''),
    if (doc.documentNumber != null) (DocumentHe.timelineIssued, formatDateHe(doc.issueDate)),
    if (row?.sentAt != null) (DocumentHe.timelineSent, formatDateHe(row!.sentAt!.split('T').first)),
    if (doc.paidTotalMinor > BigInt.zero) (DocumentHe.timelinePaid, money(doc.paidTotalMinor)),
    if ((doc.creditedMinor ?? BigInt.zero) > BigInt.zero)
      (DocumentHe.timelineCredited, money(doc.creditedMinor!)),
    if (doc.voidedAt != null) (DocumentHe.timelineVoided, formatDateHe(doc.voidedAt!.split('T').first)),
  ];
}

/// BE-12: the server timeline (audit events, oldest first) in words; event
/// types without a label are left out.
List<(String, String)> timelineFromEvents(List<TimelineEvent> events, {BuildContext? context}) {
  String money(Object? v) {
    final m = v == null ? null : BigInt.tryParse(v.toString());
    if (m == null) return '';
    return context == null ? m.toString() : moneyText(context, m);
  }

  return [
    for (final e in events)
      if (DocumentHe.timelineEvents[e.event] case final label?)
        (
          label,
          [
            if (e.event == 'payment.allocated') money(e.detail['amountMinor']),
            if (e.event == 'document.credited') money(e.detail['creditTotalMinor']),
            if (e.event == 'document.sent' && e.detail['recipient'] != null) '${e.detail['recipient']}',
            _localDay(e.at),
          ].where((t) => t.isNotEmpty).join(' · '),
        ),
  ];
}

String _localDay(String at) {
  final t = DateTime.tryParse(at);
  return t == null ? '' : formatDateHe(isoDay(t.toLocal()));
}

/// BE-11 `payments[]`: method · amount · date (voided ones marked).
class DocPaymentsList extends StatelessWidget {
  const DocPaymentsList({super.key, required this.payments});

  final List<DocPayment> payments;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('doc-payments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
          child: Text(DocumentHe.paymentsTitle, style: AppText.headline),
        ),
        for (final pay in payments)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(children: [
              Expanded(
                child: Text(
                  [
                    paymentMethodLabel(pay.method),
                    if (pay.paymentDate != null) formatDateHe(pay.paymentDate),
                    if (pay.voidedAt != null) DocumentHe.voidedPayment,
                  ].join(' · '),
                  style: AppText.body.copyWith(color: pay.voidedAt != null ? p.muted : p.ink),
                ),
              ),
              AmountText(pay.allocatedMinor ?? pay.amountMinor),
            ]),
          ),
      ],
    );
  }
}

/// BE-11 `linkedDocuments[]`: receipts, credits, conversions — tap opens D.
class DocLinksList extends StatelessWidget {
  const DocLinksList({super.key, required this.links, required this.onOpen});

  final List<DocLink> links;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('doc-links'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
          child: Text(DocumentHe.linkedTitle, style: AppText.headline),
        ),
        for (final l in links)
          ListTile(
            key: Key('doc-link-${l.id}'),
            minTileHeight: Hit.row,
            contentPadding: EdgeInsets.zero,
            title: Text(docTitle(l.documentType, l.documentNumber), style: AppText.body),
            subtitle: Text(DocumentHe.linkRelations[l.relation] ?? '',
                style: AppText.secondary.copyWith(color: p.muted)),
            trailing: l.totalMinor == null ? null : AmountText(l.totalMinor!),
            onTap: () => onOpen(l.id),
          ),
      ],
    );
  }
}

class DocTimeline extends StatelessWidget {
  const DocTimeline({super.key, required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('doc-timeline'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (what, detail) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Row(children: [
              Icon(Iconsax.record, size: 8, color: p.muted),
              const SizedBox(width: Space.s),
              Expanded(child: Text(what, style: AppText.body)),
              Text(detail, style: AppText.secondary.copyWith(color: p.muted)),
            ]),
          ),
      ],
    );
  }
}

/// Quote card: header, and the lines with BE-06 (shown while the PDF loads,
/// or instead of it). P0 (list row only): header and a note.
class QuoteCard extends StatelessWidget {
  const QuoteCard({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(quote.customerName ?? '', style: AppText.headline),
          const SizedBox(height: Space.s),
          if (quote.amountHidden)
            const HiddenAmount(style: AppText.amountCard)
          else
            AmountDisplay(amountMinor: quote.totalMinor, style: AppText.amountCard),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.s, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            StatusPill.quote(quoteListStatus(quote.status)),
            if (quote.validUntil != null)
              Text('${DocumentHe.quoteValidUntil} ${formatDateHe(quote.validUntil)}',
                  style: AppText.secondary.copyWith(color: p.muted)),
          ]),
          const SizedBox(height: Space.s),
          if (quote.lines.isEmpty)
            Text(DocumentHe.quoteNoPdf, style: AppText.secondary.copyWith(color: p.muted))
          else ...[
            const Divider(),
            for (final l in quote.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Row(children: [
                  Expanded(child: Text(l.description, style: AppText.body)),
                  if (quote.amountHidden) const HiddenAmount() else AmountText(_lineNet(l)),
                ]),
              ),
            if (quote.notes != null && quote.notes!.isNotEmpty)
              Text(quote.notes!, style: AppText.secondary.copyWith(color: p.muted)),
          ],
        ],
      ),
    );
  }

  /// quantity × unit price − discount (agorot, half-up on the micros).
  static BigInt _lineNet(QuoteLine l) {
    final gross = l.quantityMicros * l.unitPriceMinor;
    final micro = BigInt.from(1000000);
    final rounded = (gross + micro ~/ BigInt.two) ~/ micro;
    return rounded - (l.discountMinor ?? BigInt.zero);
  }
}

/// A draft / pending document has no PDF yet: its lines instead. Also an
/// issued document whose PDF could not be shown ([footer], [onRetry]).
class DraftLinesCard extends StatelessWidget {
  const DraftLinesCard({
    super.key,
    required this.doc,
    this.notes,
    this.customerName,
    this.footer = DocumentHe.draftNoPdf,
    this.onRetry,
  });

  final DocumentDetail doc;

  /// BE-07 note (the PDF prints it after issue).
  final String? notes;
  final String? customerName;
  final String footer;

  /// The PDF failed to load (offline / server): "נסה שוב".
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hidden = doc.amountHidden;
    return AppCard(
      key: const Key('doc-lines'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (customerName != null && customerName!.isNotEmpty) ...[
            Text(customerName!, style: AppText.headline),
            const SizedBox(height: Space.s),
          ],
          for (final l in doc.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Row(children: [
                Expanded(child: Text(l.description, style: AppText.body)),
                if (hidden) const HiddenAmount() else AmountText(l.totalMinor),
              ]),
            ),
          const Divider(),
          Row(children: [
            const Expanded(child: SizedBox()),
            if (hidden)
              const HiddenAmount(key: Key('doc-total-hidden'), style: AppText.amountCard)
            else
              AmountDisplay(amountMinor: doc.totalMinor, style: AppText.amountCard),
          ]),
          if (notes != null && notes!.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text(notes!, key: const Key('doc-notes'), style: AppText.body),
          ],
          if (footer.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Text(footer, key: const Key('doc-lines-footer'), style: AppText.secondary.copyWith(color: p.muted)),
          ],
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('doc-pdf-retry'),
                onPressed: onRetry,
                child: const Text(DocumentHe.retry),
              ),
            ),
        ],
      ),
    );
  }
}

/// "₪•••" where the server redacted an amount (BE-03, as list rows show it).
class HiddenAmount extends StatelessWidget {
  const HiddenAmount({super.key, this.style = AppText.amountRow});

  final TextStyle style;

  @override
  Widget build(BuildContext context) => Semantics(
        label: hiddenAmountSpoken,
        excludeSemantics: true,
        child: Text(hiddenAmountText,
            textDirection: TextDirection.ltr, style: style.copyWith(color: context.palette.muted)),
      );
}

/// A one-line card above the document (after an action, or the rejection reason).
class DocBanner extends StatelessWidget {
  const DocBanner({super.key, required this.text, this.action, this.onAction, this.danger = false});

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = danger ? p.danger : p.ok;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.m),
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        decoration: BoxDecoration(color: p.tint(tone), borderRadius: BorderRadius.circular(Radii.card)),
        child: Row(children: [
          Expanded(child: Text(text, style: AppText.body.copyWith(color: p.ink))),
          if (action != null && onAction != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      ),
    );
  }
}
