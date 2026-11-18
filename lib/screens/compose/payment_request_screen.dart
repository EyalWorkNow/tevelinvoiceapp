// בקשת תשלום — a short form, not the Composer (owner 2026-11-18, tester
// feedback "בקשת תשלום מובילה ליצירת חשבונית"). Route: /payment-request.
//
// Customer, amount (incl. VAT, exact: the typed amount is what the customer
// pays — agreedTotalMinor when the server keeps agreed totals), one-line
// description, due date (the customer's / business's payment terms, else
// שוטף+30) and an optional note. "שלח בקשת תשלום" issues the same 300 the
// Composer issues for intent REQUEST — the same ComposeLoad / runCompose
// (draft → evaluate/finalize or submit for approval, signing, dispatch,
// WhatsApp with the payment link, D with its send options) — so nothing about
// the issue differs; only the screen. "עריכה מתקדמת" opens the Composer.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/models/models.dart';
import '../../router.dart' show openCompose;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/intent_resolver.dart';
import '../../util/labels/compose_he.dart';
import '../../util/labels/payment_request_he.dart';
import '../../util/labels/common_he.dart' show formatDateHe;
import '../../util/money.dart';
import '../../util/money_input.dart';
import '../../util/phone.dart';
import '../people/sheets/s2_customer.dart';
import 'compose_loader.dart';
import 'compose_submit.dart';

/// S2 (pick / quick-add a customer). Tests replace it.
Future<Customer?> Function(BuildContext context) pickRequestCustomer = (c) =>
    showCustomerSheet(c, openExistingCard: false);

class PaymentRequestScreen extends StatefulWidget {
  const PaymentRequestScreen({super.key, this.customerId});

  final String? customerId;

  @override
  State<PaymentRequestScreen> createState() => _PaymentRequestScreenState();
}

