// H · בית (SPEC-v2 §6.H). Owner: squad A.
//
// At most 4 blocks under the header: money card (2 numbers), 2 intent
// buttons, "לטיפול" (≤3 cards), "אחרונים" (≤5 rows). No template chips, no
// search icon. A read screen: zero PrimaryButtons (AT-90). Every block asks
// its capability; a block without one is not built (F5).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/documents_api.dart' show deleteDraft, documentsVersion;
import '../../api/inbox_api.dart' show dismissSetup;
import '../../api/notifications_api.dart'
    show notificationsUnread, notificationsVersion, refreshNotificationsUnread;
import '../../util/labels/notifications_he.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/cache.dart';
import '../../state/caps.dart';
import '../../state/session.dart' show session;
import '../../ui/ds.dart';
import '../../ui/widgets/ceiling_gauge.dart';
import '../../ui/widgets/shell_inset.dart';
import '../../util/labels/common_he.dart';
import '../debts/debts_home_row.dart';
import '../reports/daily_summary_home_row.dart';
import '../../api/reports_api.dart' show dailySummaryKind;
import '../../util/money.dart' show formatMoney;
import '../../util/labels/inbox_he.dart';
import '../people/customer_crm_agenda_screen.dart';
import '../business/sheets/editor_configs.dart' show openTypeChangeSheet;
import '../business/sheets/s14_switch.dart';
import 'doc_rows.dart';
import 'home_controller.dart';
import 'inbox_cards.dart';
import '../tutorial/coach_mark.dart';
import '../tutorial/tutorial_screen.dart';
import '../tutorial/tutorial_state.dart';
import '../../util/labels/tutorial_he.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Tab "בית" for everyone except the accountant presets (they get R).
/// Shown inside AppShell (no AppBar of its own).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.controller, this.onOpenProfile});

  /// Tests pass a controller and drive [HomeController.load] themselves.
  final HomeController? controller;
  final VoidCallback? onOpenProfile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _c = widget.controller ?? HomeController();
  bool get _owned => widget.controller == null;
  final _recentSearch = TextEditingController();
  bool _recentSearchOpen = false;
  final Set<String> _deletedRecentDrafts = {};
  Uint8List? _profileAvatar;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    businessContext.addListener(_onBusiness);
    documentsVersion.addListener(_reload);
    notificationsVersion.addListener(_refreshBell);
    if (_owned) unawaited(_c.load());
    _refreshBell();
    unawaited(_loadProfileAvatar());
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tutorial()));
  }

  /// 2611 §1: a new owner / member — the cards, then the coach mark on
  /// "חשבונית" (the navbar's create button, found by its key).
  Future<void> _tutorial() async {
    if (!mounted) return;
    if (await tutorialState.takeCards() && mounted) {
      await openTutorial(context);
    }
    if (!mounted) return;
    await maybeShowCoachMark(
      context,
      id: CoachIds.home,
      target: const Key('tab-create'),
      text: TutorialHe.coachHome,
    );
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    businessContext.removeListener(_onBusiness);
    documentsVersion.removeListener(_reload);
    notificationsVersion.removeListener(_refreshBell);
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

  void _reload() {
    unawaited(_c.load());
    _refreshBell();
  }

  /// The bell badge (tester 2026-11-18): Home load, business switch, a push.
  void _refreshBell() => unawaited(refreshNotificationsUnread());

  String? get _profileAvatarKey {
    final userId = session.account?.userId;
    return userId == null ? null : 'profile_avatar_$userId';
  }

  Future<void> _loadProfileAvatar() async {
    final key = _profileAvatarKey;
    if (key == null) return;
    final value = await AppCache.readUserData(key);
    if (!mounted || value is! String) return;
    try {
      setState(() => _profileAvatar = base64Decode(value));
    } on FormatException {
      // The initial fallback remains available if local photo data is invalid.
    }
  }

  Future<void> _pickProfileAvatar() async {
    final key = _profileAvatarKey;
    if (key == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 78,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      await AppCache.writeUserData(key, base64Encode(bytes));
      if (mounted) setState(() => _profileAvatar = bytes);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא הצלחנו לעדכן את תמונת הפרופיל.')),
      );
    }
  }

  Future<void> _deleteRecentDraft(DocumentSummary document) async {
    if (!await confirmDraftDeletion(context) || !mounted) return;
    setState(() => _deletedRecentDrafts.add(document.id));
    try {
      await deleteDraft(document.id);
      if (mounted) _reload();
    } on Object {
      if (!mounted) return;
      setState(() => _deletedRecentDrafts.remove(document.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא הצלחנו למחוק את הטיוטה. נסו שוב.')),
      );
    }
  }

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
                    shellListBottom(context),
                  ),
                  children: [
                    OfflineBanner(visible: _c.offline, onRetry: _reload),
                    Row(
                      children: [
                        Expanded(
                          child: _Header(
                            onOpenProfile: widget.onOpenProfile,
                            onEditAvatar: _pickProfileAvatar,
                            avatarBytes: _profileAvatar,
                          ),
                        ),
                        // Tester 2026-11-18: an in-app inbox of updates
                        // (quote accepted, document signed, payment …).
                        const _Bell(),
                      ],
                    ),
                    SizedBox(height: context.isDark ? 10 : 36),
                    if (data != null && (data.openMinor != null)) ...[
                      _moneyCard(context, data),
                      // C1: "מי חייב לי" (one row, money viewers only).
                      if (caps.can(Cap.moneyView))
                        DebtsHomeRow(
                          onTap: () => unawaited(openDebts(context)),
                        ),
                      SizedBox(height: context.isDark ? 10 : Space.l),
                    ],
                    // A6: עוסק פטור ceiling gauge (exempt only, money viewers).
                    if (businessContext.businessType == 'OSEK_PATUR' &&
                        caps.can(Cap.moneyView)) ...[
                      CeilingGauge(
                        rules:
                            businessContext.me?.rules ?? const BusinessRules(),
                        onSwitchToMurshe: caps.can(Cap.settingsBusiness)
                            ? () => unawaited(openTypeChangeSheet(context))
                            : null,
                      ),
                      const SizedBox(height: Space.l),
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
                    // B1: the cashier's Home is one fast "קיבלתי תשלום".
                    if (caps.homeIsCashier) ...[
                      _CashierPaid(caps: caps),
                      const SizedBox(height: Space.l),
                    ],
                    // C2: "סיכום היום שלי" for an employee / cashier (no
                    // money:read — the server answers with their own count).
                    if (!caps.can(Cap.moneyView) && caps.can(Cap.docView)) ...[
                      DailySummaryHomeRow(
                        onTap: () =>
                            unawaited(openReport(context, dailySummaryKind)),
                      ),
                      const SizedBox(height: Space.m),
                    ],
                    if (caps.showIntentButtons ||
                        caps.can(Cap.docView) ||
                        caps.can(Cap.expenseCapture)) ...[
                      _IntentButtons(caps: caps),
                      SizedBox(height: context.isDark ? 12 : Space.section),
                    ],
                    // Tester 2026-11-18: search everything from Home, above
                    // "משימות קרובות" ("הצעת מחיר של כהן").
                    if (caps.can(Cap.docView)) ...[
                      const _HomeSearchField(),
                      const SizedBox(height: Space.l),
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
    final businessId = businessContext.business?.businessId;
    return [
      if (caps.can(Cap.customerManage) && businessId != null)
        CustomerCrmReminderPreview(
          businessId: businessId,
          onOpenAgenda: () =>
              unawaited(openCustomerCrmAgenda(context, businessId: businessId)),
          onOpenCustomer: (id) => unawaited(openPerson(context, id)),
        ),
      if (inboxVisible(caps) && data.cards.isNotEmpty) ..._todo(context, data),
      if (data.recent.isNotEmpty || data.recentEvents.isNotEmpty)
        ..._recent(context, data),
      if (inboxVisible(caps) && data.cards.isEmpty) ...[
        const SizedBox(height: Space.section),
        ..._todo(context, data),
      ],
    ];
  }

  Widget _moneyCard(BuildContext context, HomeData data) {
    final amount = data.openMinor ?? BigInt.zero;
    final overdue = data.overdueMinor ?? BigInt.zero;
    final late = overdue > BigInt.zero;
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
                    if (mounted) _reload();
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
    final available = data.recent.where(
      (document) => !_deletedRecentDrafts.contains(document.id),
    );
    final recent = query.isEmpty
        ? available.take(5).toList()
        : available
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
            for (final row in _mergedRecent(recent, data.recentEvents, query))
              if (row is RecentEvent)
                RecentEventRow(
                  event: row,
                  onTap: () => unawaited(
                    row.kind == RecentEvent.quoteAccepted
                        ? openQuote(context, row.id)
                        : openSignRequest(context, row.id),
                  ),
                )
              else if (row is DocumentSummary)
                docRowFor(
                  row,
                  today: _c.now?.call(),
                  onTap: () => unawaited(openDocument(context, row.id)),
                  onDelete: () => unawaited(_deleteRecentDraft(row)),
                ),
            if (!_recentSearchOpen)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('home-all-activity'),
                  onPressed: () =>
                      unawaited(openActivity(context, chip: 'all')),
                  child: const Text(InboxHe.allInvoicesAction),
                ),
              ),
          ],
        ),
      ),
    ];
  }
}

