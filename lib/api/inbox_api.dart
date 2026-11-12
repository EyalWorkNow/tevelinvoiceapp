// Home (H) + activity (L) data. Owner: squad A (SPEC-v2 §6.H, §6.H.1, §6.L, §9.3).
//
// H source:
// * P1 (BE-05): GET /mobile/inbox → HomeData as is.
// * P0 fallback (route missing → 404 NOT_FOUND): compose the cards on the
//   client from GET /dashboard, GET /documents?limit=100,
//   ?status=WAITING_FOR_ALLOCATION|ARTIFACT_PENDING&limit=20, GET /approvals,
//   GET /expenses/inbox, /me (shaam) and the profile ([composeHome], pure).
// Every source is fetched only when the user's caps can show its card.
//
// L source: P0 GET /documents?limit=500 (+ ?unpaid=1, GET /quotes) with a
// client-side search over the 500 rows; P1 (BE-10) when the server echoes
// `offset`: search on the server ([serverSearchDocuments]: q for names, lines
// and numbers, minTotal=maxTotal for amounts, customer tax ID through
// GET /customers?q=) and "טען עוד" paging past the first page.

import 'dart:async';

import '../state/cache.dart';
import '../state/caps.dart';
import '../state/session.dart';
import '../util/allowed_urls.dart';
import '../util/labels/inbox_he.dart';
import '../util/phone.dart';
import '../util/status_map.dart';
import 'client.dart';
import 'models/models.dart';
import 'signing_api.dart';

ApiClient get _api => ApiClient.instance;

String get _bid => session.business?.businessId ?? _api.businessId ?? 'none';

// ---- H: load ------------------------------------------------------------------

/// Null until the first /mobile/inbox answer; false after a 404 (BE-05 not
/// deployed), so later loads go straight to the P0 composition.
bool? mobileInboxAvailable;

/// Cached H for the selected business (F9: paint before the network).
Future<HomeData?> readCachedHome() async {
  final v = await AppCache.read('home_$_bid');
  if (v is! Map<String, dynamic>) return null;
  try {
    return HomeData.fromJson(v);
  } on Object {
    return null;
  }
}

/// Fetches H from the network and caches it. [caps] filters every card;
/// [now] is injectable for tests.
Future<HomeData> fetchHome({required Caps caps, DateTime? now}) async {
  final business = _bid;
  final today = now ?? DateTime.now();
  final dismissed = await readDismissedSetup();
  HomeData data;
  if (mobileInboxAvailable != false) {
    try {
      final json = await _api.get('/mobile/inbox', query: {'limit': '10'});
      mobileInboxAvailable = true;
      final server = HomeData.fromJson(json, now: today);
      // BE-05 knows server drafts only; this device's interrupted issue is ours.
      data = filterHome(mergeLocalUnfinished(server, await localUnfinishedProbe(), caps: caps),
          caps: caps, dismissedSetup: dismissed);
      await _writeHome(business, data);
      return data;
    } on ApiException catch (e) {
      if (!(e.status == 404 && e.code == 'NOT_FOUND')) rethrow;
      mobileInboxAvailable = false;
    }
  }
  final sources = await fetchInboxSources(caps);
  data = composeHome(sources,
      ctx: InboxContext(
        caps: caps,
        userId: session.me?.userId,
        businessType: session.me?.businessType ?? session.profile?.businessType ?? 'OSEK_MURSHE',
        today: today,
        shaam: session.me?.shaam,
        paymentLinkUrl: session.profile?.paymentLinkUrl,
        memberCount: session.me?.memberCount,
        recoveryCodesSaved: _recoveryCodesSaved(session.me),
        hasLogo: sources.hasLogo,
        dismissedSetup: dismissed,
        localUnfinished: await localUnfinishedProbe(),
      ));
  await _writeHome(business, data);
  return data;
}

Future<void> _writeHome(String business, HomeData data) async {
  if (business != _bid) return; // business switched while loading
  try {
    await AppCache.write('home_$business', data.toJson());
  } on Object {
    // a cache write never breaks H
  }
}

/// `/me.mfa.recoveryCodesSaved` (not in BE-02 yet → no card).
bool? _recoveryCodesSaved(Me? me) {
  final mfa = me?.raw['mfa'];
  if (mfa is Map && mfa['recoveryCodesSaved'] is bool) return mfa['recoveryCodesSaved'] as bool;
  return null;
}

