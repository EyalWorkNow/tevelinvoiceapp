// B · עסק (one template: rows → sub-page / S13) (SPEC-v2 §6.B, §13). Owner: squad E.
// Routes: /business (tab) and /business/:section (see BusinessSection in router.dart).
// Rows exist only with their capability (§4.4, F5): the owner sees at most 10;
// rarely used rows sit under one "עוד הגדרות" row (/business/more, PM 2026-11-12).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/settings_api.dart'
    show fetchRemindersEnabled, saveRemindersEnabled;
import '../../app_shell.dart' show AppTab;
import '../../router.dart';
import '../people/customer_crm_agenda_screen.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart' show AppText, Space, showErrorSnack;
import '../../ui/theme.dart';
import '../../ui/widgets/quick_action_grid.dart';
import '../../ui/widgets/sheet.dart' show SheetTitle, showAppSheet;
import '../../util/composer_config.dart'
    show DocKind, configFor, kindAllowedForCaps, moreKinds;
import '../../util/intent_resolver.dart' show intentQuote, typeIntent;
import '../../util/labels/labels.dart';
import 'account_page.dart';
import 'system_notice_settings.dart';
import '../../util/labels/system_notices_he.dart';
import 'branding_screen.dart';
import 'integrations_screen.dart';
import '../billing/billing_screen.dart';
import 'business_template.dart';
import 'collection_settings_screen.dart';
import 'sheets/s13_editor.dart';
import 'sheets/s14_switch.dart';
import 'shaam_page.dart';
import 'team_page.dart';
import '../audit/audit_log_screen.dart' show canViewAuditLog, openAuditLog;
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../people/sheets/s2_customer.dart' show showCustomerSheet;
import '../retainers/retainers_month_screen.dart';
import '../calendar/calendar_screen.dart';
import '../people/sheets/payment_terms_sheet.dart';
import '../../api/customer_timeline_api.dart' show fetchBusinessPaymentTerms;
import '../../util/labels/timeline_he.dart';
import 'employees_screen.dart';
import 'vault_screen.dart';
import 'notification_preferences_screen.dart';
import '../../api/accountant_api.dart' show leaveClient;
import '../../state/accountant_store.dart';
import '../auth/auth_flow.dart' show routeSignedIn;

/// טופס 101 is built but not released yet (see the row below).
const form101Released = bool.fromEnvironment('FORM101');

class BusinessScreen extends StatelessWidget {
  const BusinessScreen({super.key, this.section});

  /// Null = the business list (tab "עסק"); else a sub-page slug.
  final String? section;

  @override
  Widget build(BuildContext context) => switch (section) {
    'team' => const TeamPage(),
    'integrations' => const IntegrationsScreen(),
    'account' => const AccountPage(),
    'notifications' => const SystemNoticeSettings(),
    'shaam' => const ShaamPage(),
    'profile' => const EditorPage(instance: '13.1', title: BusinessHe.profile),
    'branding' => const BrandingScreen(),
    'approvals' => const EditorPage(
      instance: '13.6',
      title: BusinessHe.approvals,
    ),
    'desktop' => const EditorPage(instance: '13.9', title: BusinessHe.desktop),
    'numbering' => const EditorPage(
      instance: '13.3',
      title: BusinessHe.numbering,
    ),
    'more' => const _MoreSettingsPage(),
    'vault' => const VaultScreen(),
    'employees' => const EmployeesScreen(),
    'alerts' => const NotificationPreferencesScreen(),
    _ => const _BusinessList(),
  };
}

/// Rarely used rows grouped under "עוד הגדרות" (SPEC §6.B: B ≤ 10 rows).
const Set<String> moreSettingsKeys = {
  // 0110: the business-default payment terms.
  'paymentTerms',
  'integrations',
  'subscription',
  'notifications',
  'desktop',
  // C5: the activity log (owner, partner, accountants).
  'audit',
  // 0134 "עובדים וטופס 101" (B stays ≤ 10 rows; the pushes open it directly).
  'employees',
};

/// The "עוד הגדרות" row of B.
const BusinessRowSpec moreSettingsRow = BusinessRowSpec(
  'more',
  BusinessHe.moreSettings,
  Iconsax.setting_2,
);

