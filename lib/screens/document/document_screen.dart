// D · מסמך (SPEC-v2 §6.D; also quotes, drafts, approvals). Owner: squad C.
// Routes: /doc/:id and /quote/:id ([isQuote] = true).
//
// Header (type + number, ⋯) → PDF preview (60% height, tap → full screen) →
// one status line (tap → timeline) → ONE primary button from [nextAction].

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/actions_api.dart';
import '../../api/client.dart';
import '../../api/documents_api.dart' show documentsVersion, notifyDocumentsChanged;
import '../../api/models/models.dart';
import '../../api/signing_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/cache.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/errors_he.dart';
import '../../util/labels/labels.dart';
import '../../util/phone.dart';
import 'dialogs.dart';
import 'document_parts.dart';
import 'next_action.dart';
import 'pdf_viewer_screen.dart';
import 'sheets/s5_payment.dart';
import 'sheets/s6_share.dart';
import 'sheets/s8_cancel.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({
    super.key,
    required this.id,
    this.isQuote = false,
    this.banner,
    this.openShare = false,
    this.justIssued = false,
  });

  final String id;
  final bool isQuote;

  /// "הופק ✓ · נשלח לדנה בווטסאפ" (the Composer passes it after issuing).
  final String? banner;

  /// "הפק" without WhatsApp → D opens S6 by itself (§6.C).
  final bool openShare;

  /// First issue on this device → the one-time commitment toast (§6.C.5).
  final bool justIssued;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

const _commitToastFlag = 'doc_commit_toast_shown';

class _DocumentScreenState extends State<DocumentScreen> {
  DocumentDetail? _doc;
  DocumentExtras _extras = DocumentExtras.empty;
  Quote? _quote;
  Customer? _customer;
  DocumentSummary? _row;
  AllocationState? _alloc;
  Uint8List? _pdf;

  /// The PDF could not be loaded (offline, server) → lines + "נסה שוב".
  bool _pdfFailed = false;

  /// The server has no stored original (ARTIFACT_REQUIRED) → rows 6 / 7.
  bool _artifactMissing = false;
  bool _triedCreate = false;
  Object? _error;
  bool _fromCache = false;
  String? _busy;
  String? _banner;
  String? _receiptId;
  bool _timeline = false;

  @override
  void initState() {
    super.initState();
    _banner = widget.banner;
    businessContext.addListener(_rebuild);
    documentsVersion.addListener(_changedElsewhere);
    _load(first: true);
  }

