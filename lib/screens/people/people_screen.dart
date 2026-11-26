// P · לקוחות (+ ספקים) (SPEC-v2 §6.P). Owner: squad D.
// Route: /people?chip=   (chip ∈ all | debtors | suppliers). Tab "לקוחות".
//
// Header "לקוחות" + text button "+ לקוח" → search → chips הכל · חייבים
// (money.view) · ספקים (§4.4: supplier.manage, expense capture or approve —
// employee and accountant view; "+ ספק" stays supplier.manage) → rows: recent first, then א–ת.
// Row: name · phone · "חייב לך ₪X" (money.view). 2611 §4: chips פעילים ·
// לא פעילים · הכול with counts; an inactive customer is grey, tagged "לא פעיל"
// (under פעילים it appears only in search). Balances come from BE-09 rows, else one
// GET /documents?unpaid=1&limit=500; a capped answer hides them (no partial
// number). No primary button (list screen).

import 'dart:async';

import 'package:flutter/material.dart';

import 'dart:typed_data';

import '../../api/client.dart';
import '../../api/customer_import_api.dart';
import '../../api/customers_api.dart';
import '../../api/models/models.dart';
import '../../api/suppliers_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/customer_import_he.dart';
import '../../util/labels/people_he.dart';
import '../../util/phone.dart';
import 'import/customer_import_screen.dart';
import 'sheets/s2_customer.dart';
import '../tutorial/coach_mark.dart';
import '../tutorial/tutorial_state.dart';
import '../../util/labels/tutorial_he.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// 2611 §4: פעילים (default) · לא פעילים · הכול, then חייבים · ספקים.
enum PeopleChip { active, inactive, all, debtors, suppliers }

PeopleChip? peopleChipFrom(String? s) => switch (s) {
  'active' => PeopleChip.active,
  'inactive' => PeopleChip.inactive,
  'all' => PeopleChip.all,
  'debtors' => PeopleChip.debtors,
  'suppliers' => PeopleChip.suppliers,
  _ => null,
};

