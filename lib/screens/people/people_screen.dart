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
import '../../api/customer_groups_api.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/groups_he.dart';
import '../groups/group_screen.dart';
import '../groups/group_sheets.dart';
import '../groups/groups_strip.dart';
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

  /// V4 §8: the groups row (null = not loaded / no groups server) and the
  /// long-press multi-select.
  GroupList? _groups;
  final CustomerSelection _selection = CustomerSelection();

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
      _groups = null;
      _selection.clear();
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

  Future<void> _loadGroups() async {
    final business = _business;
    try {
      final g = await fetchGroups();
      if (mounted && business == _business) setState(() => _groups = g);
    } on Object {
      // Offline / no groups on the server yet: the row stays hidden.
    }
  }

  bool get _canGroup => _caps.can(Cap.customerManage);

  void _toggle(String id) => setState(() => _selection.toggle(id));

  void _toastText(String text) => ScaffoldMessenger.maybeOf(
    context,
  )?.showNotchNotice(SnackBar(content: Text(text)));

  Future<void> _openGroup(String id, {GroupActionKind? startAction}) async {
    await openGroup(context, id, startAction: startAction);
    if (mounted) _load();
  }

  Future<void> _newGroup() async {
    final g = await showGroupEditorSheet(context);
    if (g == null || !mounted) return;
    await _openGroup(g.id);
  }

  /// The selection → a group (picked or new). Null = cancelled / failed.
  Future<GroupSummary?> _selectionToGroup() async {
    final ids = _selection.ids.toList();
    final g = await showPickGroupSheet(
      context,
      groups: _groups?.groups ?? const [],
      subtitle: GroupsHe.selected(ids.length),
    );
    if (g == null || !mounted) return null;
    try {
      await addGroupMembers(g.id, ids);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return null;
    }
    if (!mounted) return g;
    setState(_selection.clear);
    unawaited(_loadGroups());
    _toastText(GroupsHe.addedToGroup(ids.length, g.name));
    return g;
  }

  Future<void> _selectionQuickAction() async {
    final ids = groupActionIds(_caps, smart: null).where((a) => a != 'add');
    final chosen = await showAppSheet<String>(
      context,
      builder: (sheet) => Column(
        key: const Key('people-quick-sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetTitle(
            GroupsHe.quickActionTitle,
            subtitle: GroupsHe.quickActionHint,
          ),
          for (final id in ids)
            ListTile(
              key: Key('people-quick-$id'),
              contentPadding: EdgeInsets.zero,
              title: Text(switch (id) {
                'payment' => GroupsHe.actPayment,
                'broadcast' => GroupsHe.actBroadcast,
                'document' => GroupsHe.actDocument,
                'invite' => GroupsHe.actInvite,
                _ => GroupsHe.actStatement,
              }),
              onTap: () => Navigator.of(sheet).pop(id),
            ),
        ],
      ),
    );
    final kind = chosen == null ? null : groupActionKind(chosen);
    if (kind == null || !mounted) return;
    final g = await _selectionToGroup();
    if (g != null && mounted) await _openGroup(g.id, startAction: kind);
  }

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
      unawaited(_loadGroups());
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
    if (!chips.contains(_chip)) _chip = PeopleChip.all;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selection.active) _selectionBar(context),
            if (!_selection.active)
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
            if (_canAdd && !_selection.active)
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
            if (_showGroups) ...[
              GroupsStrip(
                groups: _groups!,
                onOpen: (g) => unawaited(_openGroup(g.id)),
                onNew: _canGroup ? () => unawaited(_newGroup()) : null,
              ),
              const SizedBox(height: Space.xs),
            ],
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
              : PeopleHe.noMatches,
          // Not found → add them right here (tester 2026-11-18).
          actionLabel: _chip != PeopleChip.debtors && _canAdd
              ? PeopleHe.addCustomer
              : null,
          onAction: _chip != PeopleChip.debtors && _canAdd ? _add : null,
        ),
      );
    }
    final showCap = list.capped && _chip == PeopleChip.all;
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
        final selecting = _selection.active;
        final row = PersonRow(
          key: Key('person-${c.id}'),
          name: c.name,
          subtitle: (c.phone != null && c.phone!.isNotEmpty)
              ? formatPhoneHe(c.phone)
              : null,
          badge: c.isArchived ? PeopleHe.archivedBadge : null,
          amountLabel: owed != null ? PeopleHe.owesYou : null,
          amountMinor: owed,
          onTap: selecting ? () => _toggle(c.id) : () => _open(c.id),
        );
        if (!_canGroup) return row;
        return GestureDetector(
          key: Key('person-select-${c.id}'),
          onLongPress: () => _toggle(c.id),
          child: !selecting
              ? row
              : Row(
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Space.page,
                      ),
                      child: Icon(
                        _selection.contains(c.id)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: Key('person-check-${c.id}'),
                        color: _selection.contains(c.id) ? p.accent : p.muted,
                      ),
                    ),
                    Expanded(child: row),
                  ],
                ),
        );
      },
    );
  }

  bool get _showGroups =>
      _groups != null &&
      _chip == PeopleChip.all &&
      _search.text.trim().isEmpty &&
      !_selection.active &&
      (_canGroup || _groups!.groups.isNotEmpty || _groups!.smart.isNotEmpty);

  Widget _selectionBar(BuildContext context) => Padding(
    key: const Key('people-selection'),
    padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.s, Space.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  GroupsHe.selected(_selection.count),
                  style: AppText.displayTitle,
                ),
              ),
            ),
            IconButton(
              key: const Key('people-selection-cancel'),
              tooltip: GroupsHe.cancelSelection,
              onPressed: () => setState(_selection.clear),
              icon: const Icon(Iconsax.close_circle),
            ),
          ],
        ),
        const SizedBox(height: Space.s),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: Space.page - Space.s),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('people-add-to-group'),
                  onPressed: () => unawaited(_selectionToGroup()),
                  icon: const Icon(Iconsax.profile_add, size: 20),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  label: const Text(GroupsHe.addToGroup),
                ),
              ),
              if (groupActionIds(
                _caps,
                smart: null,
              ).any((a) => a != 'add')) ...[
                const SizedBox(width: Space.s),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('people-quick-action'),
                    onPressed: () => unawaited(_selectionQuickAction()),
                    icon: const Icon(Iconsax.flash_1, size: 20),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    label: const Text(GroupsHe.quickAction),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

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