/// Raw P0 inputs of [composeHome].
class InboxSources {
  InboxSources({
    this.dashboard,
    this.documents = const [],
    this.waitingAllocation = const [],
    this.artifactPending = const [],
    this.approvals = const [],
    this.expenseStatuses = const [],
    this.hasLogo,
  });

  final DashboardSummary? dashboard;

  /// GET /documents?limit=100, newest first.
  final List<DocumentSummary> documents;
  final List<DocumentSummary> waitingAllocation;
  final List<DocumentSummary> artifactPending;
  final List<ApprovalRow> approvals;

  /// `status` of every GET /expenses/inbox row.
  final List<String> expenseStatuses;

  /// GET /settings/branding has a logo (null = not asked).
  final bool? hasLogo;
}

/// Runs the P0 requests in parallel, each only when a card could use it.
Future<InboxSources> fetchInboxSources(Caps caps) async {
  final dashboard = _api.get('/dashboard');
  final documents = fetchDocumentRows(limit: 100);
  final allocation = caps.can(Cap.allocationRequest)
      ? fetchDocumentRows(status: 'WAITING_FOR_ALLOCATION', limit: 20)
      : Future.value(const ActivityPage(0, []));
  final pending = caps.can(Cap.docIssue)
      ? fetchDocumentRows(status: 'ARTIFACT_PENDING', limit: 20)
      : Future.value(const ActivityPage(0, []));
  final approvals = caps.can(Cap.approvalDecide)
      ? _api.get('/approvals')
      : Future.value(const <String, dynamic>{});
  final expenses = caps.can(Cap.expenseApprove)
      ? _api.get('/expenses/inbox')
      : Future.value(const <String, dynamic>{});
  final logo = caps.can(Cap.settingsDesign) ? _hasLogo() : Future<bool?>.value(null);
  // Wait for all at once: one failure must not leave the others' errors unhandled.
  await Future.wait<Object?>([dashboard, documents, allocation, pending, approvals, expenses, logo]);
  return InboxSources(
    dashboard: DashboardSummary.fromJson(await dashboard),
    documents: (await documents).documents,
    waitingAllocation: (await allocation).documents,
    artifactPending: (await pending).documents,
    approvals: [
      for (final a in ((await approvals)['approvals'] as List? ?? const []))
        ApprovalRow.fromJson(a as Map<String, dynamic>)
    ],
    expenseStatuses: [
      for (final e in ((await expenses)['expenses'] as List? ?? const []))
        if (e is Map) '${e['status']}'
    ],
    hasLogo: await logo,
  );
}

/// Asks /settings/branding once; a business that has a logo is remembered
/// (the logo data URI is large — no need to fetch it on every home load).
Future<bool?> _hasLogo() async {
  final key = 'home_logo_$_bid';
  if (await AppCache.read(key) == true) return true;
  try {
    final json = await _api.get('/settings/branding');
    final branding = json['branding'];
    final has = branding is Map && '${branding['logoDataUri'] ?? ''}'.isNotEmpty;
    if (has) await AppCache.write(key, true);
    return has;
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return null; // unknown → no logo card
  }
}

/// An issue still in progress on this device (squad B's local journal):
/// `{draftId, totalMinor, customerName}` or null. Default reads B's cache
/// entry `nd_pending_issue_<business>`; tests replace it.
Future<LocalUnfinished?> Function() localUnfinishedProbe = _readPendingIssue;

class LocalUnfinished {
  const LocalUnfinished({this.draftId, this.totalMinor, this.customerName});

  final String? draftId;
  final BigInt? totalMinor;
  final String? customerName;
}

Future<LocalUnfinished?> _readPendingIssue() async {
  final v = await AppCache.read('nd_pending_issue_$_bid');
  if (v is! Map) return null;
  final form = v['form'];
  return LocalUnfinished(
    draftId: v['draftId'] as String?,
    totalMinor: BigInt.tryParse('${v['totalMinor']}'),
    customerName: form is Map ? form['customerName'] as String? : null,
  );
}

// ---- H: compose (pure, unit-tested) -------------------------------------------

/// Who is looking, and the non-list inputs of the cards.
class InboxContext {
  const InboxContext({
    required this.caps,
    required this.userId,
    required this.businessType,
    required this.today,
    this.shaam,
    this.paymentLinkUrl,
    this.memberCount,
    this.recoveryCodesSaved,
    this.hasLogo,
    this.dismissedSetup = const {},
    this.localUnfinished,
  });

