// P2 · כרטיס לקוח / ספק (SPEC-v2 §6.P2). Owner: squad D.
// Route: /person/:id   (?kind=supplier for a supplier card).
//
// Name (+ "ספק" / "בארכיון") → 3 contact circles (חייג · ווטסאפ · מייל, only
// those with data) → "חייב לך ₪X" (money.view) → ONE primary button:
// "בקש תשלום" when the balance is > 0, else "מסמך חדש ל-X" (doc.draft);
// supplier: "הוצאה חדשה מ-X" (expense.capture) → documents → "פרטים ועריכה"
// (customer.manage; S2 form in edit mode) · "שלח כרטסת" (BE-17: e-mail when
// the customer has one and the member may send, else the PDF to the share
// sheet; hidden while the server has no BE-17) → ⋯ "ארכב" (red,
// customer.manage; a dialog when money is still open).
// Supplier card with BE-16: "פרטים ועריכה" + ⋯ "ארכב" (supplier.manage).

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/customers_api.dart';
import '../../api/models/models.dart';
import '../../api/suppliers_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/session.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../debts/reminder_hold_tile.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/document_he.dart';
import '../../util/labels/people_he.dart';
import '../../util/labels/status_he.dart';
import '../../util/phone.dart';
import '../../util/crm_visit.dart';
import '../../util/intent_resolver.dart' show invoiceIntentFor;
import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/debts_he.dart';
import '../../util/status_map.dart';
import '../calendar/calendar_screen.dart' show mayUseCalendar;
import '../calendar/customer_booking_sheet.dart';
import '../document/sheets/s6_share.dart' show pdfSharer;
import '../../util/labels/calendar_he.dart';
import '../compose/compose_repeat.dart' show lastRepeatable, openRepeat;
import '../expense/expense_capture_screen.dart' show nextCaptureSupplier;
import '../debts/debt_entry_sheet.dart';
import '../../util/labels/compose_he.dart';
import 'sheets/s2_customer.dart';
import 'customer_crm_agenda_screen.dart';
import 'customer_crm_panel.dart';
import 'customer_timeline_screen.dart';
import 'sheets/payment_terms_sheet.dart';
import '../../api/customer_timeline_api.dart' show PaymentTermsValue;
import '../../util/labels/timeline_he.dart';
import '../../util/payment_terms.dart' show paymentTermsLabel;
import 'package:iconsax_flutter/iconsax_flutter.dart';

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
  Object? _error;
  bool _busy = false;

  Caps get _caps => businessContext.caps;

  @override
  void initState() {
    super.initState();
    _load();
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
        // Never holds the card up: the row appears when the probe answers.
        statementAvailable(widget.id).then((v) {
          if (mounted && v != _statement) setState(() => _statement = v);
        }, onError: (Object _) {});
      }
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

  String get _name => _supplier?.name ?? _detail?.customer.name ?? '';
  String? get _phone => _supplier?.phone ?? _detail?.customer.phone;
  String? get _email => _supplier?.email ?? _detail?.customer.email;
  bool get _archived =>
      _supplier?.isArchived ?? _detail?.customer.isArchived ?? false;

  Future<void> _launch(Uri uri) async {
    HapticFeedback.selectionClick();
    await launchAllowed(uri);
  }

  Future<void> _openVisitTarget(Uri? uri) async {
    if (uri == null) return;
    try {
      final opened = await launchAllowed(uri);
      if (!opened) throw StateError('External app unavailable');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(CustomerCrmHe.launchError)),
        );
      }
    }
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

  /// "שלח כרטסת" (J11). E-mail when the customer has one and the member may
  /// send to customers (asked first: it reaches the customer at once, QA
  /// 2026-11-16 owner/114); otherwise the PDF goes to the share sheet.
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

  /// The one primary action (or none).
  PrimaryButton? _primary() {
    if (_archived) return null;
    final offline = businessContext.offline;
    if (widget.isSupplier) {
      if (!_caps.can(Cap.expenseCapture)) return null;
      return PrimaryButton(
        label: PeopleHe.newExpenseFrom(_name),
        offline: offline,
        onPressed: () {
          nextCaptureSupplier = _supplier;
          openExpenseCapture(context);
        },
      );
    }
    if (!_caps.can(Cap.docDraft)) return null;
    final owes = (_open ?? BigInt.zero) > BigInt.zero;
    return PrimaryButton(
      key: const Key('person-primary'),
      label: owes ? CommonHe.requestPayment : PeopleHe.newDocFor(_name),
      offline: offline,
      // A5: "חשבונית חדשה ל-X" follows the "+ חשבונית" default (פטור → קבלה).
      // Owner 2026-11-18: "בקש תשלום" opens the short payment-request form.
      onPressed: () => owes
          ? openPaymentRequest(context, customerId: widget.id)
          : openCompose(
              context,
              intent: invoiceIntentFor(businessContext.businessType),
              customerId: widget.id,
            ),
    );
  }

  /// Secondary actions under the primary button (customer card only):
  /// "קיבלתי תשלום" (payment.record) and, when the primary asks for payment,
  /// a plain "new invoice" for this customer.
  List<Widget> _secondary() {
    if (widget.isSupplier || _archived) return const [];
    final owes = (_open ?? BigInt.zero) > BigInt.zero;
    return [
      if (owes && _caps.can(Cap.docDraft))
        TextButton.icon(
          key: const Key('person-new-invoice'),
          onPressed: () => openCompose(
            context,
            intent: invoiceIntentFor(businessContext.businessType),
            customerId: widget.id,
          ),
          icon: const Icon(Iconsax.receipt_add, size: 18),
          label: const Text(PeopleHe.newInvoice),
        ),
      // C1: "רשום חוב" — a debt-book line without a document.
      if (_caps.can(Cap.docDraft) &&
          _caps.can(Cap.moneyView) &&
          _detail != null)
        TextButton.icon(
          key: const Key('person-debt'),
          onPressed: () =>
              showDebtEntrySheet(context, customer: _detail!.customer),
          icon: const Icon(Iconsax.note_add, size: 18),
          label: const Text(DebtsHe.add),
        ),
      // C3 "כמו בפעם הקודמת": the last document again, two taps (persona 04).
      if ((_caps.can(Cap.docDraft) || _caps.can(Cap.paymentIssue)) &&
          lastRepeatable(_docs ?? const []) != null)
        TextButton.icon(
          key: const Key('person-repeat'),
          onPressed: () async {
            final opened = await openRepeat(context, widget.id);
            if (!opened && mounted) {
              ScaffoldMessenger.of(context).showNotchNotice(
                const SnackBar(content: Text(ComposeHe.repeatNone)),
              );
            }
          },
          icon: const Icon(Iconsax.repeat, size: 18),
          label: const Text(ComposeHe.repeatLast),
        ),
      if (_caps.can(Cap.paymentIssue))
        TextButton.icon(
          key: const Key('person-paid'),
          onPressed: () =>
              openCompose(context, intent: 'PAID', customerId: widget.id),
          icon: const Icon(Iconsax.money_recive, size: 18),
          label: const Text(CommonHe.paid),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loaded = widget.isSupplier ? _supplier != null : _detail != null;
    final primary = loaded ? _primary() : null;
    final manage =
        !_archived &&
        (widget.isSupplier
            ? _be16 && _caps.can(Cap.supplierManage)
            : _caps.can(Cap.customerManage));
    final secondary = loaded ? _secondary() : const <Widget>[];
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(_name, style: AppText.displayTitle),
                    ),
                  ),
                  if (loaded && manage)
                    MoreMenu(
                      items: [
                        MoreMenuItem(
                          label: PeopleHe.archive,
                          destructive: true,
                          onSelected: _archive,
                        ),
                      ],
                    ),
                  const SizedBox(width: 8),
                  const DesignBackButton(),
                ],
              ),
            ),
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
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: _load,
                              child: _content(context, manage),
                            ),
                          ),
                          if (primary != null || secondary.isNotEmpty)
                            BottomActionArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (secondary.isNotEmpty)
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: Space.s,
                                      children: secondary,
                                    ),
                                  ?primary,
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, bool manage) {
    final p = context.palette;
    final wa = waPhone(_phone);
    final open = _open;
    final docs = _docs;
    final businessId = businessContext.business?.businessId;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: Space.l),
      children: [
        if (widget.isSupplier || _archived)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: Wrap(
              spacing: Space.s,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.isSupplier)
                  Text(
                    PeopleHe.supplierBadge,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                if (_archived)
                  Text(
                    PeopleHe.archivedBadge,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
              ],
            ),
          ),
        if (widget.isSupplier || _archived) const SizedBox(height: Space.l),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if ((_phone ?? '').trim().isNotEmpty)
              _ContactCircle(
                key: const Key('person-call'),
                icon: Iconsax.call,
                label: PeopleHe.call,
                onTap: () => _launch(
                  Uri(scheme: 'tel', path: normalizePhoneInput(_phone!)),
                ),
              ),
            if (wa != null)
              _ContactCircle(
                key: const Key('person-whatsapp'),
                icon: Iconsax.message,
                label: PeopleHe.whatsapp,
                onTap: () => _launch(Uri.parse('https://wa.me/$wa')),
              ),
            if ((_email ?? '').trim().isNotEmpty)
              _ContactCircle(
                key: const Key('person-mail'),
                icon: Iconsax.sms,
                label: PeopleHe.mail,
                onTap: () =>
                    _launch(Uri(scheme: 'mailto', path: _email!.trim())),
              ),
          ],
        ),
        if (!widget.isSupplier && manage && businessId != null) ...[
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: CustomerCrmPanel(
              businessId: businessId,
              customerId: widget.id,
              customerName: _name,
              canEdit: manage,
              canViewMoney: _caps.can(Cap.moneyView),
              documentsOpenMinor: open,
              hasDocuments:
                  (docs?.isNotEmpty ?? false) ||
                  _detail?.customer.lastDocumentAt != null,
              onNavigate: (job) =>
                  unawaited(_openVisitTarget(crmVisitMapUri(job))),
              onMessage: wa == null
                  ? null
                  : (job) => unawaited(
                      _openVisitTarget(crmVisitMessageUri(job, _phone)),
                    ),
              onCreateDocument: _caps.can(Cap.docDraft) && !_archived
                  ? () => unawaited(
                      openCompose(
                        context,
                        intent: invoiceIntentFor(businessContext.businessType),
                        customerId: widget.id,
                      ),
                    )
                  : null,
              onOpenAgenda: () => unawaited(
                openCustomerCrmAgenda(context, businessId: businessId),
              ),
            ),
          ),
        ],
        if (open != null && open > BigInt.zero) ...[
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: AppCard(
              key: const Key('person-owes'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(PeopleHe.owesYou, style: AppText.headline),
                  ),
                  AmountText(open, style: AppText.amountCard, color: p.warn),
                ],
              ),
            ),
          ),
        ],
        if (manage) ...[
          const SizedBox(height: Space.l),
          ListTile(
            key: const Key('person-edit'),
            minTileHeight: Hit.row,
            leading: const Icon(Iconsax.edit),
            title: const Text(PeopleHe.detailsAndEdit, style: AppText.body),
            trailing: const Icon(Iconsax.arrow_left_2),
            onTap: _edit,
          ),
        ],
        // 0110 תנאי תשלום (the customer's, else the business default).
        if (!widget.isSupplier && _detail != null) ...[
          if (!manage) const SizedBox(height: Space.l),
          ListTile(
            key: const Key('person-terms'),
            minTileHeight: Hit.row,
            leading: const Icon(Iconsax.calendar_2),
            title: const Text(TimelineHe.terms, style: AppText.body),
            subtitle: Text(
              _termsLine(_detail!),
              key: const Key('person-terms-value'),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            trailing: manage ? const Icon(Iconsax.arrow_left_2) : null,
            onTap: manage ? _editTerms : null,
          ),
        ],
        // Calendar v2: suggest times / send the personal link / book for them.
        if (!widget.isSupplier &&
            !_archived &&
            _detail != null &&
            mayUseCalendar(_caps))
          ListTile(
            key: const Key('person-book'),
            minTileHeight: Hit.row,
            leading: const Icon(Iconsax.calendar_add),
            title: const Text(CalendarHe.bookFor, style: AppText.body),
            trailing: const Icon(Iconsax.arrow_left_2),
            onTap: () => unawaited(
              showCustomerBookingSheet(
                context,
                customerId: widget.id,
                name: _name,
                phone: _phone,
              ),
            ),
          ),
        if (!widget.isSupplier && _statement && !_archived)
          ListTile(
            key: const Key('person-statement'),
            minTileHeight: Hit.row,
            leading: const Icon(Iconsax.receipt_item),
            title: const Text(PeopleHe.sendStatement, style: AppText.body),
            subtitle: Text(
              PeopleHe.statementPeriod,
              style: AppText.secondary.copyWith(color: p.muted),
            ),
            onTap: _busy ? null : _sendStatement,
          ),
        // 0111: "אל תשלח תזכורות ללקוח הזה" (owner / partner).
        if (!widget.isSupplier && !_archived)
          ReminderHoldTile(customerId: widget.id),
        if (!widget.isSupplier && _caps.can(Cap.docView)) ...[
          const SizedBox(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    PeopleHe.documents,
                    style: AppText.headline.copyWith(color: p.muted),
                  ),
                ),
                // 0110: the full history (documents, quotes, payments,
                // reminders, notes…) of this customer.
                TextButton.icon(
                  key: const Key('person-timeline'),
                  onPressed: () => unawaited(
                    openCustomerTimeline(
                      context,
                      customerId: widget.id,
                      customerName: _name,
                    ),
                  ),
                  icon: const Icon(Iconsax.clock, size: 18),
                  label: const Text(TimelineHe.title),
                ),
              ],
            ),
          ),
          if (docs == null) const SkeletonList(rows: 3),
          if (docs != null && docs.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.page),
              child: Text(
                PeopleHe.noDocuments,
                style: AppText.body.copyWith(color: p.muted),
              ),
            ),
          for (final d in docs ?? const <DocumentSummary>[]) _docRow(d),
        ],
      ],
    );
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
      amountMinor: d.amountHidden
          ? null
          : (credit ? -d.totalMinor.abs() : d.totalMinor),
      status: StatusPill.doc(st.status),
      attributes: [for (final a in st.attributes) docAttributeLabels[a]!],
      onTap: () => openDocument(context, d.id),
    );
  }
}

class _ContactCircle extends StatelessWidget {
  const _ContactCircle({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m),
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: p.line,
                child: Icon(icon, color: p.ink),
              ),
              const SizedBox(height: Space.xs),
              Text(label, style: AppText.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
