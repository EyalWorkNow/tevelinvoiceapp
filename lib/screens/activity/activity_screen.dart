// L · פעילות (SPEC-v2 §6.L). Owner: squad A.
// Route: /activity?chip=   (chip ∈ all | unpaid | drafts | quotes | inbox)
//
// Fixed search (name, amount "1,200", document number) → chips הכל · לא שולם
// · טיוטות · הצעות (+ לטיפול only when opened from "עוד N" or cards exist) →
// rows grouped by month. A read screen: no PrimaryButton.
// BE-10 (P1, detected by the echoed `offset`): the search runs on the server
// for הכל / לא שולם / טיוטות, and "טען עוד" pages past the loaded rows.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/documents_api.dart' show documentsVersion;
import '../../api/inbox_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/inbox_he.dart';
import '../home/doc_rows.dart';
import '../home/inbox_cards.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum ActivityChip { all, unpaid, drafts, quotes, inbox }

ActivityChip chipFromQuery(String? chip) => switch (chip) {
  'unpaid' => ActivityChip.unpaid,
  'drafts' => ActivityChip.drafts,
  'quotes' => ActivityChip.quotes,
  'inbox' => ActivityChip.inbox,
  _ => ActivityChip.all,
};

const Set<String> _draftStatuses = {
  'DRAFT',
  'VALIDATING',
  'READY_TO_FINALIZE',
  'REJECTED',
};

/// The 500-row cap of P0 (BE-10a).
const int activityLimit = 500;

/// L state: cached lists first, then the network.
class ActivityController extends ChangeNotifier {
  ActivityController({this.now});

  final DateTime Function()? now;

  List<DocumentSummary>? all;
  bool allCapped = false;
  bool serverSearch = false;
  List<DocumentSummary>? unpaid;
  List<QuoteRow>? quotes;
  List<InboxItem> cards = const [];
  bool loading = false;
  bool loadingMore = false;
  ApiException? error;

  /// Server totals (BE-10 paging of the plain lists).
  int _allTotal = 0;
  int _unpaidTotal = 0;

  /// BE-10 results for the current query (null = use the local filter).
  SearchPage? _searchPage;
  String _searchQuery = '';
  bool _searchUnpaid = false;
  int _searchGen = 0;

  List<DocumentSummary>? get searchResults => _searchPage?.documents;

  bool get offline => (error?.isNetwork ?? false) || businessContext.offline;

  bool _disposed = false;