class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key, this.chip, this.onBack});

  final String? chip;
  final VoidCallback? onBack;

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _search = TextEditingController();
  PeopleChip _chip = PeopleChip.active;
  CustomerList? _list;
  Map<String, BigInt>? _balances;
  List<Supplier>? _suppliers;
  List<String> _recent = const [];
  List<Customer>? _serverHits;
  Object? _error;
  bool _offline = false;
  Timer? _debounce;
  String? _business;

  @override
  void initState() {
    super.initState();
    _chip = peopleChipFrom(widget.chip) ?? PeopleChip.active;
    _search.addListener(_onSearch);
    businessContext.addListener(_onContext);
    _business = businessContext.business?.businessId;
    _load();
  }

  @override
  void didUpdateWidget(PeopleScreen old) {
    super.didUpdateWidget(old);
    final c = peopleChipFrom(widget.chip);
    if (c != null && widget.chip != old.chip) setState(() => _chip = c);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    businessContext.removeListener(_onContext);
    _search.dispose();
    super.dispose();
  }

  void _onContext() {
    final id = businessContext.business?.businessId;
    if (id == _business) return;
    _business = id;
    _debounce?.cancel();
    setState(() {
      _list = null;
      _balances = null;
      _suppliers = null;
      _serverHits = null;
      _error = null;
    });
    _load();
  }

  Caps get _caps => businessContext.caps;

  /// §4.4 "ספקים": employee views (creates from an expense), accountant views.
  bool get _seesSuppliers =>
      _caps.can(Cap.supplierManage) ||
      _caps.can(Cap.expenseCapture) ||
      _caps.can(Cap.expenseApprove);

  List<PeopleChip> get _chips => [
    PeopleChip.active,
    PeopleChip.inactive,
    PeopleChip.all,
    if (_caps.can(Cap.moneyView) && _balances != null) PeopleChip.debtors,
    if (_seesSuppliers) PeopleChip.suppliers,
  ];

  Future<void> _load() async {
    final business = _business;
    _recent = await readRecentCustomerIds();
    final cached = await readCachedCustomerList();
    if (cached != null && mounted && _list == null && business == _business) {
      setState(() => _list = cached);
    }
    try {
      final list = await fetchCustomerList();
      Map<String, BigInt>? balances;
      if (_caps.can(Cap.moneyView)) {
        balances = list.be09 ? _be09Balances(list) : await fetchOpenBalances();
      }
      List<Supplier>? suppliers;
      if (_seesSuppliers) suppliers = await fetchSuppliers();
      if (!mounted || business != _business) return;
      setState(() {
        _list = list;
        _balances = balances;
        _suppliers = suppliers;
        _error = null;
        _offline = false;
      });
      // 2611 §1: the first time here (after the tutorial), "+ לקוח חדש".
      if (_canAdd) {
        unawaited(
          maybeShowCoachMark(
            context,
            id: CoachIds.people,
            target: const Key('people-add'),
            text: TutorialHe.coachPeople,
          ),
        );
      }
    } on Object catch (e) {
      if (!mounted || business != _business) return;
      final network = e is ApiException && e.isNetwork;
      _suppliers ??= network ? await readCachedSuppliers() : null;
      if (!mounted) return;
      setState(() {
        _offline = network && _list != null;
        if (_list == null) _error = e;
      });
    }
  }

  Map<String, BigInt> _be09Balances(CustomerList list) => {
    for (final c in list.customers)
      if ((c.balanceMinor ?? BigInt.zero) > BigInt.zero) c.id: c.balanceMinor!,
  };

  void _onSearch() {
    setState(() {});
    _debounce?.cancel();
    final q = _search.text.trim();
    final list = _list;
    if (q.isEmpty || list == null || !list.capped || !list.be09) {
      if (_serverHits != null) setState(() => _serverHits = null);
      return;
    }
    // Over 500 customers with BE-09: search the server too.
    final business = _business;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final hits = await searchCustomers(q);
        if (mounted && _search.text.trim() == q && business == _business) {
          setState(() => _serverHits = hits);
        }
      } on Object {
        // Local results stay; nothing to show.
      }
    });
  }

  Future<void> _add() async {
    if (_chip == PeopleChip.suppliers) {
      final s = await showSupplierSheet(context, startOnNew: true);
      if (s != null) _load();
      return;
    }
    final c = await showCustomerSheet(context, startOnNew: true);
    if (c != null) _load();
  }

  Future<void> _open(String id, {bool supplier = false}) async {
    await openPerson(context, id, supplier: supplier);
    if (mounted) _load();
  }

  bool get _canImport =>
      _chip != PeopleChip.suppliers && _caps.can(Cap.customerImport);

  Future<void> _import() async {
    if (await openCustomerImport(context) && mounted) _load();
  }

  Future<void> _export() async {
    try {
      final Uint8List bytes = await exportCustomersXlsx();
      await shareImportFile(
        bytes,
        'customers.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text(ImportHe.exportFailed)));
      }
    }
  }

  bool get _canAdd => _chip == PeopleChip.suppliers
      ? _caps.can(Cap.supplierManage)
      : _caps.can(Cap.docDraft);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chips = _chips;
    if (!chips.contains(_chip)) _chip = PeopleChip.active;
    final counts = _list?.statusCounts;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.l,
                Space.s,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        PeopleHe.title,
                        style: AppText.displayTitle,
                      ),
                    ),
                  ),
                  if (_canImport)
                    // Header-sized "⋯" (the shared MoreMenu button is 46pt and
                    // would push P's list when the keyboard is up).
                    IconButton(
                      key: const Key('people-more'),
                      tooltip: CommonHe.more,
                      onPressed: () => MoreMenu.show(context, [
                        MoreMenuItem(
                          label: ImportHe.menuImport,
                          icon: Iconsax.document_download,
                          onSelected: _import,
                        ),
                        if ((_list?.active.length ?? 0) > 0)
                          MoreMenuItem(
                            label: ImportHe.menuExport,
                            icon: Iconsax.document_upload,
                            onSelected: _export,
                          ),
                      ]),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(Hit.min, Hit.min),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Iconsax.more, size: 22),
                    ),
                  if (widget.onBack != null)
                    IconButton(
                      key: const Key('people-back'),
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: widget.onBack,
                      icon: const Icon(Iconsax.arrow_right_3),
                    ),
                ],
              ),
            ),
            // Tester 2026-11-18: a clear, full-width "+ לקוח חדש" right
            // under the title (was a small text link in the corner).
            if (_canAdd)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  0,
                  Space.page,
                  Space.m,
                ),
                child: FilledButton.icon(
                  key: const Key('people-add'),
                  onPressed: _add,
                  icon: const Icon(Iconsax.user_add, size: 20),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: AppText.button,
                  ),
                  label: Text(
                    _chip == PeopleChip.suppliers
                        ? PeopleHe.addSupplier
                        : PeopleHe.addCustomer,
                  ),
                ),
              ),
            OfflineBanner(
              visible: _offline || businessContext.offline,
              onRetry: _load,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: TextField(
                key: const Key('people-search'),
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: PeopleHe.searchContacts,
                  prefixIcon: const Icon(Iconsax.search_normal_1),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('people-search-clear'),
                          tooltip: CommonHe.close,
                          onPressed: _search.clear,
                          icon: const Icon(Iconsax.close_circle),
                        ),
                ),
              ),
            ),
            if (chips.length > 1) ...[
              const SizedBox(height: Space.m),
              ChipRow<PeopleChip>(
                options: [
                  for (final c in chips)
                    ChipOption(
                      c,
                      switch (c) {
                        PeopleChip.active => PeopleHe.chipActive(
                          counts?.active ?? 0,
                        ),
                        PeopleChip.inactive => PeopleHe.chipInactive(
                          counts?.inactive ?? 0,
                        ),
                        PeopleChip.all => PeopleHe.chipAllCustomers(
                          counts?.all ?? 0,
                        ),
                        PeopleChip.debtors => PeopleHe.chipDebtors,
                        PeopleChip.suppliers => PeopleHe.chipSuppliers,
                      },
                      icon: switch (c) {
                        PeopleChip.debtors =>
                          Icons.account_balance_wallet_outlined,
                        PeopleChip.suppliers => Icons.local_shipping_outlined,
                        _ => null,
                      },
                    ),
                ],
                selected: _chip,
                onSelected: (c) => setState(() => _chip = c),
              ),
            ],
            const SizedBox(height: Space.s),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _body(context, p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppPalette p) {
    if (_chip == PeopleChip.suppliers) return _suppliersBody(context, p);
    final list = _list;
    if (list == null) {
      if (_error != null) {
        // Scrollable: with the keyboard up the header leaves little room.
        return _scrollable(
          ErrorView(
            error: _error!,
            onRetry: () {
              setState(() => _error = null);
              _load();
            },
          ),
        );
      }
      return const SingleChildScrollView(child: SkeletonList());
    }
    final q = _search.text.trim();
    final rows = _rows(list, q);
    if (list.customers.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: Iconsax.profile_2user,
          title: PeopleHe.emptyCustomers,
          actionLabel: _caps.can(Cap.docDraft)
              ? PeopleHe.emptyCustomersAction
              : null,
          onAction: _caps.can(Cap.docDraft) ? _add : null,
          secondaryLabel: _canImport ? ImportHe.emptyImportAction : null,
          onSecondary: _canImport ? _import : null,
        ),
      );
    }
    if (rows.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: _chip == PeopleChip.debtors
              ? Iconsax.tick_circle
              : Iconsax.search_status,
          title: _chip == PeopleChip.debtors
              ? PeopleHe.emptyDebtors
              : _chip == PeopleChip.inactive && q.isEmpty
              ? PeopleHe.emptyInactive
              : PeopleHe.noMatches,
          // Not found → add them right here (tester 2026-11-18).
          actionLabel: _chip == PeopleChip.active && _canAdd
              ? PeopleHe.addCustomer
              : null,
          onAction: _chip == PeopleChip.active && _canAdd ? _add : null,
        ),
      );
    }
    final showCap =
        list.capped && (_chip == PeopleChip.active || _chip == PeopleChip.all);
    return ListView.builder(
      key: const Key('people-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + Space.xl,
      ),
      itemCount: rows.length + (showCap ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == rows.length) {
          return Padding(
            padding: const EdgeInsets.all(Space.page),
            child: Text(
              PeopleHe.capped500,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          );
        }
        final c = rows[i];
        final owed = _balances?[c.id];
        return PersonRow(
          key: Key('person-${c.id}'),
          name: c.name,
          subtitle: (c.phone != null && c.phone!.isNotEmpty)
              ? formatPhoneHe(c.phone)
              : null,
          badge: c.isArchived ? PeopleHe.inactiveBadge : null,
          dimmed: c.isArchived,
          amountLabel: owed != null ? PeopleHe.owesYou : null,
          amountMinor: owed,
          onTap: () => _open(c.id),
        );
      },
    );
  }

  List<Customer> _rows(CustomerList list, String q) {
    if (_chip == PeopleChip.debtors) {
      final b = _balances ?? const {};
      final debtors = [
        for (final c in list.customers)
          if (b.containsKey(c.id) && customerMatches(c, q)) c,
      ]..sort((a, z) => b[z.id]!.compareTo(b[a.id]!));
      return debtors;
    }
    // 2611 §4: each chip is its own list; a search under "פעילים" still finds
    // an inactive customer (grey, tagged), as the archive did.
    final base = switch (_chip) {
      PeopleChip.inactive => list.inactive,
      PeopleChip.active when q.isEmpty => list.active,
      _ => list.customers,
    };
    if (q.isEmpty) return sortForPeople(base, recentIds: _recent);
    final local = [
      for (final c in base)
        if (customerMatches(c, q)) c,
    ];
    final ids = {for (final c in local) c.id};
    return sortForPeople([
      ...local,
      ...?_serverHits?.where(
        (c) =>
            !ids.contains(c.id) &&
            (_chip != PeopleChip.inactive || c.isArchived),
      ),
    ], recentIds: _recent);
  }

  Widget _suppliersBody(BuildContext context, AppPalette p) {
    final list = _suppliers;
    if (list == null) {
      if (_error != null) return ErrorView(error: _error!, onRetry: _load);
      return const SingleChildScrollView(child: SkeletonList());
    }
    final q = _search.text.trim();
    final rows = [
      for (final s in list)
        if ((q.isEmpty ? !s.isArchived : true) &&
            personMatches(
              q,
              name: s.name,
              email: s.email,
              phone: s.phone,
              taxId: s.taxId,
            ))
          s,
    ];
    if (rows.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: Iconsax.truck,
          title: list.isEmpty ? PeopleHe.emptySuppliers : PeopleHe.noMatches,
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + Space.xl,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final s = rows[i];
        return PersonRow(
          key: Key('supplier-${s.id}'),
          name: s.name,
          subtitle: formatPhoneHe(s.phone),
          badge: s.isArchived ? PeopleHe.archivedBadge : PeopleHe.supplierBadge,
          onTap: () => _open(s.id, supplier: true),
        );
      },
    );
  }

  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: child,
      ),
    ),
  );
}
