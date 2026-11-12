// The Composer's issue sequence (SPEC-v2 §6.C API, §8.2). Owner: squad B.
//
//   POST /documents → (VAT business, 305/320) POST /allocation/evaluate
//   [REQUIRES_USER_INPUT → ask "עוסק מורשה?" → PATCH /customers/:id → evaluate]
//   → POST /finalize [Idempotency-Key] (APPROVAL_REQUIRED → POST /submit)
//   → POST /artifact (signing:'LOCKED' → Face ID → POST /settings/signing/unlock
//   → POST /documents/:id/sign) → PAID 320: POST /payments [key] +
//   POST /documents/:id/payments.
//   400/405 (receipt only): POST /payments [key] → POST /receipts [key] → artifact.
//   300/100 → 305 (TAX_INVOICE_DUE, §8.2.3): the draft is made by BE-08
//   POST /documents/:source/clone {documentType, link:true} and then PUT with
//   the Composer's content; the server writes CONVERTED_FROM on finalize.
//
// Every step is persisted in AppCache, so a retry — even after the app was
// killed — continues where it stopped and never creates a second document
// ("שום דבר לא ייווצר פעמיים"). Credit, approve and S5 receipts live in
// actions_api.dart (squad C).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../state/cache.dart';
import '../state/session.dart';
import '../util/composer_config.dart' show isPaidServerType;
import 'client.dart';
import 'documents_api.dart' show fetchDocument, notifyDocumentsChanged;
import 'models/models.dart';

export 'documents_api.dart' show fetchDocument;

final ApiClient _api = ApiClient.instance;

/// Draft (non-numbered) preview PDF with a "דוגמה" watermark.
Future<Uint8List> previewPdf(Map<String, dynamic> draftBody) =>
    _api.postBytes('/documents/preview', draftBody, accept: 'application/pdf');

// ---------------------------------------------------------------------------
// Callbacks the UI provides
// ---------------------------------------------------------------------------

/// `signing:'LOCKED'`: Face ID → Keychain passphrase → POST
/// /settings/signing/unlock (squad C signing_api). True when the session is
/// unlocked now; false = the user cancelled.
typedef SigningUnlocker = Future<bool> Function();

/// Answer of the "{לקוח} הוא עוסק מורשה?" dialog (§4.9).
class VatStatusAnswer {
  const VatStatusAnswer({required this.authorizedDealer, this.taxId});

  final bool authorizedDealer;
  final String? taxId;
}

/// Evaluate said REQUIRES_USER_INPUT. [reasonCode]: CUSTOMER_VAT_STATUS_UNKNOWN
/// | CUSTOMER_VAT_NUMBER_MISSING. Null = the user closed the dialog.
typedef VatStatusAsker = Future<VatStatusAnswer?> Function(String reasonCode);

/// The user closed a dialog the sequence needed. The pending issue stays.
class IssueCancelled implements Exception {
  const IssueCancelled();
}

enum IssueOutcome {
  issued,
  submittedForApproval,
  waitingForAllocation,
  signingLocked,
}

class IssueResult {
  const IssueResult(this.outcome, this.document);
  final IssueOutcome outcome;
  final DocumentDetail document;
}

// ---------------------------------------------------------------------------
// Single calls (also used by D / H "המשך")
// ---------------------------------------------------------------------------

/// 'default' when configured, else the first scope from GET /sequences.
/// Remembered per business for the app run (one round-trip less per issue);
/// a refused finalize/receipt forgets it, so a removed scope is re-read.
Future<String> resolveScopeKey() async {
  final business = currentBusinessId;
  final known = _scopeKeys[business];
  if (known != null) return known;
  final json = await _api.get('/sequences');
  final list = [
    for (final s in (json['sequences'] as List? ?? const []))
      (s as Map<String, dynamic>)['numbering_scope_key'] as String,
  ];
  final key = list.isEmpty || list.contains('default') ? 'default' : list.first;
  return _scopeKeys[business] = key;
}

final Map<String, String> _scopeKeys = {};

void _forgetScopeKeyOn(ApiException e) {
  if (!e.isNetwork) _scopeKeys.clear();
}

@visibleForTesting
void resetScopeKeyCache() => _scopeKeys.clear();

