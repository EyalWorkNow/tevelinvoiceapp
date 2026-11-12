// What the Composer opens with (SPEC-v2 §6.C entry): the intent's kind, the
// VAT rate, the customer, and a prefill from a draft (`draftId`, also the
// UNFINISHED / MY_REJECTED "המשך"/"תקן"), a duplicate (`fromDocId`, §8.2.9;
// also TAX_INVOICE_DUE: TYPE:305 + the paid 300) or a quote converted to an
// invoice draft (`fromQuoteId`, §8.2.4: SENT → ACCEPTED → convert).
// P1: intent QUOTE + `fromQuoteId` = edit that quote (BE-06 PUT, DRAFT/SENT)
// or a prefilled copy of it (any other status); TYPE:305 + `fromDocId` of an
// issued 300/100 = BE-08 linked conversion (TAX_INVOICE_DUE); the due date
// comes from the customer's terms (BE-07/BE-09); 500 picks a supplier.
// Owner: squad B.

import '../../api/client.dart' show ApiException;
import '../../api/customers_api.dart' show fetchCustomerDetail;
import '../../api/issue_api.dart';
import '../../api/models/models.dart';
import '../../api/quotes_api.dart';
import '../../api/suppliers_api.dart' show fetchSupplier;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../util/composer_config.dart';
import '../../util/intent_resolver.dart';
import 'compose_memory.dart';
import 'compose_state.dart';
import 'compose_submit.dart';

class ComposeLoad {
  ComposeLoad(this.state, {required this.switchKinds});

  final ComposeState state;

  /// S3 type list (empty for a quote).
  final List<DocKind> switchKinds;
  String? existingDraftId;
  String? existingDraftType;

  /// "תקן ושלח שוב": the approver's reason (BE-37).
  String? rejectionReason;

  /// BE-06: the quote this Composer edits (PUT instead of POST /quotes).
  String? editQuoteId;

  /// BE-08: the issued 300/100 this 305 is a linked conversion of.
  String? cloneFrom;
  String? cloneTotal;

  /// QUOTE_ACCEPTED: converted on the server only when the button is pressed.
  Quote? convertQuote;

  /// What was left here unsent last time (local draft, or an issue that
  /// stopped before the server had a draft). Not applied: the screen asks
  /// "המשך טיוטה?" first ([resumeLeftover] / [dropLeftover]).
  Map<String, dynamic>? leftoverForm;
  PendingIssue? leftoverIssue;

  void resumeLeftover() {
    final form = leftoverForm;
    if (form == null) return;
    final kind = state.kind;
    state.restore(form);
    final pending = leftoverIssue;
    if (pending != null) {
      resume(pending);
    } else {
      state.setKind(kind); // a local draft keeps the intent's kind
    }
    leftoverForm = null;
    leftoverIssue = null;
  }

  Future<void> dropLeftover() async {
    final pending = leftoverIssue;
    leftoverForm = null;
    leftoverIssue = null;
    if (pending == null) return clearLocalDraft();
    // A POST that may have reached the server keeps its journal (the next
    // issue adopts that draft instead of making a second one).
    if (pending.createAttemptTotal == null) await clearPendingIssue(pending.businessId);
  }

  ComposeRun? _run;

  /// The run of the primary button; one per screen, so a retry keeps its keys.
  ComposeRun run({required ComposerAction action, required bool needsApproval}) {
    final r = _run ??= ComposeRun(
        state: state,
        action: action,
        needsApproval: needsApproval,
        existingDraftId: existingDraftId,
        existingDraftType: existingDraftType,
        cloneFrom: cloneFrom,
        cloneTotal: cloneTotal,
        convertQuote: convertQuote)
      ..quoteId ??= editQuoteId
      ..editQuote = editQuoteId != null;
    r
      ..action = action
      ..needsApproval = needsApproval;
    return r;
  }

  void resume(PendingIssue pending) => (_run ??= ComposeRun(
          state: state,
          action: ComposerAction.issue,
          needsApproval: pending.needsApproval,
          existingDraftId: existingDraftId,
          existingDraftType: existingDraftType))
      .pending = pending;
}

