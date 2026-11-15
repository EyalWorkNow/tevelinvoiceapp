// A3 (QA 2026-11-16): the list a home card opens is EXACTLY what the card
// counts. GET /documents?inbox=KIND applies the card's own server predicate
// (UNFINISHED, MY_REJECTED, TAX_INVOICE_DUE, OVERDUE), so "92 לא הושלמו"
// opens 92 rows (paged), never "the drafts among the 500 newest". Squad A.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/documents_api.dart' show isDraftStatus;
import '../../api/inbox_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../util/labels/inbox_he.dart';
import 'doc_rows.dart';
import 'inbox_cards.dart' show typeIntent;
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Opens the documents behind the [kind] card.
Future<void> openInboxList(BuildContext context, InboxKind kind) =>
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => InboxListPage(kind: kind)));

class InboxListPage extends StatefulWidget {
  const InboxListPage({super.key, required this.kind});

  final InboxKind kind;

  @override
  State<InboxListPage> createState() => _InboxListPageState();
}

class _InboxListPageState extends State<InboxListPage> {
  List<DocumentSummary>? _rows;
  int _total = 0;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
    });
    try {
      final page = await fetchInboxList(widget.kind);
      if (!mounted) return;
      setState(() {
        _rows = page.documents;
        _total = page.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _more() async {
    final rows = _rows;
    if (rows == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await fetchInboxList(widget.kind, offset: rows.length);
      if (!mounted) return;
      setState(() {
        _rows = [...rows, ...page.documents];
        _total = page.documents.isEmpty ? _rows!.length : page.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(DocumentSummary d) async {
    if (isDraftStatus(d.status)) {
      await openCompose(
        context,
        intent: typeIntent(d.documentType),
        draftId: d.id,
      );
    } else {
      await openDocument(context, d.id);
    }
    if (mounted) unawaited(_load());
  }

  String get _title => switch (widget.kind) {
    InboxKind.unfinished => InboxHe.unfinishedMany(_total),
    InboxKind.myRejected => InboxHe.myRejectedMany(_total),
    InboxKind.taxInvoiceDue => InboxHe.taxInvoiceDueMany(_total),
    InboxKind.overdue => InboxHe.overdue(_total),
    _ => InboxHe.inboxListCount(_total),
  };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(rows == null ? '' : _title)),
      body: SafeArea(child: _body(context, rows)),
    );
  }

  Widget _body(BuildContext context, List<DocumentSummary>? rows) {
    if (_error != null && rows == null) {
      return ErrorView(error: _error!, onRetry: _load);
    }
    if (rows == null) return const SkeletonList(rows: 6);
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Iconsax.tick_circle,
        title: InboxHe.inboxListEmpty,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: Key('inbox-list-${widget.kind.wire}'),
        padding: const EdgeInsets.fromLTRB(
          Space.page,
          Space.s,
          Space.page,
          Space.xl,
        ),
        children: [
          Text(
            InboxHe.inboxListCount(_total),
            key: const Key('inbox-list-count'),
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: Space.s),
          for (final d in rows) docRowFor(d, onTap: () => unawaited(_open(d))),
          if (rows.length < _total)
            TextButton(
              key: const Key('inbox-list-more'),
              onPressed: _loadingMore ? null : () => unawaited(_more()),
              child: const Text(InboxHe.loadMore),
            ),
        ],
      ),
    );
  }
}