/// POST /documents/:id/sign (the original exists). Throws SIGNING_LOCKED
/// while the business signing session is locked.
Future<void> _sign(String id) async {
  try {
    await _api.post('/documents/$id/sign');
  } on ApiException catch (e) {
    if (e.code != 'DOCUMENT_ALREADY_SIGNED') rethrow;
  }
}

/// POST /documents/:id/allocation/evaluate → {state, evaluation:{reasonCode…}}.
Future<Map<String, dynamic>> evaluateAllocation(String id) =>
    _api.post('/documents/$id/allocation/evaluate', const {});

/// POST /documents/:id/share-link → public /d/:token URL (needs the original).
Future<String> createIssueShareLink(String id) async {
  Map<String, dynamic> json;
  try {
    json = await _api.post('/documents/$id/share-link');
  } on ApiException catch (e) {
    if (e.code != 'ARTIFACT_REQUIRED') rethrow;
    await _createArtifact(id);
    json = await _api.post('/documents/$id/share-link');
  }
  return json['url'] as String;
}

/// Continues the saved issue of [documentId] (UNFINISHED card, D "המשך",
/// after an allocation number or a signature arrived). Null when nothing is
/// saved for it.
Future<IssueResult?> resumeIssueFor(
  String documentId, {
  SigningUnlocker? unlockSigning,
  bool skipPayment = false,
}) async {
  final p = await loadPendingIssue();
  if (p == null || p.draftId != documentId) return null;
  if (skipPayment) p.payment = null;
  return runIssue(p, unlockSigning: unlockSigning);
}

/// V1 name kept for callers of the allocation flow.
Future<IssueResult?> resumeAfterAllocation(
  String documentId, {
  bool skipPayment = false,
}) => resumeIssueFor(documentId, skipPayment: skipPayment);

// ---------------------------------------------------------------------------
// The sequence
// ---------------------------------------------------------------------------

/// Runs (or resumes) [p] to the end. [onStage] reports progress for the UI.
/// Throws ApiException / [IssueCancelled]; [p] stays saved so the same call
/// can be retried.
Future<IssueResult> runIssue(
  PendingIssue p, {
  void Function(IssueStage stage)? onStage,
  SigningUnlocker? unlockSigning,
  VatStatusAsker? askVatStatus,
}) async {
  try {
    return p.receiptOnly
        ? await _runReceipt(p, onStage, unlockSigning)
        : await _runDocument(p, onStage, unlockSigning, askVatStatus);
  } finally {
    notifyDocumentsChanged(); // lists refresh whether it finished or stopped midway
  }
}

Future<IssueResult> _runDocument(
  PendingIssue p,
  void Function(IssueStage)? onStage,
  SigningUnlocker? unlock,
  VatStatusAsker? askVat,
) async {
  void report() => onStage?.call(p.stage);
  Future<void> save() => savePendingIssue(p);

  await _ensureDraft(p);
  final id = p.draftId!;
  report();

  // Approval policy (§4.8): submit instead of finalize.
  if (p.stage == IssueStage.draft && p.needsApproval) return _submitResult(p);
  if (p.stage == IssueStage.submitted) {
    return IssueResult(
      IssueOutcome.submittedForApproval,
      await fetchDocument(id),
    );
  }

  if (p.stage == IssueStage.draft) {
    // §4.9: the server decides the allocation; unknown dealer status → ask once.
    if (p.evaluate && !p.evaluated) {
      await _evaluate(p, askVat);
      p.evaluated = true;
      await save();
    }
    p.scopeKey ??= await resolveScopeKey();
    p.finalizeKey ??= ApiClient.newIdempotencyKey();
    await save();
    final Map<String, dynamic> json;
    try {
      json = await _api.post('/documents/$id/finalize', {
        'scopeKey': p.scopeKey,
        if (p.requestAllocation) 'requestAllocation': true,
      }, p.finalizeKey);
    } on ApiException catch (e) {
      if (e.code == 'APPROVAL_REQUIRED') return _submitResult(p);
      _forgetScopeKeyOn(e);
      rethrow;
    }
    p.documentNumber = json['documentNumber']?.toString();
    p.stage = json['status'] == 'WAITING_FOR_ALLOCATION'
        ? IssueStage.waitingAllocation
        : IssueStage.finalized;
    await save();
    report();
  }

  // Waiting for a SHAAM number: ask the ITA once now (AT-60: the number lands on D
  // with no extra step); anything else stays on D (§6.D 4/5) and resume calls again.
  if (p.stage == IssueStage.waitingAllocation) {
    await _requestAllocationOnce(id);
    final doc = await fetchDocument(id);
    if (doc.status == 'WAITING_FOR_ALLOCATION') {
      return IssueResult(IssueOutcome.waitingForAllocation, doc);
    }
    p.stage = IssueStage.finalized;
    await save();
  }

  final locked = await _artifactAndSign(p, unlock, report);
  if (locked != null) return locked;

  // PAID 320: the payment, with the server's total.
  if (p.stage == IssueStage.artifact) {
    final pay = p.payment;
    if (pay != null) {
      final doc = await fetchDocument(id);
      final amount = doc.totalMinor;
      await _createPayment(p, pay, amount);
      if (doc.paidTotalMinor < amount) {
        try {
          await _api.post('/documents/$id/payments', {
            'paymentId': p.paymentId,
            'amountMinor': amount.toString(),
          });
        } on ApiException catch (e) {
          // A lost response of an allocation that did happen.
          if (e.code != 'PAYMENT_OVERALLOCATED' ||
              (await fetchDocument(id)).paidTotalMinor < amount) {
            rethrow;
          }
        }
      }
    }
    p.stage = IssueStage.paymentRecorded;
    await save();
    report();
  }
  return _done(p, report);
}