/// "מסמכים אחרונים" = recent documents + what customers did (quote accepted,
/// document signed — tester 2026-11-18), newest first, at most 5. Documents
/// without a creation time (older server / cache) keep their order after the
/// events. A local search filters the events by name / label too.
List<Object> _mergedRecent(
  List<DocumentSummary> docs,
  List<RecentEvent> events,
  String query,
) {
  final shown = query.isEmpty
      ? events
      : events.where(
          (e) => [
            e.customerName,
            e.label,
          ].whereType<String>().join(' ').toLowerCase().contains(query),
        );
  DateTime? timeOf(Object o) => o is RecentEvent
      ? o.at
      : DateTime.tryParse((o as DocumentSummary).createdAt ?? '');
  final all = <Object>[...shown, ...docs];
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
  indexed.sort((a, b) {
    final ta = timeOf(a.$2);
    final tb = timeOf(b.$2);
    if (ta != null && tb != null) return tb.compareTo(ta);
    return a.$1.compareTo(b.$1);
  });
  return [for (final (_, o) in indexed.take(5)) o];
}

/// Home bell with the unread badge (not in the navbar — its design is frozen).
class _Bell extends StatelessWidget {
  const _Bell();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: notificationsUnread,
    builder: (context, unread, _) => Semantics(
      button: true,
      label: NotificationsHe.bellA11y(unread),
      excludeSemantics: true,
      child: IconButton(
        key: const Key('home-bell'),
        tooltip: NotificationsHe.bellTooltip,
        style: IconButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
        onPressed: () => unawaited(openNotifications(context)),
        icon: Badge(
          key: const Key('home-bell-badge'),
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: Icon(
            unread > 0 ? Iconsax.notification_bing : Iconsax.notification,
            size: 26,
          ),
        ),
      ),
    ),
  );
}