  final Caps caps;
  final String? userId;
  final String businessType;
  final DateTime today;
  final ShaamState? shaam;
  final String? paymentLinkUrl;
  final int? memberCount;
  final bool? recoveryCodesSaved;
  final bool? hasLogo;
  final Set<SetupStep> dismissedSetup;
  final LocalUnfinished? localUnfinished;

  /// "שלו בלבד לעובד" (§4.4): employees see only their own drafts.
  bool get ownOnly => caps.preset == Preset.employee || caps.preset == Preset.employeeIssuer;
}

const Set<String> _unfinishedStatuses = {'DRAFT', 'VALIDATING', 'READY_TO_FINALIZE', 'REJECTED'};
const Set<String> _vatBusinesses = {'OSEK_MURSHE', 'COMPANY', 'PARTNERSHIP'};
const Set<String> _expenseReviewStatuses = {'NEEDS_REVIEW', 'READY_TO_APPROVE'};

/// SHAAM_RENEW shows when the connection expires within this many days.
const int shaamRenewDays = 14;

/// §6.H.1: builds the sorted "לטיפול" cards + money + recent from P0 sources.
HomeData composeHome(InboxSources s, {required InboxContext ctx}) {
  final caps = ctx.caps;
  final cards = <InboxItem>[];
  final docs = s.documents;

  // APPROVAL_NEEDED — the approver's queue (own submissions only when the
  // approver is alone: BE-37 lets a sole approver approve their own).
  if (caps.can(Cap.approvalDecide)) {
    final queue = [
      for (final a in s.approvals)
        if (a.submittedBy == null ||
            a.submittedBy != ctx.userId ||
            !caps.approvalPolicy.otherApproverExists)
          a
    ];
    if (queue.isNotEmpty) {
      cards.add(InboxItem(
        kind: InboxKind.approvalNeeded,
        count: queue.length,
        amountMinor: queue.fold<BigInt>(BigInt.zero, (t, a) => t + a.totalMinor),
        documentIds: [for (final a in queue) a.id],
      ));
    }
  }

  // MY_REJECTED — the submitter's rejected drafts (BE-37 rejection/submittedBy).
  final rejected = [
    for (final d in docs)
      if (caps.can(Cap.docDraft) &&
          d.rejection != null &&
          _unfinishedStatuses.contains(d.status) &&
          (d.submittedBy == null || d.submittedBy == ctx.userId))
        d
  ];
  if (rejected.isNotEmpty) {
    final d = rejected.first;
    cards.add(InboxItem(
      kind: InboxKind.myRejected,
      count: rejected.length,
      amountMinor: rejected.length == 1 ? d.totalMinor : null,
      documentIds: [for (final r in rejected) r.id],
      customerName: d.customerName,
      documentType: d.documentType,
      reason: d.rejection!.reason,
    ));
  }

  // TAX_INVOICE_DUE — a paid 300 at a VAT business needs a 305 (14 days).
  if (caps.can(Cap.docIssue) && _vatBusinesses.contains(ctx.businessType)) {
    final due = [
      for (final d in docs)
        if (_paidTransactionInvoice(d) && !_hasLaterTaxInvoice(d, docs)) d
    ];
    if (due.isNotEmpty) {
      final d = due.first;
      cards.add(InboxItem(
        kind: InboxKind.taxInvoiceDue,
        count: due.length,
        amountMinor: due.length == 1 ? d.totalMinor : null,
        documentIds: [for (final x in due) x.id],
        customerName: d.customerName,
        documentType: d.documentType,
      ));
    }
  }

  // ALLOCATION_PROBLEM.
  if (caps.can(Cap.allocationRequest) && s.waitingAllocation.isNotEmpty) {
    final d = s.waitingAllocation.first;
    cards.add(InboxItem(
      kind: InboxKind.allocationProblem,
      count: s.waitingAllocation.length,
      documentIds: [for (final x in s.waitingAllocation) x.id],
      documentNumber: s.waitingAllocation.length == 1 ? d.documentNumber : null,
    ));
  }

  // SIGNING_LOCKED.
  if (caps.can(Cap.docIssue) && s.artifactPending.isNotEmpty) {
    cards.add(InboxItem(
      kind: InboxKind.signingLocked,
      count: s.artifactPending.length,
      documentIds: [for (final x in s.artifactPending) x.id],
    ));
  }

  // UNFINISHED — drafts (own only for employees) + the local issue journal.
  if (caps.can(Cap.docDraft)) {
    final drafts = [
      for (final d in docs)
        if (_unfinishedStatuses.contains(d.status) &&
            d.rejection == null &&
            (!ctx.ownOnly || d.createdBy == null || d.createdBy == ctx.userId))
          d
    ];
    final local = ctx.localUnfinished;
    final localExtra = local != null && !drafts.any((d) => d.id == local.draftId);
    final count = drafts.length + (localExtra ? 1 : 0);
    if (count > 0) {
      final single = count == 1;
      final d = drafts.isEmpty ? null : drafts.first;
      cards.add(InboxItem(
        kind: InboxKind.unfinished,
        count: count,
        amountMinor: single ? (d?.totalMinor ?? local?.totalMinor) : null,
        documentIds: [for (final x in drafts) x.id, if (localExtra && local.draftId != null) local.draftId!],
        customerName: single ? (d?.customerName ?? local?.customerName) : null,
        documentType: d?.documentType,
      ));
    }
  }

  // OVERDUE — server aggregate (BE-01).
  final dash = s.dashboard;
  if (caps.can(Cap.docSend) && caps.can(Cap.moneyView) && (dash?.overdueCount ?? 0) > 0) {
    cards.add(InboxItem(
      kind: InboxKind.overdue,
      count: dash!.overdueCount!,
      amountMinor: dash.overdueTotalMinor,
    ));
  }

  // EXPENSE_REVIEW.
  if (caps.can(Cap.expenseApprove)) {
    final n = s.expenseStatuses.where(_expenseReviewStatuses.contains).length;
    if (n > 0) cards.add(InboxItem(kind: InboxKind.expenseReview, count: n));
  }

  // SHAAM_RENEW.
  final shaam = ctx.shaam;
  if (caps.can(Cap.settingsBusiness) && shaam != null && shaam.status == 'CONNECTED') {
    final expires = DateTime.tryParse(shaam.refreshTokenExpiresAt ?? '');
    if (expires != null) {
      final days = expires.difference(ctx.today).inHours ~/ 24;
      if (days <= shaamRenewDays) {
        cards.add(InboxItem(kind: InboxKind.shaamRenew, daysLeft: days < 0 ? 0 : days));
      }
    }
  }

  // SETUP — one at a time.
  final step = nextSetupStep(ctx);
  if (step != null) cards.add(InboxItem(kind: InboxKind.setup, setupStep: step));

  cards.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  final money = caps.can(Cap.moneyView) && dash != null;
  return HomeData(
    openMinor: money ? (dash.unpaidTotalMinor ?? dash.unpaidBalanceMinor) : null,
    overdueMinor: money ? (dash.overdueTotalMinor ?? BigInt.zero) : null,
    cards: cards,
    recent: docs.take(5).toList(),
    hasDocuments: docs.isNotEmpty,
  );
}

