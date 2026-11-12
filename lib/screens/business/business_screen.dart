// B · עסק (one template: rows → sub-page / S13) (SPEC-v2 §6.B, §13). Owner: squad E.
// Routes: /business (tab) and /business/:section (see BusinessSection in router.dart).
// Rows exist only with their capability (§4.4, F5): the owner sees at most 10.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/settings_api.dart'
    show fetchRemindersEnabled, saveRemindersEnabled;
import '../../router.dart';
import '../people/customer_crm_agenda_screen.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart' show AppText, Space, showErrorSnack;
import '../../ui/theme.dart';
import '../../ui/widgets/design_controls.dart' show ActionOrb;
import '../../ui/widgets/sheet.dart' show SheetTitle, showAppSheet;
import '../../util/composer_config.dart' show DocKind, configFor, moreKinds;
import '../../util/intent_resolver.dart' show intentQuote, typeIntent;
import '../../util/labels/labels.dart';
import 'account_page.dart';
import 'system_notice_settings.dart';
import '../../util/labels/system_notices_he.dart';
import 'branding_screen.dart';
import 'integrations_screen.dart';
import '../billing/billing_screen.dart';
import 'business_template.dart';
import 'sheets/s13_editor.dart';
import 'sheets/s14_switch.dart';
import 'shaam_page.dart';
import 'team_page.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../people/sheets/s2_customer.dart' show showCustomerSheet;

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
    _ => const _BusinessList(),
  };
}

/// The rows of B for [caps] (key, label, icon, action). Public for capability and navigation tests.
/// [reminders]: BE-19 switch state; null = the server has no reminders (row hidden).
List<BusinessRowSpec> businessRows(
  Caps caps, {
  required int memberCount,
  bool? reminders,
}) => [
  if (caps.can(Cap.reportView) && !caps.homeIsReports)
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

  void _open(BuildContext context, String key) {
    switch (key) {
      case 'integrations':
        openBusinessSection(context, BusinessSection.integrations);
      case 'subscription':
        showBillingPlans(context);
      case 'reports':
        openReports(context);
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
      case 'customers':
        openPeople();
      case 'branding':
        openBusinessSection(context, BusinessSection.branding);
      case 'approvals':
        showEditorSheet(context, instance: '13.6');
      case 'numbering':
        showEditorSheet(context, instance: '13.3');
      case 'desktop':
        showEditorSheet(context, instance: '13.9');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: businessContext,
    builder: (context, _) {
      final caps = businessContext.caps;
      final rows = businessRows(
        caps,
        memberCount: businessContext.me?.memberCount ?? 1,
        reminders: _reminders,
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
                // Only the switch toggles: tapping the label to read it must not
                // start e-mailing customers.
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
    final actions = <_ManagementAction>[
      _ManagementAction(
        id: 'customers',
        label: 'לקוחות',
        icon: Iconsax.profile_2user,
        orb: const Icon(
          Iconsax.profile_2user,
          color: Color(0xFF35556A),
          size: 28,
        ),
        color: const Color(0xFFC9E7F4),
        onTap: openPeople,
      ),
      if (currentBusinessId != null)
        _ManagementAction(
          id: 'crm-agenda',
          label: 'לוח מעקב',
          icon: Iconsax.calendar,
          orb: const Icon(Iconsax.calendar, color: Color(0xFF385D6E), size: 27),
          color: const Color(0xFFD6EDF5),
          onTap: () => unawaited(
            openCustomerCrmAgenda(
              context,
              businessId: currentBusinessId,
              onOpenCustomer: (id) => unawaited(openPerson(context, id)),
            ),
          ),
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
    Widget actionOrb(_ManagementAction action) => ActionOrb(
      key: Key('management-action-${action.id}'),
      label: action.label,
      icon: action.orb,
      color: action.color,
      labelSpacing: 5,
      onPressed: action.onTap,
    );

    final rows = <Widget>[];
    for (var start = 0; start < visible.length; start += 4) {
      final row = visible.skip(start).take(4).toList(growable: false);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final action in row) Expanded(child: actionOrb(action)),
            for (var empty = row.length; empty < 4; empty++)
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (start + 4 < visible.length) {
        rows.add(const SizedBox(height: Space.xs));
      }
    }

    return Column(
      key: const Key('management-quick-actions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('פעולות מהירות', style: AppText.title),
        const SizedBox(height: Space.s),
        ...rows,
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
