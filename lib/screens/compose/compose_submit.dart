// The Composer's primary button, end to end (SPEC-v2 §6.C API, §8.2, F7).
// Owner: squad B. Quote → POST /quotes (or PUT when editing, BE-06) →
// POST /quotes/:id/share-link (BE-06: the quote page + PDF) → WhatsApp /
// share → status SENT → D. Without BE-06 the text lists the lines (P0).
// Document → runIssue (evaluate, finalize, signature, payment) →
// share-link → wa.me → D with "הופק ✓ · נשלח ל… בווטסאפ".

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/commerce_api.dart';
import '../../state/caps.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/client.dart';
import '../../api/issue_api.dart';
import '../../api/models/models.dart' show Quote;
import '../../api/quotes_api.dart';
import '../../router.dart' show openDocument, openQuote;
import '../../ui/widgets/error_view.dart' show errorTextHe;
import '../business/cardcom_merchant_screen.dart'
    show CustomerPaymentPreviewScreen;
import '../../state/business_context.dart';
import '../../util/allowed_urls.dart';
import '../../util/composer_config.dart';
import '../../util/intent_resolver.dart';
import '../../util/labels/labels.dart';
import '../../util/phone.dart';
import '../../util/vat.dart';
import 'compose_dialogs.dart';
import 'compose_memory.dart';
import 'compose_state.dart';
import 'signing_unlock.dart';

/// System share sheet for text (quote to a customer without a phone). Tests
/// replace it. Throws [ShareDismissed] when the user closed the sheet.
Future<void> Function(String text) shareText = (text) async {
  final r = await SharePlus.instance.share(ShareParams(text: text));
  if (r.status == ShareResultStatus.dismissed) throw const ShareDismissed();
};

/// The share sheet was closed without sharing.
class ShareDismissed implements Exception {
  const ShareDismissed();
}

/// D after issuing (replaces C) and the auto-opened S6. Tests replace them
/// so the Composer is tested without squad C's screens.
Future<void> Function(BuildContext context, String id) openIssuedDocument =
    (c, id) => openDocument(c, id, replace: true, justIssued: true);
Future<void> Function(BuildContext context, String id) openIssuedQuote =
    (c, id) => openQuote(c, id, replace: true);
// QA 1.2: D's success state (justIssued) carries WhatsApp / copy link / "עוד";
// S6 no longer pops up over it.
Future<void> Function(BuildContext context, String id) openShareAfterIssue =
    (c, id) async {};

/// What the screen needs to run the button.
class ComposeRun {
  ComposeRun({
    required this.state,
    required this.action,
    required this.needsApproval,
    this.existingDraftId,
    this.existingDraftType,
    this.cloneFrom,
    this.cloneTotal,
    this.convertQuote,
  });

  final ComposeState state;
  ComposerAction action;
  bool needsApproval;

  /// Continue this server draft (draftId / converted quote) instead of creating one.
  String? existingDraftId;
  String? existingDraftType;

  /// QUOTE_ACCEPTED: the quote is converted on the server only when the user
  /// presses the button (opening the Composer and leaving changes nothing).
  final Quote? convertQuote;

  /// BE-08 linked conversion source (see PendingIssue.cloneFrom).
  final String? cloneFrom;
  final String? cloneTotal;

  /// A quote already created by an earlier tap (the sending failed after it),
  /// or the quote this Composer edits.
  String? quoteId;

  /// [quoteId] is edited in place: PUT /quotes/:id before sending (BE-06).
  bool editQuote = false;

  /// The issue of an earlier tap (or the saved one this Composer resumes):
  /// a retry continues it with the same keys — nothing is created twice.
  PendingIssue? pending;
}

PendingIssue _pendingFor(ComposeRun run) {
  final s = run.state;
  final c = s.config;
  final body = c.receiptOnly
      ? <String, dynamic>{
          'documentType': c.serverType,
          'customerId': s.customer!.id,
        }
      : s.requestBody();
  final old = run.pending;
  if (old != null && !old.editable) {
    return old; // numbered: finish what was issued
  }
  final p =
      old ??
      PendingIssue(
        businessId: currentBusinessId,
        body: body,
        form: const {},
        totalMinor: s.totalMinor,
        needsApproval: run.needsApproval,
        receiptOnly: c.receiptOnly,
        draftId: run.existingDraftId,
        draftType: run.existingDraftType,
        stage: run.existingDraftId == null
            ? IssueStage.start
            : IssueStage.draft,
        cloneFrom: run.existingDraftId == null ? run.cloneFrom : null,
        cloneTotal: run.cloneTotal,
      );
  p
    ..body = body
    ..form = s.toJson()
    ..payment = s.payment
    ..totalMinor = s.totalMinor
    ..needsApproval = run.needsApproval
    ..evaluate =
        s.showVat &&
        (c.kind == DocKind.taxInvoice || c.kind == DocKind.taxInvoiceReceipt)
    ..requestAllocation = s.requestAllocation;
  return run.pending = p;
}

