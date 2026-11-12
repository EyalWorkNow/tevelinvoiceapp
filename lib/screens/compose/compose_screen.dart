// C · Composer (SPEC-v2 §6.C, §8.1–8.2). Owner: squad B.
// Route: /compose?intent=&customerId=&fromDocId=&fromQuoteId=&draftId=
// Three decisions on the screen: customer, amount, button (J1 = 3 taps).
// The type is resolved from the intent (intent_resolver.dart) and never shown
// before issuing (F1); S3 can switch it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/customers_api.dart' show rememberRecentPaymentCustomer;
import '../../api/models/models.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/composer_config.dart';
import '../../util/intent_resolver.dart';
import '../../util/labels/labels.dart';
import '../../util/money.dart';
import '../people/sheets/s2_customer.dart';
import 'compose_dialogs.dart';
import 'compose_loader.dart';
import 'compose_memory.dart';
import 'compose_submit.dart';
import '../../router.dart' show BusinessSection, openBusinessSection;
import 'fields/allocation_hint_line.dart';
import 'fields/amount_field.dart';
import 'fields/customer_chip.dart';
import 'fields/summary_section.dart';
import 'sheets/s3_more.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// S2 (squad D). Tests replace it to simulate one tap on a recent customer.
Future<Customer?> Function(BuildContext context) pickCustomer = (c) =>
    showCustomerSheet(c);

/// S2 with recent recipients for the “received payment” flow.
Future<Customer?> Function(BuildContext context) pickPaymentCustomer = (c) =>
    showCustomerSheet(c, recentPayments: true);

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

  /// U1: the primary button appears where the keypad's bottom row was a
  /// moment ago; taps on it are ignored for [_armDelay] after it appears.
  static const _armDelay = Duration(milliseconds: 400);
  bool _armed = true;
  bool _wasReady = false;
  Timer? _armTimer;

  @override
  void initState() {
    super.initState();
    // Toasts from the previous issue would sit over the issue button and eat the first tap.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => mounted
          ? ScaffoldMessenger.maybeOf(context)?.clearNotchNotices()
          : null,
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
      _wasReady = load.state.ready;
      if (load.leftoverForm != null) {
        await _waitForEntrance();
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        await _askLeftover(load);
        if (!mounted) return;
        setState(() => _pickingInitialCustomer = load.state.customer == null);
      }
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

  /// U5: what was left here last time is offered, never restored silently.
  Future<void> _askLeftover(ComposeLoad load) async {
    final form = load.leftoverForm!;
    final customer = form['customer'];
    final resume = await askResumeDraft(
      context,
      customerName: customer is Map ? customer['name'] as String? : null,
      amountMinor: keypadToAgorot(form['amountText'] as String? ?? ''),
    );
    if (resume) {
      load.resumeLeftover();
    } else {
      await load.dropLeftover();
    }
  }

  void _changed() {
    if (!mounted) return;
    final ready = _load?.state.ready ?? false;
    if (ready && !_wasReady) {
      _armed = false;
      _armTimer?.cancel();
      _armTimer = Timer(_armDelay, () {
        if (mounted) setState(() => _armed = true);
      });
    }
    _wasReady = ready;
    setState(() {});
  }

  @override
  void dispose() {
    _armTimer?.cancel();
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
    final c = supplier
        ? await pickSupplier(context)
        : s.config.paid && s.config.counterparty == Counterparty.customer
        ? await pickPaymentCustomer(context)
        : await pickCustomer(context);
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
    if (mounted && run.pending?.stage.name == 'done') {
      _issuedOrLeft = true;
      if (load.state.kind == DocKind.receipt ||
          load.state.kind == DocKind.taxInvoiceReceipt) {
        final customer = load.state.customer;
        if (customer != null) {
          unawaited(rememberRecentPaymentCustomer(customer.id));
        }
      }
    }
  }

  /// U0: ✕ always leaves the Composer in one tap (the customer is changed
  /// from the chip). With an amount: "לשמור טיוטה?" – save (the local draft
  /// is written on dispose), discard, or stay.
  Future<void> _close() async {
    final s = _load?.state;
    if (!_issuedOrLeft && s != null && s.amountMinor > BigInt.zero) {
      FocusScope.of(context).unfocus();
      final save = await askSaveDraft(context);
      if (save == null || !mounted) return;
      if (!save) {
        _issuedOrLeft = true; // nothing to keep
        await clearLocalDraft();
        if (!mounted) return;
      }
    }
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final load = _load;
    return Scaffold(
      body: SafeArea(
        child: _unavailable || _error != null
            // U3: never a dead end – the message keeps the ✕.
            ? Column(
                children: [
                  _closeHeader(),
                  Expanded(
                    child: _unavailable
                        ? const EmptyState(
                            icon: Iconsax.forbidden_2,
                            title: ComposeHe.notAvailable,
                          )
                        : ErrorView(error: _error!, onRetry: _start),
                  ),
                ],
              )
            : (load == null || _pickingInitialCustomer)
            ? Column(
                children: [
                  _closeHeader(),
                  if (!_pickingInitialCustomer) const SkeletonList(rows: 3),
                ],
              )
            : ContentReveal(child: _body(load)),
      ),
    );
  }

  Widget _closeHeader() => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Padding(
      padding: const EdgeInsets.all(Space.page),
      child: _CloseButton(onPressed: _close),
    ),
  );

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
              _CloseButton(onPressed: _close),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            child: Column(
              children: [
                const SizedBox(height: 12),
                AmountField(state: s),
                // R7: "יקבל מספר הקצאה" / "נדרש חיבור" above the threshold only.
                if (s.totalMinor > BigInt.zero)
                  AllocationHintLine(
                    state: s,
                    onConnect: () =>
                        openBusinessSection(context, BusinessSection.shaam),
                  ),
                if (s.totalMinor == BigInt.zero) ...[
                  const SizedBox(height: 24),
                  _kindActions(load),
                  const SizedBox(height: 24),
                ],
                if (s.totalMinor > BigInt.zero)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.l),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 352),
                        child: SummarySection(
                          state: s,
                          onMoreDetails: () => showMoreDetailsSheet(
                            context,
                            state: s,
                            kinds: load.switchKinds,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!s.discountValid)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s),
                    child: Text(
                      ComposeHe.discountTooBig,
                      key: const Key('compose-discount-error'),
                      textAlign: TextAlign.center,
                      style: AppText.secondary.copyWith(
                        color: context.palette.danger,
                      ),
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
        // U1: the area is always there (empty until ready), so the keypad
        // never jumps up under the finger when the button appears.
        BottomActionArea(
          note: note,
          child: s.ready || bc.offline
              ? PrimaryButton(
                  key: const Key('compose-primary'),
                  label: actionLabel(action),
                  offline: bc.offline,
                  loadingText: _step,
                  onPressed: () {
                    if (_armed) _press(action, needsApproval);
                  },
                )
              : const _ButtonSpace(),
        ),
      ],
    );
  }
}

/// ✕ of the Composer (same control as the design back button).
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 57.303,
    child: IconButton(
      key: const Key('compose-close'),
      tooltip: CommonHe.close,
      onPressed: onPressed,
      style: IconButton.styleFrom(backgroundColor: DesignTokens.control),
      icon: Icon(Icons.close_rounded, color: context.palette.ink),
    ),
  );
}

/// The height of the primary button, empty: reserved before it appears.
class _ButtonSpace extends StatelessWidget {
  const _ButtonSpace();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Hit.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.m),
        child: Text('', style: AppText.button),
      ),
    ),
  );
}