  @override
  void dispose() {
    businessContext.removeListener(_rebuild);
    documentsVersion.removeListener(_changedElsewhere);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _changedElsewhere() {
    if (_busy == null && mounted) unawaited(_load());
  }

  String get _cacheName => 'doc_${businessContext.business?.businessId ?? 'none'}_${widget.id}';

  Future<void>? _inFlight;
  bool _again = false;

  /// One load at a time; a request during a load runs once more after it
  /// (an action's own reload + the documentsVersion bump coalesce).
  Future<void> _load({bool first = false}) async {
    if (_inFlight != null) {
      _again = true;
      return _inFlight;
    }
    _inFlight = _loadOnce(first: first);
    try {
      await _inFlight;
      while (_again && mounted) {
        _again = false;
        await _loadOnce();
      }
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _loadOnce({bool first = false}) async {
    try {
      if (widget.isQuote) {
        final q = await fetchQuote(widget.id);
        if (q == null) throw ApiException(404, 'QUOTE_NOT_FOUND', errorMessageHe('QUOTE_NOT_FOUND'));
        final c = q.customerId == null ? null : await _customerOrNull(q.customerId!);
        if (!mounted) return;
        setState(() {
          _quote = q;
          _customer = c;
          _error = null;
          _fromCache = false;
        });
        // The quote PDF is ownOrMoney (BE-03): not asked for when hidden.
        if (quoteHasLines(q) && !q.amountHidden) unawaited(_loadQuotePdf(q.id));
      } else {
        final json = await fetchDocumentJson(widget.id);
        unawaited(AppCache.write(_cacheName, json).catchError((Object _) {})); // offline copy, best effort
        final doc = DocumentDetail.fromJson(json);
        final extras = DocumentExtras.fromJson(json);
        final results = await Future.wait<Object?>([
          if (doc.customerId != null) _customerOrNull(doc.customerId!) else Future.value(null),
          // BE-12 timeline gives sentAt; only an older server needs the list row.
          extras.hasTimeline ? Future.value(null) : _rowOrNull(doc),
          doc.status == 'WAITING_FOR_ALLOCATION' ? _allocOrNull(doc.id) : Future.value(null),
        ]);
        if (!mounted) return;
        setState(() {
          _doc = doc;
          _extras = extras;
          _customer = results[0] as Customer?;
          _row = results[1] as DocumentSummary?;
          _alloc = results[2] as AllocationState?;
          _error = null;
          _fromCache = false;
        });
        unawaited(_loadPdf(doc));
      }
    } on ApiException catch (e) {
      if (!widget.isQuote && e.isNetwork && _doc == null) {
        final cached = await AppCache.read(_cacheName);
        if (cached is Map<String, dynamic> && mounted) {
          setState(() {
            _doc = DocumentDetail.fromJson(cached);
            _extras = DocumentExtras.fromJson(cached);
            _fromCache = true;
          });
          return;
        }
      }
      if (mounted) setState(() => _error = e);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (first && mounted) _afterFirstLoad();
  }

  void _afterFirstLoad() {
    if (widget.justIssued) {
      unawaited(() async {
        if (await AppCache.read(_commitToastFlag) == true || !mounted) return;
        await AppCache.write(_commitToastFlag, true);
        if (mounted) toast(context, DocumentHe.commitToast);
      }());
    }
    if (widget.openShare && _doc != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _do(DocAction.share));
    }
  }

  Future<Customer?> _customerOrNull(String id) async {
    try {
      return await fetchCustomerById(id);
    } on ApiException {
      return null;
    }
  }

  Future<DocumentSummary?> _rowOrNull(DocumentDetail doc) async {
    try {
      return await fetchDocumentRow(doc);
    } on ApiException {
      return null;
    }
  }

  Future<AllocationState?> _allocOrNull(String id) async {
    try {
      return await fetchAllocationState(id);
    } on ApiException {
      return null;
    }
  }

  static const _withPdf = {'SIGNED', 'ARCHIVED', 'SENT', 'FINALIZED'};

  /// The original PDF. A FINALIZED document without one gets it created
  /// (§6.D edge) when the viewer may issue. Hidden amounts = the PDF is
  /// ownOrMoney for this viewer (BE-03): not asked for, so no false 403
  /// "permissions changed".
  Future<void> _loadPdf(DocumentDetail doc) async {
    if (!_withPdf.contains(doc.status) || doc.amountHidden) return;
    var missing = false;
    try {
      Uint8List bytes;
      try {
        bytes = await fetchOriginalPdf(doc.id);
      } on ApiException catch (e) {
        if (e.code != 'ARTIFACT_REQUIRED') rethrow;
        missing = true;
        // Once per screen: the create bumps documentsVersion → reload.
        if (doc.status != 'FINALIZED' || !businessContext.can(Cap.docIssue) || _triedCreate) rethrow;
        _triedCreate = true;
        await createOriginalArtifact(doc.id); // signing LOCKED → ARTIFACT_PENDING → row 6
        notifyDocumentsChanged();
        bytes = await fetchOriginalPdf(doc.id);
      }
      if (mounted) {
        setState(() {
          _pdf = bytes;
          _pdfFailed = false;
          _artifactMissing = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _pdfFailed = true;
          _artifactMissing = missing || e.code == 'ARTIFACT_REQUIRED';
        });
      }
    }
  }

  void _retryPdf() {
    final doc = _doc;
    if (doc == null) return;
    setState(() => _pdfFailed = false);
    unawaited(_loadPdf(doc));
  }

  Future<void> _loadQuotePdf(String id) async {
    try {
      final bytes = await quotePdfBytes(id);
      if (mounted) setState(() => _pdf = bytes);
    } on ApiException {
      // QuoteCard with the lines stays.
    }
  }

  // ---- what to show -----------------------------------------------------------

  DocFacts get _facts {
    final q = _quote;
    if (q != null) {
      return DocFacts(
        status: q.status,
        isQuote: true,
        totalMinor: q.totalMinor,
        customerHasPhone: waPhone(_customer?.phone) != null,
        convertedDocumentId: q.convertedDocumentId,
        quoteFull: quoteHasLines(q),
        amountHidden: q.amountHidden,
      );
    }
    final d = _doc!;
    return DocFacts(
      status: d.status,
      documentType: d.documentType,
      totalMinor: d.totalMinor,
      openMinor: _openMinor,
      creditedMinor: d.creditedMinor ?? _row?.creditedMinor,
      paidMinor: d.paidTotalMinor,
      voidedAt: d.voidedAt ?? _row?.voidedAt,
      sentAt: _extras.sentAt ?? _row?.sentAt,
      submittedBy: d.submittedBy,
      rejected: d.rejection != null,
      customerHasPhone: waPhone(_customer?.phone) != null,
      allocationDecisionAllowed: _alloc?.decisionAllowed ?? false,
      allocationNeedsAuthorization: _alloc?.needsAuthorization ?? false,
      convertedToInvoice: _extras.convertedTo != null,
      amountHidden: d.amountHidden,
      pdfMissing: _artifactMissing,
    );
  }

  BigInt? get _openMinor =>
      _doc?.amountHidden ?? false ? null : _extras.openMinor ?? _row?.openMinor ?? _doc?.openMinor;

  DocViewer get _viewer => DocViewer(
        caps: businessContext.caps,
        userId: businessContext.me?.userId,
        vatExempt: businessContext.isVatExempt,
        manualAllocationEnabled: businessContext.me?.shaam?.manualEntryEnabled ?? false,
      );

  // ---- actions ----------------------------------------------------------------

  Future<void> _guard(String busyText, Future<String?> Function() work) async {
    if (_busy != null) return;
    setState(() => _busy = busyText);
    try {
      final message = await work();
      if (!mounted) return;
      if (message != null && message.isNotEmpty) {
        HapticFeedback.mediumImpact();
        setState(() => _banner = message);
      }
      await _load();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<PassphraseAnswer?> _askPass() => askSigningPassphrase(context);

  Future<void> _do(DocAction a) async {
    final doc = _doc;
    final quote = _quote;
    final label = docActionLabel(a, hasPhone: _facts.customerHasPhone);
    switch (a) {
      case DocAction.approve:
        await _guard(label, () async {
          final out = await approveDocument(doc!, askPassphrase: _askPass);
          return out.status == 'FINALIZED' ? DocumentHe.approved : null;
        });
      case DocAction.reject:
        final reason = await askReason(context);
        if (reason == null) return;
        await _guard(label, () async {
          await rejectDocument(doc!.id, reason);
          return DocumentHe.rejected;
        });
      case DocAction.continueDraft:
        final code = docTypeCodes[doc!.documentType];
        await openCompose(context, intent: code == null ? 'REQUEST' : 'TYPE:$code', draftId: doc.id);
        if (mounted) await _load();
      case DocAction.retryAllocation:
        await _guard(label, () async {
          final s = await retryAllocation(doc!.id);
          return s.serviceNoticeHe ?? s.detailHe ?? DocumentHe.allocationRetried;
        });
      case DocAction.manualAllocation:
        final number = await askManualAllocation(context);
        if (number == null) return;
        await _guard(label, () async {
          await attachManualAllocation(doc!.id, number);
          return null;
        });
      case DocAction.continueWithoutNumber:
        await _guard(label, () async {
          await continueWithoutAllocation(doc!.id);
          return null;
        });
      case DocAction.cancelAllocation:
        await _guard(label, () async {
          await cancelAllocationRequest(doc!.id);
          return null;
        });
      case DocAction.connectTaxAuthority:
        await continueOnComputer(context, DocumentHe.connectTaxAuthority);
      case DocAction.signAndIssue:
        await _guard(label, () async {
          // ARTIFACT_PENDING is sealed; an issued document without a stored
          // original (row 6 by pdfMissing) gets it created first.
          final done = await issueSignedOriginal(doc!.id,
              askPassphrase: _askPass, alreadySealed: doc.status == 'ARTIFACT_PENDING');
          if (done && mounted && defaultTargetPlatform == TargetPlatform.iOS) {
            toast(context, DocumentHe.timelineIssued, motion: NoticeMotion.signed);
          }
          return done ? DocumentHe.timelineIssued : null;
        });
      case DocAction.sendWhatsApp:
        if (!_facts.customerHasPhone) return _openShare();
        await _guard(label, () async {
          await sendDocumentWhatsApp(doc!, _customer);
          return null;
        });
      case DocAction.send || DocAction.share:
        return _openShare();
      case DocAction.sendAgain:
        if (quote != null) return _sendQuote(label);
        return _openShare();
      case DocAction.sendReminder:
        if (!_facts.customerHasPhone) return _openShare();
        await _guard(label, () async {
          await sendDocumentWhatsApp(doc!, _customer, reminder: true);
          return null;
        });
      case DocAction.recordPayment:
        final out = await showPaymentSheet(context, documentId: doc!.id, doc: doc);
        if (out == null || !mounted) return;
        HapticFeedback.mediumImpact();
        setState(() {
          _receiptId = out.receiptId;
          _banner = out.receiptId != null ? PaymentHe.receiptIssued : PaymentHe.paymentRecorded;
        });
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          toast(context, _banner!, motion: NoticeMotion.payment);
        }
        await _load();
      case DocAction.sendQuote:
        return _sendQuote(label);
      case DocAction.convertQuote:
        String? draftId;
        await _guard(label, () async {
          draftId = await quoteToInvoice(quote!,
              vatExempt: businessContext.isVatExempt, vatRateBasisPoints: _vatRate());
          return null;
        });
        if (draftId != null && mounted) {
          await openCompose(context,
              intent: businessContext.isVatExempt ? 'TYPE:300' : 'TYPE:305',
              draftId: draftId,
              fromQuoteId: quote!.id);
        }
      case DocAction.customerRejected:
        await _guard(label, () async {
          await setQuoteStatus(quote!.id, 'REJECTED');
          return DocumentHe.markedRejected;
        });
      case DocAction.openInvoice:
        await openDocument(context, quote!.convertedDocumentId!, replace: true);
      case DocAction.issueTaxInvoice:
        String? draftId;
        await _guard(label, () async {
          draftId = await issueTaxInvoiceFrom(doc!.id);
          return null;
        });
        if (draftId != null && mounted) {
          await openCompose(context, intent: 'TYPE:305', draftId: draftId, fromDocId: doc!.id);
        }
      case DocAction.duplicate when quote != null:
        String? quoteId;
        await _guard(label, () async {
          quoteId = await duplicateQuote(quote.id);
          return null;
        });
        if (quoteId != null && mounted) await openQuote(context, quoteId!);
      case DocAction.duplicate:
        String? draftId;
        await _guard(label, () async {
          draftId = await duplicateDocument(doc!);
          return DocumentHe.duplicated;
        });
        if (draftId != null && mounted) {
          final code = docTypeCodes[doc!.documentType];
          await openCompose(context, intent: code == null ? 'REQUEST' : 'TYPE:$code', draftId: draftId);
        }
      case DocAction.cancelOrCredit:
        final out = await showCancelSheet(context, documentId: doc!.id, doc: doc);
        if (out == null || !mounted) return;
        HapticFeedback.mediumImpact();
        setState(() => _banner = out.voided ? DocumentHe.documentVoided : DocumentHe.creditIssued);
        await _load();
        final creditId = out.credit?.creditId;
        if (creditId != null && mounted) await openDocument(context, creditId);
    }
  }

  /// The business VAT rate of the source lines (convert keeps it), else 18%.
  int _vatRate() => 1800;

  Future<void> _openShare() async {
    final quote = _quote;
    if (quote != null) return _shareQuote();
    final doc = _doc;
    if (doc == null) return;
    final message = await showShareSheet(context,
        documentId: doc.id, doc: doc, customer: _customer, hasLiveLink: _extras.hasLiveShareLink);
    if (!mounted) return;
    if (message != null && message.isNotEmpty) toast(context, message, motion: NoticeMotion.sent);
    await _load();
  }

  /// "שתף" on a quote (BE-06): its PDF with the text and link, through the
  /// share sheet (no doc.send: the PDF alone).
  Future<void> _shareQuote() => _guard(DocumentHe.share, () async {
        final q = _quote!;
        final bytes = _pdf ?? await quotePdfBytes(q.id);
        String? text;
        if (businessContext.can(Cap.docSend)) text = await _quoteText(q);
        await pdfSharer(bytes, DocumentHe.quoteTitle, text: text);
        return null;
      });

  /// §8.2.4: P1 (BE-06) the text carries the quote's /d/ link; P0 header only.
  Future<String> _quoteText(Quote q) async {
    String? link;
    if (quoteHasLines(q)) {
      try {
        link = await quoteShareUrl(q.id);
      } on ApiException catch (e) {
        if (e.isNetwork) rethrow; // otherwise the P0 text still goes
      }
    }
    return quoteWhatsAppMessage(
        customerName: q.customerName ?? _customer?.name,
        totalMinor: q.totalMinor,
        validUntil: q.validUntil,
        businessName: businessContext.displayName,
        link: link);
  }

  /// Send the quote by WhatsApp (link + text), then status SENT.
  Future<void> _sendQuote(String label) => _guard(label, () async {
        final q = _quote!;
        final text = await _quoteText(q);
        final phone = waPhone(_customer?.phone);
        if (phone != null) {
          await launchAllowed(whatsAppUri(phone: phone, text: text));
        } else {
          await textSharer(text);
        }
        if (q.status == 'DRAFT') await setQuoteStatus(q.id, 'SENT');
        return null;
      });

  Future<void> _sendReceiptWhatsApp() async {
    final id = _receiptId;
    if (id == null) return;
    await _guard(PaymentHe.sendReceipt, () async {
      final receipt = await fetchDocumentDetail(id);
      await sendDocumentWhatsApp(receipt, _customer);
      return null;
    });
  }

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final quote = _quote;
    final title = quote != null
        ? DocumentHe.quoteTitle
        : doc == null
            ? (widget.isQuote ? DocumentHe.quoteTitle : '')
            : docTitle(doc.documentType, doc.documentNumber);
    if (doc == null && quote == null) {
      return Scaffold(
        appBar: context.isDark ? null : AppBar(title: Text(title)),
        body: SafeArea(
          child: Column(
            children: [
              if (context.isDark)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.m, Space.page, Space.s),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: AppText.displayTitle)),
                      const DesignBackButton(),
                    ],
                  ),
                ),
              Expanded(
                child: _error == null
                    ? const SkeletonList(rows: 4)
                    : ErrorView(error: _error!, onRetry: () {
                        setState(() => _error = null);
                        _load();
                      }),
              ),
            ],
          ),
        ),
      );
    }
    final next = nextAction(_facts, _viewer);
    final offline = _fromCache || businessContext.offline;
    return Scaffold(
      appBar: context.isDark
          ? null
          : AppBar(
              title: Text(title),
              actions: [
                MoreMenu(items: [
                  for (final a in next.menu)
                    MoreMenuItem(
                      label: docActionLabel(a, hasPhone: _facts.customerHasPhone),
                      destructive: a == DocAction.cancelOrCredit,
                      onSelected: () => _do(a),
                    ),
                ]),
              ],
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (context.isDark)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.page, Space.m, Space.page, Space.s),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppText.displayTitle,
                      ),
                    ),
                    MoreMenu(items: [
                      for (final a in next.menu)
                        MoreMenuItem(
                          label: docActionLabel(a, hasPhone: _facts.customerHasPhone),
                          destructive: a == DocAction.cancelOrCredit,
                          onSelected: () => _do(a),
                        ),
                    ]),
                    const SizedBox(width: 8),
                    const DesignBackButton(),
                  ],
                ),
              ),
            OfflineBanner(visible: offline, onRetry: _load),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Space.page),
                children: [
                  if (_banner != null)
                    DocBanner(
                      key: const Key('doc-banner'),
                      text: _banner!,
                      action: _receiptId != null && businessContext.can(Cap.docSend) ? PaymentHe.sendReceipt : null,
                      onAction: _sendReceiptWhatsApp,
                    ),
                  if (doc?.rejection != null)
                    DocBanner(
                      key: const Key('doc-rejection'),
                      text: '${DocumentHe.rejectedBecause} ${doc!.rejection!.reason}',
                      danger: true,
                    ),
                  // ADR-SHAAM-DEGRADATION: the authority is down — calm, not an error.
                  if (_alloc?.serviceNoticeHe != null && doc?.status == 'WAITING_FOR_ALLOCATION')
                    DocBanner(key: const Key('doc-allocation-service'), text: _alloc!.serviceNoticeHe!)
                  else if (_alloc?.detailHe != null && doc?.status == 'WAITING_FOR_ALLOCATION')
                    DocBanner(text: _alloc!.detailHe!, danger: true),
                  if (quote != null) _quotePreview(quote) else _preview(doc!),
                  if (doc != null) ...[
                    const SizedBox(height: Space.s),
                    DocStatusLine(
                      state: docStateOf(doc, row: _row, extras: _extras),
                      openMinor: _openMinor,
                      dueDate: doc.dueDate,
                      allocationNumber: doc.allocationNumber,
                      expanded: _timeline,
                      onTap: () => setState(() => _timeline = !_timeline),
                    ),
                    if (_timeline) ...[
                      DocTimeline(
                          entries: _extras.hasTimeline
                              ? timelineFromEvents(_extras.timeline, context: context)
                              : timelineOf(doc, row: _row, context: context)),
                      if (_extras.payments.isNotEmpty && !doc.amountHidden)
                        DocPaymentsList(payments: _extras.payments),
                      if (_extras.linked.isNotEmpty)
                        DocLinksList(links: _extras.linked, onOpen: (id) => openDocument(context, id)),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: _bottom(next, offline),
    );
  }

  Widget? _bottom(NextAction next, bool offline) {
    if (next.primary != null) {
      return BottomActionArea(
        child: PrimaryButton(
          key: const Key('doc-primary'),
          label: next.label!,
          offline: offline,
          loadingText: _busy,
          onPressed: () => _do(next.primary!),
        ),
      );
    }
    if (next.waiting != null) {
      return BottomActionArea(
        child: Text(next.waiting!,
            key: const Key('doc-waiting'),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: context.palette.muted)),
      );
    }
    return null;
  }

  /// BE-06 quote: its PDF (lines card while it loads or when it fails).
  Widget _quotePreview(Quote quote) {
    if (_pdf == null) return QuoteCard(quote: quote);
    return _pdfBox(DocumentHe.quoteTitle);
  }

  Widget _preview(DocumentDetail doc) {
    if (!_withPdf.contains(doc.status)) return DraftLinesCard(doc: doc, notes: _extras.notes);
    // No PDF to show (not ours to see, not created, or failed): the lines,
    // the customer and the total — never a blank box.
    if (doc.amountHidden || _pdfFailed) {
      return DraftLinesCard(
        doc: doc,
        notes: _extras.notes,
        customerName: _customer?.name,
        footer: doc.amountHidden
            ? ''
            : _artifactMissing
                ? DocumentHe.pdfNotCreated
                : DocumentHe.pdfLoadFailed,
        onRetry: doc.amountHidden || _artifactMissing ? null : _retryPdf,
      );
    }
    return _pdfBox(docTitle(doc.documentType, doc.documentNumber));
  }

  Widget _pdfBox(String title) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    final bytes = _pdf;
    return Semantics(
      button: bytes != null,
      label: bytes != null ? DocumentHe.pdfOpen : DocumentHe.pdfUnavailable,
      child: GestureDetector(
        key: const Key('doc-pdf'),
        onTap: bytes == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => PdfViewerScreen(bytes: bytes, title: title),
                )),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: height,
            child: bytes != null
                ? AbsorbPointer(child: pdfPreviewBuilder(bytes))
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
  }
}