class _PaymentRequestScreenState extends State<PaymentRequestScreen> {
  ComposeLoad? _load;
  Object? _error;
  bool _unavailable = false;
  String? _step;
  bool _tried = false;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _load?.state.removeListener(_changed);
    _amount.dispose();
    _description.dispose();
    _note.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _unavailable = false;
    });
    try {
      final load = await loadComposer(
        intent: intentRequest,
        customerId: widget.customerId,
      );
      if (!mounted) return;
      if (load == null) return setState(() => _unavailable = true);
      final s = load.state
        // The typed amount is the total, VAT included (exact).
        ..inclusive = true
        ..vatNone = false
        ..vatPerLine = false
        ..extraLines.clear()
        ..discountText = ''
        ..description = ''
        ..notes = '';
      // A leftover of the Composer is the Composer's to offer, not ours.
      load
        ..leftoverForm = null
        ..leftoverIssue = null;
      s.addListener(_changed);
      setState(() => _load = load);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _chooseCustomer() async {
    final s = _load?.state;
    if (s == null) return;
    final c = await pickRequestCustomer(context);
    if (c == null || !mounted) return;
    s
      ..customer = c
      ..changed();
    await applyCustomerTerms(s);
  }

  Future<void> _pickDueDate() async {
    final s = _load!.state;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = DateTime.tryParse(s.dueDate) ?? today;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
      initialDate: initial.isBefore(today) ? today : initial,
    );
    if (picked == null || !mounted) return;
    s
      ..pickedDueDate =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}'
      ..changed();
  }

  BigInt get _amountMinor => parseAmount(_amount.text) ?? BigInt.zero;

  String? get _customerError => _tried && _load?.state.customer == null
      ? PaymentRequestHe.needCustomer
      : null;
  String? get _amountError => _tried && _amountMinor <= BigInt.zero
      ? PaymentRequestHe.needAmount
      : null;
  String? get _descriptionError => _tried && _description.text.trim().isEmpty
      ? PaymentRequestHe.needDescription
      : null;

  /// Copies the form into the Composer state (the one the issue reads).
  void _sync() {
    final s = _load!.state;
    s
      ..amountText = _amountMinor > BigInt.zero
          ? agorotToKeypadText(_amountMinor)
          : ''
      ..description = _description.text.trim()
      ..descriptionTouched = true
      ..notes = _note.text.trim();
  }

  ({bool needsApproval, ComposerAction action}) _resolve() {
    final s = _load!.state;
    final bc = businessContext;
    final needsApproval = kindNeedsApproval(
      s.kind,
      () => bc.caps.approvalNeeded(s.totalMinor, paid: s.config.paid),
      cappedReceipts: bc.caps.isCashier,
    );
    return (
      needsApproval: needsApproval,
      action: resolveAction(
        kind: s.kind,
        needsApproval: needsApproval,
        hasPhone: s.hasPhone,
        canSend: bc.can(Cap.docSend),
      ),
    );
  }

  Future<void> _send() async {
    if (_step != null) return;
    FocusScope.of(context).unfocus();
    _sync();
    final load = _load!;
    final s = load.state;
    if (s.customer == null ||
        _amountMinor <= BigInt.zero ||
        s.mainDescription.isEmpty ||
        s.requestLines.length != 1) {
      setState(() => _tried = true);
      return;
    }
    final r = _resolve();
    final run = load.run(action: r.action, needsApproval: r.needsApproval);
    await runCompose(
      context,
      run,
      onStep: (step) {
        if (mounted) setState(() => _step = step);
      },
    );
  }

  /// "עריכה מתקדמת": the full Composer with what was typed; this screen
  /// closes so issuing there never lands back on a stale form.
  void _advanced() {
    _sync();
    final s = _load?.state;
    final nav = Navigator.of(context);
    final root = nav.context;
    nav.pop();
    unawaited(
      openCompose(
        root,
        intent: intentRequest,
        customerId: s?.customer?.id ?? widget.customerId,
        prefillAmountMinor: _amountMinor > BigInt.zero ? _amountMinor : null,
        prefillDescription: s?.mainDescription.isEmpty ?? true
            ? null
            : s!.mainDescription,
        prefillNotes: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: businessContext,
    builder: (context, _) => Scaffold(
      key: const Key('payment-request'),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _unavailable
                  ? const EmptyState(
                      icon: Iconsax.forbidden_2,
                      title: PaymentRequestHe.notAvailable,
                    )
                  : _error != null
                  ? ErrorView(error: _error!, onRetry: _start)
                  : _load == null
                  ? const SkeletonList(rows: 3)
                  : ContentReveal(child: _form(_load!)),
            ),
            if (_load != null && !_unavailable && _error == null)
              _bottom(_load!),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(Space.page, Space.s, Space.page, 0),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(PaymentRequestHe.title, style: AppText.title),
              Text(
                PaymentRequestHe.subtitle,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
            ],
          ),
        ),
        const DesignBackButton(key: Key('payment-request-close')),
      ],
    ),
  );

  Widget _form(ComposeLoad load) {
    final s = load.state;
    final p = context.palette;
    final customer = s.customer;
    Widget error(String? text) => text == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              text,
              style: AppText.secondary.copyWith(color: p.danger),
            ),
          );
    return ListView(
      padding: const EdgeInsets.all(Space.page),
      children: [
        OfflineBanner(visible: businessContext.offline),
        Text(PaymentRequestHe.customer, style: AppText.secondary),
        const SizedBox(height: Space.s),
        AppCard(
          key: const Key('payment-request-customer'),
          onTap: _step == null ? _chooseCustomer : null,
          child: Row(
            children: [
              if (customer != null) ...[
                PersonAvatar(name: customer.name),
                const SizedBox(width: Space.m),
              ] else ...[
                Icon(Iconsax.user_add, color: p.ink),
                const SizedBox(width: Space.m),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer?.name ?? PaymentRequestHe.chooseCustomer,
                      style: AppText.body,
                    ),
                    if (customer?.phone case final phone? when phone.isNotEmpty)
                      Text(
                        formatPhoneHe(phone),
                        textDirection: TextDirection.ltr,
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                  ],
                ),
              ),
              if (customer != null)
                Text(
                  PaymentRequestHe.changeCustomer,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
            ],
          ),
        ),
        error(_customerError),
        const SizedBox(height: Space.section),
        TextField(
          key: const Key('payment-request-amount'),
          controller: _amount,
          keyboardType: moneyKeyboard,
          inputFormatters: const [DecimalTextInputFormatter.money],
          textDirection: TextDirection.ltr,
          style: AppText.amountCard,
          decoration: InputDecoration(
            labelText: PaymentRequestHe.amount,
            hintText: PaymentRequestHe.amountHint,
            prefixText: '₪ ',
            errorText: _amountError,
          ),
          onChanged: (_) => setState(() {}),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Text(
            s.showVat
                ? PaymentRequestHe.amountExactVat
                : PaymentRequestHe.amountExact,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
        const SizedBox(height: Space.l),
        TextField(
          key: const Key('payment-request-description'),
          controller: _description,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: PaymentRequestHe.description,
            hintText: PaymentRequestHe.descriptionHint,
            counterText: '',
            errorText: _descriptionError,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Space.l),
        AppCard(
          key: const Key('payment-request-due'),
          onTap: _step == null ? _pickDueDate : null,
          child: Row(
            children: [
              Icon(Iconsax.calendar_1, color: p.ink),
              const SizedBox(width: Space.m),
              const Expanded(
                child: Text(PaymentRequestHe.dueDate, style: AppText.body),
              ),
              Text(formatDateHe(s.dueDate), style: AppText.body),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        TextField(
          key: const Key('payment-request-note'),
          controller: _note,
          maxLength: 500,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: PaymentRequestHe.note,
            counterText: '',
          ),
        ),
        const SizedBox(height: Space.l),
        Center(
          child: TextButton.icon(
            key: const Key('payment-request-advanced'),
            onPressed: _step == null ? _advanced : null,
            icon: const Icon(Iconsax.setting_4, size: 18),
            label: const Text(PaymentRequestHe.advanced),
          ),
        ),
      ],
    );
  }

  Widget _bottom(ComposeLoad load) {
    final s = load.state;
    _sync();
    final r = _resolve();
    final bc = businessContext;
    final policy = bc.caps.approvalPolicy;
    final note =
        r.action == ComposerAction.submit &&
            policy.isThreshold &&
            bc.can(Cap.docIssue)
        ? approvalNote(policy.thresholdMinor)
        : _amountMinor > BigInt.zero
        ? PaymentRequestHe.issuesAs(s.totalMinor)
        : null;
    return BottomActionArea(
      note: note,
      child: PrimaryButton(
        key: const Key('payment-request-send'),
        label: r.action == ComposerAction.submit
            ? actionLabel(ComposerAction.submit)
            : PaymentRequestHe.send,
        icon: Iconsax.send_1,
        offline: bc.offline,
        loadingText: _step,
        onPressed: () => unawaited(_send()),
      ),
    );
  }
}
