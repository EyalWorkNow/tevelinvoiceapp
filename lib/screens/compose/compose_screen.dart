// C · Composer (SPEC-v2 §6.C, §8.1–8.2). Owner: squad B.
// Route: /compose?intent=&customerId=&fromDocId=&fromQuoteId=&draftId=
// Three decisions on the screen: customer, amount, button (J1 = 3 taps).
// The type is resolved from the intent (intent_resolver.dart) and never shown
// before issuing (F1); S3 can switch it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../app_shell.dart' show AppTab, currentTab;
import '../../ui/widgets/notch_notice.dart';
import '../../api/customers_api.dart'
    show rememberRecentPaymentCustomer, updateCustomer;
import '../../api/issue_api.dart' show IssueStage;
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
import 'compose_state.dart';
import 'compose_memory.dart';
import 'compose_repeat.dart';
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
    showCustomerSheet(c, openExistingCard: false);

/// S2 with recent recipients for the “received payment” flow.
Future<Customer?> Function(BuildContext context) pickPaymentCustomer = (c) =>
    showCustomerSheet(c, recentPayments: true, openExistingCard: false);

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
    this.prefillAmountMinor,
    this.prefillDescription,
    this.prefillNotes,
    this.onIssued,
  });

  final String intent;
  final String? customerId;
  final String? fromDocId;
  final String? fromQuoteId;
  final String? draftId;

  /// C1 "הפק קבלה" from a debt-book entry: the amount and the note to start
  /// with, and the issued document's id once it is issued (closes the entry).
  final BigInt? prefillAmountMinor;
  final String? prefillDescription;

  /// בקשת תשלום → "עריכה מתקדמת": the note to the customer typed there.
  final String? prefillNotes;
  final ValueChanged<String>? onIssued;

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

  /// The fixed keypad steps aside while the user works below the amount
  /// (scrolls the card, picks צ'ק): owner/037, owner/040. A tap on the
  /// amount, or "הצג מקלדת", brings it back.
  bool _keypadAway = false;
  String? _lastMethod;
  bool _lastSplit = false;
  bool _markingDealer = false;

  /// C3 "כמו בפעם הקודמת" for the chosen customer (null: nothing to repeat).
  RepeatTemplate? _repeat;
  String? _repeatFor;

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
      if (!mounted) return;
      if (load == null) return setState(() => _unavailable = true);
      _applyPrefill(load.state);
      load.state.addListener(_changed);
      _lastMethod = load.state.method;
      setState(() {
        _load = load;
        _pickingInitialCustomer = load.state.customer == null;
      });
      _wasReady = load.state.ready;
      if (load.leftoverForm != null) {
        await _waitForEntrance();
        if (!await _untilCurrent()) return;
        await _askLeftover(load);
        if (!mounted) return;
        setState(() => _pickingInitialCustomer = load.state.customer == null);
      }
      if (load.state.customer == null) {
        await _waitForEntrance();
        if (!await _untilCurrent()) return;

        final chosen = await _chooseCustomer();
        if (!mounted) return;
        if (chosen == null || load.state.customer == null) {
          // Keep the amount screen hidden throughout both reverse transitions.
          if (ModalRoute.of(context)?.isCurrent == true) {
            _returnHome();
          }
          return;
        }
        setState(() => _pickingInitialCustomer = false);
      }
      unawaited(_findRepeat());
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _applyPrefill(ComposeState s) {
    final amount = widget.prefillAmountMinor;
    if (amount != null && amount > BigInt.zero) {
      s.amountText = agorotToKeypadText(amount);
    }
    final description = widget.prefillDescription?.trim() ?? '';
    if (description.isNotEmpty) {
      s.description = description;
      s.descriptionTouched = true;
    }
    final notes = widget.prefillNotes?.trim() ?? '';
    if (notes.isNotEmpty) s.notes = notes;
  }

  /// True once this Composer is the top route again (a dialog or screen
  /// opened over it while it loaded closes first); false when it was popped.
  /// Returning early instead left an endless skeleton (QA 2026-11-15).
  Future<bool> _untilCurrent() async {
    final route = ModalRoute.of(context);
    while (mounted && route != null && route.isActive) {
      if (route.isCurrent) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
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
    final method = _load?.state.method;
    if (method == 'CHECK' && _lastMethod != null && _lastMethod != 'CHECK') {
      _keypadAway = true; // four cheque fields need the room
    }
    _lastMethod = method;
    final split = _load?.state.split ?? false;
    if (split && !_lastSplit) _keypadAway = true; // the lines need the room
    _lastSplit = split;
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
    if (!s.methodTouched) s.method = await lastPaymentMethod(c.id);
    if (!s.descriptionTouched) {
      s.description = defaultDescription(
        businessDefault: businessContext.profile?.defaultLineDescription,
      );
    }
    s.suggestedDescription = await suggestedDescription(c);
    s.changed();
    await applyCustomerTerms(s, preferMethod: !s.methodTouched);
    unawaited(_findRepeat());
    return c;
  }

  /// C3: what was issued last for the customer (device memory, else the
  /// server). Best effort: no chip on any failure.
  Future<void> _findRepeat() async {
    final s = _load?.state;
    final id = s?.customer?.id;
    if (s == null ||
        id == null ||
        s.config.isQuote ||
        s.config.counterparty != Counterparty.customer) {
      return;
    }
    if (_repeatFor == id) return;
    _repeatFor = id;
    RepeatTemplate? t;
    try {
      t = await findRepeat(
        id,
        businessType: s.businessType,
        vatBasisPoints: s.vatBasisPoints,
      );
    } on Object {
      t = null;
    }
    if (!mounted || s.customer?.id != id) return;
    setState(() => _repeat = t);
  }

  void _applyRepeat() {
    final t = _repeat;
    final load = _load;
    if (t == null || load == null) return;
    applyRepeat(load.state, t);
    setState(() => _repeat = null);
  }

  /// "סמן כעוסק מורשה" under the amount: the customer's status is saved on
  /// the server, so the allocation line (and the issue flow) know it.
  Future<void> _markDealer() async {
    final s = _load!.state;
    final c = s.customer;
    if (c == null || _markingDealer) return;
    setState(() => _markingDealer = true);
    try {
      await updateCustomer(c.id, {'vatDealerStatus': 'AUTHORIZED_DEALER'});
      if (!mounted) return;
      s.customer = c.copyWith(vatDealerStatus: 'AUTHORIZED_DEALER');
      s.changed();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _markingDealer = false);
    }
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
    final stage = run.pending?.stage;
    // The document exists on the server once it was submitted for approval
    // or parked waiting for its allocation number: leaving C then must not
    // keep a local draft of it ("המשך טיוטה" would offer to issue it again).
    if (mounted &&
        stage != null &&
        stage.index >= IssueStage.submitted.index &&
        stage != IssueStage.done) {
      _issuedOrLeft = true;
    }
    if (stage == IssueStage.done && run.pending?.draftId != null) {
      widget.onIssued?.call(run.pending!.draftId!);
    }
    if (mounted && stage == IssueStage.done) {
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
        // Walkthrough #4: also an issue attempt's journal + server draft.
        await _load!.discardUnfinished();
        if (!mounted) return;
      }
    }
    await Navigator.of(context).maybePop();
  }

  void _returnHome() {
    if (!mounted) return;
    currentTab.value = AppTab.home;
    Navigator.of(context).popUntil((route) => route.isFirst);
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
    // בקשת תשלום (REQUEST) is a 300 for every business type: its orb is the
    // 300 even where the business also issues a 305.
    final invoice =
        widget.intent != intentRequest &&
            load.switchKinds.contains(DocKind.taxInvoice)
        ? DocKind.taxInvoice
        : DocKind.transactionInvoice;
    final paid = load.switchKinds.contains(DocKind.taxInvoiceReceipt)
        ? DocKind.taxInvoiceReceipt
        : DocKind.receipt;
    Widget choice(
      DocKind kind,
      String label,
      IconData icon,
      Color color,
      String key,
    ) {
      final selected = s.kind == kind;
      return Semantics(
        selected: selected,
        child: Container(
          key: Key(key),
          width: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: selected ? context.palette.ink : Colors.transparent,
              width: 2,
            ),
          ),
          child: ActionOrb(
            label: label,
            icon: Icon(icon, color: const Color(0xFF302139), size: 28),
            color: color,
            onPressed: () => s.setKind(kind),
          ),
        ),
      );
    }

    // עוסק פטור / עמותה: the plain words "בקשת תשלום" / "קבלה" (A5).
    final exempt = invoice == DocKind.transactionInvoice;
    final choices = <Widget>[
      if (load.switchKinds.contains(invoice))
        choice(
          invoice,
          exempt ? ComposeHe.requestChoice : ComposeHe.newInvoice,
          Iconsax.document_text,
          DesignTokens.lavender,
          'compose-kind-request',
        ),
      if (load.switchKinds.contains(paid))
        choice(
          paid,
          paid == DocKind.receipt
              ? ComposeHe.receiptChoice
              : ComposeHe.recordIncome,
          Iconsax.money_recive,
          DesignTokens.yellow,
          'compose-kind-paid',
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
      () => bc.caps.approvalNeeded(s.totalMinor, paid: s.config.paid),
      cappedReceipts: bc.caps.isCashier,
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
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              // Scrolling on to the card below: the keypad steps aside.
              if (n.direction == ScrollDirection.reverse &&
                  !_keypadAway &&
                  s.amountMinor > BigInt.zero) {
                setState(() => _keypadAway = true);
              }
              return false;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  AmountField(
                    state: s,
                    // Walkthrough #5: which document this is, at all times
                    // (at ₪0 the two big choices below say it); a tap
                    // switches it (S3) when there is a choice.
                    header:
                        s.totalMinor > BigInt.zero ||
                            load.switchKinds.length < 2
                        ? KindPill(
                            label: kindChipLabel(s.kind),
                            onTap: load.switchKinds.length > 1
                                ? () => showMoreDetailsSheet(
                                    context,
                                    state: s,
                                    kinds: load.switchKinds,
                                  )
                                : null,
                          )
                        : null,
                    onTap: _keypadAway
                        ? () => setState(() => _keypadAway = false)
                        : null,
                  ),
                  // R7: "יקבל מספר הקצאה" / "נדרש חיבור" above the threshold
                  // only; "אם הלקוח עוסק מורשה…" when the status is unknown.
                  if (s.totalMinor > BigInt.zero)
                    AllocationHintLine(
                      state: s,
                      onConnect: () =>
                          openBusinessSection(context, BusinessSection.shaam),
                      onMarkDealer: _markingDealer || bc.offline
                          ? null
                          : _markDealer,
                    ),
                  if (s.totalMinor == BigInt.zero) ...[
                    if (_repeat != null &&
                        _repeatFor == s.customer?.id &&
                        !s.config.isQuote)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.l),
                        child: FilledButton.tonalIcon(
                          key: const Key('compose-repeat'),
                          onPressed: _applyRepeat,
                          icon: const Icon(Iconsax.repeat, size: 19),
                          label: Text(
                            ComposeHe.repeatLastAmount(_repeat!.totalMinor),
                          ),
                        ),
                      ),
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
                            allowSplit: !bc.caps.isCashier,
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
        ),
        // The system keyboard (cheque fields, description) covers the same
        // place: never both.
        if (_keypadAway || MediaQuery.viewInsetsOf(context).bottom > 0)
          (MediaQuery.viewInsetsOf(context).bottom > 0)
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: TextButton.icon(
                    key: const Key('compose-show-keypad'),
                    onPressed: () => setState(() => _keypadAway = false),
                    icon: const Icon(Iconsax.keyboard, size: 18),
                    label: const Text(ComposeHe.showKeypad),
                  ),
                )
        else
          // AT-70: keys are a fixed 64pt; past 150% the 28pt digits would not fit.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Keypad(
              onKey: (k) {
                s.amountText = keypadApply(s.amountText, k);
                s.changed();
              },
              // Walkthrough #7: what is under the keys (payment chips,
              // "פרטים נוספים") is one visible tap away once there is an
              // amount; the row is always there so the keys never move.
              onDone: () => setState(() => _keypadAway = true),
              doneLabel: s.amountMinor > BigInt.zero
                  ? ComposeHe.hideKeypad
                  : null,
            ),
          ),
        // U1: the area is always there (empty until ready), so the keypad
        // never jumps up under the finger when the button appears.
        BottomActionArea(
          note: note,
          child: s.ready || bc.offline
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PrimaryButton(
                      key: const Key('compose-primary'),
                      label: composerActionLabel(action, s.kind),
                      offline: bc.offline,
                      loadingText: _step,
                      onPressed: () {
                        if (_armed) _press(action, needsApproval);
                      },
                    ),
                    // Owner feedback 2026-11-16: a quote can be saved (and
                    // previewed / edited in D) before it goes to the customer.
                    if (s.config.isQuote && action != ComposerAction.saveQuote)
                      TextButton(
                        key: const Key('compose-save-quote'),
                        onPressed: bc.offline || _step != null
                            ? null
                            : () {
                                if (_armed) {
                                  _press(
                                    ComposerAction.saveQuote,
                                    needsApproval,
                                  );
                                }
                              },
                        child: Text(actionLabel(ComposerAction.saveQuote)),
                      ),
                  ],
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