/// The rows of B for [caps] (key, label, icon). Public for capability and
/// navigation tests. When two or more [moreSettingsKeys] rows exist they are
/// replaced by one [moreSettingsRow] (their page: [moreSettingsRows]).
/// [reminders]: BE-19 switch state; null = the server has no reminders (row hidden).
/// [exempt]: עוסק פטור / עמותה; alone, "צוות והרשאות" moves to "עוד הגדרות"
/// (persona 01: a one-person business has no team; the accountant invite
/// stays one row away).
List<BusinessRowSpec> businessRows(
  Caps caps, {
  required int memberCount,
  bool? reminders,
  bool exempt = false,
}) {
  final all = allBusinessRows(
    caps,
    memberCount: memberCount,
    reminders: reminders,
  );
  final keys = _moreKeys(memberCount: memberCount, exempt: exempt);
  final more = moreSettingsRows(
    caps,
    memberCount: memberCount,
    reminders: reminders,
    exempt: exempt,
  );
  if (more.isEmpty) return all;
  return [
    for (final r in all)
      if (!keys.contains(r.key)) r,
    moreSettingsRow,
  ];
}

Set<String> _moreKeys({required int memberCount, required bool exempt}) => {
  ...moreSettingsKeys,
  if (exempt && memberCount <= 1) 'team',
};

/// The rows of the "עוד הגדרות" page; empty when fewer than two exist (a
/// single one stays in B itself).
List<BusinessRowSpec> moreSettingsRows(
  Caps caps, {
  required int memberCount,
  bool? reminders,
  bool exempt = false,
}) {
  final keys = _moreKeys(memberCount: memberCount, exempt: exempt);
  final more = [
    for (final r in allBusinessRows(
      caps,
      memberCount: memberCount,
      reminders: reminders,
    ))
      if (keys.contains(r.key)) r,
  ];
  return more.length < 2 ? const [] : more;
}

/// Every destination of B for [caps], before grouping (§4.4).
List<BusinessRowSpec> allBusinessRows(
  Caps caps, {
  required int memberCount,
  bool? reminders,
}) => [
  // Accountants: R is their home tab; the row takes them there (QA
  // 2026-11-16 accountant/09: "no דוחות in ניהול" read as "no reports").
  if (caps.can(Cap.reportView))
    const BusinessRowSpec('reports', BusinessHe.reports, Iconsax.chart_2),
  if (caps.can(Cap.expenseCapture) || caps.can(Cap.expenseApprove))
    const BusinessRowSpec(
      'expenses',
      BusinessHe.expenses,
      Iconsax.receipt_item,
    ),
  if (caps.can(Cap.teamManage))
    const BusinessRowSpec('team', BusinessHe.team, Iconsax.profile_2user),
  if (caps.can(Cap.settingsBusiness))
    const BusinessRowSpec('profile', BusinessHe.profile, Iconsax.shop),
  // 0119 (tester 2026-11-18): עוסק מורשה, ניהול ספרים, ניכוי במקור …
  if (caps.can(Cap.vaultView))
    const BusinessRowSpec('vault', VaultHe.title, Iconsax.folder_open),
  // 0134 (spec §10): salaried employees + their טופס 101 (owner + accountants).
  // Hidden until the Tax Authority system approval + accountant check (owner 2026-11-26);
  // build with --dart-define=FORM101=true to show it.
  if (form101Released && caps.can(Cap.employeeForms))
    const BusinessRowSpec('employees', Form101He.row, Iconsax.people),
  if (caps.can(Cap.settingsDesign))
    const BusinessRowSpec('branding', BusinessHe.branding, Iconsax.colorfilter),
  // §13.6: only when the business has another member.
  if (caps.can(Cap.settingsBusiness) && memberCount > 1)
    const BusinessRowSpec(
      'approvals',
      BusinessHe.approvals,
      Iconsax.task_square,
    ),
  if (caps.can(Cap.settingsBusiness) && reminders != null)
    const BusinessRowSpec(
      'reminders',
      BusinessHe.reminders,
      Iconsax.notification_bing,
    ),
  if (caps.can(Cap.settingsBusiness))
    const BusinessRowSpec(
      'paymentTerms',
      TimelineHe.businessTermsTitle,
      Iconsax.calendar_2,
    ),
  if (caps.can(Cap.settingsBusiness) || caps.can(Cap.reportView))
    const BusinessRowSpec('shaam', BusinessHe.shaam, Iconsax.verify),
  if (caps.can(Cap.settingsNumbering))
    const BusinessRowSpec('numbering', BusinessHe.numbering, Iconsax.hashtag),
  if (caps.can(Cap.settingsBusiness))
    const BusinessRowSpec('integrations', 'חיבורים ושליחה', Iconsax.link),
  if (caps.can(Cap.owner))
    const BusinessRowSpec('subscription', 'המסלול של העסק', Iconsax.crown),
  const BusinessRowSpec(
    'notifications',
    SystemNoticesHe.title,
    Iconsax.notification,
  ),
  const BusinessRowSpec('account', BusinessHe.account, Iconsax.user),
  if (caps.can(Cap.settingsBusiness) || caps.can(Cap.reportView))
    const BusinessRowSpec('desktop', BusinessHe.desktop, Iconsax.monitor),
  if (canViewAuditLog(caps))
    const BusinessRowSpec('audit', AuditHe.row, Iconsax.note_2),
];

