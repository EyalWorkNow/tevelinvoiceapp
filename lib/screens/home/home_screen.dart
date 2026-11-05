// H · בית (SPEC-v2 §6.H). Owner: squad A.
//
// At most 4 blocks under the header: money card (2 numbers), 2 intent
// buttons, "לטיפול" (≤3 cards), "אחרונים" (≤5 rows). No template chips, no
// search icon. A read screen: zero PrimaryButtons (AT-90). Every block asks
// its capability; a block without one is not built (F5).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/documents_api.dart' show documentsVersion;
import '../../api/inbox_api.dart' show dismissSetup;
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/inbox_he.dart';
import '../business/sheets/s14_switch.dart';
import 'doc_rows.dart';
import 'home_controller.dart';
import 'inbox_cards.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Tab "בית" for everyone except the accountant presets (they get R).
/// Shown inside AppShell (no AppBar of its own).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller});

  /// Tests pass a controller and drive [HomeController.load] themselves.
  final HomeController? controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _c = widget.controller ?? HomeController();
  bool get _owned => widget.controller == null;
  final _recentSearch = TextEditingController();
  bool _recentSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    businessContext.addListener(_onBusiness);
    documentsVersion.addListener(_reload);
    if (_owned) unawaited(_c.load());
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    businessContext.removeListener(_onBusiness);
    documentsVersion.removeListener(_reload);
    _recentSearch.dispose();
    if (_owned) _c.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onBusiness() {
    if (_c.businessChanged()) {
      _reload();
    } else if (_c.capsChanged()) {
      _c.applyCaps();
      _reload();
    } else {
      _changed();
    }
  }

  void _reload() => unawaited(_c.load());

  @override
  Widget build(BuildContext context) {
    final caps = businessContext.caps;
    final data = _c.data;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: ClipRect(
              child: RefreshIndicator(
                onRefresh: () => _c.load(refreshMe: true),
                child: ListView(
                  key: const Key('home-list'),
                  padding: EdgeInsets.fromLTRB(
                    Space.page,
                    context.isDark ? 0 : 14,
                    Space.page,
                    MediaQuery.paddingOf(context).bottom + Space.xl,
                  ),
                  children: [
                    OfflineBanner(visible: _c.offline, onRetry: _reload),
                    _Header(caps: caps),
                    SizedBox(height: context.isDark ? 10 : 36),
                    if (data != null && (data.openMinor != null)) ...[
                      _moneyCard(context, data),
                      SizedBox(height: context.isDark ? 10 : Space.l),
                    ],
                    if (data != null &&
                        !data.hasDocuments &&
                        caps.showIntentButtons) ...[
                      Text(
                        InboxHe.firstDocHint,
                        style: AppText.headline,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Space.s),
                    ],
                    if (context.isDark ||
                        caps.showIntentButtons ||
                        caps.can(Cap.docView) ||
                        caps.can(Cap.expenseCapture)) ...[
                      _IntentButtons(caps: caps),
                      SizedBox(height: context.isDark ? 12 : Space.section),
                    ],
                    ContentReveal(
                      key: ValueKey(data != null),
                      child: Column(children: _body(context, caps, data)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, Caps caps, HomeData? data) {
    if (data == null) {
      if (_c.error != null && !_c.loading) {
        return [ErrorView(error: _c.error!, onRetry: _reload)];
      }
      return const [SkeletonList(rows: 4)];
    }
    return [
      if (inboxVisible(caps) && data.cards.isNotEmpty) ..._todo(context, data),
      if (data.recent.isNotEmpty) ..._recent(context, data),
      if (inboxVisible(caps) && data.cards.isEmpty) ...[
        const SizedBox(height: Space.section),
        ..._todo(context, data),
      ],
    ];
  }

  Widget _moneyCard(BuildContext context, HomeData data) {
    final amount = data.openMinor ?? BigInt.zero;
    final overdue = data.overdueMinor ?? BigInt.zero;
    final late = !context.isDark && overdue > BigInt.zero;
    return MoneyCard(
      key: const Key('home-money'),
      label: InboxHe.moneyLabel,
      amountMinor: amount,
      secondaryLabel: late ? InboxHe.moneyOverdue : null,
      secondaryMinor: late ? overdue : null,
      onTap: () => unawaited(openActivity(context, chip: 'unpaid')),
    );
  }

  List<Widget> _todo(BuildContext context, HomeData data) {
    final cards = data.cards;
    final summaryRows = cards
        .take(3)
        .map(
          (c) => InboxSummaryRow(
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
        )
        .toList();

    return [
      if (cards.isEmpty)
        Column(
          children: [
            _SectionTitle(InboxHe.todo),
            Padding(
              key: const Key('home-all-handled'),
              padding: const EdgeInsets.symmetric(vertical: Space.m),
              child: Text(
                CommonHe.allHandled,
                style: AppText.body.copyWith(color: context.palette.muted),
              ),
            ),
          ],
        )
      else ...[
        InboxSummaryCard(
          key: const Key('home-inbox-summary'),
          title: InboxHe.todo,
          rows: summaryRows,
          moreLabel: cards.length > 3
              ? InboxHe.moreCards(cards.length - 3)
              : null,
          onMore: cards.length > 3
              ? () => unawaited(openActivity(context, chip: 'inbox'))
              : null,
        ),
      ],
      const SizedBox(height: Space.section),
    ];
  }

  List<Widget> _recent(BuildContext context, HomeData data) {
    final query = _recentSearch.text.trim().toLowerCase();
    final recent = query.isEmpty
        ? data.recent.take(5).toList()
        : data.recent
              .where((document) {
                final searchable = [
                  document.customerName,
                  document.documentNumber,
                  document.documentType,
                  document.status,
                  document.issueDate,
                  document.id,
                  document.totalMinor.toString(),
                  (document.totalMinor ~/ BigInt.from(100)).toString(),
                ].whereType<String>().join(' ').toLowerCase();
                return searchable.contains(query);
              })
              .take(5)
              .toList();
    return [
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _recentSearchOpen
                          ? TextField(
                              key: const Key('home-recent-search-field'),
                              controller: _recentSearch,
                              autofocus: true,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: InboxHe.searchHint,
                                prefixIcon: const Icon(Iconsax.search_normal_1),
                                suffixIcon: _recentSearch.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: CommonHe.close,
                                        onPressed: () {
                                          _recentSearch.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Iconsax.close_circle),
                                      ),
                              ),
                            )
                          : Text(
                              InboxHe.recent,
                              key: const ValueKey('home-recent-title'),
                              style: AppText.headline,
                            ),
                    ),
                  ),
                  IconButton(
                    key: const Key('home-recent-search'),
                    tooltip: _recentSearchOpen
                        ? CommonHe.close
                        : InboxHe.searchLabel,
                    onPressed: () => setState(() {
                      _recentSearchOpen = !_recentSearchOpen;
                      if (!_recentSearchOpen) _recentSearch.clear();
                    }),
                    icon: Icon(
                      _recentSearchOpen
                          ? Icons.close_rounded
                          : Icons.search_rounded,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_recentSearchOpen && recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.l),
                child: Text(
                  InboxHe.noResults,
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: context.palette.muted),
                ),
              ),
            for (final d in recent)
              docRowFor(
                d,
                today: _c.now?.call(),
                onTap: () => unawaited(openDocument(context, d.id)),
              ),
            if (!_recentSearchOpen && !context.isDark)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('home-all-activity'),
                  onPressed: () => unawaited(openActivity(context)),
                  child: const Text(InboxHe.allActivity),
                ),
              )
            else if (!_recentSearchOpen)
              Offstage(
                offstage: true,
                child: TextButton(
                  key: const Key('home-all-activity'),
                  onPressed: () => unawaited(openActivity(context)),
                  child: const Text(InboxHe.allActivity),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

/// "לטיפול" exists only for someone who can get at least one card kind
/// (§4.4: צפייה בלבד has none).
bool inboxVisible(Caps caps) =>
    caps.can(Cap.docDraft) ||
    caps.can(Cap.approvalDecide) ||
    caps.can(Cap.expenseApprove) ||
    caps.can(Cap.settingsBusiness);

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Semantics(header: true, child: Text(text, style: AppText.headline)),
  );
}

/// Business name (+ role tag for a non-owner). Opens S14 only with >1 business.
class _Header extends StatelessWidget {
  const _Header({required this.caps});

  final Caps caps;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tag = caps.roleTag == null ? null : presetTagLabels[caps.roleTag];
    final many = businessContext.hasManyBusinesses;
    if (context.isDark) {
      final headerRow = Row(
        children: [
          MoreMenu(
            items: [
              MoreMenuItem(
                label: CommonHe.tabBusiness,
                onSelected: () => openBusiness(),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Container(
            width: 57.303,
            height: 57.303,
            decoration: const BoxDecoration(
              color: DesignTokens.control,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/design/danielle_avatar.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const DesignIcon('profile', size: 33),
            ),
          ),
          const Spacer(),
          Offstage(
            offstage: true,
            child: Row(
              children: [
                Text(
                  businessContext.displayName,
                  key: const Key('home-business-name'),
                ),
                if (tag != null) Text(tag, key: const Key('home-role-tag')),
                if (many)
                  InkWell(
                    key: const Key('home-switch-business'),
                    onTap: () => unawaited(showSwitchBusinessSheet(context)),
                  ),
              ],
            ),
          ),
        ],
      );
      return Semantics(header: true, child: headerRow);
    }
    final row = Row(
      children: [
        Container(
          width: 57.303,
          height: 57.303,
          decoration: const BoxDecoration(
            color: DesignTokens.control,
            shape: BoxShape.circle,
          ),
          child: const DesignIcon('profile', size: 33),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                businessContext.displayName,
                key: const Key('home-business-name'),
                style: AppText.body,
                overflow: TextOverflow.ellipsis,
              ),
              if (tag != null)
                Text(
                  tag,
                  key: const Key('home-role-tag'),
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
            ],
          ),
        ),
        if (many) Icon(Iconsax.arrow_down_1, color: p.muted),
        MoreMenu(
          items: [
            MoreMenuItem(
              label: CommonHe.tabBusiness,
              onSelected: () => openBusiness(),
            ),
          ],
        ),
      ],
    );
    if (!many) return Semantics(header: true, child: row);
    return Semantics(
      button: true,
      header: true,
      hint: InboxHe.switchBusinessHint,
      child: InkWell(
        key: const Key('home-switch-business'),
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => unawaited(showSwitchBusinessSheet(context)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: row,
        ),
      ),
    );
  }
}

/// קיבלתי תשלום (lime) · בקש תשלום — half width, 72pt. "קיבלתי" needs
/// payment.record (§19 q7: hidden for an employee without finalize).
class _IntentButtons extends StatelessWidget {
  const _IntentButtons({required this.caps});

  final Caps caps;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (caps.can(Cap.docView))
        ActionOrb(
          label: InboxHe.documentsAction,
          icon: const DesignIcon('documents'),
          color: DesignTokens.coral,
          onPressed: () => unawaited(openActivity(context)),
        ),
      if (caps.can(Cap.paymentRecord))
        ActionOrb(
          key: const Key('intent-paid'),
          label: CommonHe.paid,
          icon: const DesignIcon('income'),
          color: DesignTokens.lavender,
          onPressed: () => unawaited(openCompose(context, intent: 'PAID')),
        ),
      if (caps.can(Cap.expenseCapture) || caps.can(Cap.expenseApprove))
        ActionOrb(
          label: InboxHe.expensesAction,
          icon: const DesignIcon('expense'),
          color: DesignTokens.yellow,
          onPressed: () => unawaited(
            caps.can(Cap.expenseApprove) && caps.can(Cap.moneyView)
                ? openExpenseOverview(context)
                : openExpenses(context),
          ),
        ),
      if (caps.showIntentButtons)
        ActionOrb(
          key: const Key('intent-request'),
          label: CommonHe.requestPayment,
          icon: const DesignIcon('request'),
          color: DesignTokens.green,
          onPressed: () => unawaited(openCompose(context, intent: 'REQUEST')),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final action in actions) Expanded(child: action)],
    );
  }
}
