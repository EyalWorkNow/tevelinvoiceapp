// S14 · החלפת עסק (SPEC-v2 §6 sheets, J12 = 2 taps). Owner: squad E.
// Search when > 7 businesses · rows: name · role tag · "פעיל" on the current.
// Switching reloads /me + profile (session.selectBusiness clears the old
// business's /me, profile and caps) and resets the stack to home.
// Search (> 7) asks the server (BE-24 GET /mobile/businesses?q=, paged);
// a server without it → the session's list filtered locally.
// "+ עסק נוסף" (BE-40) → A setup for a new business; shown only when the
// server has POST /businesses.
// Accountant (2026-11-22): one GET /mobile/accountant/clients gives every
// client's readiness + open tasks (badge), the reviewed ✓, pending access
// requests (grey rows, resend / cancel) and "＋ הוספת לקוח". A server without
// it (404) → the per-business ReadinessBoard as before.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/accountant_api.dart';
import '../../../api/auth_api.dart' show searchBusinesses;
import '../../../api/client.dart';
import '../../../api/settings_api.dart' show serverHasPost;
import '../../../api/models/models.dart';
import '../../../router.dart';
import '../../../state/accountant_store.dart';
import '../../../state/business_context.dart';
import '../../../state/session.dart';
import '../../../ui/ds.dart';
import '../../auth/onboarding_screen.dart' show openNewBusiness;
import '../../../util/labels/labels.dart';
import '../../reports/readiness_card.dart' show ReadinessBadge;
import 'accountant_sheets.dart';
import 'readiness_board.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// [required] = right after sign-in with several businesses (no dismiss, no
/// reset: the sign-in flow routes on). Returns the chosen business.
Future<Business?> showSwitchBusinessSheet(
  BuildContext context, {
  bool required = false,
}) async {
  final picked = await showModalBottomSheet<Business>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: !required,
    isDismissible: !required,
    enableDrag: !required,
    builder: (_) => SwitchBusinessSheet(required: required),
  );
  return picked;
}

class SwitchBusinessSheet extends StatefulWidget {
  const SwitchBusinessSheet({super.key, this.required = false});

  final bool required;

  @override
  State<SwitchBusinessSheet> createState() => _SwitchBusinessSheetState();
}

class _SwitchBusinessSheetState extends State<SwitchBusinessSheet> {
  String _query = '';
  String? _loadingId;
  Object? _error;
  Timer? _debounce;

  /// Server search results (BE-24); null = show the session's list.
  List<Business>? _remote;
  int _remoteTotal = 0;
  bool _canAdd = false;

  /// C6: the accountant's board (scores per business, least ready first).
  final ReadinessBoard _board = ReadinessBoard();
  int _boardLimit = ReadinessBoard.pageSize;

  /// The accountant's one-call overview applies (see [_clients]).
  bool _accountant = false;

  @override
  void initState() {
    super.initState();
    _board.addListener(_onBoard);
    accountantStore.addListener(_onBoard);
    _accountant =
        ReadinessBoard.appliesTo(
          session.businesses,
          actingAsAccountant: businessContext.caps.homeIsReports,
        ) ||
        (!widget.required &&
            (accountantStore.isAccountant ||
                businessContext.caps.homeIsReports));
    if (_accountant) unawaited(accountantStore.load());
    if (!widget.required) unawaited(_probeAdd());
  }