/// BE-05 + the local issue journal (AT-18): the interrupted issue joins the
/// UNFINISHED card unless the server already shows that draft.
HomeData mergeLocalUnfinished(HomeData data, LocalUnfinished? local, {required Caps caps}) {
  if (local == null || !caps.can(Cap.docDraft)) return data;
  final id = local.draftId;
  if (id != null && data.cards.any((c) => c.documentIds.contains(id))) return data;
  final cards = [...data.cards];
  final i = cards.indexWhere((c) => c.kind == InboxKind.unfinished);
  if (i < 0) {
    cards.add(InboxItem(
      kind: InboxKind.unfinished,
      amountMinor: local.totalMinor,
      documentIds: [?id],
      customerName: local.customerName,
    ));
  } else {
    final c = cards[i];
    cards[i] = InboxItem(
      kind: InboxKind.unfinished,
      count: c.count + 1,
      documentIds: [...c.documentIds, ?id],
      documentType: c.documentType,
    );
  }
  cards.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return HomeData(
    openMinor: data.openMinor,
    overdueMinor: data.overdueMinor,
    cards: cards,
    recent: data.recent,
    hasDocuments: data.hasDocuments,
  );
}

/// The SETUP step to show now (recovery codes → logo → payment link → team).
SetupStep? nextSetupStep(InboxContext ctx) {
  final caps = ctx.caps;
  bool open(SetupStep s) => !ctx.dismissedSetup.contains(s);
  if (ctx.recoveryCodesSaved == false && open(SetupStep.recoveryCodes)) return SetupStep.recoveryCodes;
  if (caps.can(Cap.settingsDesign) && ctx.hasLogo == false && open(SetupStep.logo)) {
    return SetupStep.logo;
  }
  if (caps.can(Cap.settingsBusiness) &&
      (ctx.paymentLinkUrl == null || ctx.paymentLinkUrl!.isEmpty) &&
      open(SetupStep.paymentLink)) {
    return SetupStep.paymentLink;
  }
  if (caps.can(Cap.teamManage) && ctx.memberCount == 1 && open(SetupStep.team)) return SetupStep.team;
  return null;
}