/// Runs the button. [onStep] gets the loading text ("מפיק…", "חותם…").
/// Errors are shown as a toast; the pending issue stays for "נסה שוב".
Future<void> runCompose(
  BuildContext context,
  ComposeRun run, {
  required void Function(String? step) onStep,
}) async {
  final s = run.state;
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  if (run.action != ComposerAction.submit &&
      !s.config.isQuote &&
      s.totalMinor >= bigAmountConfirmMinor &&
      !await confirmBigAmount(context, s.totalMinor)) {
    return;
  }
  onStep(ComposeHe.stepIssuing);
  try {
    if (s.config.isQuote) {
      await _sendQuote(run, messenger);
      if (context.mounted) {
        unawaited(
          openIssuedQuote(context, run.quoteId!),
        ); // completes when D closes
      }
      return;
    }
    if (!context.mounted) return;
    await _convertQuoteFirst(run);
    if (!context.mounted) return;
    final result = await _issue(context, run, onStep);
    await clearLocalDraft();
    final id = result.document.id;
    if (result.outcome == IssueOutcome.issued) {
      await rememberDescription(s.customer?.id, s.mainDescription);
      if (s.config.paid) await rememberPaymentMethod(s.method);
    }
    // From here the document exists: nothing below may look like a failed
    // issue. A failed send says so, and D opens with S6 to share by hand.
    var sentByWhatsApp = false;
    var needsRecipient = false;
    var shareFailed = false;
    String? deliveryMessage;
    if (result.outcome == IssueOutcome.issued &&
        businessContext.can(Cap.docSend)) {
      onStep(ComposeHe.stepSending);
      try {
        final dispatch = await dispatchDocument(id);
        sentByWhatsApp = dispatch.delivered;
        needsRecipient = dispatch.needsRecipient;
        deliveryMessage = dispatch.message;
      } on ApiException catch (e) {
        if (e.status != 404) {
          deliveryMessage = ComposeHe.issuedDeliveryFailed(e.messageHe);
        }
      } on Object {
        deliveryMessage = ComposeHe.issuedShareFailed;
        shareFailed = true;
      }
    }
    if (result.outcome == IssueOutcome.issued &&
        run.action == ComposerAction.issueAndWhatsApp &&
        deliveryMessage == null) {
      onStep(ComposeHe.stepSending);
      try {
        final link = await createIssueShareLink(id);
        final text = issueWhatsAppText(
          customerName: s.customer!.name,
          typeLabel: docTypeLabel(result.document.documentType),
          number: result.document.documentNumber,
          totalMinor: result.document.totalMinor,
          link: link,
          businessName: businessContext.displayName,
        );
        final opened = await launchAllowed(
          whatsAppUri(phone: waPhone(s.customer!.phone), text: text),
        );
        if (opened) {
          deliveryMessage = ComposeHe.issuedWhatsAppOpened;
        } else {
          deliveryMessage = ComposeHe.issuedShareFailed;
          shareFailed = true;
        }
      } on Object {
        deliveryMessage = ComposeHe.issuedShareFailed;
        shareFailed = true;
      }
    }
    bool first;
    try {
      first =
          result.outcome == IssueOutcome.issued && await takeFirstIssueFlag();
    } on Object {
      first = false;
    }
    if (!context.mounted) return;
    if (result.outcome == IssueOutcome.issued &&
        s.config.after == AfterIssue.collect &&
        kDebugMode) {
      await nav.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/demo/customer-payment'),
          builder: (_) => CustomerPaymentPreviewScreen(
            businessName: businessContext.displayName,
            invoiceLabel: result.document.documentNumber == null
                ? docTypeLabel(result.document.documentType)
                : '${docTypeLabel(result.document.documentType)} · ${result.document.documentNumber}',
            amountMinor: result.document.totalMinor,
          ),
        ),
      );
      if (!context.mounted) return;
    }
    unawaited(openIssuedDocument(context, id)); // completes when D closes
    messenger.showNotchNotice(
      SnackBar(
        content: Text(
          deliveryMessage ?? _toast(result.outcome, sentByWhatsApp, s),
        ),
      ),
      motion: NoticeMotion.document,
    );
    if (first) {
      messenger.showNotchNotice(
        const SnackBar(content: Text(ComposeHe.firstIssueNote)),
      );
    }
    if (result.outcome == IssueOutcome.issued &&
        (needsRecipient ||
            shareFailed ||
            (run.action == ComposerAction.issue && deliveryMessage == null))) {
      // "הפק" → D, where S6 opens by itself (§6.C step 4).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (nav.mounted) openShareAfterIssue(nav.context, id);
      });
    }
  } on IssueCancelled {
    // The user closed a dialog; nothing to say.
  } on Object catch (e) {
    // ApiException → its Hebrew message; anything else (a platform error)
    // still gets a message instead of a silent button.
    messenger.showNotchNotice(
      SnackBar(content: Text(errorTextHe(e))),
      motion: NoticeMotion.error,
    );
  } finally {
    onStep(null);
  }
}

