// C3 "כמו בפעם הקודמת" (QA 2026-11-16, persona 04: the regular client).
// Owner: squad B. One tap fills the Composer with what was issued last for a
// customer: lines, amount and payment method (a split too). The user checks
// the amount and issues: two taps for a regular client.
//
// Source: this device's memory of the last issue for the customer (exactly
// what was typed), else the customer's last issued document on the server
// (GET /documents?customerId → GET /documents/:id). Never a cheque number:
// a new visit means a new cheque.

import 'package:flutter/material.dart';

import '../../api/customers_api.dart' show fetchCustomerDocuments;
import '../../api/issue_api.dart' show cacheWrite, fetchDocument, todayIso;
import '../../api/models/models.dart';
import '../../router.dart' show openCompose;
import '../../state/business_context.dart';
import '../../state/cache.dart';
import '../../util/composer_config.dart';
import '../../util/labels/payment_he.dart' show chipOf;
import '../../util/money.dart';
import '../../util/still_here.dart';
import 'compose_memory.dart' show fetchVatRate, repeatMemoryKey;
import 'compose_state.dart';

/// What "כמו בפעם הקודמת" puts in the Composer.
class RepeatTemplate {
  const RepeatTemplate({
    required this.kind,
    required this.form,
    required this.totalMinor,
  });

  /// The kind issued last time (the customer card opens the Composer with it).
  final DocKind kind;

  /// The [ComposeState.toJson] keys to copy (see [repeatKeys]).
  final Map<String, dynamic> form;

  /// For the label: "כמו בפעם הקודמת · ₪350".
  final BigInt totalMinor;
}

/// The Composer fields a repeat copies; nothing about this visit (customer,
/// notes, dates, allocation request, donor ID).
const List<String> repeatKeys = [
  'amountText',
  'inclusive',
  'description',
  'extraLines',
  'discountText',
  'vatNone',
  'vatPerLine',
  'method',
  'bankNumber',
  'branchNumber',
  'accountNumber',
  'split',
  'splits',
];

/// Kinds a repeat can come from (documents issued for a customer).
const Set<DocKind> _repeatable = {
  DocKind.taxInvoiceReceipt,
  DocKind.taxInvoice,
  DocKind.transactionInvoice,
  DocKind.receipt,
};

String get _memoryKey => repeatMemoryKey;

/// The repeatable fields of [s], cheque numbers cleared and dates reset.
Map<String, dynamic> repeatForm(ComposeState s) {
  final j = s.toJson();
  final splits = [
    for (final l in (j['splits'] as List? ?? const []))
      {...Map<String, dynamic>.from(l as Map), 'checkNumber': '', 'date': null},
  ];
  return {
    for (final k in repeatKeys)
      if (j.containsKey(k)) k: j[k],
    'splits': splits,
  };
}

/// After an issue: remember it for this customer (best effort). Every kind
/// is remembered (the payment method of a 405 too, C2); "כמו בפעם הקודמת"
/// only repeats the [_repeatable] customer kinds ([findRepeat]).
Future<void> rememberRepeat(ComposeState s) async {
  final id = s.customer?.id;
  if (id == null) return;
  try {
    final old = await AppCache.read(_memoryKey);
    final map = <String, dynamic>{
      if (old is Map) ...Map<String, dynamic>.from(old),
    }..remove(id);
    // Newest last; a few hundred regulars are plenty.
    while (map.length >= 300) {
      map.remove(map.keys.first);
    }
    map[id] = {'kind': s.kind.name, 'form': repeatForm(s)};
    await cacheWrite(_memoryKey, map);
  } on Object {
    // memory only
  }
}