class BusinessRowSpec {
  const BusinessRowSpec(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

class _BusinessList extends StatefulWidget {
  const _BusinessList();

  @override
  State<_BusinessList> createState() => _BusinessListState();
}

class _BusinessListState extends State<_BusinessList> {
  bool? _reminders;
  String? _remindersFor;

  @override
  void initState() {
    super.initState();
    businessContext.addListener(_maybeLoad);
    _maybeLoad();
  }

  @override
  void dispose() {
    businessContext.removeListener(_maybeLoad);
    super.dispose();
  }

  /// BE-19 state, once per business.
  void _maybeLoad() {
    final id = session.business?.businessId;
    if (id == null ||
        id == _remindersFor ||
        !businessContext.can(Cap.settingsBusiness)) {
      return;
    }
    _remindersFor = id;
    _reminders = null;
    unawaited(() async {
      try {
        final on = await fetchRemindersEnabled();
        if (mounted && _remindersFor == id) setState(() => _reminders = on);
      } on Object {
        // Offline: the row comes back on the next visit.
        _remindersFor = null;
      }
    }());
  }

  /// Turning reminders on e-mails customers: say what will be sent first.
  Future<bool> _confirmRemindersOn() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(BusinessHe.remindersConfirmTitle),
        content: const Text(BusinessHe.remindersConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('reminders-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(BusinessHe.remindersConfirmAction),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Feature 7 "הפסקת ליווי": confirm, POST leave, reload the businesses and
  /// route on (another client, the picker, or the empty clients screen).
  Future<void> _leave() async {
    final b = session.business;
    if (b == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('leave-confirm'),
        title: Text(AccountantHe.leaveTitle(b.legalName)),
        content: const Text(AccountantHe.leaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AccountantHe.leaveCancel),
          ),
          TextButton(
            key: const Key('leave-yes'),
            style: TextButton.styleFrom(
              foregroundColor: dialogContext.palette.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AccountantHe.leaveConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await leaveClient(b.businessId);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
      return;
    }
    messengerKey.currentState?.showNotchNotice(
      const SnackBar(content: Text(AccountantHe.left)),
      motion: NoticeMotion.sent,
    );
    try {
      await session.refreshAccount();
      final next = session.business;
      if (next != null && next.businessId != b.businessId) {
        await session.selectBusiness(next);
      } else if (next == null) {
        session
          ..me = null
          ..profile = null;
      }
    } on Object {
      // Offline: the next start reloads the businesses.
    }
    unawaited(accountantStore.load());
    final nav = navigatorKey.currentContext;
    if (nav != null && nav.mounted) await routeSignedIn(nav);
  }

  /// The ladder settings; the switch above reflects what was saved there.
  Future<void> _openCollectionSettings() async {
    await openCollectionSettings(context);
    if (!mounted) return;
    try {
      final on = await fetchRemindersEnabled();
      if (mounted) setState(() => _reminders = on);
    } on Object {
      // Keep the last known state.
    }
  }

  Future<void> _setReminders(bool on) async {
    if (on && !await _confirmRemindersOn()) return;
    if (!mounted) return;
    final before = _reminders;
    setState(() => _reminders = on);
    try {
      await saveRemindersEnabled(on);
      if (mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          SnackBar(
            content: Text(
              on ? BusinessHe.remindersOn : BusinessHe.remindersOff,
            ),
          ),
          motion: NoticeMotion.reminder,
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _reminders = before);
      showErrorSnack(context, e);
    }
  }

  void _open(BuildContext context, String key) => openBusinessRow(context, key);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: businessContext,
    builder: (context, _) {
      final caps = businessContext.caps;
      final rows = businessRows(
        caps,
        memberCount: businessContext.me?.memberCount ?? 1,
        reminders: _reminders,
        exempt: businessContext.isVatExempt,
      );
      final many = businessContext.hasManyBusinesses;
      return BusinessPage(
        title: 'ניהול',
        showAppBar: false,
        // One business: a plain title, not a row that looks tappable.
        header: many
            ? BusinessRow(
                key: const Key('business-name'),
                label: businessContext.displayName,
                icon: Iconsax.shop,
                onTap: () => showSwitchBusinessSheet(context),
                trailing: TextButton(
                  onPressed: () => showSwitchBusinessSheet(context),
                  child: const Text(BusinessHe.switchBusiness),
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Semantics(
                  label: businessContext.displayName,
                  child: Row(
                    children: [
                      Icon(
                        Iconsax.shop,
                        size: 17,
                        color: context.palette.muted,
                      ),
                      const SizedBox(width: Space.s),
                      Flexible(
                        child: Text(
                          businessContext.displayName,
                          key: const Key('business-name'),
                          style: AppText.secondary.copyWith(
                            color: context.palette.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        children: [
          _quickActions(context, caps),
          const RowGroupGap(),
          for (final r in rows)
            if (r.key == 'reminders')
              BusinessRow(
                key: const Key('brow-reminders'),
                label: r.label,
                value: BusinessHe.remindersHint,
                icon: r.icon,
                // Only the switch toggles: tapping the label opens the ladder
                // (0111: days, wording, channels) — it never starts e-mailing.
                onTap: () => unawaited(_openCollectionSettings()),
                trailing: Switch.adaptive(
                  key: const Key('reminders-switch'),
                  value: _reminders ?? false,
                  onChanged: session.offline ? null : _setReminders,
                ),
              )
            else
              BusinessRow(
                key: Key('brow-${r.key}'),
                label: r.label,
                icon: r.icon,
                onTap: () => _open(context, r.key),
              ),
          // Feature 7: an accountant leaves this client (never the owner).
          if (caps.homeIsReports && session.business != null) ...[
            const RowGroupGap(),
            BusinessRow(
              key: const Key('brow-leave'),
              label: AccountantHe.leave,
              icon: Iconsax.logout_1,
              destructive: true,
              onTap: session.offline ? null : () => unawaited(_leave()),
            ),
          ],
        ],
      );
    },
  );

  Widget _quickActions(BuildContext context, Caps caps) {
    final businessType = businessContext.businessType;
    final currentBusinessId = businessContext.business?.businessId;
    final section46 =
        (businessContext.profile?.section46ApprovalNumber ?? '').isNotEmpty;
    // Actions only: everything that is a settings row below (reports, team,
    // branding, business details, numbering, …) lives there once (07·U9).
    // Customers are a tab of their own (§5, PM 2026-11-12), not an action here.
    final actions = <_ManagementAction>[
      // Owner 2026-11-17: "בקשת תשלום" (a 300) first, for every business type.
      if (kindAllowedForCaps(DocKind.transactionInvoice, caps))
        _ManagementAction(
          id: 'payment-request',
          label: ComposeHe.requestChoice,
          icon: Iconsax.money_send,
          orb: const Icon(
            Iconsax.money_send,
            color: Color(0xFF2F5B47),
            size: 28,
          ),
          color: const Color(0xFFCFF5DE),
          onTap: () => unawaited(openPaymentRequest(context)),
        ),
      if (currentBusinessId != null)
        _ManagementAction(
          id: 'crm-agenda',
          label: 'לוח מעקב',
          icon: Iconsax.calendar,
          orb: const Icon(Iconsax.calendar, color: Color(0xFF385D6E), size: 27),
          color: const Color(0xFFD6EDF5),
          onTap: () => unawaited(
            openCustomerCrmAgenda(context, businessId: currentBusinessId),
          ),
        ),
      // 0106 "יומן": bookings from the public link + the phone's busy times.
      if (mayUseCalendar(caps))
        _ManagementAction(
          id: 'calendar',
          label: CalendarHe.title,
          icon: Iconsax.calendar_2,
          orb: const Icon(
            Iconsax.calendar_2,
            color: Color(0xFF2F5B47),
            size: 27,
          ),
          color: const Color(0xFFCFF5DE),
          onTap: () => unawaited(openCalendar(context)),
        ),
      // C4 "חבילת ריטיינר": the month's recurring drafts, reviewed and issued at once.
      if (mayUseRetainers(caps))
        _ManagementAction(
          id: 'retainers',
          label: RetainerHe.monthTitle,
          icon: Iconsax.calendar_tick,
          orb: const Icon(
            Iconsax.calendar_tick,
            color: Color(0xFF3E6250),
            size: 27,
          ),
          color: const Color(0xFFD8EFE2),
          onTap: () => unawaited(openRetainersMonth(context)),
        ),
      if (caps.can(Cap.docDraft)) ...[
        _ManagementAction(
          id: 'quote',
          label: 'הצעת מחיר',
          icon: Iconsax.receipt_edit,
          orb: Icon(
            Iconsax.receipt_edit,
            color: const Color(0xFF58623B),
            size: 28,
          ),
          color: const Color(0xFFF3E9A9),
          onTap: () => unawaited(openCompose(context, intent: intentQuote)),
        ),
        _ManagementAction(
          id: 'customer-new',
          label: 'לקוח חדש',
          icon: Iconsax.user_add,
          orb: Icon(Iconsax.user_add, color: const Color(0xFF624D73), size: 28),
          color: const Color(0xFFE6D4F4),
          onTap: () => _openNewCustomer(context),
        ),
      ],
      for (final kind in moreKinds(
        businessType,
        caps,
        section46: section46,
        supplierPicker: true,
      ))
        // עוסק פטור / עמותה: orders are a business-to-business flow, kept
        // out of the quick actions (persona 01); still open by link.
        if (!(businessContext.isVatExempt && _ordersOnly.contains(kind)))
          _ManagementAction(
            id: 'type-${configFor(kind).code}',
            label: _docKindLabel(kind),
            icon: Iconsax.document_text,
            orb: Icon(
              Iconsax.document_text,
              color: const Color(0xFF614A68),
              size: 28,
            ),
            color: const Color(0xFFE8D9EF),
            onTap: () =>
                unawaited(openCompose(context, intent: typeIntent(kind))),
          ),
    ];

    return _ManagementQuickActions(
      actions: actions,
      onMore: (hidden) => _showMoreActions(context, hidden),
    );
  }

  Future<void> _openNewCustomer(BuildContext context) async {
    await showCustomerSheet(context, startOnNew: true);
  }

  Future<void> _showMoreActions(
    BuildContext context,
    List<_ManagementAction> actions,
  ) async {
    final selected = await showAppSheet<_ManagementAction>(
      context,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(
            'פעולות נוספות',
            subtitle: 'סוגי מסמכים ופעולות נוספים לעסק',
          ),
          for (final action in actions)
            ListTile(
              key: Key('management-more-${action.id}'),
              leading: Icon(action.icon, color: context.palette.ink),
              title: Text(action.label, style: AppText.body),
              trailing: Icon(
                Iconsax.arrow_left_2,
                color: context.palette.muted,
              ),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
        ],
      ),
    );
    if (!context.mounted || selected == null) return;
    selected.onTap();
  }
}

const Set<DocKind> _ordersOnly = {DocKind.purchaseOrder, DocKind.salesOrder};

String _docKindLabel(DocKind kind) => switch (kind) {
  DocKind.taxInvoiceReceipt => 'חשבונית מס-קבלה',
  DocKind.taxInvoice => 'חשבונית מס',
  DocKind.transactionInvoice => 'חשבון עסקה / פרופורמה',
  DocKind.receipt => 'קבלה',
  DocKind.donationReceipt => 'קבלה על תרומה',
  DocKind.credit => 'זיכוי',
  DocKind.quote => 'הצעת מחיר',
  DocKind.salesOrder => 'הזמנה',
  DocKind.purchaseOrder => 'הזמנת רכש',
};

class _ManagementAction {
  const _ManagementAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.orb,
    required this.color,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final Widget orb;
  final Color color;
  final VoidCallback onTap;
}

class _ManagementQuickActions extends StatelessWidget {
  const _ManagementQuickActions({required this.actions, required this.onMore});

  final List<_ManagementAction> actions;
  final ValueChanged<List<_ManagementAction>> onMore;

  @override
  Widget build(BuildContext context) {
    final hasMore = actions.length > 8;
    final visible = hasMore
        ? actions.take(7).toList()
        : actions.take(8).toList();
    if (hasMore) {
      visible.add(
        _ManagementAction(
          id: 'more',
          label: 'פעולות נוספות',
          icon: Iconsax.more,
          orb: const Icon(Iconsax.more, color: Color(0xFF624D73), size: 28),
          color: const Color(0xFFE6D4F4),
          onTap: () => onMore(actions.skip(7).toList()),
        ),
      );
    }
    return Column(
      key: const Key('management-quick-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('פעולות מהירות', style: AppText.title),
        const SizedBox(height: Space.s),
        QuickActionGrid(
          keyPrefix: 'management-action',
          actions: [
            for (final a in visible)
              QuickAction(
                id: a.id,
                label: a.label,
                icon: a.icon,
                ink: Colors.transparent,
                orb: a.orb,
                color: a.color,
                onTap: a.onTap,
              ),
          ],
        ),
      ],
    );
  }
}

/// A settings instance as a full page (/business/profile, …) — same form as S13.
class EditorPage extends StatelessWidget {
  const EditorPage({
    super.key,
    required this.instance,
    required this.title,
    this.header,
    this.showTitle = true,
  });

  final String instance;
  final String title;
  final Widget? header;
  final bool showTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showTitle ? AppBar(title: Text(title)) : null,
    body: SafeArea(
      child: Column(
        children: [
          if (header != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                Space.page,
                showTitle ? Space.s : Space.l,
                Space.page,
                Space.m,
              ),
              child: header!,
            ),
          ],
          Expanded(child: EditorLoader(instance: instance)),
        ],
      ),
    ),
  );
}

/// Opens the destination of the B row [key] (the B list and "עוד הגדרות").
void openBusinessRow(BuildContext context, String key) {
  switch (key) {
    case 'integrations':
      openBusinessSection(context, BusinessSection.integrations);
    case 'subscription':
      showBillingPlans(context);
    case 'reports':
      if (businessContext.caps.homeIsReports) {
        Navigator.of(context).popUntil((r) => r.isFirst);
        selectTab(AppTab.home);
      } else {
        openReports(context);
      }
    case 'expenses':
      if (businessContext.can(Cap.expenseApprove) &&
          businessContext.can(Cap.moneyView)) {
        openExpenseOverview(context);
      } else {
        openExpenses(context);
      }
    case 'team':
      openBusinessSection(context, BusinessSection.team);
    case 'shaam':
      openBusinessSection(context, BusinessSection.shaam);
    case 'notifications':
      openBusinessSection(context, BusinessSection.notifications);
    case 'account':
      openBusinessSection(context, BusinessSection.account);
    case 'profile':
      showEditorSheet(context, instance: '13.1');
    case 'more':
      openBusinessSection(context, BusinessSection.more);
    case 'vault':
      openBusinessSection(context, BusinessSection.vault);
    case 'employees':
      openBusinessSection(context, BusinessSection.employees);
    case 'branding':
      openBusinessSection(context, BusinessSection.branding);
    case 'approvals':
      showEditorSheet(context, instance: '13.6');
    case 'numbering':
      showEditorSheet(context, instance: '13.3');
    case 'desktop':
      showEditorSheet(context, instance: '13.9');
    case 'audit':
      unawaited(openAuditLog(context));
    case 'paymentTerms':
      unawaited(_openBusinessTerms(context));
  }
}

/// 0110: the default terms for customers without their own.
Future<void> _openBusinessTerms(BuildContext context) async {
  try {
    final current = await fetchBusinessPaymentTerms();
    if (!context.mounted) return;
    final saved = await showPaymentTermsSheet(context, initial: current);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showNotchNotice(const SnackBar(content: Text(TimelineHe.termsSaved)));
    }
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// "עוד הגדרות" (/business/more): the rarely used rows of B, same template.
class _MoreSettingsPage extends StatelessWidget {
  const _MoreSettingsPage();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: businessContext,
    builder: (context, _) => BusinessPage(
      title: BusinessHe.moreSettings,
      children: [
        for (final r in moreSettingsRows(
          businessContext.caps,
          memberCount: businessContext.me?.memberCount ?? 1,
          exempt: businessContext.isVatExempt,
        ))
          BusinessRow(
            key: Key('brow-${r.key}'),
            label: r.label,
            icon: r.icon,
            onTap: () => openBusinessRow(context, r.key),
          ),
      ],
    ),
  );
}