/// Looks like a field; opens the search screen (keyboard up there).
class _HomeSearchField extends StatelessWidget {
  const _HomeSearchField();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: SearchHe.fieldHint,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: StadiumBorder(side: BorderSide(color: p.line)),
        child: InkWell(
          key: const Key('home-search'),
          customBorder: const StadiumBorder(),
          onTap: () => unawaited(openGlobalSearch(context)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Row(
                children: [
                  Icon(Iconsax.search_normal_1, color: p.muted, size: 20),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(
                      SearchHe.fieldHint,
                      style: AppText.body.copyWith(color: p.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
  const _Header({this.onOpenProfile, this.onEditAvatar, this.avatarBytes});

  final VoidCallback? onOpenProfile;
  final VoidCallback? onEditAvatar;
  final Uint8List? avatarBytes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final many = businessContext.hasManyBusinesses;
    final accountName = (session.account?.displayName ?? '')
        .replaceAll(
          RegExp(
            r'[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]',
          ),
          '',
        )
        .trim();
    final normalizedName = accountName.toLowerCase().replaceAll(
      RegExp(r'[\s.,:;!?\-]'),
      '',
    );
    final isPlaceholderName = const [
      'account',
      'חשבון',
      'משתמש',
      'user',
    ].any(normalizedName.startsWith);
    final hasAccountName = normalizedName.isNotEmpty && !isPlaceholderName;
    final firstName = hasAccountName
        ? accountName.split(RegExp(r'\s+')).first
        : '';
    final roleTag = presetTagLabels[businessContext.caps.preset];
    final initial = firstName.isEmpty
        ? 'ת'
        : String.fromCharCode(firstName.runes.first).toUpperCase();
    const avatarColors = [
      Color(0xFFD9C4F2),
      Color(0xFFBFE9DB),
      Color(0xFFF7E59C),
      Color(0xFFBFDDF0),
    ];
    final avatarColor =
        avatarColors[accountName.hashCode.abs() % avatarColors.length];
    final avatar = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: SizedBox(
        width: 58,
        height: 58,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(3.5),
              child: Material(
                color: avatarColor,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('home-profile-avatar'),
                  onTap: onOpenProfile,
                  customBorder: const CircleBorder(),
                  child: avatarBytes == null
                      ? Center(
                          child: Text(
                            initial,
                            style: AppText.title.copyWith(
                              color: const Color(0xFF302139),
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : Image.memory(
                          avatarBytes!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              initial,
                              style: AppText.title.copyWith(
                                color: const Color(0xFF302139),
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.isDark
                        ? Colors.white.withValues(alpha: .78)
                        : p.line,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: context.isDark ? .2 : .08,
                      ),
                      blurRadius: 9,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            if (onEditAvatar != null)
              Positioned(
                left: 0,
                bottom: 0,
                child: Material(
                  color: DesignTokens.lavender,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const Key('home-edit-avatar'),
                    onTap: onEditAvatar,
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(
                        Icons.edit_rounded,
                        size: 12,
                        color: Color(0xFF302139),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    final row = Row(
      children: [
        avatar,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName.isEmpty ? 'שלום' : 'שלום, $firstName',
                key: const Key('home-greeting-name'),
                style: AppText.headline.copyWith(fontSize: 19),
                overflow: TextOverflow.ellipsis,
              ),
              // 1.8: which business this is and in which role, always.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      businessContext.displayName,
                      key: const Key('home-business-name'),
                      style: AppText.secondary.copyWith(color: p.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (roleTag != null) ...[
                    const SizedBox(width: Space.s),
                    Container(
                      key: const Key('home-role-tag'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(Radii.card),
                        border: Border.all(color: p.line),
                      ),
                      child: Text(
                        roleTag,
                        style: AppText.secondary.copyWith(color: p.ink),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (many) Icon(Iconsax.arrow_down_1, color: p.muted),
      ],
    );
    if (!many) return Semantics(header: true, child: row);
    return Semantics(
      button: true,
      header: true,
      label: businessContext.displayName,
      hint: InboxHe.switchBusinessHint,
      child: InkWell(
        key: const Key('home-switch-business'),
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: () => unawaited(showSwitchBusinessSheet(context)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.min),
          child: ExcludeSemantics(child: row),
        ),
      ),
    );
  }
}

/// B1: the cashier's primary action — a receipt for money taken now, no
/// amounts dashboard. The line under it says up to where no approval is needed.
class _CashierPaid extends StatelessWidget {
  const _CashierPaid({required this.caps});

  final Caps caps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PrimaryButton(
        key: const Key('cashier-paid'),
        label: CommonHe.paid,
        icon: Iconsax.money_recive,
        offline: businessContext.offline,
        onPressed: () => unawaited(openCompose(context, intent: 'PAID')),
      ),
      const SizedBox(height: Space.s),
      Text(
        InboxHe.cashierPaidHint(
          formatMoney(
            caps.approvalPolicy.cashierCapMinor,
            trimZeroAgorot: true,
          ),
        ),
        key: const Key('cashier-paid-hint'),
        style: AppText.secondary,
        textAlign: TextAlign.center,
      ),
    ],
  );
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
          icon: const Icon(
            Iconsax.receipt_item,
            color: Color(0xFF302139),
            size: 27,
          ),
          color: DesignTokens.coral,
          onPressed: () => unawaited(openActivity(context)),
        ),
      if (caps.can(Cap.paymentIssue) && !caps.homeIsCashier)
        ActionOrb(
          key: const Key('intent-paid'),
          label: CommonHe.paid,
          icon: const DesignIcon('income'),
          color: DesignTokens.lavender,
          onPressed: () => unawaited(openCompose(context, intent: 'PAID')),
        ),
      if (caps.can(Cap.expenseCapture) || caps.can(Cap.expenseApprove))
        ActionOrb(
          key: const Key('intent-expenses'),
          label: InboxHe.expensesAction,
          icon: const DesignIcon('expense'),
          color: DesignTokens.yellow,
          onPressed: () => unawaited(
            caps.can(Cap.expenseApprove) && caps.can(Cap.moneyView)
                ? openExpenseOverview(context)
                // Capture-only roles (עובד) go straight to the camera, as
                // the removed S1 "הוצאה" tile did: the review queue only
                // offers capture when it is empty.
                : !caps.can(Cap.expenseApprove)
                ? openExpenseCapture(context)
                : openExpenses(context),
          ),
        ),
      if (caps.showIntentButtons)
        ActionOrb(
          key: const Key('intent-request'),
          label: CommonHe.requestPayment,
          icon: const DesignIcon('request'),
          color: DesignTokens.green,
          onPressed: () => unawaited(openPaymentRequest(context)),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final action in actions) Expanded(child: action)],
    );
  }
}
