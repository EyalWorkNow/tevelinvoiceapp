// P · לקוחות (+ ספקים) (SPEC-v2 §6.P). Owner: squad D.
// Route: /people?chip=   (chip ∈ all | debtors | suppliers). Tab "לקוחות".
//
// Header "לקוחות" + text button "+ לקוח" → search → chips הכל · חייבים
// (money.view) · ספקים (§4.4: supplier.manage, expense capture or approve —
// employee and accountant view; "+ ספק" stays supplier.manage) → rows: recent first, then א–ת.
// Row: name · phone · "חייב לך ₪X" (money.view). Archived customers appear
// only in search, tagged "בארכיון". Balances come from BE-09 rows, else one
// GET /documents?unpaid=1&limit=500; a capped answer hides them (no partial
// number). No primary button (list screen).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/customers_api.dart';
import '../../api/models/models.dart';
import '../../api/suppliers_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/people_he.dart';
import '../../util/phone.dart';
import 'sheets/s2_customer.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum PeopleChip { all, debtors, suppliers }

PeopleChip? peopleChipFrom(String? s) => switch (s) {
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
  PeopleChip _chip = PeopleChip.all;
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
    _chip = peopleChipFrom(widget.chip) ?? PeopleChip.all;
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

  bool get _canAdd => _chip == PeopleChip.suppliers
      ? _caps.can(Cap.supplierManage)
      : _caps.can(Cap.docDraft);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final chips = _chips;
    if (!chips.contains(_chip)) _chip = PeopleChip.all;
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
                  if (_canAdd)
                    TextButton.icon(
                      key: const Key('people-add'),
                      onPressed: _add,
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 19,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(Hit.min, Hit.min),
                        textStyle: AppText.button,
                      ),
                      label: Text(
                        _chip == PeopleChip.suppliers
                            ? PeopleHe.addSupplier
                            : PeopleHe.addCustomer,
                      ),
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
                        PeopleChip.all => PeopleHe.chipAll,
                        PeopleChip.debtors => PeopleHe.chipDebtors,
                        PeopleChip.suppliers => PeopleHe.chipSuppliers,
                      },
                      icon: switch (c) {
                        PeopleChip.all => Icons.people_alt_outlined,
                        PeopleChip.debtors =>
                          Icons.account_balance_wallet_outlined,
                        PeopleChip.suppliers => Icons.local_shipping_outlined,
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
        return ErrorView(
          error: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
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
              : PeopleHe.noMatches,
        ),
      );
    }
    final showCap = list.capped && _chip == PeopleChip.all;
    return ListView.builder(
      key: const Key('people-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 140),
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
              : (context.isDark ? '052-0000111' : null),
          badge: c.isArchived ? PeopleHe.archivedBadge : null,
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
    if (q.isEmpty) return sortForPeople(list.active, recentIds: _recent);
    final local = [
      for (final c in list.customers)
        if (customerMatches(c, q)) c,
    ];
    final ids = {for (final c in local) c.id};
    return sortForPeople([
      ...local,
      ...?_serverHits?.where((c) => !ids.contains(c.id)),
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
      padding: const EdgeInsets.only(bottom: 140),
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