  /// A result that arrives after dispose or after a business switch is dropped.
  bool _stale(String business) => _disposed || business != cacheBusinessKey;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchGen++;
    super.dispose();
  }

  Future<void> load({bool withCards = false}) async {
    final business = cacheBusinessKey;
    if (all == null) {
      final cached = await readCachedActivity();
      if (_stale(business)) return;
      if (cached != null) {
        _apply(cached);
        _notify();
      }
      final home = await readCachedHome();
      if (_stale(business)) return;
      if (home != null) {
        cards = filterHome(home, caps: businessContext.caps).cards;
        _notify();
      }
    }
    loading = true;
    _notify();
    try {
      final caps = businessContext.caps;
      final allF = fetchDocumentRows(limit: activityLimit);
      final unpaidF = fetchDocumentRows(unpaid: true, limit: activityLimit);
      final quotesF = caps.can(Cap.docView)
          ? fetchQuoteRows()
          : Future.value(const <QuoteRow>[]);
      final cardsF = withCards
          ? fetchHome(caps: caps, now: now?.call())
          : Future<HomeData?>.value(null);
      // All at once: one failure must not leave the others' errors unhandled.
      await Future.wait<Object?>([allF, unpaidF, quotesF, cardsF]);
      if (_stale(business)) return;
      final allPage = await allF;
      final unpaidPage = await unpaidF;
      final q = await quotesF;
      final home = await cardsF;
      all = allPage.documents;
      allCapped = allPage.documents.length >= activityLimit;
      serverSearch = allPage.serverSearch;
      _allTotal = allPage.total;
      unpaid = unpaidPage.documents;
      _unpaidTotal = unpaidPage.total;
      quotes = q;
      if (home != null) cards = home.cards;
      error = null;
      await writeCachedActivity(business, {
        'all': [for (final d in all!) d.toJson()],
        'unpaid': [for (final d in unpaid!) d.toJson()],
        'quotes': [for (final x in quotes!) x.toJson()],
        'capped': allCapped,
      });
    } on ApiException catch (e) {
      if (!_stale(business)) error = e;
    } finally {
      loading = false;
      _notify();
    }
  }

  void _apply(Map<String, dynamic> json) {
    List<DocumentSummary> docs(Object? v) => [
      for (final d in (v is List ? v : const []))
        DocumentSummary.fromJson(d as Map<String, dynamic>),
    ];
    all = docs(json['all']);
    unpaid = docs(json['unpaid']);
    quotes = [
      for (final q
          in (json['quotes'] is List ? json['quotes'] as List : const []))
        QuoteRow.fromJson(q as Map<String, dynamic>),
    ];
    allCapped = json['capped'] == true;
  }

  /// BE-10: search on the server (all documents, not only the last 500).
  /// [chip] לא שולם searches open invoices only; quotes stay local.
  Future<void> search(
    String query, {
    ActivityChip chip = ActivityChip.all,
  }) async {
    _searchQuery = query.trim();
    _searchUnpaid = chip == ActivityChip.unpaid;
    final gen = ++_searchGen;
    if (!serverSearch || _searchQuery.isEmpty || !_documentChip(chip)) {
      _searchPage = null;
      notifyListeners();
      return;
    }
    try {
      final page = await serverSearchDocuments(
        _searchQuery,
        unpaid: _searchUnpaid,
      );
      if (gen != _searchGen) return;
      _searchPage = page;
    } on ApiException {
      if (gen != _searchGen) return;
      _searchPage = null; // fall back on the local filter
    }
    _notify();
  }

  static bool _documentChip(ActivityChip c) =>
      c == ActivityChip.all ||
      c == ActivityChip.unpaid ||
      c == ActivityChip.drafts;

  bool _searching(ActivityChip chip, String query) =>
      _searchPage != null &&
      query.trim() == _searchQuery &&
      _documentChip(chip) &&
      (chip == ActivityChip.unpaid) == _searchUnpaid;

  /// "טען עוד" is offered under this chip / query (BE-10 only).
  bool canLoadMore(ActivityChip chip, String query) {
    if (!serverSearch || loadingMore) return false;
    if (query.trim().isNotEmpty) {
      return _searching(chip, query) && _searchPage!.hasMore;
    }
    return switch (chip) {
      ActivityChip.all || ActivityChip.drafts => (all?.length ?? 0) < _allTotal,
      ActivityChip.unpaid => (unpaid?.length ?? 0) < _unpaidTotal,
      _ => false,
    };
  }

  /// Next server page of the search, or of the plain list.
  Future<void> loadMore(ActivityChip chip, String query) async {
    if (!canLoadMore(chip, query)) return;
    final business = cacheBusinessKey;
    loadingMore = true;
    notifyListeners();
    try {
      if (query.trim().isNotEmpty) {
        final page = _searchPage!;
        final gen = _searchGen;
        final next = await serverSearchDocuments(
          _searchQuery,
          unpaid: _searchUnpaid,
          offset: page.documents.length,
        );
        if (gen == _searchGen) {
          _searchPage = SearchPage(next.total, [
            ...page.documents,
            ...next.documents,
          ], pageable: true);
        }
      } else if (chip == ActivityChip.unpaid) {
        final next = await fetchDocumentRows(
          unpaid: true,
          offset: unpaid!.length,
          limit: searchPageSize * 2,
        );
        if (_stale(business)) return;
        unpaid = [...unpaid!, ...next.documents];
        _unpaidTotal = next.documents.isEmpty ? unpaid!.length : next.total;
      } else {
        final next = await fetchDocumentRows(
          offset: all!.length,
          limit: searchPageSize * 2,
        );
        if (_stale(business)) return;
        all = [...all!, ...next.documents];
        _allTotal = next.documents.isEmpty ? all!.length : next.total;
      }
    } on ApiException catch (e) {
      if (!_stale(business)) error = e;
    } finally {
      loadingMore = false;
      _notify();
    }
  }

  /// Rows of a document chip after the search.
  List<DocumentSummary> docsFor(ActivityChip chip, String query) {
    final drafts = chip == ActivityChip.drafts;
    if (_searching(chip, query)) {
      return [
        for (final d in _searchPage!.documents)
          if (!drafts || _draftStatuses.contains(d.status)) d,
      ];
    }
    final base = switch (chip) {
      ActivityChip.unpaid => unpaid ?? const <DocumentSummary>[],
      ActivityChip.drafts => [
        for (final d in all ?? const <DocumentSummary>[])
          if (_draftStatuses.contains(d.status)) d,
      ],
      _ => all ?? const <DocumentSummary>[],
    };
    return searchDocuments(base, query);
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.chip, this.controller});

  /// Initial chip: all | unpaid | drafts | quotes | inbox ("לטיפול").
  final String? chip;

  /// Tests pass a controller and drive [ActivityController.load] themselves.
  final ActivityController? controller;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final ActivityController _c = widget.controller ?? ActivityController();
  late ActivityChip _chip = chipFromQuery(widget.chip);
  late final bool _openedOnInbox = _chip == ActivityChip.inbox;
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    documentsVersion.addListener(_reload);
    businessContext.addListener(_changed);
    if (widget.controller == null) {
      unawaited(_c.load(withCards: _openedOnInbox));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.removeListener(_changed);
    documentsVersion.removeListener(_reload);
    businessContext.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _reload() => unawaited(_c.load(withCards: true));

  void _onQuery(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_c.search(text, chip: _chip)),
    );
  }

  bool get _showInboxChip => _openedOnInbox || _c.cards.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final chips = <ChipOption<ActivityChip>>[
      const ChipOption(
        ActivityChip.all,
        InboxHe.chipAll,
        icon: Icons.all_inbox_outlined,
      ),
      const ChipOption(
        ActivityChip.unpaid,
        InboxHe.chipUnpaid,
        icon: Icons.payments_outlined,
      ),
      const ChipOption(
        ActivityChip.drafts,
        InboxHe.chipDrafts,
        icon: Icons.edit_note_outlined,
      ),
      const ChipOption(
        ActivityChip.quotes,
        InboxHe.chipQuotes,
        icon: Icons.request_quote_outlined,
      ),
      if (_showInboxChip)
        const ChipOption(
          ActivityChip.inbox,
          InboxHe.chipInbox,
          icon: Icons.inbox_outlined,
        ),
    ];
    if (!_showInboxChip && _chip == ActivityChip.inbox) {
      _chip = ActivityChip.all;
    }
    return Scaffold(
      appBar: context.isDark
          ? null
          : AppBar(title: const Text(InboxHe.activityTitle)),
      body: SafeArea(
        child: Column(
          children: [
            if (context.isDark)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.m,
                  Space.page,
                  Space.s,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        InboxHe.activityTitle,
                        style: AppText.displayTitle,
                      ),
                    ),
                    const DesignBackButton(),
                  ],
                ),
              ),
            OfflineBanner(visible: _c.offline, onRetry: _reload),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.s,
                Space.page,
                Space.s,
              ),
              child: Semantics(
                label: InboxHe.searchLabel,
                textField: true,
                child: TextField(
                  key: const Key('activity-search'),
                  controller: _search,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: InboxHe.searchHint,
                    prefixIcon: const Icon(Iconsax.search_normal_1),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: CommonHe.close,
                            icon: const Icon(Iconsax.close_circle),
                            onPressed: () {
                              _search.clear();
                              _onQuery('');
                            },
                          ),
                  ),
                ),
              ),
            ),
            ChipRow<ActivityChip>(
              key: const Key('activity-chips'),
              options: chips,
              selected: _chip,
              onSelected: (c) {
                setState(() => _chip = c);
                if (_search.text.trim().isNotEmpty) {
                  unawaited(_c.search(_search.text, chip: c));
                }
              },
            ),
            const SizedBox(height: Space.s),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _c.load(withCards: true),
                child: ContentReveal(
                  key: ValueKey((_chip, _c.all != null, _c.quotes != null)),
                  child: _list(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final query = _search.text;
    if (_chip == ActivityChip.inbox) return _inboxList(context);
    final loaded = _chip == ActivityChip.quotes
        ? _c.quotes != null
        : _c.all != null;
    if (!loaded) {
      if (_c.error != null && !_c.loading) {
        return ListView(
          children: [ErrorView(error: _c.error!, onRetry: _reload)],
        );
      }
      return const SingleChildScrollView(child: SkeletonList(rows: 6));
    }
    final List<Widget> rows;
    var count = 0;
    if (_chip == ActivityChip.quotes) {
      final qs = searchQuotes(_c.quotes!, query);
      count = qs.length;
      rows = [
        for (final g in groupByMonth(
          qs,
          (q) => q.createdAt,
          today: _c.now?.call(),
        )) ...[
          _MonthHeader(g.title),
          for (final q in g.rows)
            quoteRowFor(q, onTap: () => unawaited(openQuote(context, q.id))),
        ],
      ];
    } else {
      final docs = _c.docsFor(_chip, query);
      count = docs.length;
      rows = [
        for (final g in groupByMonth(
          docs,
          (d) => d.issueDate,
          today: _c.now?.call(),
        )) ...[
          _MonthHeader(g.title),
          for (final d in g.rows)
            docRowFor(
              d,
              today: _c.now?.call(),
              onTap: () => unawaited(openDocument(context, d.id)),
            ),
        ],
      ];
    }
    if (count == 0) return ListView(children: [_empty(context, query)]);
    final showCap =
        _c.allCapped &&
        !_c.serverSearch &&
        (_chip == ActivityChip.all || _chip == ActivityChip.drafts);
    final more = _c.canLoadMore(_chip, query);
    return ListView(
      key: const Key('activity-list'),
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
      children: [
        ...rows,
        if (showCap)
          Padding(
            key: const Key('activity-capped'),
            padding: const EdgeInsets.symmetric(vertical: Space.l),
            child: Text(
              InboxHe.capped,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(color: context.palette.muted),
            ),
          ),
        if (more || _c.loadingMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Center(
              child: TextButton(
                key: const Key('activity-more'),
                onPressed: () => unawaited(_c.loadMore(_chip, query)),
                child: const Text(InboxHe.loadMore),
              ),
            ),
          ),
      ],
    );
  }

  Widget _inboxList(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final cards = query.isEmpty
        ? _c.cards
        : _c.cards.where((card) {
            final searchable = [
              inboxTitle(card),
              card.customerName,
              card.documentNumber,
              card.reason,
              card.amountMinor?.toString(),
              if (card.amountMinor != null)
                (card.amountMinor! ~/ BigInt.from(100)).toString(),
            ].whereType<String>().join(' ').toLowerCase();
            return searchable.contains(query);
          }).toList();
    if (cards.isEmpty) {
      if (_c.loading) {
        return const SingleChildScrollView(child: SkeletonList(rows: 3));
      }
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(
              query.isNotEmpty ? InboxHe.noResults : CommonHe.allHandled,
              textAlign: TextAlign.center,
              style: AppText.headline,
            ),
          ),
        ],
      );
    }
    return ListView(
      key: const Key('activity-inbox'),
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
      children: [
        InboxSummaryCard(
          key: const Key('activity-inbox-summary'),
          title: InboxHe.inboxListTitle,
          rows: [
            for (final c in cards)
              InboxSummaryRow(
                key: Key('inbox-${c.kind.wire}'),
                icon: inboxSummaryIcon(c.kind),
                tone: inboxSummaryTone(c.kind),
                title: inboxTitle(c),
                onTap: () =>
                    unawaited(runInboxAction(context, c, onChanged: _reload)),
                onDismiss: c.kind == InboxKind.setup && c.setupStep != null
                    ? () async {
                        await dismissSetup(c.setupStep!);
                        _reload();
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _empty(BuildContext context, String query) {
    if (query.trim().isNotEmpty) {
      return const EmptyState(
        icon: Iconsax.search_status,
        title: InboxHe.noResults,
        message: InboxHe.noResultsHint,
      );
    }
    final canDraft = businessContext.can(Cap.docDraft);
    return switch (_chip) {
      ActivityChip.unpaid => const EmptyState(
        icon: Iconsax.tick_circle,
        title: InboxHe.emptyUnpaid,
      ),
      ActivityChip.drafts => const EmptyState(
        icon: Iconsax.note_text,
        title: InboxHe.emptyDrafts,
      ),
      ActivityChip.quotes => const EmptyState(
        icon: Iconsax.receipt_edit,
        title: InboxHe.emptyQuotes,
      ),
      _ => EmptyState(
        icon: Iconsax.receipt_item,
        title: InboxHe.emptyAll,
        actionLabel: canDraft ? CommonHe.requestPayment : null,
        onAction: canDraft
            ? () => unawaited(openCompose(context, intent: 'REQUEST'))
            : null,
      ),
    };
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: AppText.headline.copyWith(color: context.palette.muted),
      ),
    ),
  );
}