/// BE-05 cards are server-filtered; the client still hides what the caps
/// do not allow (hidden, not disabled) and drops dismissed SETUP steps.
HomeData filterHome(HomeData data, {required Caps caps, Set<SetupStep> dismissedSetup = const {}}) {
  final cards = [
    for (final c in data.cards)
      if (cardAllowed(c, caps) &&
          !(c.kind == InboxKind.setup && c.setupStep != null && dismissedSetup.contains(c.setupStep)))
        c
  ]..sort((a, b) => a.kind.index.compareTo(b.kind.index));
  final money = caps.can(Cap.moneyView);
  return HomeData(
    openMinor: money ? data.openMinor : null,
    overdueMinor: money ? data.overdueMinor : null,
    cards: cards,
    recent: data.recent,
    hasDocuments: data.hasDocuments,
  );
}

/// §6.H.1 "נראה ל-" column.
bool cardAllowed(InboxItem c, Caps caps) => switch (c.kind) {
      InboxKind.approvalNeeded => caps.can(Cap.approvalDecide),
      InboxKind.myRejected || InboxKind.unfinished || InboxKind.quoteAccepted => caps.can(Cap.docDraft),
      InboxKind.taxInvoiceDue || InboxKind.signingLocked => caps.can(Cap.docIssue),
      InboxKind.allocationProblem => caps.can(Cap.allocationRequest),
      InboxKind.overdue => caps.can(Cap.docSend) && caps.can(Cap.moneyView),
      InboxKind.expenseReview => caps.can(Cap.expenseApprove),
      InboxKind.paymentReceived => caps.can(Cap.paymentRecord),
      InboxKind.shaamRenew => caps.can(Cap.settingsBusiness),
      InboxKind.setup => switch (c.setupStep) {
          SetupStep.recoveryCodes => true,
          SetupStep.logo => caps.can(Cap.settingsDesign),
          SetupStep.paymentLink => caps.can(Cap.settingsBusiness),
          SetupStep.team => caps.can(Cap.teamManage),
          null => false,
        },
      InboxKind.reportReady || InboxKind.continuityGap => caps.can(Cap.reportView) && caps.homeIsReports,
    };

/// A 300 that is issued, fully paid and not cancelled.
bool _paidTransactionInvoice(DocumentSummary d) =>
    d.documentType == 'TRANSACTION_INVOICE' &&
    !_unfinishedStatuses.contains(d.status) &&
    d.status != 'PENDING_APPROVAL' &&
    d.voidedAt == null &&
    d.totalMinor > BigInt.zero &&
    d.openMinor == BigInt.zero &&
    (d.creditedMinor ?? BigInt.zero) < d.totalMinor;

/// A 305 for the same customer and total, issued on or after the 300 — the
/// tax invoice already exists (until BE-08 `CONVERTED_FROM` links them).
bool _hasLaterTaxInvoice(DocumentSummary t, List<DocumentSummary> docs) => docs.any((d) =>
    d.documentType == 'TAX_INVOICE' &&
    !_unfinishedStatuses.contains(d.status) &&
    d.customerId == t.customerId &&
    d.totalMinor == t.totalMinor &&
    (d.issueDate ?? '').compareTo(t.issueDate ?? '') >= 0);

// ---- SETUP dismissals (✕) -------------------------------------------------------

Future<Set<SetupStep>> readDismissedSetup() async {
  final v = await AppCache.read('home_setup_dismissed_$_bid');
  return {
    for (final s in (v is List ? v : const []))
      if (SetupStep.fromWire('$s') != null) SetupStep.fromWire('$s')!
  };
}

Future<void> dismissSetup(SetupStep step) async {
  final all = {...await readDismissedSetup(), step};
  await AppCache.write('home_setup_dismissed_$_bid', [for (final s in all) s.wire]);
}

// ---- card actions that run in place --------------------------------------------

