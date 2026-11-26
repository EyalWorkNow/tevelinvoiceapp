// Home search (tester feedback 2026-11-18): one field over customers,
// documents, quotes and documents for signature. Plain phrases work — the
// server reads a document-type word and a name ("הצעת מחיר של כהן").

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/search_api.dart';
import '../../router.dart'
    show openDocument, openPerson, openQuote, openSignRequest;
import '../../ui/ds.dart';
import '../../util/labels/labels.dart' show docTypeLabel, formatDateHe;
import '../../util/labels/notifications_he.dart';
import '../../util/money.dart' show formatMoney;

/// Search function (tests inject a fake).
typedef SearchFn = Future<List<SearchHit>> Function(String q);

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.search, this.initialQuery});

  final SearchFn? search;
  final String? initialQuery;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  late final TextEditingController _q = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  List<SearchHit>? _hits;
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  SearchFn get _search => widget.search ?? globalSearch;

  @override
  void initState() {
    super.initState();
    if (_q.text.trim().isNotEmpty) unawaited(_run());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_run()),
    );
    setState(() {});
  }

  Future<void> _run() async {
    final q = _q.text.trim();
    final generation = ++_generation;
    if (q.isEmpty) {
      setState(() {
        _hits = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final hits = await _search(q);
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = hits;
        _error = null;
      });
    } on Object catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _open(SearchHit h) => unawaited(switch (h.kind) {
    SearchHitKind.customer => openPerson(context, h.id),
    SearchHitKind.document => openDocument(context, h.id),
    SearchHitKind.quote => openQuote(context, h.id),
    SearchHitKind.signRequest => openSignRequest(context, h.id),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hits = _hits;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('global-search-field'),
          controller: _q,
          autofocus: true,
          onChanged: _changed,
          onSubmitted: (_) => unawaited(_run()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: SearchHe.screenHint,
            prefixIcon: const Icon(Iconsax.search_normal_1),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ),
      body: SafeArea(
        child: _error != null && hits == null
            ? ErrorView(error: _error!, onRetry: _run)
            : hits == null
            ? _Examples(
                onPick: (text) {
                  _q.text = text.replaceAll('…', ' ').trimRight();
                  _q.selection = TextSelection.collapsed(
                    offset: _q.text.length,
                  );
                },
              )
            : hits.isEmpty
            ? const EmptyState(
                key: Key('global-search-empty'),
                icon: Iconsax.search_status,
                title: SearchHe.noResults,
                message: SearchHe.noResultsBody,
              )
            : ListView(
                key: const Key('global-search-results'),
                children: [
                  for (final (kind, label) in const [
                    (SearchHitKind.customer, SearchHe.customers),
                    (SearchHitKind.quote, SearchHe.quotes),
                    (SearchHitKind.document, SearchHe.documents),
                    (SearchHitKind.signRequest, SearchHe.signRequests),
                  ])
                    if (hits.any((h) => h.kind == kind)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          Space.page,
                          Space.m,
                          Space.page,
                          Space.xs,
                        ),
                        child: Text(
                          label,
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                      ),
                      for (final h in hits.where((h) => h.kind == kind))
                        _HitTile(hit: h, onTap: () => _open(h)),
                    ],
                ],
              ),
      ),
    );
  }
}

class _Examples extends StatelessWidget {
  const _Examples({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Space.page),
    child: Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (final e in SearchHe.examples)
          ActionChip(label: Text(e), onPressed: () => onPick(e)),
      ],
    ),
  );
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});
  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = hit;
    final (IconData icon, String title, String? subtitle) = switch (h.kind) {
      SearchHitKind.customer => (Iconsax.user, h.name ?? '', h.title),
      SearchHitKind.document => (
        Iconsax.receipt_item,
        [
          docTypeLabel(h.documentType ?? ''),
          if (h.number != null) h.number!,
        ].join(' '),
        [
          ?h.name,
          if (h.totalMinor != null)
            formatMoney(h.totalMinor!, trimZeroAgorot: true),
          if (h.date != null) formatDateHe(h.date),
        ].join(' · '),
      ),
      SearchHitKind.quote => (
        Iconsax.document_text,
        [SearchHe.quote, ?h.number].join(' '),
        [?h.name, if (h.date != null) formatDateHe(h.date)].join(' · '),
      ),
      SearchHitKind.signRequest => (
        Iconsax.edit,
        h.title ?? SearchHe.signRequest,
        [?h.name, if (h.date != null) formatDateHe(h.date)].join(' · '),
      ),
    };
    return ListTile(
      key: Key('search-hit-${h.id}'),
      leading: Icon(icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null || subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      minTileHeight: Hit.min + 8,
      onTap: onTap,
    );
  }
}