/// The template for [customerId]: device memory, else the last issued
/// document on the server. Null when there is nothing to repeat.
Future<RepeatTemplate?> findRepeat(
  String customerId, {
  required String businessType,
  required int vatBasisPoints,
}) async {
  ComposeState fresh(DocKind kind) => ComposeState(
    kind: kind,
    businessType: businessType,
    vatBasisPoints: vatBasisPoints,
  )..agreedTotals = businessContext.me?.lineAgreedTotal ?? false;
  RepeatTemplate? from(DocKind kind, Map<String, dynamic> form) {
    final s = fresh(kind)..restore({...form, 'kind': kind.name});
    if (s.totalMinor <= BigInt.zero) return null;
    return RepeatTemplate(kind: kind, form: form, totalMinor: s.totalMinor);
  }

  try {
    final saved = await AppCache.read(_memoryKey);
    final entry = saved is Map ? saved[customerId] : null;
    if (entry is Map) {
      final kind = DocKind.values.where(
        (k) =>
            k.name == entry['kind'] &&
            _repeatable.contains(k) &&
            configFor(k).counterparty == Counterparty.customer,
      );
      final form = entry['form'];
      if (kind.isNotEmpty && form is Map) {
        final t = from(kind.first, Map<String, dynamic>.from(form));
        if (t != null) return t;
      }
    }
  } on Object {
    // fall through to the server
  }

  final docs = await fetchCustomerDocuments(customerId);
  final last = lastRepeatable(docs);
  if (last == null) return null;
  final doc = await fetchDocument(last.id);
  final kind = kindForServerType(doc.documentType)!;
  final s = fresh(kind);
  if (s.config.receiptOnly || doc.lines.isEmpty) {
    s.amountText = agorotToKeypadText(doc.totalMinor);
  } else {
    s.loadLines(doc.lines);
  }
  final paid = [
    for (final p in doc.payments)
      if (p.voidedAt == null) p,
  ];
  // C2: a wallet transfer (BANK_TRANSFER + "ביט") comes back as its chip.
  String chip(DocumentPaymentRef p) => chipOf(p.method, p.reference);
  if (paid.length == 1) {
    s.method = chip(paid.first);
  } else if (paid.length > 1 && paid.length <= maxSplitLines) {
    s.split = true;
    s.splits.addAll([
      for (final p in paid)
        SplitLine(
          method: chip(p),
          amountText: agorotToKeypadText(p.allocatedMinor ?? p.amountMinor),
        ),
    ]);
    s.method = chip(paid.first);
  }
  return from(kind, repeatForm(s));
}

/// The newest issued, uncancelled document a repeat can copy.
DocumentSummary? lastRepeatable(List<DocumentSummary> docs) {
  final ok = [
    for (final d in docs)
      if (d.documentNumber != null &&
          d.voidedAt == null &&
          !d.amountHidden &&
          _repeatable.contains(kindForServerType(d.documentType)))
        d,
  ];
  if (ok.isEmpty) return null;
  ok.sort((a, b) => (b.issueDate ?? '').compareTo(a.issueDate ?? ''));
  return ok.first;
}

/// Fills [s] from [t]. [switchKind]: also take last time's kind (only when
/// the Composer offers it).
void applyRepeat(ComposeState s, RepeatTemplate t, {bool switchKind = false}) {
  final j = s.toJson()..addAll(t.form);
  if (switchKind) j['kind'] = t.kind.name;
  // A split is the exact money of last time; cheque dates start today.
  final splits = [
    for (final l in (j['splits'] as List? ?? const []))
      {...Map<String, dynamic>.from(l as Map), 'date': todayIso()},
  ];
  s.restore({...j, 'splits': splits});
  s.descriptionTouched = true;
  s.changed();
}

/// Customer card → Composer: the template the next Composer for that
/// customer applies on open (one-shot).
({String customerId, RepeatTemplate template})? composeRepeatNext;

/// Applies [composeRepeatNext] when it is for [s]'s customer.
void takeRepeatFor(ComposeState s) {
  final next = composeRepeatNext;
  composeRepeatNext = null;
  if (next == null || next.customerId != s.customer?.id) return;
  applyRepeat(s, next.template);
}

/// "כמו בפעם הקודמת" on the customer card: finds the template and opens
/// the Composer with it (kind of last time). Nothing found → false.
Future<bool> openRepeat(BuildContext context, String customerId) async {
  RepeatTemplate? t;
  try {
    t = await findRepeat(
      customerId,
      businessType: businessContext.businessType,
      vatBasisPoints: await fetchVatRate(),
    );
  } on Object {
    t = null; // offline with nothing remembered: same as nothing to repeat
  }
  // Late navigation: the customer card was left while the template loaded.
  if (t == null || !context.mounted || !stillHere(context)) return false;
  composeRepeatNext = (customerId: customerId, template: t);
  await openCompose(
    context,
    intent: 'TYPE:${configFor(t.kind).code}',
    customerId: customerId,
  );
  return true;
}
