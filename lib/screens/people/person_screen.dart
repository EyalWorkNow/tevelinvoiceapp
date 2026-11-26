// P2 · כרטיס לקוח / ספק (owner spec 2026-11-23, "כרטיס לקוח v2").
// Route: /person/:id   (?kind=supplier for a supplier card).
//
// Top → bottom:
//  1. Header: name; under it the CRM stage (tap → stage menu) + "ספק" /
//     "בארכיון". ⋯: פרטים ועריכה · שליחת כרטסת · ארכוב (red, last). The CRM
//     sync line only when sync has a problem.
//  2. Status card: "חייב לך ₪X" + the oldest open / late document (money.view),
//     or "אין יתרה פתוחה" + the last document's age; under a divider ONE next
//     thing: a late follow-up, else the nearest meeting / visit.
//  3. "פעולות מהירות": 2 × 4 pastel orbs by priority (person_logic.dart); the
//     8th is "עוד" (the rest, fixed order, "ארכוב" last).
//  4. Short lists (3 rows + "הכל"): מסמכים · ביקורים ופגישות (CRM jobs +
//     calendar bookings) · פתקים ותזכורות; folded: כסף ורווחיות · פרטי הלקוח
//     (the only place to edit payment terms).
// No fixed bottom bar: every action is an orb, a "עוד" item or a list row.
// Supplier: חיוג · וואטסאפ · הוצאה חדשה · אימייל · עוד (פרטים ועריכה, ארכוב).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_timeline_api.dart' show PaymentTermsValue;
import '../../api/customers_api.dart';
import '../../api/models/models.dart';
import '../../api/suppliers_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/customer_crm_store.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../ui/widgets/quick_action_grid.dart';
import '../../util/allowed_urls.dart';
import '../../util/intent_resolver.dart' show intentQuote, invoiceIntentFor;
import '../../util/labels/common_he.dart';
import '../../util/labels/compose_he.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/document_he.dart';
import '../../util/labels/people_he.dart';
import '../../util/labels/person_page_he.dart';
import '../../util/labels/portal_he.dart';
import '../../util/labels/status_he.dart';
import '../../util/labels/timeline_he.dart';
import '../../util/payment_terms.dart' show paymentTermsLabel;
import '../../util/phone.dart';
import '../../util/status_map.dart';
import '../calendar/calendar_api.dart';
import '../calendar/calendar_screen.dart' show mayUseCalendar;
import '../calendar/customer_booking_sheet.dart';
import '../compose/compose_repeat.dart' show lastRepeatable, openRepeat;
import '../debts/debt_entry_sheet.dart';
import '../document/sheets/s6_share.dart' show pdfSharer;
import '../expense/expense_capture_screen.dart' show nextCaptureSupplier;
import 'customer_crm_finance_card.dart';
import 'customer_crm_panel.dart' show displayStage;
import 'customer_crm_sync_status.dart';
import 'customer_timeline_screen.dart';
import 'person_crm_ops.dart';
import 'person_logic.dart';
import 'person_sections.dart';
import 'person_visits_page.dart';
import 'sheets/payment_terms_sheet.dart';
import 'sheets/portal_link_sheet.dart';
import 'sheets/s2_customer.dart';

/// Orb colours: (circle, icon) — the ניהול pastel set.
const _orbColors = <String, (Color, Color)>{
  'call': (Color(0xFFD6EDF5), Color(0xFF385D6E)),
  'whatsapp': (Color(0xFFD8EFE2), Color(0xFF3E6250)),
  'add-phone': (Color(0xFFD6EDF5), Color(0xFF385D6E)),
  'email': (Color(0xFFE8D9EF), Color(0xFF614A68)),
  'payment-request': (Color(0xFFCFF5DE), Color(0xFF2F5B47)),
  'invoice': (Color(0xFFE8D9EF), Color(0xFF614A68)),
  'book': (Color(0xFFD6EDF5), Color(0xFF385D6E)),
  'paid': (Color(0xFFFFE1D2), Color(0xFF7A4630)),
  'quote': (Color(0xFFF3E9A9), Color(0xFF58623B)),
  'reminder': (Color(0xFFF8D7E3), Color(0xFF7A3E55)),
  'expense': (Color(0xFFF3E9A9), Color(0xFF58623B)),
  'more': (Color(0xFFE6D4F4), Color(0xFF624D73)),
};

