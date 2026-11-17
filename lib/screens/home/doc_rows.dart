// DocRow builders shared by H (אחרונים) and L (squad A). Status words come
// only from status_map → StatusPill (AT-91).

import 'package:flutter/material.dart';

import '../../api/documents_api.dart' show isDraftStatus;
import '../../api/models/models.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/inbox_he.dart';
import '../../util/labels/status_he.dart';
import '../../util/status_map.dart';

/// "חשבונית מס · 1043" (number kept left-to-right inside Hebrew).
String docSubtitle(DocumentSummary d) {
  final type = rowTypeLabels[d.documentType] ?? d.documentType;
  final n = d.documentNumber;
  return n == null || n.isEmpty ? type : '$type · ${ltrIsolate(n)}';
}

/// §15.5 state of a list row.
DocListState rowState(DocumentSummary d, {DateTime? today}) => docListState(
  status: d.status,
  documentType: d.documentType,
  totalMinor: d.totalMinor,
  openMinor: d.openMinor,
  creditedMinor: d.creditedMinor,
  voidedAt: d.voidedAt,
  dueDate: d.dueDate,
  issueDate: d.issueDate,
  sentAt: d.sentAt,
  today: today,
);

Widget docRowFor(
  DocumentSummary d, {
  required VoidCallback onTap,
  VoidCallback? onDelete,
  VoidCallback? onSend,
  DateTime? today,
  Key? key,
}) {
  final st = rowState(d, today: today);
  String dateStr = '';
  if (d.issueDate != null) {
    final dt = DateTime.tryParse(d.issueDate!);
    if (dt != null) {
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final yr = (dt.year % 100).toString().padLeft(2, '0');
      dateStr = '$day.$month.$yr';
    }
  }
  final row = DocRow(
    key: key ?? Key('doc-${d.id}'),
    title: (d.customerName == null || d.customerName!.isEmpty)
        ? InboxHe.noCustomer
        : d.customerName!,
    subtitle: docSubtitle(d),
    // #11: a credit note (330) gives money back — shown with a minus, never
    // as a green "+" income line.
    amountMinor: d.amountHidden
        ? null
        : (d.documentType == 'CREDIT_DOCUMENT'
              ? -d.totalMinor.abs()
              : d.totalMinor),
    status: StatusPill.doc(st.status),
    attributes: [
      if (dateStr.isNotEmpty) ltrIsolate(dateStr),
      for (final a in st.attributes) docAttributeLabels[a]!,
    ],
    meta: dateStr.isEmpty ? null : ltrIsolate(dateStr),
    onTap: onTap,
    // Owner 2026-11-17: send any issued document from the list (swipe or
    // long press → S6).
    swipeLabel: onSend == null ? null : CommonHe.send,
    onSwipe: onSend,
    onLongPress: onSend,
  );
  if (onDelete == null || !isDraftStatus(d.status)) return row;
  return Row(
    children: [
      Expanded(child: row),
      PopupMenuButton<String>(
        tooltip: InboxHe.draftActions,
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) {
          if (action == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 20),
                SizedBox(width: 10),
                Text(InboxHe.deleteDraft),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

Future<bool> confirmDraftDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text(InboxHe.deleteDraftTitle),
        content: const Text(InboxHe.deleteDraftBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(InboxHe.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(InboxHe.deleteDraft),
          ),
        ],
      ),
    ) ??
    false;

Widget quoteRowFor(
  QuoteRow q, {
  required VoidCallback onTap,
  VoidCallback? onSend,
  Key? key,
}) => DocRow(
  key: key ?? Key('quote-${q.id}'),
  title: q.customerName ?? q.title ?? InboxHe.quoteNoCustomer,
  subtitle: quoteSubtitle(q),
  amountMinor: q.amountHidden ? null : q.totalMinor,
  status: StatusPill.quote(quoteListStatus(q.status, expired: q.expired)),
  onTap: onTap,
  swipeLabel: onSend == null ? null : CommonHe.send,
  onSwipe: onSend,
  onLongPress: onSend,
);

/// "בתוקף עד 12.10.2026" (else "נוצרה …") — never the title's fallback
/// word. With a number (it must fit one row): "מס׳ 12 · עד 12.10.2026",
/// past validity "מס׳ 12 · פג ב-…".
String quoteSubtitle(QuoteRow q) {
  final n = q.quoteNumber;
  if (q.validUntil != null) {
    final date = ltrIsolate(formatDateHe(q.validUntil));
    if (n != null) {
      return InboxHe.quoteNumberedUntil(
        ltrIsolate(n),
        date,
        expired: q.expired,
      );
    }
    return q.expired
        ? InboxHe.quoteExpiredOn(date)
        : InboxHe.quoteValidUntil(date);
  }
  final number = n == null ? '' : '${InboxHe.quoteNumber(ltrIsolate(n))} · ';
  if (q.createdAt != null) {
    return number + InboxHe.quoteCreated(ltrIsolate(formatDateHe(q.createdAt)));
  }
  return n == null ? '' : InboxHe.quoteNumber(ltrIsolate(n));
}

/// "מסמכים אחרונים": what the customer did (tester 2026-11-18) — a quote
/// accepted on its link, a document signed — in the same list as the
/// documents, newest first. Tap → the quote / the signed document.
class RecentEventRow extends StatelessWidget {
  const RecentEventRow({super.key, required this.event, required this.onTap});

  final RecentEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final quote = event.kind == RecentEvent.quoteAccepted;
    final who = (event.customerName ?? '').trim();
    final label = (event.label ?? '').trim();
    final title = who.isEmpty ? InboxHe.noCustomer : who;
    final subtitle = quote
        ? (label.isEmpty
              ? InboxHe.recentQuoteAccepted
              : '${InboxHe.recentQuoteAccepted} · ${ltrIsolate(label)}')
        : (label.isEmpty
              ? InboxHe.recentSigned
              : '${InboxHe.recentSigned} · $label');
    final local = event.at.toLocal();
    final when =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
    return Semantics(
      button: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: InkWell(
        key: Key('recent-event-${event.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.card),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min + 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: p.ok.withValues(alpha: .14),
                  child: Icon(
                    quote ? Icons.task_alt_rounded : Icons.draw_rounded,
                    size: 19,
                    color: p.ok,
                  ),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        style: AppText.secondary.copyWith(color: p.ok),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  ltrIsolate(when),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