/// 400 / 405: POST /payments → POST /receipts → artifact (+ signature).
Future<IssueResult> _runReceipt(
  PendingIssue p,
  void Function(IssueStage)? onStage,
  SigningUnlocker? unlock,
) async {
  void report() => onStage?.call(p.stage);
  Future<void> save() => savePendingIssue(p);
  if (p.stage.index < IssueStage.finalized.index) {
    final pay = p.payment!;
    await _createPayment(p, pay, p.totalMinor);
    p.scopeKey ??= await resolveScopeKey();
    p.receiptKey ??= ApiClient.newIdempotencyKey();
    await save();
    final Map<String, dynamic> json;
    try {
      json = await _api.post('/receipts', {
        'scopeKey': p.scopeKey,
        'paymentIds': [
          {'id': p.paymentId},
        ],
        if (p.body['customerId'] != null) 'customerId': p.body['customerId'],
      }, p.receiptKey);
    } on ApiException catch (e) {
      _forgetScopeKeyOn(e);
      rethrow;
    }
    final outcome = json['outcome'] as Map<String, dynamic>? ?? const {};
    if (outcome['status'] == 'APPROVAL_REQUIRED') {
      // Before BE-37 a receipt above the threshold is refused (AT-45 edge case).
      throw ApiException(409, 'APPROVAL_REQUIRED', 'APPROVAL_REQUIRED');
    }
    p
      ..draftId = json['receiptDocumentId'] as String
      ..documentNumber = outcome['documentNumber']?.toString()
      ..stage = outcome['status'] == 'WAITING_FOR_ALLOCATION'
          ? IssueStage.waitingAllocation
          : IssueStage.finalized;
    await save();
    report();
  }
  if (p.stage == IssueStage.waitingAllocation) {
    final doc = await fetchDocument(p.draftId!);
    if (doc.status == 'WAITING_FOR_ALLOCATION') {
      return IssueResult(IssueOutcome.waitingForAllocation, doc);
    }
    p.stage = IssueStage.finalized;
  }
  final locked = await _artifactAndSign(p, unlock, report);
  if (locked != null) return locked;
  return _done(p, report);
}

/// REQUIRED/READY → POST /allocation/request. The server records the attempt
/// before calling the ITA and refuses a blind retry of an unknown outcome, so a
/// repeat after a crash is safe. Failures are left to D's "נסה שוב".
Future<void> _requestAllocationOnce(String id) async {
  try {
    final state = (await _api.get('/documents/$id/allocation'))['state'];
    if (state == 'REQUIRED' || state == 'READY') {
      await _api.post('/documents/$id/allocation/request', const {});
    }
  } on ApiException {
    // D row 4 shows the state and the retry.
  }
}