const _icons = <String, IconData>{
  'call': Iconsax.call,
  'whatsapp': Iconsax.message,
  'add-phone': Iconsax.user_edit,
  'email': Iconsax.sms,
  'payment-request': Iconsax.money_send,
  'invoice': Iconsax.receipt_add,
  'book': Iconsax.calendar_add,
  'paid': Iconsax.money_recive,
  'quote': Iconsax.receipt_edit,
  'reminder': Iconsax.notification,
  'expense': Iconsax.receipt_add,
  'more': Iconsax.more,
  'repeat': Iconsax.repeat,
  'debt': Iconsax.note_add,
  'job': Iconsax.briefcase,
  'note': Iconsax.note_text,
  'navigate': Iconsax.location,
  'statement': Iconsax.receipt_item,
  'portal': Iconsax.user_square,
  'edit': Iconsax.edit,
  'terms': Iconsax.calendar_2,
  'archive': Iconsax.archive_1,
};

String _label(String id) => switch (id) {
  'call' => PersonPageHe.call,
  'whatsapp' => PersonPageHe.whatsapp,
  'add-phone' => PersonPageHe.addPhone,
  'email' => PersonPageHe.email,
  'payment-request' => PersonPageHe.requestPayment,
  'invoice' => PersonPageHe.invoice,
  'book' => PersonPageHe.book,
  'paid' => PersonPageHe.paid,
  'quote' => PersonPageHe.quote,
  'reminder' => PersonPageHe.reminder,
  'expense' => PersonPageHe.newExpense,
  'more' => PersonPageHe.more,
  'repeat' => PersonPageHe.repeatLast,
  'debt' => PersonPageHe.debt,
  'job' => PersonPageHe.newJob,
  'note' => PersonPageHe.note,
  'navigate' => PersonPageHe.navigate,
  'statement' => PersonPageHe.statement,
  'portal' => PortalHe.sendLink,
  'edit' => PersonPageHe.details,
  'terms' => PersonPageHe.terms,
  'archive' => PersonPageHe.archive,
  _ => id,
};

class PersonScreen extends StatefulWidget {
  const PersonScreen({super.key, required this.id, this.isSupplier = false});

  final String id;
  final bool isSupplier;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  CustomerDetail? _detail;
  Supplier? _supplier;
  bool _be16 = false;
  bool _statement = false;
  List<DocumentSummary>? _docs;
  BigInt? _open;
  List<Booking> _bookings = const [];
  Object? _error;
  bool _busy = false;
  bool _notesAll = false;
  final CustomerCrmStore _store = CustomerCrmStore.instance;

  Caps get _caps => businessContext.caps;
  String? get _businessId => businessContext.business?.businessId;

