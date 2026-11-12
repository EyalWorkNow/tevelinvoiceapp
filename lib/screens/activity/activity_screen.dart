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
import 'package:flutter/services.dart';

import '../../api/client.dart';
import '../../api/documents_api.dart' show deleteDraft, documentsVersion;
import '../../api/inbox_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/business_he.dart' show ActivityHe;
import '../../util/labels/document_he.dart' show docTypeLabel;
import '../../util/labels/inbox_he.dart';
import '../home/doc_rows.dart';
import '../home/inbox_cards.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum ActivityChip { all, unpaid, drafts, quotes, paid, inbox }

ActivityChip chipFromQuery(String? chip) => switch (chip) {
  'unpaid' => ActivityChip.unpaid,
  'drafts' => ActivityChip.drafts,
  'quotes' => ActivityChip.quotes,
  'paid' => ActivityChip.paid,
  'inbox' => ActivityChip.inbox,
  _ => ActivityChip.all,
};

const Set<String> _draftStatuses = {
  'DRAFT',
  'VALIDATING',
  'READY_TO_FINALIZE',
  'REJECTED',
};

/// The 500-row cap of P0 (BE-10a): a server without paging still gets it.
const int activityLimit = 500;

/// First page of L when the server pages (BE-10); "טען עוד" brings the rest.
const int activityPageSize = 100;

/// One page of rows, or the P0 500 cap when the server does not page.
Future<ActivityPage> _firstPage({bool unpaid = false}) async {
  final page = await fetchDocumentRows(unpaid: unpaid, limit: activityPageSize);
  if (page.serverSearch || page.documents.length < activityPageSize) {
    return page;
  }
  return fetchDocumentRows(unpaid: unpaid, limit: activityLimit);
}

/// L's type / date filters over the loaded rows (null = no filter). Drafts
/// have no issue date and drop out while a date range is set.
List<DocumentSummary> filterDocuments(
  List<DocumentSummary> docs, {
  String? type,
  DateTimeRange? range,
}) {
  if (type == null && range == null) return docs;
  return [
    for (final d in docs)
      if ((type == null || d.documentType == type) &&
          (range == null || _inRange(d.issueDate, range)))
        d,
  ];
}

