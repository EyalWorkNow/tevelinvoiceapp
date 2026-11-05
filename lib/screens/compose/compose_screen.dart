// C · Composer (SPEC-v2 §6.C, §8.1–8.2). Owner: squad B.
// Route: /compose?intent=&customerId=&fromDocId=&fromQuoteId=&draftId=
// Three decisions on the screen: customer, amount, button (J1 = 3 taps).
// The type is resolved from the intent (intent_resolver.dart) and never shown
// before issuing (F1); S3 can switch it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/models/models.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/composer_config.dart';
import '../../util/intent_resolver.dart';
import '../../util/labels/labels.dart';
import '../../util/money.dart';
import '../people/sheets/s2_customer.dart';
import 'compose_loader.dart';
import 'compose_memory.dart';
import 'compose_submit.dart';
import 'fields/amount_field.dart';
import 'fields/customer_chip.dart';
import 'fields/summary_section.dart';
import 'sheets/s3_more.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// S2 (squad D). Tests replace it to simulate one tap on a recent customer.
Future<Customer?> Function(BuildContext context) pickCustomer = (c) =>
    showCustomerSheet(c);

/// S2 in supplier mode for a 500 purchase order (shown in the same chip).
Future<Customer?> Function(BuildContext context) pickSupplier = (c) async =>
    switch (await showSupplierSheet(c)) {
      final x? => supplierAsCustomer(x),
      null => null,
    };