/// ALLOCATION_PROBLEM "נסה שוב": POST /documents/:id/allocation for each
/// document (scopeKey from the document; "default" when missing).
Future<void> retryAllocation(List<String> documentIds) async {
  for (final id in documentIds) {
    final doc = await _api.get('/documents/$id');
    final scope = (doc['document'] as Map?)?['numbering_scope_key'] as String? ?? 'default';
    await _api.post('/documents/$id/allocation', {'scopeKey': scope});
  }
}

/// SIGNING_LOCKED "חתום" (one tap): Face ID / passphrase once, then each
/// sealed original is signed (squad C's signing_api). Returns how many were
/// signed; stops when the user cancels the release.
Future<int> signPendingDocuments(List<String> documentIds, {required PassphrasePrompt askPassphrase}) async {
  var signed = 0;
  for (final id in documentIds) {
    if (!await issueSignedOriginal(id, askPassphrase: askPassphrase, alreadySealed: true)) break;
    signed++;
  }
  return signed;
}

/// One overdue invoice whose customer gets the reminder on WhatsApp.
class ReminderTarget {
  const ReminderTarget({
    required this.documentId,
    this.customerName,
    this.phone,
    this.documentNumber,
    required this.openMinor,
  });

  final String documentId;
  final String? customerName;
  final String? phone;
  final String? documentNumber;
  final BigInt openMinor;
}

class ReminderResult {
  const ReminderResult(this.sent, this.whatsapp);

  /// E-mails sent.
  final int sent;

  /// No e-mail / no consent → "שלח בווטסאפ" list.
  final List<ReminderTarget> whatsapp;
}

/// §9.3 P0: every overdue invoice whose customer has an e-mail gets
/// POST /documents/:id/send {recipient, paymentUrl?} → /deliveries/:id/process.
/// No e-mail, or CONSENT_REQUIRED → the WhatsApp list. A network error stops.
/// [only] limits the run to the invoices the user confirmed (H "באיחור" preview).
Future<ReminderResult> sendReminders({DateTime? now, String? paymentUrl, Set<String>? only}) async {
  final overdue = [
    for (final d in await fetchOverdueDocuments(now: now))
      if (only == null || only.contains(d.id)) d
  ];
  if (overdue.isEmpty) return const ReminderResult(0, []);
  final customers = <String, Customer>{
    for (final c in ((await _api.get('/customers'))['customers'] as List? ?? const []))
      (c as Map<String, dynamic>)['id'] as String: Customer.fromJson(c)
  };
  var sent = 0;
  final whatsapp = <ReminderTarget>[];
  for (final d in overdue) {
    final c = customers[d.customerId];
    final target = ReminderTarget(
      documentId: d.id,
      customerName: d.customerName ?? c?.name,
      phone: c?.phone,
      documentNumber: d.documentNumber,
      openMinor: d.openMinor ?? d.totalMinor,
    );
    final email = c?.email?.trim() ?? '';
    if (email.isEmpty) {
      whatsapp.add(target);
      continue;
    }
    try {
      final delivery = await _api.post('/documents/${d.id}/send', {
        'recipient': email,
        if (paymentUrl != null && paymentUrl.isNotEmpty) 'paymentUrl': paymentUrl,
      });
      await _api.post('/deliveries/${delivery['deliveryId']}/process');
      sent++;
    } on ApiException catch (e) {
      if (e.isNetwork) rethrow;
      whatsapp.add(target); // CONSENT_REQUIRED, not deliverable, …
    }
  }
  return ReminderResult(sent, whatsapp);
}

/// Open invoices past due (what [sendReminders] would remind).
Future<List<DocumentSummary>> fetchOverdueDocuments({DateTime? now}) async {
  final today = now ?? DateTime.now();
  final unpaid = await fetchDocumentRows(unpaid: true, limit: 500);
  return [
    for (final d in unpaid.documents)
      if ((d.openMinor ?? BigInt.zero) > BigInt.zero &&
          isOverdue(dueDate: d.dueDate, issueDate: d.issueDate, today: today))
        d
  ];
}

/// "שלח בווטסאפ" for one reminder: share link (original created when
/// missing) → wa.me with the reminder text (AT-95: launchAllowed only).
Future<void> remindOnWhatsApp(ReminderTarget t, {required String businessName, String? paymentUrl}) async {
  final link = await shareLinkFor(t.documentId);
  final text = InboxHe.reminderText(
    customer: t.customerName,
    number: t.documentNumber,
    amountMinor: t.openMinor,
    business: businessName,
    link: link,
    paymentUrl: paymentUrl,
  );
  await launchAllowed(whatsAppUri(phone: waPhone(t.phone), text: text));
}

