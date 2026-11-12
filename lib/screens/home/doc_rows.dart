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
    amountMinor: d.amountHidden ? null : d.totalMinor,
    status: StatusPill.doc(st.status),
    attributes: [
      if (dateStr.isNotEmpty) ltrIsolate(dateStr),
      for (final a in st.attributes) docAttributeLabels[a]!,
    ],
    meta: dateStr.isEmpty ? null : ltrIsolate(dateStr),
    onTap: onTap,
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

Widget quoteRowFor(QuoteRow q, {required VoidCallback onTap, Key? key}) =>
    DocRow(
      key: key ?? Key('quote-${q.id}'),
      title: q.customerName ?? q.title ?? InboxHe.quoteNoCustomer,
      subtitle: quoteSubtitle(q),
      amountMinor: q.totalMinor,
      status: StatusPill.quote(quoteListStatus(q.status)),
      onTap: onTap,
    );

/// "בתוקף עד 12.10.2026" (else "נוצרה …") — never the title's fallback word.
String quoteSubtitle(QuoteRow q) {
  if (q.validUntil != null) {
    return InboxHe.quoteValidUntil(ltrIsolate(formatDateHe(q.validUntil)));
  }
  if (q.createdAt != null) {
    return InboxHe.quoteCreated(ltrIsolate(formatDateHe(q.createdAt)));
  }
  return '';
}