/// One screen for every document type. [intent]: PAID | REQUEST | QUOTE | TYPE:<code>.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({
    super.key,
    required this.intent,
    this.customerId,
    this.fromDocId,
    this.fromQuoteId,
    this.draftId,
  });

  final String intent;
  final String? customerId;
  final String? fromDocId;
  final String? fromQuoteId;
  final String? draftId;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  ComposeLoad? _load;
  Object? _error;
  bool _unavailable = false;
  String? _step;
  bool _issuedOrLeft = false;
  bool _pickingInitialCustomer = false;

  @override
  void initState() {
    super.initState();
    // Toasts from the previous issue would sit over the issue button and eat the first tap.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) =>
          mounted ? ScaffoldMessenger.maybeOf(context)?.clearSnackBars() : null,
    );
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _unavailable = false;
    });
    try {
      final load = await loadComposer(
        intent: widget.intent,
        customerId: widget.customerId,
        fromDocId: widget.fromDocId,
        fromQuoteId: widget.fromQuoteId,
        draftId: widget.draftId,
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (load == null) return setState(() => _unavailable = true);
      load.state.addListener(_changed);
      setState(() {
        _load = load;
        _pickingInitialCustomer = load.state.customer == null;
      });
      if (load.state.customer == null) {
        await _waitForEntrance();
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;

        final chosen = await _chooseCustomer();
        if (!mounted) return;
        if (chosen == null || load.state.customer == null) {
          // Keep the amount screen hidden throughout both reverse transitions.
          if (ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
          return;
        }
        setState(() => _pickingInitialCustomer = false);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _waitForEntrance() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      return;
    }
    final ready = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        animation.removeStatusListener(onStatus);
        ready.complete();
      }
    }

    animation.addStatusListener(onStatus);
    await ready.future;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final s = _load?.state;
    s?.removeListener(_changed);
    // Leaving with data → local draft without a dialog (§6.C edge).
    if (s != null && !_issuedOrLeft && s.amountMinor > BigInt.zero) {
      saveLocalDraft(widget.intent, s.toJson());
    }
    super.dispose();
  }

  Future<Customer?> _chooseCustomer() async {
    final s = _load!.state;
    final supplier = s.config.counterparty == Counterparty.supplier;
    final c = await (supplier ? pickSupplier : pickCustomer)(context);
    if (c == null || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return null;
    }
    s.customer = c;
    if (!s.descriptionTouched) {
      s.description = await defaultDescription(
        c.id,
        lastOnServer: c.lastLineDescription,
        businessDefault: businessContext.profile?.defaultLineDescription,
      );
    }
    s.changed();
    await applyCustomerTerms(s);
    return c;
  }

  Future<void> _press(ComposerAction action, bool needsApproval) async {
    final load = _load!;
    final run = load.run(action: action, needsApproval: needsApproval);
    await runCompose(
      context,
      run,
      onStep: (step) {
        if (!mounted) return;
        setState(() => _step = step);
      },
    );
    if (mounted && run.pending?.stage.name == 'done') _issuedOrLeft = true;
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    return Scaffold(
      body: SafeArea(
        child: _unavailable
            ? const EmptyState(
                icon: Iconsax.forbidden_2,
                title: ComposeHe.notAvailable,
              )
            : _error != null
            ? ErrorView(error: _error!, onRetry: _start)
            : (load == null || _pickingInitialCustomer)
            ? Column(
                children: [
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: EdgeInsets.all(Space.page),
                      child: DesignBackButton(),
                    ),
                  ),
                  if (!_pickingInitialCustomer) const SkeletonList(rows: 3),
                ],
              )
            : ContentReveal(child: _body(load)),
      ),
    );
  }

  Widget _kindActions(ComposeLoad load) {
    final s = load.state;
    final invoice = load.switchKinds.contains(DocKind.taxInvoice)
        ? DocKind.taxInvoice
        : DocKind.transactionInvoice;
    final paid = load.switchKinds.contains(DocKind.taxInvoiceReceipt)
        ? DocKind.taxInvoiceReceipt
        : DocKind.receipt;
    final choices = <Widget>[
      if (load.switchKinds.contains(invoice))
        SizedBox(
          width: 110,
          child: ActionOrb(
            label: ComposeHe.newInvoice,
            icon: const Icon(
              Iconsax.document_text,
              color: Color(0xFF302139),
              size: 28,
            ),
            color: DesignTokens.lavender,
            onPressed: () => s.setKind(invoice),
          ),
        ),
      if (load.switchKinds.contains(paid))
        SizedBox(
          width: 110,
          child: ActionOrb(
            label: ComposeHe.recordIncome,
            icon: const Icon(
              Iconsax.money_recive,
              color: Color(0xFF302139),
              size: 28,
            ),
            color: DesignTokens.yellow,
            onPressed: () => s.setKind(paid),
          ),
        ),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: choices,
    );
  }

  Widget _body(ComposeLoad load) {
    final s = load.state;
    final bc = businessContext;
    final needsApproval = kindNeedsApproval(
      s.kind,
      () => bc.caps.approvalNeeded(s.totalMinor),
    );
    final action = resolveAction(
      kind: s.kind,
      needsApproval: needsApproval,
      hasPhone: s.hasPhone,
      canSend: bc.can(Cap.docSend),
    );
    final policy = bc.caps.approvalPolicy;
    final note =
        action == ComposerAction.submit &&
            policy.isThreshold &&
            bc.can(Cap.docIssue)
        ? approvalNote(policy.thresholdMinor)
        : null;
    return Column(
      children: [
        OfflineBanner(visible: bc.offline),
        if (load.rejectionReason != null)
          Padding(
            padding: const EdgeInsets.all(Space.page),
            child: Text(
              '${ComposeHe.fixAndResend}: ${load.rejectionReason}',
              style: AppText.secondary.copyWith(color: context.palette.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 57),
              Expanded(
                child: CustomerChip(
                  customer: s.customer,
                  onTap: _chooseCustomer,
                ),
              ),
              const DesignBackButton(),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: Column(
              children: [
                const SizedBox(height: 20),
                AmountField(state: s),
                if (s.totalMinor == BigInt.zero) ...[
                  const SizedBox(height: 32),
                  _kindActions(load),
                  const SizedBox(height: 24),
                ],
                if (s.totalMinor > BigInt.zero)
                  SummarySection(
                    state: s,
                    onMoreDetails: () => showMoreDetailsSheet(
                      context,
                      state: s,
                      kinds: load.switchKinds,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // AT-70: keys are a fixed 64pt; past 150% the 28pt digits would not fit.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: Keypad(
            onKey: (k) {
              s.amountText = keypadApply(s.amountText, k);
              s.changed();
            },
          ),
        ),
        if (s.ready || bc.offline)
          BottomActionArea(
            note: note,
            child: PrimaryButton(
              key: const Key('compose-primary'),
              label: actionLabel(action),
              offline: bc.offline,
              loadingText: _step,
              onPressed: () => _press(action, needsApproval),
            ),
          ),
      ],
    );
  }
}