  void _onBoard() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    accountantStore.removeListener(_onBoard);
    _board
      ..removeListener(_onBoard)
      ..dispose();
    super.dispose();
  }

  /// Counts + requests come from the clients call (else the old board).
  AccountantOverview? get _clients =>
      _accountant && accountantStore.supported == true
      ? accountantStore.overview
      : null;

  /// The per-business readiness fallback may load (the probe answered 404,
  /// or failed).
  bool get _fallback =>
      !_accountant ||
      accountantStore.supported == false ||
      (accountantStore.supported == null && accountantStore.error != null);

  /// Tasks desc, then readiness asc (unknown last); other rows keep their
  /// place at the end.
  List<Business> _sortByClients(List<Business> list, AccountantOverview o) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    (int, int) rank((int, Business) e) {
      final c = o.clientOf(e.$2.businessId);
      if (c == null) return (1 << 20, 0);
      return (-c.openTasks, c.readiness ?? 1000);
    }

    indexed.sort((a, b) {
      final ra = rank(a), rb = rank(b);
      var r = ra.$1.compareTo(rb.$1);
      if (r == 0) r = ra.$2.compareTo(rb.$2);
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  Future<void> _probeAdd() async {
    try {
      final ok = await serverHasPost('/businesses');
      if (mounted && ok) setState(() => _canAdd = true);
    } on Object {
      // Offline: no "+ עסק נוסף" this time.
    }
  }

  void _onQuery(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _remote = null);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(v, append: false),
    );
  }

  Future<void> _search(String q, {required bool append}) async {
    try {
      final page = await searchBusinesses(
        q,
        offset: append ? (_remote?.length ?? 0) : 0,
      );
      if (!mounted || q != _query) return;
      setState(() {
        if (page == null) {
          _remote = null;
        } else {
          _remote = [...?(append ? _remote : null), ...page.businesses];
          _remoteTotal = page.total;
        }
      });
    } on ApiException {
      // Offline / transient: the local filter stays.
    }
  }

  void _addBusiness() {
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(openNewBusiness(nav.context));
  }

  Future<void> _pick(Business b, {bool focusTodo = false}) async {
    if (_loadingId != null) return;
    HapticFeedback.selectionClick();
    final current =
        session.business?.businessId == b.businessId && session.me != null;
    // A client row opens that business's "לטיפול" (feature 3).
    if (focusTodo) accountantFocusTodo.value = true;
    if (current) {
      Navigator.of(context).pop(b);
      return;
    }
    setState(() {
      _loadingId = b.businessId;
      _error = null;
    });
    try {
      await session.selectBusiness(b);
    } on ApiException catch (e) {
      // Offline: the choice is stored; home shows cached data + banner.
      if (!e.isNetwork) {
        accountantFocusTodo.value = false;
        if (mounted) setState(() => _error = e);
        return;
      }
    } finally {
      if (mounted) setState(() => _loadingId = null);
    }
    if (!mounted) return;
    Navigator.of(context).pop(b);
    if (!widget.required) resetToHome();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = session.businesses;
    final q = _query.trim();
    final shown =
        _remote ??
        (q.isEmpty
            ? all
            : [
                for (final b in all)
                  if (b.legalName.toLowerCase().contains(q.toLowerCase())) b,
              ]);
    final current = session.business?.businessId;
    // C6: an accountant of several businesses sees each one's readiness,
    // least ready first, a page at a time; scores load for the shown rows only.
    final board = ReadinessBoard.appliesTo(
      all,
      actingAsAccountant: businessContext.caps.homeIsReports,
    );
    final clients = _clients;
    final rows = clients != null
        ? _sortByClients(shown, clients)
        : board
        ? _board.sort(shown).take(_boardLimit).toList()
        : shown;
    if (board && clients == null && _fallback) _board.ensure(rows);
    final requests = clients == null || q.isNotEmpty
        ? const <AccessRequest>[]
        : clients.requests;
    final canAddClient =
        !widget.required &&
        _accountant &&
        accountantStore.supported == true &&
        (clients?.isAccountant ?? false);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.page,
              widget.required ? Space.xl : 0,
              Space.page,
              Space.m,
            ),
            child: Semantics(
              header: true,
              child: const Text(BusinessHe.switchTitle, style: AppText.title),
            ),
          ),
          if (all.length > 7)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                0,
                Space.page,
                Space.s,
              ),
              child: TextField(
                key: const Key('s14-search'),
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Iconsax.search_normal_1),
                  hintText: BusinessHe.searchBusiness,
                ),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              children: [
                if (clients != null)
                  _ClientsSummary(overview: clients)
                else if (board)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.xs),
                    child: Text(
                      ReadinessHe.sortedLeastReady,
                      key: const Key('s14-board'),
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ),
                for (final b in rows)
                  if (clients?.clientOf(b.businessId) case final c?)
                    _BusinessRow(
                      business: b,
                      current: b.businessId == current,
                      loading: _loadingId == b.businessId,
                      onTap: () => _pick(b, focusTodo: true),
                      readiness: c.readiness == null
                          ? null
                          : ReadinessBadge(
                              key: Key('s14-score-${b.businessId}'),
                              score: c.readiness,
                              size: 36,
                            ),
                      readinessScore: c.readiness,
                      client: c,
                    )
                  else
                    _BusinessRow(
                      business: b,
                      current: b.businessId == current,
                      loading: _loadingId == b.businessId,
                      onTap: () => _pick(b),
                      readiness:
                          board &&
                              ReadinessBoard.rowApplies(b) &&
                              (_board.isLoading(b.businessId) ||
                                  _board.scoreOf(b.businessId) != null)
                          ? ReadinessBadge(
                              key: Key('s14-score-${b.businessId}'),
                              score: _board.scoreOf(b.businessId),
                              size: 36,
                            )
                          : null,
                      readinessScore: board
                          ? _board.scoreOf(b.businessId)
                          : null,
                    ),
                for (final r in requests) RequestTile(request: r),
                if (board && clients == null && rows.length < shown.length)
                  TextButton(
                    key: const Key('s14-board-more'),
                    onPressed: () =>
                        setState(() => _boardLimit += ReadinessBoard.pageSize),
                    child: const Text(ReadinessHe.showMore),
                  ),
                if (_remote != null && _remote!.length < _remoteTotal)
                  TextButton(
                    key: const Key('s14-more'),
                    onPressed: () => _search(_query, append: true),
                    child: const Text(BusinessHe.showMoreBusinesses),
                  ),
                if (canAddClient)
                  ListTile(
                    key: const Key('s14-add-client'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Hit.row,
                    leading: const Icon(Iconsax.user_add),
                    title: const Text(
                      AccountantHe.addClient,
                      style: AppText.body,
                    ),
                    onTap: session.offline
                        ? null
                        : () => unawaited(showAddClientSheet(context)),
                  ),
                if (_canAdd)
                  ListTile(
                    key: const Key('s14-add'),
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Hit.row,
                    leading: const Icon(Iconsax.shop_add),
                    title: const Text(
                      BusinessHe.addBusiness,
                      style: AppText.body,
                    ),
                    onTap: session.offline ? null : _addBusiness,
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(Space.page),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  errorTextHe(_error!),
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

class _BusinessRow extends StatelessWidget {
  const _BusinessRow({
    required this.business,
    required this.current,
    required this.loading,
    required this.onTap,
    this.readiness,
    this.readinessScore,
    this.client,
  });

  final Business business;

  /// The accountant's counts for this row (feature 3, 6, 8).
  final AccountantClient? client;
  final bool current;
  final bool loading;
  final VoidCallback onTap;

  /// C6: the accountant's board badge (score ring).
  final Widget? readiness;
  final int? readinessScore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final role = PresetHe.label(presetOf(business.role, const []));
    final c = client;
    final tasks = c?.openTasks ?? 0;
    final reviewed = c != null && previousPeriodReviewed(c.lastReviewedPeriod);
    final row = Semantics(
      button: true,
      selected: current,
      label:
          '${business.legalName}, $role${current ? ', ${BusinessHe.active}' : ''}'
          '${readinessScore == null ? '' : ', ${ReadinessHe.scoreSemantics(readinessScore!, ReadinessHe.badge(readinessScore!, 90))}'}'
          '${tasks > 0 ? ', ${AccountantHe.tasksSemantics(tasks)}' : ''}'
          '${reviewed ? ', ${AccountantHe.reviewedSemantics}' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('s14-${business.businessId}'),
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: loading ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: p.charcoal,
                foregroundColor: p.accent,
                child: Text(
                  _initial(business.legalName),
                  style: AppText.headline,
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            business.legalName,
                            style: AppText.headline,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (reviewed) ...[
                          const SizedBox(width: Space.xs),
                          Icon(
                            Iconsax.tick_circle,
                            key: Key('s14-reviewed-${business.businessId}'),
                            size: 16,
                            color: p.ok,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      role,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              if (tasks > 0) ...[
                TaskCountBubble(
                  key: Key('s14-tasks-${business.businessId}'),
                  count: tasks,
                ),
                const SizedBox(width: Space.s),
              ],
              if (readiness != null) ...[
                readiness!,
                const SizedBox(width: Space.s),
              ],
              if (loading)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (current)
                Text(
                  BusinessHe.active,
                  style: AppText.secondary.copyWith(color: p.ok),
                ),
            ],
          ),
        ),
      ),
    );
    if (c == null || !canRemindOwner(c)) return row;
    return Row(
      children: [
        Expanded(child: row),
        IconButton(
          key: Key('s14-remind-${business.businessId}'),
          tooltip: AccountantHe.remind,
          icon: Icon(Iconsax.message_text, color: p.muted),
          onPressed: () => unawaited(remindOwner(c)),
        ),
      ],
    );
  }
}