/// POST /documents/:id/share-link; ARTIFACT_REQUIRED → POST /artifact once.
Future<String> shareLinkFor(String documentId) async {
  Map<String, dynamic> json;
  try {
    json = await _api.post('/documents/$documentId/share-link');
  } on ApiException catch (e) {
    if (e.code != 'ARTIFACT_REQUIRED') rethrow;
    await _api.post('/documents/$documentId/artifact');
    json = await _api.post('/documents/$documentId/share-link');
  }
  return json['url'] as String;
}

// ---- L: lists + search --------------------------------------------------------

/// One GET /documents answer.
class ActivityPage {
  const ActivityPage(this.total, this.documents, {this.serverSearch = false});

  final int total;
  final List<DocumentSummary> documents;

  /// The server answered with `offset` (BE-10): search + paging are server-side.
  final bool serverSearch;

  /// The server had more rows than it returned.
  bool get capped => total > documents.length;
}

/// GET /documents with the filters L and H use.
Future<ActivityPage> fetchDocumentRows({
  int? limit,
  bool unpaid = false,
  String? status,
  String? q,
  int? offset,
  BigInt? total,
  String? customerId,
}) async {
  final json = await _api.get('/documents', query: {
    if (limit != null) 'limit': '$limit',
    if (unpaid) 'unpaid': '1',
    'status': ?status,
    if (q != null && q.isNotEmpty) 'q': q,
    if (offset != null) 'offset': '$offset',
    if (total != null) ...{'minTotal': '$total', 'maxTotal': '$total'},
    'customerId': ?customerId,
  });
  return ActivityPage(
    (json['total'] as num?)?.toInt() ?? 0,
    [
      for (final d in (json['documents'] as List? ?? const []))
        DocumentSummary.fromJson(d as Map<String, dynamic>)
    ],
    serverSearch: json.containsKey('offset'),
  );
}

/// BE-10 page size of L.
const int searchPageSize = 50;

/// One BE-10 search answer.
class SearchPage {
  const SearchPage(this.total, this.documents, {required this.pageable});

  final int total;
  final List<DocumentSummary> documents;

  /// One server query behind it: "טען עוד" asks the next offset. Digit
  /// queries merge several queries (number, amount, tax ID) → first page only.
  final bool pageable;

  bool get hasMore => pageable && total > documents.length;
}

/// §6.L search on the server (BE-10). Text → `q` (customer name, line text,
/// number). An amount ("1,200", "₪1,200.50") → minTotal=maxTotal. Digits
/// only → document number first, then amount, then the documents of a
/// customer with that tax ID (GET /customers?q=, BE-09), then the rest.
Future<SearchPage> serverSearchDocuments(String query, {bool unpaid = false, int offset = 0}) async {
  final q = query.trim();
  final amount = parseAmountQuery(q);
  final digitsOnly = RegExp(r'^\d+$').hasMatch(q);
  if (!digitsOnly) {
    final page = amount != null
        ? await fetchDocumentRows(total: amount, unpaid: unpaid, offset: offset, limit: searchPageSize)
        : await fetchDocumentRows(q: q, unpaid: unpaid, offset: offset, limit: searchPageSize);
    return SearchPage(page.total, page.documents, pageable: true);
  }
  final byText = fetchDocumentRows(q: q, unpaid: unpaid, offset: 0, limit: searchPageSize);
  final byAmount = fetchDocumentRows(total: amount, unpaid: unpaid, offset: 0, limit: searchPageSize);
  final byTaxId = q.length >= 8 ? _documentsOfTaxId(q, unpaid: unpaid) : Future.value(const <DocumentSummary>[]);
  await Future.wait<Object?>([byText, byAmount, byTaxId]);
  final text = (await byText).documents;
  final merged = <String, DocumentSummary>{};
  for (final d in [
    for (final d in text)
      if (d.documentNumber == q) d,
    ...(await byAmount).documents,
    ...await byTaxId,
    ...text,
  ]) {
    merged.putIfAbsent(d.id, () => d);
  }
  return SearchPage(merged.length, merged.values.toList(), pageable: false);
}