/// Null when the intent cannot be served for this business / user.
Future<ComposeLoad?> loadComposer({
  required String intent,
  String? customerId,
  String? fromDocId,
  String? fromQuoteId,
  String? draftId,
}) async {
  final bc = businessContext;
  final bt = bc.businessType;
  final caps = bc.caps;
  final section46 = (bc.profile?.section46ApprovalNumber ?? '').isNotEmpty;
  final kind = resolveIntent(intent, bt,
      section46: section46, canRecordPayment: caps.can(Cap.paymentRecord));
  if (kind == null || !kindAllowedForCaps(kind, caps, supplierPicker: true)) return null;

  final vat = await fetchVatRate();
  final s = ComposeState(kind: kind, businessType: bt, vatBasisPoints: vat)
    ..method = await lastPaymentMethod();
  final load = ComposeLoad(s,
      switchKinds: kind == DocKind.quote
          ? const []
          : {
              kind,
              // The chip holds a customer or a supplier: never switch across.
              for (final k in moreKinds(bt, caps, section46: section46, supplierPicker: true))
                if ((configFor(k).counterparty == Counterparty.supplier) ==
                    (configFor(kind).counterparty == Counterparty.supplier))
                  k
            }.toList());

  final sourceId = draftId ?? fromDocId;
  if (fromQuoteId != null && kind == DocKind.quote) {
    await _prefillQuote(load, fromQuoteId);
  } else if (fromQuoteId != null && draftId == null) {
    // QUOTE_ACCEPTED: prefill from the quote; the server converts it only
    // when the user issues (backing out leaves the quote as it was).
    final quote = await fetchQuote(fromQuoteId);
    if (quote == null) throw StateError('quote $fromQuoteId not found');
    final converted = quote.status == 'CONVERTED' && quote.convertedDocumentId != null;
    if (converted) {
      await _prefill(load, quote.convertedDocumentId!, asDraft: true);
    } else {
      if (!quote.amountHidden) s.loadQuoteLines(quote.lines);
      s.notes = quote.notes ?? '';
      if (quote.customerId != null) s.customer = await findCustomer(quote.customerId!);
      load.convertQuote = quote;
    }
  } else if (sourceId != null) {
    final pending = await loadPendingIssue();
    if (draftId != null && pending != null && pending.draftId == draftId) {
      s.restore(pending.form);
      load
        ..existingDraftId = draftId
        ..existingDraftType = pending.draftType
        ..resume(pending);
    } else {
      final doc = await _prefill(load, sourceId, asDraft: draftId != null);
      if (fromDocId != null) {
        s.setKind(kind); // duplicate / 300 → 305 keeps the intent's kind
        if (_linkedConversion(doc, kind) && !doc.amountHidden) {
          load
            ..cloneFrom = doc.id
            ..cloneTotal = doc.totalMinor.toString();
        }
      }
    }
  } else if (customerId == null) {
    // UNFINISHED without a server draft: the local issue journal; otherwise
    // the local draft. Both wait for "המשך טיוטה?" on the screen.
    final pending = await loadPendingIssue();
    if (pending != null &&
        pending.draftId == null &&
        pending.businessId == currentBusinessId &&
        pending.form.isNotEmpty) {
      load
        ..leftoverForm = pending.form
        ..leftoverIssue = pending;
    } else {
      load.leftoverForm = await loadLocalDraft(intent);
    }
  }
  if (customerId != null) s.customer = await findCustomer(customerId) ?? s.customer;
  if (s.customer != null && s.description.isEmpty) {
    s.description = await defaultDescription(s.customer!.id,
        lastOnServer: s.customer!.lastLineDescription,
        businessDefault: bc.profile?.defaultLineDescription);
  }
  await applyCustomerTerms(s);
  return load;
}

/// BE-08: an issued 300 / 100 turned into a 305 (TAX_INVOICE_DUE "הפק",
/// §8.2.3) keeps the CONVERTED_FROM link.
bool _linkedConversion(DocumentDetail source, DocKind target) =>
    target == DocKind.taxInvoice &&
    (source.documentType == 'TRANSACTION_INVOICE' || source.documentType == 'SALES_ORDER') &&
    !source.isDraft &&
    source.documentNumber != null;

/// F8 / BE-07: the customer's payment terms (GET /customers/:id, BE-09) for
/// the due date of a collect kind; unknown → שוטף+30. Best effort: never
/// fails the Composer; a date the user picked still wins ([pickedDueDate]).
Future<void> applyCustomerTerms(ComposeState s) async {
  final c = s.customer;
  String? terms;
  if (c != null && s.config.counterparty != Counterparty.supplier) {
    try {
      terms = (await fetchCustomerDetail(c.id)).paymentTerms;
    } on Object {
      terms = null;
    }
  }
  if (s.customer?.id != c?.id) return; // another customer was chosen meanwhile
  s
    ..customerTerms = terms
    ..changed();
}

Future<DocumentDetail> _prefill(ComposeLoad load, String documentId, {required bool asDraft}) async {
  final s = load.state;
  final doc = await fetchDocument(documentId);
  final docKind = kindForServerType(doc.documentType);
  if (docKind != null && configFor(docKind).viaComposer) s.kind = docKind;
  // BE-03 hidden amounts: the lines are all ₪0 – start without them.
  if (!doc.amountHidden) s.loadLines(doc.lines);
  s.notes = doc.notes ?? '';
  if (doc.supplierId != null) {
    s.customer = await _supplierAsCustomer(doc.supplierId!);
  } else if (doc.customerId != null) {
    s.customer = await findCustomer(doc.customerId!);
  }
  if (asDraft) {
    s.pickedDueDate = doc.dueDate;
    load
      ..existingDraftId = doc.id
      ..existingDraftType = doc.documentType
      ..rejectionReason = doc.rejection?.reason;
  }
  return doc;
}

/// BE-06: GET /quotes/:id → the Composer. DRAFT / SENT are edited in place
/// (PUT); any other status becomes a new quote with the same content.
Future<void> _prefillQuote(ComposeLoad load, String quoteId) async {
  final s = load.state;
  final q = await fetchQuote(quoteId);
  if (q == null) throw StateError('quote $quoteId not found');
  // BE-03 hidden amounts: never load ₪0 prices, never PUT them over the quote.
  if (!q.amountHidden) s.loadQuoteLines(q.lines);
  s.notes = q.notes ?? '';
  if (q.customerId != null) s.customer = await findCustomer(q.customerId!);
  if (q.editable && q.detailed && !q.amountHidden) {
    load.editQuoteId = q.id;
    if (q.validUntil != null) s.validUntil = q.validUntil!;
  }
}

/// A supplier shown in the customer chip (500 sends `supplierId`).
Customer supplierAsCustomer(Supplier x) =>
    Customer(id: x.id, name: x.name, taxId: x.taxId, email: x.email, phone: x.phone);

Future<Customer?> _supplierAsCustomer(String id) async {
  try {
    return supplierAsCustomer(await fetchSupplier(id));
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return null;
  }
}