bool _inRange(String? date, DateTimeRange range) {
  final day = date == null ? null : DateTime.tryParse(date);
  if (day == null) return false;
  final d = DateTime(day.year, day.month, day.day);
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final to = DateTime(range.end.year, range.end.month, range.end.day);
  return !d.isBefore(from) && !d.isAfter(to);
}

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
      final allF = _firstPage();
      final unpaidF = _firstPage(unpaid: true);
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
      // Rows first; the cache write (encode + fsync) does not hold them back.
      _notify();
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
      c == ActivityChip.drafts ||
      c == ActivityChip.paid;

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
      ActivityChip.all ||
      ActivityChip.drafts ||
      ActivityChip.paid => (all?.length ?? 0) < _allTotal,
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
          if (chip == ActivityChip.paid
              ? d.isPaid
              : (!drafts || _draftStatuses.contains(d.status)))
            d,
      ];
    }
    final base = switch (chip) {
      ActivityChip.unpaid => unpaid ?? const <DocumentSummary>[],
      ActivityChip.drafts => [
        for (final d in all ?? const <DocumentSummary>[])
          if (_draftStatuses.contains(d.status)) d,
      ],
      ActivityChip.paid => [
        for (final d in all ?? const <DocumentSummary>[])
          if (d.isPaid) d,
      ],
      _ => all ?? const <DocumentSummary>[],
    };
    return searchDocuments(base, query);
  }
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.chip, this.controller});

  /// Initial chip: all | unpaid | drafts | quotes | paid | inbox ("לטיפול").
  final String? chip;

  /// Tests pass a controller and drive [ActivityController.load] themselves.
  final ActivityController? controller;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late final ActivityController _c = widget.controller ?? ActivityController();
  late ActivityChip _chip = chipFromQuery(widget.chip);
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String? _type;
  DateTimeRange? _range;

  /// The flattened rows (month headers + rows) of the last build, rebuilt
  /// only when an input changes, not on every frame.
  Object? _itemsKey;
  List<Object> _items = const [];

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    documentsVersion.addListener(_reload);
    businessContext.addListener(_changed);
    if (widget.controller == null) unawaited(_c.load(withCards: true));
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

  Future<void> _deleteDraft(DocumentSummary document) async {
    if (!await confirmDraftDeletion(context) || !mounted) return;
    try {
      await deleteDraft(document.id);
      _reload();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא הצלחנו למחוק את הטיוטה. נסו שוב.')),
      );
    }
  }

  void _onQuery(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_c.search(text, chip: _chip)),
    );
  }

  Widget _filterGrid(List<ChipOption<ActivityChip>> options) {
    Widget tile(ChipOption<ActivityChip> option) {
      final selected = option.value == _chip;
      final palette = context.palette;
      final background = selected ? palette.accent : palette.surface;
      final foreground = selected ? palette.accentInk : palette.ink;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Semantics(
            button: true,
            selected: selected,
            label: option.label,
            child: Material(
              color: background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: selected ? background : palette.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: selected
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _chip = option.value);
                        if (_search.text.trim().isNotEmpty) {
                          unawaited(
                            _c.search(_search.text, chip: option.value),
                          );
                        }
                      },
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(option.icon, size: 17, color: foreground),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.secondary.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      key: const Key('activity-chips'),
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: Column(
        children: [
          Row(children: [for (final option in options.take(3)) tile(option)]),
          Row(
            children: [
              for (final option in options.skip(3).take(3)) tile(option),
            ],
          ),
        ],
      ),
    );
  }

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
      const ChipOption(
        ActivityChip.paid,
        InboxHe.chipPaid,
        icon: Icons.check_circle_outline_rounded,
      ),
      const ChipOption(
        ActivityChip.inbox,
        InboxHe.chipInbox,
        icon: Icons.inbox_outlined,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.m,
                  Space.page,
                  Space.s,
                ),
                child: Row(
                  children: [
                    // One name with the home button (07·U9): "מסמכים".
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          InboxHe.documentsAction,
                          style: AppText.displayTitle,
                        ),
                      ),
                    ),
                    if (ModalRoute.of(context)?.canPop ?? false)
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
            _filterGrid(chips),
            if (_chip != ActivityChip.quotes && _chip != ActivityChip.inbox)
              _filterRow(context),
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
    final key = (
      _chip,
      query,
      _type,
      _range,
      _c.all,
      _c.unpaid,
      _c.quotes,
      _c.searchResults,
    );
    if (_itemsKey != key) {
      _itemsKey = key;
      _items = [
        if (_chip == ActivityChip.quotes)
          for (final g in groupByMonth(
            searchQuotes(_c.quotes!, query),
            (q) => q.createdAt,
            today: _c.now?.call(),
          )) ...[_MonthTitle(g.title), ...g.rows]
        else
          for (final g in groupByMonth(
            filterDocuments(
              _c.docsFor(_chip, query),
              type: _type,
              range: _range,
            ),
            (d) => d.issueDate,
            today: _c.now?.call(),
          )) ...[_MonthTitle(g.title), ...g.rows],
      ];
    }
    final items = _items;
    if (items.isEmpty) return ListView(children: [_empty(context, query)]);
    final showCap =
        _c.allCapped &&
        !_c.serverSearch &&
        (_chip == ActivityChip.all ||
            _chip == ActivityChip.drafts ||
            _chip == ActivityChip.paid);
    final more = _c.canLoadMore(_chip, query);
    final footer = <Widget>[
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
    ];
    // Lazy: only the rows on screen are built (2.5; up to hundreds of rows).
    return ListView.builder(
      key: const Key('activity-list'),
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
      itemCount: items.length + footer.length,
      itemBuilder: (context, i) {
        if (i >= items.length) return footer[i - items.length];
        final item = items[i];
        return switch (item) {
          _MonthTitle(:final title) => _MonthHeader(title),
          QuoteRow q => quoteRowFor(
            q,
            onTap: () => unawaited(openQuote(context, q.id)),
          ),
          DocumentSummary d => docRowFor(
            d,
            today: _c.now?.call(),
            onTap: () => unawaited(openDocument(context, d.id)),
            onDelete: () => unawaited(_deleteDraft(d)),
          ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }

  Widget _filterRow(BuildContext context) {
    final p = context.palette;
    final types = <String>{
      for (final d in _c.all ?? const <DocumentSummary>[]) d.documentType,
    }.toList()..sort((a, b) => docTypeLabel(a).compareTo(docTypeLabel(b)));
    Widget pill(Key key, String label, bool active, VoidCallback onTap) =>
        ActionChip(
          key: key,
          label: Text(label, style: AppText.secondary),
          avatar: Icon(
            Iconsax.arrow_down_1,
            size: 14,
            color: active ? p.accent : p.muted,
          ),
          side: BorderSide(color: active ? p.accent : p.line),
          onPressed: onTap,
        );
    return Padding(
      key: const Key('activity-filters'),
      padding: const EdgeInsets.fromLTRB(Space.page, Space.xs, Space.page, 0),
      // Wrap, not a sideways scroll: "נקה סינון" must never sit off-screen.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(
          spacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            pill(
              const Key('activity-filter-type'),
              _type == null ? ActivityHe.filterType : docTypeLabel(_type!),
              _type != null,
              () => unawaited(_pickType(types)),
            ),
            pill(
              const Key('activity-filter-date'),
              _range == null
                  ? ActivityHe.filterDate
                  : ltrIsolate(ActivityHe.range(_range!.start, _range!.end)),
              _range != null,
              () => unawaited(_pickRange()),
            ),
            if (_type != null || _range != null)
              TextButton(
                key: const Key('activity-filter-clear'),
                onPressed: () => setState(() {
                  _type = null;
                  _range = null;
                }),
                child: const Text(ActivityHe.clearFilters),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickType(List<String> types) async {
    final picked = await showAppSheet<String>(
      context,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(ActivityHe.filterType),
          for (final t in ['', ...types])
            ListTile(
              key: Key('activity-type-${t.isEmpty ? 'all' : t}'),
              title: Text(
                t.isEmpty ? ActivityHe.allTypes : docTypeLabel(t),
                style: AppText.body,
              ),
              selected: (_type ?? '') == t,
              onTap: () => Navigator.of(sheet).pop(t),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _type = picked.isEmpty ? null : picked);
  }

  Future<void> _pickRange() async {
    final now = _c.now?.call() ?? DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      currentDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
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
      ActivityChip.paid => const EmptyState(
        icon: Iconsax.tick_circle,
        title: 'אין מסמכים ששולמו',
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

/// A month header in the flattened list.
class _MonthTitle {
  const _MonthTitle(this.title);

  final String title;
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