/// finalized → artifact; LOCKED → [unlock] → /sign. Returns a result when the
/// sequence has to stop (signature not released).
Future<IssueResult?> _artifactAndSign(
  PendingIssue p,
  SigningUnlocker? unlock,
  void Function() report,
) async {
  final id = p.draftId!;
  if (p.stage == IssueStage.finalized) {
    final signing = await _createArtifact(id);
    p
      ..signingPending = signing == 'LOCKED'
      ..stage = IssueStage.artifact;
    await savePendingIssue(p);
    report();
  }
  if (p.stage == IssueStage.artifact && p.signingPending) {
    try {
      await _sign(
        id,
      ); // the session may already be open (another device, earlier unlock)
    } on ApiException catch (e) {
      if (e.code != 'SIGNING_LOCKED') rethrow;
      final unlocked = unlock != null && await unlock();
      if (!unlocked) {
        return IssueResult(IssueOutcome.signingLocked, await fetchDocument(id));
      }
      await _sign(id);
    }
    p.signingPending = false;
    await savePendingIssue(p);
  }
  return null;
}

/// POST /documents/:id/artifact → its `signing` ('SIGNED' | 'LOCKED' |
/// 'NOT_APPLICABLE'). An original that already exists: LOCKED when the
/// document still waits for its signature.
Future<String?> _createArtifact(String id) async {
  try {
    final json = await _api.post('/documents/$id/artifact');
    return json['signing'] as String?;
  } on ApiException catch (e) {
    if (e.code != 'ORIGINAL_ARTIFACT_REGENERATION_FORBIDDEN') rethrow;
    final doc = await fetchDocument(id);
    return doc.status == 'ARTIFACT_PENDING' ? 'LOCKED' : null;
  }
}

Future<void> _createPayment(
  PendingIssue p,
  PaymentInput pay,
  BigInt amount,
) async {
  if (p.paymentId != null) return;
  p.paymentKey ??= ApiClient.newIdempotencyKey();
  p.paymentDate ??= todayIso();
  await savePendingIssue(p);
  final json = await _api.post(
    '/payments',
    pay.requestBody(amount, p.paymentDate!),
    p.paymentKey,
  );
  p.paymentId = json['paymentId'] as String;
  await savePendingIssue(p);
}

Future<void> _evaluate(PendingIssue p, VatStatusAsker? askVat) async {
  final id = p.draftId!;
  Map<String, dynamic> view;
  try {
    view = await evaluateAllocation(id);
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return; // advisory: finalize still applies the server rule
  }
  if (view['state'] != 'REQUIRES_USER_INPUT') return;
  final reason =
      (view['evaluation'] as Map<String, dynamic>?)?['reasonCode'] as String? ??
      'CUSTOMER_VAT_STATUS_UNKNOWN';
  final answer = askVat == null ? null : await askVat(reason);
  if (answer == null) throw const IssueCancelled();
  final customerId = p.body['customerId'] as String?;
  if (customerId != null) {
    await _api.patch('/customers/$customerId', {
      'vatDealerStatus': answer.authorizedDealer
          ? 'AUTHORIZED_DEALER'
          : 'PRIVATE',
      if (answer.taxId != null && answer.taxId!.isNotEmpty)
        'taxId': answer.taxId,
    });
  }
  try {
    await evaluateAllocation(id);
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
  }
}

Future<IssueResult> _done(PendingIssue p, void Function() report) async {
  final doc = await fetchDocument(p.draftId!);
  p.stage = IssueStage.done;
  report();
  await clearPendingIssue(p.businessId);
  return IssueResult(IssueOutcome.issued, doc);
}

Future<IssueResult> _submitResult(PendingIssue p) async {
  try {
    await _api.post('/documents/${p.draftId}/submit');
  } on ApiException catch (e) {
    if (e.code != 'DOCUMENT_INVALID_TRANSITION') rethrow; // already submitted
  }
  p.stage = IssueStage.submitted;
  await clearPendingIssue(p.businessId); // the approver takes it from here
  return IssueResult(
    IssueOutcome.submittedForApproval,
    await fetchDocument(p.draftId!),
  );
}

// ---------------------------------------------------------------------------
// Draft (create / update / replace)
// ---------------------------------------------------------------------------