/// The count of open tasks in a small circle (feature 3).
class TaskCountBubble extends StatelessWidget {
  const TaskCountBubble({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.warn,
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.secondary.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// "12 לקוחות · 3 דורשים טיפול" + the pending requests (a dot and a phrase).
class _ClientsSummary extends StatelessWidget {
  const _ClientsSummary({required this.overview});

  final AccountantOverview overview;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pending = overview.pending.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clientsSummaryText(
              overview.clients.length,
              overview.needingAttention,
            ),
            key: const Key('s14-clients-summary'),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          if (pending > 0)
            Row(
              key: const Key('s14-pending-summary'),
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: p.warn,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Text(
                  AccountantHe.pendingCount(pending),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "12 לקוחות · 3 דורשים טיפול" / "· הכול מסודר"; [attention] null = count only.
String clientsSummaryText(int count, int? attention) {
  final head = AccountantHe.clients(count);
  if (attention == null || count == 0) return head;
  return attention == 0
      ? '$head · ${AccountantHe.allClear}'
      : '$head · ${AccountantHe.needAttention(attention)}';
}

/// A grey access-request row: "ממתין לאישור" (resend / cancel) or
/// "הבקשה לא אושרה" / "פג תוקף הבקשה" (resend).
class RequestTile extends StatelessWidget {
  const RequestTile({super.key, required this.request});

  final AccessRequest request;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = request;
    final status = switch (r.status) {
      AccessRequestStatus.pending => AccountantHe.pending,
      AccessRequestStatus.declined => AccountantHe.declined,
      _ => AccountantHe.expired,
    };
    return Padding(
      key: Key('s14-request-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: p.line,
            foregroundColor: p.muted,
            child: const Icon(Iconsax.clock, size: 20),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ltrIsolate(r.contact),
                  style: AppText.body.copyWith(color: p.muted),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$status · ${AccountantHe.roleName(r.role)}',
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('s14-request-resend-${r.id}'),
            onPressed: session.offline
                ? null
                : () => unawaited(resendRequest(context, r)),
            child: const Text(AccountantHe.resend),
          ),
          if (r.status == AccessRequestStatus.pending)
            TextButton(
              key: Key('s14-request-cancel-${r.id}'),
              onPressed: session.offline
                  ? null
                  : () => unawaited(cancelRequest(context, r)),
              child: const Text(AccountantHe.cancel),
            ),
        ],
      ),
    );
  }
}

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first;
}