/// QUOTE_ACCEPTED: POST /quotes/:id/convert now, then the issue continues
/// that draft (its lines are replaced by what the Composer shows).
Future<void> _convertQuoteFirst(ComposeRun run) async {
  final quote = run.convertQuote;
  if (quote == null || run.existingDraftId != null || run.pending != null) {
    return;
  }
  final s = run.state;
  final exempt = isVatExemptBusiness(s.businessType);
  final type = exempt ? 'TRANSACTION_INVOICE' : 'TAX_INVOICE';
  run
    ..existingDraftId = await convertQuoteToInvoice(
      quote,
      documentType: type,
      taxRateBasisPoints: exempt ? 0 : s.vatBasisPoints,
    )
    ..existingDraftType = type;
}

String _toast(IssueOutcome outcome, bool sent, ComposeState s) =>
    switch (outcome) {
      IssueOutcome.issued =>
        sent ? ComposeHe.issuedSentTo(s.customer!.name) : ComposeHe.issued,
      IssueOutcome.submittedForApproval => ComposeHe.submitted,
      IssueOutcome.waitingForAllocation => ComposeHe.waitingAllocation,
      IssueOutcome.signingLocked => ComposeHe.waitingSignature,
    };

Future<IssueResult> _issue(
  BuildContext context,
  ComposeRun run,
  void Function(String? step) onStep,
) async {
  final s = run.state;
  final c = s.config;
  final customer = s.customer!;
  if (c.counterparty == Counterparty.donor && (customer.taxId ?? '').isEmpty) {
    await ApiClient.instance.patch('/customers/${customer.id}', {
      'taxId': s.donorTaxId.trim(),
    });
  }
  final p = _pendingFor(run);
  return runIssue(
    p,
    onStage: (stage) => onStep(switch (stage) {
      IssueStage.draft =>
        p.evaluate ? ComposeHe.stepAuthority : ComposeHe.stepIssuing,
      IssueStage.finalized => ComposeHe.stepSigning,
      IssueStage.artifact =>
        p.payment != null ? ComposeHe.stepPayment : ComposeHe.stepPdf,
      _ => ComposeHe.stepIssuing,
    }),
    unlockSigning: () => ensureSigningUnlocked(context),
    askVatStatus: (reason) => askVatDealer(
      context,
      customerName: customer.name,
      needsNumber:
          reason == 'CUSTOMER_VAT_NUMBER_MISSING' ||
          (customer.taxId ?? '').isEmpty,
    ),
  );
}

Future<void> _sendQuote(
  ComposeRun run,
  ScaffoldMessengerState messenger,
) async {
  final s = run.state;
  final customer = s.customer!;
  if (run.quoteId == null) {
    run.quoteId = await createQuote(
      customerId: customer.id,
      lines: s.quoteLines,
      validUntil: s.validUntil,
      notes: s.notes,
    );
  } else if (run.editQuote) {
    await updateQuote(
      run.quoteId!,
      customerId: customer.id,
      lines: s.quoteLines,
      validUntil: s.validUntil,
      notes: s.notes,
    );
  }
  String? link;
  try {
    link = await createQuoteShareLink(run.quoteId!);
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    link = null; // a server without BE-06: the P0 text with the lines
  }
  final text = link != null
      ? quoteLinkWhatsAppText(
          customerName: customer.name,
          totalMinor: s.totalMinor,
          validUntil: formatDateHe(s.validUntil),
          link: link,
          businessName: businessContext.displayName,
        )
      : quoteWhatsAppText(
          customerName: customer.name,
          lines: [
            for (final l in s.requestLines)
              (
                l['description'] as String,
                calculateLine(
                  quantityMicros: BigInt.parse(l['quantityMicros'] as String),
                  unitPriceMinor: BigInt.parse(l['unitPriceMinor'] as String),
                  discountMinor: BigInt.tryParse(
                    l['discountMinor'] as String? ?? '',
                  ),
                  taxRateBasisPoints: l['taxRateBasisPoints'] as int,
                ).totalMinor,
              ),
          ],
          totalMinor: s.totalMinor,
          validUntil: formatDateHe(s.validUntil),
          businessName: businessContext.displayName,
        );
  // SENT only when it really left: WhatsApp opened / the share sheet shared.
  var sent = false;
  try {
    if (run.action == ComposerAction.sendQuoteWhatsApp) {
      sent = await launchAllowed(
        whatsAppUri(phone: waPhone(customer.phone), text: text),
      );
    } else {
      await shareText(text);
      sent = true;
    }
  } on Object {
    sent = false; // dismissed or failed: the quote stays as it is
  }
  if (sent) await setQuoteStatus(run.quoteId!, 'SENT');
  messenger.showNotchNotice(
    SnackBar(
      content: Text(sent ? ComposeHe.quoteSent : ComposeHe.quoteNotSent),
    ),
    motion: sent ? NoticeMotion.sent : NoticeMotion.error,
  );
}