Future<void> _ensureDraft(PendingIssue p) async {
  Future<void> save() => savePendingIssue(p);
  // Another type (S3 switch after a failure): PUT keeps the old type → replace.
  if (p.draftId != null &&
      p.editable &&
      p.draftType != null &&
      p.draftType != p.documentType) {
    try {
      await _api.delete('/documents/${p.draftId}');
      p.forgetDraft();
    } on ApiException catch (e) {
      if (e.code == 'DOCUMENT_NOT_FOUND') {
        p.forgetDraft();
      } else if (e.code == 'DOCUMENT_ACTION_FORBIDDEN') {
        // Numbered behind our back (lost finalize response): finish it as issued.
        p.body = {...p.body, 'documentType': p.draftType};
        if (!isPaidServerType(p.draftType!)) p.payment = null;
      } else {
        rethrow;
      }
    }
    await save();
  }
  // A lost POST /documents response: adopt that draft instead of a second one.
  if (p.draftId == null && p.createAttemptTotal != null) {
    final lost = await _findLostDraft(p);
    if (lost != null) {
      p
        ..draftId = lost
        ..draftType = p.documentType
        ..bodyHash = null
        ..stage = IssueStage.draft;
      await save();
    }
  }
  // BE-08 linked conversion (300/100 → 305): clone, then the PUT below.
  if (p.draftId == null && p.cloneFrom != null) {
    p.createAttemptTotal =
        p.cloneTotal; // a lost clone response is adopted like a lost POST
    await save();
    final cloned = await _cloneLinked(p);
    if (cloned != null) {
      p
        ..draftId = cloned
        ..draftType = p.documentType
        ..bodyHash = null
        ..stage = IssueStage.draft;
      await save();
    }
  }
  final hash = sha256.convert(utf8.encode(jsonEncode(p.body))).toString();
  if (p.draftId == null) {
    p.createAttemptTotal = p.totalMinor.toString();
    await save(); // before the call: a crash after it still finds the draft
    final json = await _api.post('/documents', p.body);
    p
      ..draftId = json['id'] as String
      ..draftType = p.documentType
      ..bodyHash = hash
      ..stage = IssueStage.draft;
    await save();
  } else if (p.editable && p.bodyHash != hash) {
    try {
      await _api.put('/documents/${p.draftId}', p.body);
      p
        ..bodyHash = hash
        ..finalizeKey =
            null // new content → new finalize key
        ..evaluated = false;
      if (p.stage == IssueStage.start) p.stage = IssueStage.draft;
      await save();
    } on ApiException catch (e) {
      if (e.code != 'DOCUMENT_ALREADY_FINALIZED' &&
          e.code != 'DOCUMENT_INVALID_TRANSITION')
        rethrow;
    }
  }
}

/// POST /documents/:source/clone {documentType, link:true} → the new draft.
/// Null (and [PendingIssue.cloneFrom] dropped → a plain POST) on a server
/// without BE-08 or a source that cannot be linked.
Future<String?> _cloneLinked(PendingIssue p) async {
  try {
    final json = await _api.post('/documents/${p.cloneFrom}/clone', {
      'documentType': p.documentType,
      'link': true,
    });
    return json['id'] as String;
  } on ApiException catch (e) {
    final missingRoute = e.status == 404 && e.code == 'NOT_FOUND';
    if (!missingRoute &&
        e.code != 'DOCUMENT_NOT_FINAL' &&
        e.code != 'CLONE_TYPE_NOT_ALLOWED')
      rethrow;
    p
      ..cloneFrom = null
      ..createAttemptTotal = null;
    return null;
  }
}

/// The DRAFT a POST /documents with a lost response created: same type,
/// customer and total. Null when none (or never attempted).
Future<String?> _findLostDraft(PendingIssue p) async {
  final total = p.createAttemptTotal;
  final customerId = p.body['customerId'];
  if (total == null || customerId is! String) return null;
  final json = await _api.get(
    '/documents',
    query: {
      'status': 'DRAFT',
      'documentType': p.documentType,
      'customerId': customerId,
    },
  );
  for (final d in (json['documents'] as List? ?? const [])) {
    final m = d as Map<String, dynamic>;
    if (m['status'] == 'DRAFT' &&
        m['documentType'] == p.documentType &&
        m['customerId'] == customerId &&
        m['totalMinor']?.toString() == total) {
      return m['id'] as String;
    }
  }
  return null;
}

/// "בטל" on an unfinished issue: deletes the server draft when nothing was
/// numbered yet; never touches an issued document.
Future<void> discardPendingIssue(PendingIssue p) async {
  final draftId =
      p.draftId ??
      (p.editable && !p.receiptOnly ? await _findLostDraft(p) : null);
  if (draftId != null && p.editable && !p.receiptOnly) {
    try {
      await _api.delete('/documents/$draftId');
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
    }
  }
  await clearPendingIssue(p.businessId);
}