  @override
  void initState() {
    super.initState();
    _load();
    final businessId = _businessId;
    if (!widget.isSupplier && businessId != null) {
      loadCrmAfterBuild(this, _store, () => businessId);
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      if (widget.isSupplier) {
        final card = await fetchSupplierCard(widget.id);
        if (mounted) {
          setState(() {
            _supplier = card.supplier;
            _be16 = card.be16;
          });
        }
        return;
      }
      final detail = await fetchCustomerDetail(widget.id);
      if (!mounted) return;
      setState(() => _detail = detail);
      final docsF = _caps.can(Cap.docView)
          ? fetchCustomerDocuments(widget.id)
          : Future.value(const <DocumentSummary>[]);
      final openF = !_caps.can(Cap.moneyView)
          ? Future<BigInt?>.value(null)
          : detail.openMinor != null
          ? Future<BigInt?>.value(detail.openMinor)
          : fetchCustomerOpenMinor(widget.id);
      if (_statementCap) {
        // Never holds the card up: the item appears when the probe answers.
        statementAvailable(widget.id).then((v) {
          if (mounted && v != _statement) setState(() => _statement = v);
        }, onError: (Object _) {});
      }
      unawaited(_loadBookings());
      // Both futures are awaited together, so a failure in one never leaves
      // the other as an unhandled async error.
      final (docs, open) = await (docsF, openF).wait;
      if (mounted) {
        setState(() {
          _docs = docs;
          _open = open;
        });
      }
    } on ParallelWaitError<
      (List<DocumentSummary>?, BigInt?),
      (AsyncError?, AsyncError?)
    > catch (e) {
      final cause = e.errors.$1?.error ?? e.errors.$2?.error ?? e;
      if (mounted) setState(() => _error = cause);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The customer's meetings (owner / partner): a month back, two ahead.
  Future<void> _loadBookings() async {
    if (widget.isSupplier || !mayUseCalendar(_caps)) return;
    final now = DateTime.now();
    try {
      final a = await fetchCalendarAgenda(
        now.subtract(const Duration(days: 30)),
        now.add(const Duration(days: 62)),
      );
      if (!mounted) return;
      setState(
        () => _bookings = [
          for (final b in a.bookings)
            if (b.customerId == widget.id) b,
        ],
      );
    } on Object {
      // A hint, not the page: no meetings shown.
    }
  }

  String get _name => _supplier?.name ?? _detail?.customer.name ?? '';
  String? get _phone => _supplier?.phone ?? _detail?.customer.phone;
  String? get _email => _supplier?.email ?? _detail?.customer.email;
  String? get _address {
    final a = _detail?.address;
    if (a == null || a.isEmpty) return null;
    return a.display;
  }

  bool get _archived =>
      _supplier?.isArchived ?? _detail?.customer.isArchived ?? false;

  bool get _manage =>
      !_archived &&
      (widget.isSupplier
          ? _be16 && _caps.can(Cap.supplierManage)
          : _caps.can(Cap.customerManage));

  bool get _crmLoaded {
    final b = _businessId;
    return !widget.isSupplier &&
        b != null &&
        _store.isLoadedFor(b) &&
        !_store.hasLoadErrorFor(b);
  }

  PersonCrmOps? get _ops {
    final b = _businessId;
    if (b == null || widget.isSupplier) return null;
    return PersonCrmOps(
      businessId: b,
      customerId: widget.id,
      customerName: _name,
    );
  }

  bool get _owes => (_open ?? BigInt.zero) > BigInt.zero;

  Future<void> _launch(Uri uri) async {
    HapticFeedback.selectionClick();
    await launchAllowed(uri);
  }

  Future<void> _edit() async {
    if (widget.isSupplier) {
      final s = _supplier;
      if (s == null) return;
      final saved = await showSupplierSheet(context, edit: s);
      if (saved != null && mounted) _load();
      return;
    }
    final d = _detail;
    if (d == null) return;
    final saved = await showCustomerSheet(context, edit: d.customer, detail: d);
    if (saved != null && mounted) _load();
  }

  /// 0110 "תנאי תשלום": the customer's own terms (managers edit them).
  Future<void> _editTerms() async {
    final d = _detail;
    if (d == null) return;
    final saved = await showPaymentTermsSheet(
      context,
      customerId: widget.id,
      initial: PaymentTermsValue(
        code: d.paymentTerms,
        days: d.paymentTermsDays,
        method: d.preferredPaymentMethod,
      ),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showNotchNotice(const SnackBar(content: Text(TimelineHe.termsSaved)));
    unawaited(_load());
  }

  /// "שוטף+30 · העברה" — the customer's, else the business default (marked).
  String _termsLine(CustomerDetail d) {
    final line = termsSummary(
      paymentTermsLabel(d.effectiveTerms, days: d.effectiveTermsDays),
      d.effectiveMethod,
    );
    if (line == null) return TimelineHe.termsNone;
    return d.effectiveSource == 'BUSINESS'
        ? '$line (${TimelineHe.termsFromBusiness})'
        : line;
  }

  /// §4.4: statement for managers and the accountant (P2).
  bool get _statementCap =>
      _caps.can(Cap.customerManage) || _caps.can(Cap.reportView);

  /// "שליחת כרטסת" (J11). E-mail when the customer has one and the member may
  /// send to customers (asked first); otherwise the PDF goes to the share sheet.
  Future<void> _sendStatement() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final email = (_email ?? '').trim();
    final byEmail =
        email.isNotEmpty &&
        _caps.can(Cap.docSend) &&
        _caps.can(Cap.customerManage);
    if (byEmail && !await _confirmStatement(email)) return;
    if (!mounted) return;
    final business = session.business?.businessId;
    setState(() => _busy = true);
    try {
      if (byEmail) {
        await sendStatement(widget.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showNotchNotice(
            SnackBar(content: Text(PeopleHe.statementSent(email))),
            motion: NoticeMotion.sent,
          );
        }
      } else {
        final bytes = await fetchStatementPdf(widget.id);
        if (!mounted ||
            ModalRoute.of(context)?.isCurrent != true ||
            business != session.business?.businessId) {
          return;
        }
        await pdfSharer(bytes, PeopleHe.statementFileName(_name));
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmStatement(String email) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(PeopleHe.statementConfirmTitle),
        content: Text(PeopleHe.statementConfirmBody(_name, ltrIsolate(email))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('statement-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(CommonHe.send),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _archive() async {
    if (_busy) return;
    final open = _open ?? BigInt.zero;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          widget.isSupplier
              ? PeopleHe.supplierArchiveConfirm
              : open > BigInt.zero
              ? PeopleHe.archiveWithBalance(moneyInline(open))
              : PeopleHe.archiveConfirm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text(PeopleHe.archive),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (widget.isSupplier) {
        await archiveSupplier(widget.id);
      } else {
        await archiveCustomer(widget.id);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showNotchNotice(
        SnackBar(
          content: Text(
            widget.isSupplier ? PeopleHe.supplierArchived : PeopleHe.archived,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  // ---- actions ----

  PersonActionFacts get _facts => PersonActionFacts(
    supplier: widget.isSupplier,
    archived: _archived,
    hasPhone: (_phone ?? '').trim().isNotEmpty,
    hasWhatsapp: waPhone(_phone) != null,
    hasEmail: (_email ?? '').trim().isNotEmpty,
    hasAddress: _address != null,
    owes: _owes,
    canDraft: _caps.can(Cap.docDraft),
    canPaymentIssue: _caps.can(Cap.paymentIssue),
    canMoneyView: _caps.can(Cap.moneyView),
    canCalendar: !widget.isSupplier && mayUseCalendar(_caps),
    canManage: _manage,
    crmReady: _crmLoaded && _store.readyForEdits,
    canRepeat: lastRepeatable(_docs ?? const []) != null,
    statement: _statement,
    canExpense: _caps.can(Cap.expenseCapture),
  );

  Future<void> _run(String id) async {
    final ops = _ops;
    switch (id) {
      case 'call':
        await _launch(Uri(scheme: 'tel', path: normalizePhoneInput(_phone!)));
      case 'whatsapp':
        await _launch(Uri.parse('https://wa.me/${waPhone(_phone)}'));
      case 'email':
        await _launch(Uri(scheme: 'mailto', path: _email!.trim()));
      case 'add-phone' || 'edit':
        await _edit();
      case 'payment-request':
        await openPaymentRequest(context, customerId: widget.id);
      case 'invoice':
        await openCompose(
          context,
          intent: invoiceIntentFor(businessContext.businessType),
          customerId: widget.id,
        );
      case 'quote':
        await openCompose(context, intent: intentQuote, customerId: widget.id);
      case 'paid':
        await openCompose(context, intent: 'PAID', customerId: widget.id);
      case 'book':
        await showCustomerBookingSheet(
          context,
          customerId: widget.id,
          name: _name,
          phone: _phone,
          email: _email,
        );
        if (mounted) unawaited(_loadBookings());
      case 'reminder':
        if (ops != null && await ops.quickReminder(context) && mounted) {
          toast(PersonPageHe.reminderSaved);
        }
      case 'repeat':
        final opened = await openRepeat(context, widget.id);
        if (!opened && mounted) toast(ComposeHe.repeatNone);
      case 'debt':
        final d = _detail;
        if (d != null) await showDebtEntrySheet(context, customer: d.customer);
      case 'job':
        await ops?.editJob(context, showMoney: _caps.can(Cap.moneyView));
      case 'note':
        if (ops != null && await ops.addNote(context) && mounted) {
          toast(PersonPageHe.noteSaved);
        }
      case 'navigate':
        final a = _address;
        if (a != null) {
          await _launch(Uri.https('maps.apple.com', '/', {'q': a}));
        }
      case 'statement':
        await _sendStatement();
      case 'portal':
        await showPortalLinkSheet(
          context,
          customerId: widget.id,
          name: _name,
          phone: _phone,
          email: _email,
        );
      case 'terms':
        await _editTerms();
      case 'archive':
        await _archive();
      case 'expense':
        nextCaptureSupplier = _supplier;
        await openExpenseCapture(context);
    }
  }

  void toast(String text) => ScaffoldMessenger.of(
    context,
  ).showNotchNotice(SnackBar(content: Text(text)));

  Future<void> _showMore(List<String> ids) async {
    final p = context.palette;
    final chosen = await showAppSheet<String>(
      context,
      builder: (sheet) => Column(
        key: const Key('person-more-sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetTitle(PersonPageHe.moreTitle, subtitle: _name),
          for (final id in ids)
            ListTile(
              key: Key('person-more-$id'),
              minTileHeight: Hit.row - 8,
              contentPadding: EdgeInsets.zero,
              enabled: !(businessContext.offline && serverActions.contains(id)),
              leading: Icon(
                _icons[id],
                color: id == 'archive' ? p.danger : p.ink,
              ),
              title: Text(
                _label(id),
                style: AppText.body.copyWith(
                  color: id == 'archive' ? p.danger : null,
                ),
              ),
              onTap: () => Navigator.of(sheet).pop(id),
            ),
        ],
      ),
    );
    if (chosen != null && mounted) await _run(chosen);
  }

  Widget _quickActions(BuildContext context) {
    final facts = _facts;
    final row = personRowActions(facts);
    if (row.isEmpty) return const SizedBox.shrink();
    final more = personMoreActions(facts, row);
    final offline = businessContext.offline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, Space.l, Space.page, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(PersonPageHe.quickActions, style: AppText.title),
          const SizedBox(height: Space.s),
          QuickActionGrid(
            key: const Key('person-actions'),
            keyPrefix: 'person-action',
            actions: [
              for (final id in row)
                QuickAction(
                  id: id,
                  label: _label(id),
                  semanticsLabel: id == 'expense'
                      ? PeopleHe.newExpenseFrom(_name)
                      : null,
                  icon: _icons[id]!,
                  color: _orbColors[id]!.$1,
                  ink: _orbColors[id]!.$2,
                  enabled: !(offline && serverActions.contains(id)),
                  onTap: () => id == 'more'
                      ? unawaited(_showMore(more))
                      : unawaited(_run(id)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final loaded = widget.isSupplier ? _supplier != null : _detail != null;
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _store,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, loaded),
              Expanded(
                child: !loaded
                    ? (_error != null
                          ? ErrorView(error: _error!, onRetry: _load)
                          : const SingleChildScrollView(child: SkeletonList()))
                    : AbsorbPointer(
                        absorbing: _busy,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OfflineBanner(
                              visible: businessContext.offline,
                              onRetry: _load,
                            ),
                            if (_syncProblem)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.page,
                                ),
                                child: CustomerCrmSyncStatus(store: _store),
                              ),
                            Expanded(
                              child: RefreshIndicator(
                                onRefresh: () async {
                                  await _load();
                                  await _loadBookings();
                                },
                                child: _content(context),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _syncProblem =>
      _crmLoaded &&
      _store.remoteActive &&
      (_store.syncError != null ||
          _store.rejectedCount > 0 ||
          _store.hasConflict);

  Widget _header(BuildContext context, bool loaded) {
    final p = context.palette;
    final menu = <MoreMenuItem>[
      if (_manage)
        MoreMenuItem(
          label: PersonPageHe.details,
          icon: Iconsax.edit,
          onSelected: () => unawaited(_edit()),
        ),
      if (!widget.isSupplier && _statement && !_archived)
        MoreMenuItem(
          label: PersonPageHe.statement,
          icon: Iconsax.receipt_item,
          onSelected: () => unawaited(_sendStatement()),
        ),
      if (_manage)
        MoreMenuItem(
          label: PersonPageHe.archive,
          icon: Iconsax.archive_1,
          destructive: true,
          onSelected: () => unawaited(_archive()),
        ),
    ];
    final badges = <Widget>[
      if (_crmLoaded) _stage(context),
      if (widget.isSupplier) PersonTag(PeopleHe.supplierBadge, color: p.muted),
      if (_archived) PersonTag(PeopleHe.archivedBadge, color: p.muted),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.m,
        Space.page,
        Space.s,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(_name, style: AppText.displayTitle),
                ),
                if (loaded && badges.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: badges,
                  ),
                ],
              ],
            ),
          ),
          if (loaded) MoreMenu(items: menu),
          const SizedBox(width: 8),
          const DesignBackButton(),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final p = context.palette;
    final stage = displayStage(
      _store.entryFor(widget.id).stage,
      hasDocuments:
          (_docs?.isNotEmpty ?? false) ||
          _detail?.customer.lastDocumentAt != null,
    );
    final chip = Container(
      padding: const EdgeInsetsDirectional.fromSTEB(Space.s, 4, 6, 4),
      decoration: BoxDecoration(
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stage.label, style: AppText.secondary.copyWith(color: p.ink)),
          if (_manage) Icon(Icons.expand_more, size: 18, color: p.muted),
        ],
      ),
    );
    if (!_manage || !_store.readyForEdits) {
      return KeyedSubtree(key: const Key('person-stage'), child: chip);
    }
    final ops = _ops!;
    return PopupMenuButton<CustomerCrmStage>(
      key: const Key('person-stage'),
      tooltip: CustomerCrmHe.stage,
      onSelected: (s) =>
          unawaited(ops.run(context, () => _store.setStage(widget.id, s))),
      itemBuilder: (_) => [
        for (final s in CustomerCrmStage.values)
          PopupMenuItem(value: s, child: Text(s.label)),
      ],
      child: chip,
    );
  }

  Widget _content(BuildContext context) {
    final now = DateTime.now();
    final crm = _crmLoaded;
    final entry = crm ? _store.entryFor(widget.id) : const CustomerCrmEntry();
    final visits = crm || _bookings.isNotEmpty
        ? upcomingVisits(entry.jobs, _bookings, now)
        : const <VisitItem>[];
    final reminders = crm
        ? _store.remindersForCustomer(widget.id, includeCompleted: false)
        : const <CustomerCrmReminder>[];
    return ListView(
      key: const Key('person-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: Space.m, bottom: Space.xxl),
      children: [
        if (!widget.isSupplier)
          _statusCard(context, nextThing(visits, reminders, now)),
        _quickActions(context),
        if (!widget.isSupplier) ...[
          if (_caps.can(Cap.docView)) ..._documents(context),
          if (crm || _bookings.isNotEmpty) ..._visits(context, entry, visits),
          if (crm) ..._notes(context, entry, reminders, now),
          if (crm && _caps.can(Cap.moneyView)) ...[
            const SizedBox(height: Space.s),
            PersonFold(
              key: const Key('person-money'),
              title: PersonPageHe.money,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.page),
                  child: CustomerCrmFinanceCard(
                    jobs: entry.jobs,
                    documentsOpenMinor: _open,
                    onOpenJob: (job) => unawaited(
                      _ops?.editJob(context, job: job, showMoney: true),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
        _details(context),
      ],
    );
  }

  // ---- status card ----

  String _docName(DocumentSummary d) {
    final type = docTypeLabels[d.documentType] ?? d.documentType;
    final n = d.documentNumber;
    return n == null || n.isEmpty ? type : '$type ${ltrIsolate(n)}';
  }

  Widget? _nextLine(BuildContext context, NextThing? next) {
    final p = context.palette;
    if (next == null) {
      return Text(
        PersonPageHe.nothingNext,
        key: const Key('person-next-none'),
        style: AppText.secondary.copyWith(color: p.muted),
      );
    }
    final late = next.reminder != null;
    // Only a meeting, or what this member may edit, opens from here.
    final opens = next.visit?.booking != null || _manage;
    return InkWell(
      key: const Key('person-next'),
      onTap: opens ? () => unawaited(_openNext(next)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            Icon(
              late
                  ? Iconsax.notification
                  : next.visit?.booking != null
                  ? Iconsax.calendar_1
                  : Iconsax.briefcase,
              size: 20,
              color: late ? p.danger : p.ink,
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                next.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(color: late ? p.danger : p.ink),
              ),
            ),
            if (opens) Icon(Icons.chevron_right, size: 20, color: p.muted),
          ],
        ),
      ),
    );
  }

  Future<void> _openNext(NextThing next) async {
    final r = next.reminder;
    if (r != null) {
      if (_manage) await _ops?.editReminder(context, r);
      return;
    }
    final v = next.visit;
    if (v != null) await _openVisit(v);
  }

  Future<void> _openVisit(VisitItem v) async {
    final b = v.booking;
    if (b != null) {
      if (await showPersonBooking(context, b) && mounted) {
        unawaited(_loadBookings());
      }
      return;
    }
    if (_manage) {
      await _ops?.editJob(
        context,
        job: v.job,
        showMoney: _caps.can(Cap.moneyView),
      );
    }
  }

  Widget _statusCard(BuildContext context, NextThing? next) {
    final p = context.palette;
    final money = _caps.can(Cap.moneyView);
    final docs = _docs;
    final open = _open;
    final children = <Widget>[];
    if (money && docs != null) {
      if (open != null && open > BigInt.zero) {
        final line = oldestOpenDoc(docs, DateTime.now(), _docName);
        final late = line?.overdue ?? false;
        children.addAll([
          Row(
            key: const Key('person-owes'),
            children: [
              const Expanded(
                child: Text(PersonPageHe.owesYou, style: AppText.headline),
              ),
              AmountText(
                open,
                style: AppText.amountCard,
                color: late ? p.warn : p.ink,
              ),
            ],
          ),
          if (line != null)
            InkWell(
              key: const Key('person-status-doc'),
              onTap: () => openDocument(context, line.doc.id),
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.text,
                        style: AppText.secondary.copyWith(
                          color: late ? p.warn : p.muted,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: p.muted),
                  ],
                ),
              ),
            ),
        ]);
      } else {
        final days = daysSinceLastDoc(
          _detail?.customer.lastDocumentAt ??
              (docs.isEmpty
                  ? null
                  : (docs.map((d) => d.issueDate ?? '').toList()..sort()).last),
          DateTime.now(),
        );
        children.addAll([
          const Row(
            key: Key('person-no-balance'),
            children: [
              Expanded(
                child: Text(PersonPageHe.noBalance, style: AppText.headline),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            days == null
                ? PersonPageHe.noDocsYet
                : PersonPageHe.lastDocAgo(days),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ]);
      }
    }
    final nextLine = _nextLine(context, next);
    if (children.isEmpty && next == null) return const SizedBox.shrink();
    if (children.isNotEmpty) {
      children.add(Divider(color: p.line, height: Space.xl));
    }
    if (nextLine != null) children.add(nextLine);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: AppCard(
        key: const Key('person-status'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  // ---- lists ----

  List<Widget> _documents(BuildContext context) {
    final p = context.palette;
    final docs = _docs;
    return [
      PersonSectionTitle(
        title: PersonPageHe.documents,
        allKey: const Key('person-timeline'),
        // 0110: the full history (documents, quotes, payments, reminders…).
        onAll: () => unawaited(
          openCustomerTimeline(
            context,
            customerId: widget.id,
            customerName: _name,
          ),
        ),
      ),
      if (docs == null) const SkeletonList(rows: 3),
      if (docs != null && docs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  PersonPageHe.noDocsYet,
                  style: AppText.body.copyWith(color: p.muted),
                ),
              ),
              if (_caps.can(Cap.docDraft) && !_archived)
                TextButton(
                  key: const Key('person-first-invoice'),
                  onPressed: () => unawaited(_run('invoice')),
                  child: const Text(PersonPageHe.firstInvoice),
                ),
            ],
          ),
        ),
      for (final d in docsForCard(docs ?? const []).take(3)) _docRow(d),
    ];
  }

  Widget _docRow(DocumentSummary d) {
    final st = docListState(
      status: d.status,
      documentType: d.documentType,
      totalMinor: d.totalMinor,
      openMinor: d.openMinor,
      creditedMinor: d.creditedMinor,
      voidedAt: d.voidedAt,
      dueDate: d.dueDate,
      issueDate: d.issueDate,
      sentAt: d.sentAt,
    );
    final type = docTypeLabels[d.documentType] ?? d.documentType;
    final n = d.documentNumber;
    final date = relativeDateHe(d.issueDate);
    // A credit note reduces what the customer owes: shown with a minus.
    final credit = d.documentType == 'CREDIT_DOCUMENT';
    return DocRow(
      key: Key('person-doc-${d.id}'),
      title: n == null || n.isEmpty ? type : '$type · ${ltrIsolate(n)}',
      subtitle: date.isEmpty ? PeopleHe.notIssuedYet : date,
      amountMinor: d.amountHidden || !_caps.can(Cap.moneyView)
          ? null
          : (credit ? -d.totalMinor.abs() : d.totalMinor),
      status: StatusPill.doc(st.status),
      attributes: [for (final a in st.attributes) docAttributeLabels[a]!],
      onTap: () => openDocument(context, d.id),
    );
  }

  List<Widget> _visits(
    BuildContext context,
    CustomerCrmEntry entry,
    List<VisitItem> visits,
  ) {
    final p = context.palette;
    final now = DateTime.now();
    final ops = _ops;
    final pinned = entry.notes.where((n) => n.pinned).toList();
    final canBook = mayUseCalendar(_caps) && !_archived;
    final canJob = _manage && _crmLoaded && _store.readyForEdits;
    return [
      PersonSectionTitle(
        title: PersonPageHe.visits,
        allKey: const Key('person-visits-all'),
        onAll: ops == null || (!_crmLoaded && _bookings.isEmpty)
            ? null
            : () => unawaited(
                openPersonVisits(
                  context,
                  ops: ops,
                  bookings: _bookings,
                  canEdit: _manage,
                  showMoney: _caps.can(Cap.moneyView),
                  phone: _phone,
                  onCreateDocument: _caps.can(Cap.docDraft) && !_archived
                      ? () => unawaited(_run('invoice'))
                      : null,
                  onChanged: () => unawaited(_loadBookings()),
                ),
              ),
      ),
      if (visits.isEmpty)
        Padding(
          key: const Key('person-visits-empty'),
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  PersonPageHe.noVisits,
                  style: AppText.body.copyWith(color: p.muted),
                ),
              ),
              if (canBook)
                TextButton(
                  onPressed: () => unawaited(_run('book')),
                  child: const Text(PersonPageHe.book),
                )
              else if (canJob)
                TextButton(
                  onPressed: () => unawaited(_run('job')),
                  child: const Text(PersonPageHe.newJob),
                ),
            ],
          ),
        ),
      for (final (i, v) in visits.take(3).indexed) ...[
        if (i == 0)
          for (final n in pinned) PersonBeforeArrival(note: n),
        PersonVisitRow(
          item: v,
          now: now,
          onTap: v.booking != null || _manage
              ? () => unawaited(_openVisit(v))
              : null,
        ),
      ],
    ];
  }

  List<Widget> _notes(
    BuildContext context,
    CustomerCrmEntry entry,
    List<CustomerCrmReminder> reminders,
    DateTime now,
  ) {
    final p = context.palette;
    final ops = _ops!;
    final edit = _manage && _store.readyForEdits;
    final notes = entry.notes.toList()
      ..sort(
        (a, b) => a.pinned == b.pinned
            ? b.createdAt.compareTo(a.createdAt)
            : a.pinned
            ? -1
            : 1,
      );
    final rows = <Widget>[
      for (final r in reminders)
        PersonReminderRow(
          reminder: r,
          now: now,
          onToggle: edit
              ? () => unawaited(ops.toggleReminder(context, r))
              : null,
          onTap: edit ? () => unawaited(ops.editReminder(context, r)) : null,
          onDelete: edit
              ? () => unawaited(ops.deleteReminder(context, r))
              : null,
        ),
      for (final n in notes)
        PersonNoteRow(
          note: n,
          onTap: edit ? () => unawaited(ops.editNote(context, n)) : null,
          onPin: edit ? () => unawaited(ops.pinNote(context, n)) : null,
          onDelete: edit ? () => unawaited(ops.deleteNote(context, n)) : null,
        ),
    ];
    return [
      PersonSectionTitle(
        title: PersonPageHe.notes,
        allKey: const Key('person-notes-all'),
        allLabel: _notesAll ? PersonPageHe.less : PersonPageHe.all,
        onAll: rows.length > 3
            ? () => setState(() => _notesAll = !_notesAll)
            : null,
      ),
      if (rows.isEmpty)
        Padding(
          key: const Key('person-notes-empty'),
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  PersonPageHe.noNotes,
                  style: AppText.body.copyWith(color: p.muted),
                ),
              ),
              if (edit)
                TextButton(
                  key: const Key('person-add-note'),
                  onPressed: () => unawaited(_run('note')),
                  child: const Text(PersonPageHe.addNote),
                ),
            ],
          ),
        ),
      ...(_notesAll ? rows : rows.take(3)),
    ];
  }

  Widget _details(BuildContext context) {
    final d = _detail;
    final s = _supplier;
    String v(String? x) =>
        (x ?? '').trim().isEmpty ? PersonPageHe.missing : x!.trim();
    final taxId = d?.customer.taxId ?? s?.taxId;
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: PersonFold(
        key: const Key('person-details'),
        // A supplier card is short: its details show at once.
        initiallyExpanded: widget.isSupplier,
        title: widget.isSupplier
            ? PersonPageHe.supplierDetails
            : PersonPageHe.customerDetails,
        children: [
          PersonDetailRow(
            label: PersonPageHe.phone,
            value: v(_phone),
            ltr: (_phone ?? '').trim().isNotEmpty,
            onTap: (_phone ?? '').trim().isEmpty ? null : () => _run('call'),
          ),
          PersonDetailRow(
            label: PersonPageHe.email,
            value: v(_email),
            ltr: (_email ?? '').trim().isNotEmpty,
            onTap: (_email ?? '').trim().isEmpty ? null : () => _run('email'),
          ),
          if (!widget.isSupplier)
            PersonDetailRow(
              label: PersonPageHe.address,
              value: v(_address),
              onTap: _address == null ? null : () => _run('navigate'),
            ),
          PersonDetailRow(
            label: PersonPageHe.taxId,
            value: v(taxId),
            ltr: (taxId ?? '').trim().isNotEmpty,
          ),
          if (d != null)
            PersonDetailRow(
              key: const Key('person-terms'),
              valueKey: const Key('person-terms-value'),
              label: PersonPageHe.terms,
              value: _termsLine(d),
              onTap: _manage ? () => unawaited(_editTerms()) : null,
            ),
          if (!widget.isSupplier && !_archived)
            PersonAutoRemindersRow(customerId: widget.id),
          if (!widget.isSupplier && _manage && _caps.can(Cap.moneyView))
            PersonPortalRow(
              customerId: widget.id,
              name: _name,
              phone: _phone,
              email: _email,
            ),
          if (_manage)
            PersonDetailRow(
              key: const Key('person-edit'),
              label: PersonPageHe.details,
              value: '',
              onTap: () => unawaited(_edit()),
            ),
        ],
      ),
    );
  }
}