/// Documents of the customers whose tax ID is exactly [taxId] (≤3 customers).
Future<List<DocumentSummary>> _documentsOfTaxId(String taxId, {required bool unpaid}) async {
  final Map<String, dynamic> json;
  try {
    json = await _api.get('/customers', query: {'q': taxId, 'limit': '5'});
  } on ApiException catch (e) {
    if (e.isNetwork) rethrow;
    return const []; // no customer list for this user: number/amount still match
  }
  final ids = [
    for (final c in (json['customers'] as List? ?? const []))
      if (c is Map<String, dynamic> && Customer.fromJson(c).taxId == taxId) c['id'] as String
  ].take(3);
  final pages = await Future.wait([
    for (final id in ids) fetchDocumentRows(customerId: id, unpaid: unpaid, limit: searchPageSize)
  ]);
  return [for (final p in pages) ...p.documents];
}

/// GET /quotes (newest first, ≤200).
Future<List<QuoteRow>> fetchQuoteRows() async {
  final json = await _api.get('/quotes');
  return [
    for (final q in (json['quotes'] as List? ?? const [])) QuoteRow.fromJson(q as Map<String, dynamic>)
  ];
}

/// L's cached lists for the selected business.
Future<Map<String, dynamic>?> readCachedActivity() async {
  final v = await AppCache.read('activity_$_bid');
  return v is Map<String, dynamic> ? v : null;
}

/// The business whose cache keys reads/writes use right now. Callers capture
/// it before awaiting and pass it back to [writeCachedActivity].
String get cacheBusinessKey => _bid;

/// Writes L's lists under [business] (captured when the load started); a no-op
/// once the selected business has changed, so A's rows never land in B's cache.
Future<void> writeCachedActivity(String business, Map<String, dynamic> json) async {
  if (business != _bid) return;
  try {
    await AppCache.write('activity_$business', json);
  } on Object {
    // best effort
  }
}

/// "1,200" / "₪1,200.50" / "1200" → agorot; null when not an amount.
BigInt? parseAmountQuery(String query) {
  final t = query.replaceAll(RegExp(r'[₪,\s]'), '');
  final m = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (m == null) return null;
  final cents = (m.group(2) ?? '').padRight(2, '0');
  return BigInt.parse(m.group(1)!) * BigInt.from(100) + BigInt.parse(cents);
}

/// §6.L search over the loaded rows: name, document number, amount.
/// Digits only → document-number matches first, then amount matches.
List<DocumentSummary> searchDocuments(List<DocumentSummary> docs, String query) {
  final q = query.trim();
  if (q.isEmpty) return docs;
  final lower = q.toLowerCase();
  final amount = parseAmountQuery(q);
  final digitsOnly = RegExp(r'^\d+$').hasMatch(q);
  final byNumber = <DocumentSummary>[];
  final byAmount = <DocumentSummary>[];
  final byName = <DocumentSummary>[];
  for (final d in docs) {
    if (digitsOnly && (d.documentNumber ?? '') == q) {
      byNumber.add(d);
    } else if (amount != null && d.totalMinor.abs() == amount) {
      byAmount.add(d);
    } else if (digitsOnly && (d.documentNumber ?? '').startsWith(q)) {
      byNumber.add(d);
    } else if ((d.customerName ?? '').toLowerCase().contains(lower)) {
      byName.add(d);
    }
  }
  return [...byNumber, ...byAmount, ...byName];
}

List<QuoteRow> searchQuotes(List<QuoteRow> quotes, String query) {
  final q = query.trim();
  if (q.isEmpty) return quotes;
  final lower = q.toLowerCase();
  final amount = parseAmountQuery(q);
  return [
    for (final x in quotes)
      if ((amount != null && x.totalMinor == amount) ||
          (x.customerName ?? '').toLowerCase().contains(lower) ||
          (x.title ?? '').toLowerCase().contains(lower))
        x
  ];
}

/// Rows grouped by month of [dateOf] ('YYYY-MM-DD'; null → [today]'s month),
/// newest month first; order inside a month is kept.
List<MonthGroup<T>> groupByMonth<T>(List<T> rows, String? Function(T) dateOf, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final groups = <String, MonthGroup<T>>{};
  for (final r in rows) {
    final d = DateTime.tryParse(dateOf(r) ?? '') ?? now;
    final key = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
    groups.putIfAbsent(key, () => MonthGroup(d.year, d.month, [])).rows.add(r);
  }
  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) groups[k]!];
}

class MonthGroup<T> {
  MonthGroup(this.year, this.month, this.rows);

  final int year;
  final int month;
  final List<T> rows;

  String get title => InboxHe.monthTitle(year, month);
}