// ---------------------------------------------------------------------------
// Pending issue (persisted per business)
// ---------------------------------------------------------------------------

/// The selected business ('none' when signed out).
String get currentBusinessId =>
    session.business?.businessId ?? _api.businessId ?? 'none';

/// Cache writes are a convenience: a full disk must never fail an API call.
Future<void> cacheWrite(String name, Object? json) async {
  try {
    await AppCache.write(name, json);
  } on Object {
    // ignore
  }
}

/// 'YYYY-MM-DD' of today (local).
String todayIso([DateTime? now]) {
  final n = now ?? DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

/// How far the issue sequence got. Order matters (index comparisons).
enum IssueStage {
  start,
  draft,
  submitted,
  waitingAllocation,
  finalized,
  artifact,
  paymentRecorded,
  done,
}

/// The money received in a PAID issue (§9.1). CHECK: reference = cheque number.
class PaymentInput {
  const PaymentInput({
    required this.method,
    this.bankNumber,
    this.branchNumber,
    this.accountNumber,
    this.checkNumber,
  });

  factory PaymentInput.fromJson(Map<String, dynamic> j) => PaymentInput(
    method: j['method'] as String,
    bankNumber: j['bankNumber'] as String?,
    branchNumber: j['branchNumber'] as String?,
    accountNumber: j['accountNumber'] as String?,
    checkNumber: j['checkNumber'] as String?,
  );

  /// CASH | BANK_TRANSFER | CREDIT_CARD | CHECK | DIRECT_DEBIT | OTHER
  final String method;
  final String? bankNumber;
  final String? branchNumber;
  final String? accountNumber;
  final String? checkNumber;

  Map<String, dynamic> toJson() => {
    'method': method,
    'bankNumber': bankNumber,
    'branchNumber': branchNumber,
    'accountNumber': accountNumber,
    'checkNumber': checkNumber,
  };

  /// POST /payments body. Only CHECK writes `reference` (it is part of the
  /// idempotency hash; "העברה / ביט" never writes it, §9.1).
  Map<String, dynamic> requestBody(BigInt amountMinor, String paymentDate) => {
    'method': method,
    'amountMinor': amountMinor.toString(),
    'currency': 'ILS',
    'paymentDate': paymentDate,
    if (method == 'CHECK') ...{
      'bankNumber': bankNumber,
      'branchNumber': branchNumber,
      'accountNumber': accountNumber,
      'reference': checkNumber,
    },
  };
}

/// One issue in progress. [form] is the Composer state (restored on resume).
class PendingIssue {
  PendingIssue({
    required this.businessId,
    required this.body,
    required this.form,
    this.payment,
    required this.totalMinor,
    required this.needsApproval,
    this.evaluate = false,
    this.requestAllocation = false,
    this.receiptOnly = false,
    this.stage = IssueStage.start,
    this.draftId,
    this.draftType,
    this.createAttemptTotal,
    this.bodyHash,
    this.finalizeKey,
    this.scopeKey,
    this.paymentKey,
    this.receiptKey,
    this.paymentDate,
    this.paymentId,
    this.documentNumber,
    this.evaluated = false,
    this.signingPending = false,
    this.cloneFrom,
    this.cloneTotal,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory PendingIssue.fromJson(Map<String, dynamic> j) => PendingIssue(
    businessId: j['businessId'] as String,
    body: Map<String, dynamic>.from(j['body'] as Map),
    form: Map<String, dynamic>.from(j['form'] as Map),
    payment: j['payment'] == null
        ? null
        : PaymentInput.fromJson(Map<String, dynamic>.from(j['payment'] as Map)),
    totalMinor: BigInt.parse(j['totalMinor'] as String),
    needsApproval: j['needsApproval'] == true,
    evaluate: j['evaluate'] == true,
    requestAllocation: j['requestAllocation'] == true,
    receiptOnly: j['receiptOnly'] == true,
    stage: IssueStage.values.byName(j['stage'] as String),
    draftId: j['draftId'] as String?,
    draftType: j['draftType'] as String?,
    createAttemptTotal: j['createAttemptTotal'] as String?,
    bodyHash: j['bodyHash'] as String?,
    finalizeKey: j['finalizeKey'] as String?,
    scopeKey: j['scopeKey'] as String?,
    paymentKey: j['paymentKey'] as String?,
    receiptKey: j['receiptKey'] as String?,
    paymentDate: j['paymentDate'] as String?,
    paymentId: j['paymentId'] as String?,
    documentNumber: j['documentNumber'] as String?,
    evaluated: j['evaluated'] == true,
    signingPending: j['signingPending'] == true,
    cloneFrom: j['cloneFrom'] as String?,
    cloneTotal: j['cloneTotal'] as String?,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
  );

  final String businessId;

  /// POST /documents body (documentType, customerId, lines…); for a
  /// receipt-only issue: documentType + customerId.
  Map<String, dynamic> body;
  Map<String, dynamic> form;
  PaymentInput? payment;
  BigInt totalMinor;
  bool needsApproval;

  /// Call POST /allocation/evaluate before finalize (VAT business, 305/320).
  bool evaluate;

  /// "הלקוח ביקש מספר הקצאה" (voluntary; the server decides otherwise).
  bool requestAllocation;

  /// 400 / 405: POST /payments → POST /receipts (no POST /documents).
  bool receiptOnly;
  IssueStage stage;

  /// The document (draft, or the receipt for [receiptOnly]).
  String? draftId;

  /// The server draft's documentType (PUT never changes it).
  String? draftType;

  /// Set just before POST /documents (no Idempotency-Key there): a retry
  /// first looks for the draft a lost response created.
  String? createAttemptTotal;
  String? bodyHash;
  String? finalizeKey;
  String? scopeKey;
  String? paymentKey;
  String? receiptKey;

  /// Fixed on the first POST /payments: it is part of the idempotency hash.
  String? paymentDate;
  String? paymentId;
  String? documentNumber;
  bool evaluated;

  /// The original exists but waits for the business signature.
  bool signingPending;

  /// BE-08: make the draft as a linked clone of this issued document (300/100
  /// → 305) instead of POST /documents. [cloneTotal]: the source total (the
  /// clone's total before the PUT), to adopt a lost clone response.
  String? cloneFrom;
  String? cloneTotal;
  final DateTime createdAt;

  String get documentType => body['documentType'] as String;

  /// Content can still change (nothing numbered yet).
  bool get editable => stage.index <= IssueStage.draft.index;

  void forgetDraft() {
    draftId = null;
    draftType = null;
    createAttemptTotal = null;
    bodyHash = null;
    finalizeKey = null;
    evaluated = false;
    stage = IssueStage.start;
  }

  Map<String, dynamic> toJson() => {
    'businessId': businessId,
    'body': body,
    'form': form,
    'payment': payment?.toJson(),
    'totalMinor': totalMinor.toString(),
    'needsApproval': needsApproval,
    'evaluate': evaluate,
    'requestAllocation': requestAllocation,
    'receiptOnly': receiptOnly,
    'stage': stage.name,
    'draftId': draftId,
    'draftType': draftType,
    'createAttemptTotal': createAttemptTotal,
    'bodyHash': bodyHash,
    'finalizeKey': finalizeKey,
    'scopeKey': scopeKey,
    'paymentKey': paymentKey,
    'receiptKey': receiptKey,
    'paymentDate': paymentDate,
    'paymentId': paymentId,
    'documentNumber': documentNumber,
    'evaluated': evaluated,
    'signingPending': signingPending,
    'cloneFrom': cloneFrom,
    'cloneTotal': cloneTotal,
    'createdAt': createdAt.toIso8601String(),
  };
}

String _pendingKey(String businessId) => 'nd_pending_issue_$businessId';

/// The unfinished issue of the current business, if any (UNFINISHED card).
Future<PendingIssue?> loadPendingIssue() async {
  Object? v;
  try {
    v = await AppCache.read(_pendingKey(currentBusinessId));
  } on Object {
    return null;
  }
  if (v is! Map<String, dynamic>) return null;
  try {
    return PendingIssue.fromJson(v);
  } on Object {
    return null;
  }
}

Future<void> savePendingIssue(PendingIssue p) =>
    cacheWrite(_pendingKey(p.businessId), p.toJson());

Future<void> clearPendingIssue([String? businessId]) async {
  try {
    await AppCache.remove(_pendingKey(businessId ?? currentBusinessId));
  } on Object {
    // nothing to clear
  }
}
