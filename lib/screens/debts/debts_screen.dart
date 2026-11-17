// C1 · "מי חייב לי" — ONE trustworthy list of who owes the business money.
//
// One row per customer, the oldest overdue debt first (server order). The
// header is the server's open-documents sum — the same figure as Home's
// "מגיע לך" — with the debt book shown NEXT to it, never inside it (a
// debt-book line is an internal note, not a document or revenue). Per
// customer: "שלח תזכורת בווטסאפ" (tone by the reminders already sent),
// "קיבלתי תשלום" (the existing payment flow) and the documents. A debt-book
// line: edit, "הפק קבלה" (a real receipt that closes it) or delete.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/debts_api.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/debts_he.dart';
import '../../util/labels/reminder_he.dart';
import '../../util/payment_reminder.dart' show daysSince;
import '../../util/still_here.dart';
import '../../util/labels/collection_he.dart';
import 'collection_batch_screen.dart';
import 'debt_entry_sheet.dart';
import 'debt_reminder.dart';

/// Loads the list (tests replace it).
Future<WhoOwesMe> Function() loadWhoOwesMe = fetchWhoOwesMe;

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key, this.now, this.openBatch = false});

  /// Injectable clock (tests).
  final DateTime Function()? now;

  /// 0111: open "תזכורות מוכנות לשליחה" at once (the daily summary push).
  final bool openBatch;

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  WhoOwesMe? _data;
  Object? _error;

  /// 0111: WhatsApp reminders waiting for a tap (0 = no banner).
  int _ready = 0;
  final Set<String> _expanded = {};

  Caps get _caps => businessContext.caps;
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (widget.openBatch && _mayBatch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openBatch());
      });
    }
  }

  bool get _mayBatch => _caps.can(Cap.docSend) && _caps.can(Cap.moneyView);

  Future<void> _loadReady() async {
    if (!_mayBatch) return;
    try {
      final n = (await loadReadyReminders()).length;
      if (mounted && n != _ready) setState(() => _ready = n);
    } on Object {
      // A hint only: the list works without it.
    }
  }

  Future<void> _openBatch() async {
    await openCollectionBatch(context);
    await _load();
  }

  Future<void> _load() async {
    // Also runs after an await (a reminder, a sheet): the screen may be gone.
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final data = await loadWhoOwesMe();
      if (mounted) setState(() => _data = data);
      unawaited(_loadReady());
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add({Customer? customer}) async {
    final saved = await showDebtEntrySheet(context, customer: customer);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(DebtsHe.saved)));
      await _load();
    }
  }

  Future<void> _remind(Debtor d) async {
    try {
      await remindDebtor(d, now: _now, alive: () => stillHere(context));
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    await _load();
  }

  /// "קיבלתי תשלום": the existing receipt flow for this customer. When all
  /// that is open is in the debt book, the receipt starts with its total and
  /// notes and closes those lines once issued.
  Future<void> _paid(Debtor d) async {
    final id = d.customerId;
    if (id == null) return;
    if (d.documents.isEmpty && d.debtEntries.isNotEmpty) {
      return _receiptFor(id, d.debtEntries);
    }
    await openCompose(context, intent: 'PAID', customerId: id);
    if (mounted) await _load();
  }

  /// "הפק קבלה" for debt-book lines → the real receipt, then the lines close.
  Future<void> _receiptFor(String customerId, List<DebtEntry> entries) async {
    final closing = <Future<void>>[];
    var failed = false;
    final total = entries.fold(BigInt.zero, (s, e) => s + e.amountMinor);
    await openCompose(
      context,
      intent: 'PAID',
      customerId: customerId,
      prefillAmountMinor: total,
      prefillDescription: entries.map((e) => e.note).join(', '),
      onIssued: (receiptId) {
        for (final e in entries) {
          closing.add(
            closeDebtEntry(
              e.id,
              receiptId,
            ).then<void>((_) {}, onError: (Object _) => failed = true),
          );
        }
      },
    );
    await Future.wait(closing);
    if (!mounted) return;
    if (closing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failed ? DebtsHe.closeFailed : DebtsHe.closed)),
      );
    }
    await _load();
  }

  Future<void> _documents(Debtor d) async {
    if (d.documents.length == 1) {
      await openDocument(context, d.documents.single.id);
    } else if (d.customerId != null) {
      await openPerson(context, d.customerId!);
    }
    if (mounted) await _load();
  }

  Future<void> _editEntry(Debtor d, DebtEntry e) async {
    final saved = await showDebtEntrySheet(
      context,
      edit: e,
      customerName: d.customerName,
    );
    if (saved != null && mounted) await _load();
  }

  Future<void> _deleteEntry(DebtEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(DebtsHe.deleteConfirmTitle),
        content: const Text(DebtsHe.deleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text(DebtsHe.cancel),
          ),
          TextButton(
            key: const Key('debt-delete-confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text(DebtsHe.deleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteDebtEntry(e.id);
    } on Object catch (err) {
      if (mounted) showErrorSnack(context, err);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final canAdd = _caps.can(Cap.docDraft) && _caps.can(Cap.moneyView);
    return Scaffold(
      key: const Key('debts-screen'),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.m,
                Space.page,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(DebtsHe.title, style: AppText.displayTitle),
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Expanded(
              child: data == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(onRefresh: _load, child: _list(data)),
            ),
            if (data != null && canAdd)
              BottomActionArea(
                child: PrimaryButton(
                  key: const Key('debts-add'),
                  icon: Iconsax.note_add,
                  label: DebtsHe.add,
                  onPressed: () => unawaited(_add()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 0111: "N תזכורות מוכנות לשליחה" → the daily WhatsApp batch.
  List<Widget> _readyBanner() => [
    if (_ready > 0) ...[
      AppCard(
        key: const Key('debts-ready-banner'),
        onTap: () => unawaited(_openBatch()),
        child: Row(
          children: [
            const Icon(Iconsax.message_time),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(
                CollectionHe.batchBanner(_ready),
                style: AppText.headline,
              ),
            ),
            Text(
              CollectionHe.batchBannerAction,
              style: AppText.body.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: Space.m),
    ],
  ];

  Widget _list(WhoOwesMe data) {
    if (data.customers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        children: [
          const SizedBox(height: Space.s),
          ..._readyBanner(),
          const SizedBox(height: Space.xxl),
          const EmptyState(
            key: Key('debts-empty'),
            icon: Iconsax.happyemoji,
            title: DebtsHe.empty,
            message: DebtsHe.emptyBody,
          ),
        ],
      );
    }
    return ListView(
      key: const Key('debts-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        Space.xl,
      ),
      children: [
        ..._readyBanner(),
        MoneyCard(
          key: const Key('debts-header'),
          label: DebtsHe.headerLabel,
          amountMinor: data.documentsOpenMinor,
          secondaryLabel: data.documentsOverdueMinor > BigInt.zero
              ? DebtsHe.headerOverdue
              : null,
          secondaryMinor: data.documentsOverdueMinor > BigInt.zero
              ? data.documentsOverdueMinor
              : null,
        ),
        if (data.debtBookOpenMinor > BigInt.zero) ...[
          const SizedBox(height: Space.s),
          _BookExtra(amountMinor: data.debtBookOpenMinor),
        ],
        const SizedBox(height: Space.l),
        for (final d in data.customers) ...[
          _DebtorCard(
            key: Key('debtor-${d.customerId ?? 'none'}'),
            debtor: d,
            now: _now,
            caps: _caps,
            expanded: _expanded.contains(d.customerId ?? '-'),
            onToggle: () => setState(() {
              final k = d.customerId ?? '-';
              _expanded.contains(k) ? _expanded.remove(k) : _expanded.add(k);
            }),
            onRemind: () => unawaited(_remind(d)),
            onPaid: () => unawaited(_paid(d)),
            onDocuments: () => unawaited(_documents(d)),
            onOpenDocument: (id) =>
                unawaited(openDocument(context, id).then((_) => _load())),
            onEditEntry: (e) => unawaited(_editEntry(d, e)),
            onReceiptEntry: (e) => unawaited(_receiptFor(d.customerId!, [e])),
            onDeleteEntry: (e) => unawaited(_deleteEntry(e)),
          ),
          const SizedBox(height: Space.m),
        ],
      ],
    );
  }
}

class _BookExtra extends StatelessWidget {
  const _BookExtra({required this.amountMinor});

  final BigInt amountMinor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      key: const Key('debts-book-extra'),
      children: [
        Icon(Iconsax.book, size: 18, color: p.muted),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            '${DebtsHe.bookExtra} · ${DebtsHe.bookExtraNote}',
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ),
        AmountText(amountMinor, style: AppText.amountSmall),
      ],
    );
  }
}

class _DebtorCard extends StatelessWidget {
  const _DebtorCard({
    super.key,
    required this.debtor,
    required this.now,
    required this.caps,
    required this.expanded,
    required this.onToggle,
    required this.onRemind,
    required this.onPaid,
    required this.onDocuments,
    required this.onOpenDocument,
    required this.onEditEntry,
    required this.onReceiptEntry,
    required this.onDeleteEntry,
  });

  final Debtor debtor;
  final DateTime now;
  final Caps caps;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onRemind;
  final VoidCallback onPaid;
  final VoidCallback onDocuments;
  final ValueChanged<String> onOpenDocument;
  final ValueChanged<DebtEntry> onEditEntry;
  final ValueChanged<DebtEntry> onReceiptEntry;
  final ValueChanged<DebtEntry> onDeleteEntry;

  String get _age {
    final d = debtor;
    if (d.oldestOverdueDays != null) {
      return DebtsHe.overdueDays(d.oldestOverdueDays!);
    }
    if (d.documents.isEmpty && d.oldestEntryDays != null) {
      return DebtsHe.bookSince(d.oldestEntryDays!);
    }
    return DebtsHe.notOverdue;
  }

  String get _reminded => debtor.lastRemindedAt == null
      ? DebtsHe.neverReminded
      : ReminderHe.lastReminded(daysSince(debtor.lastRemindedAt!, now));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = debtor;
    final name = d.customerName.isEmpty ? DebtsHe.noCustomer : d.customerName;
    final key = d.customerId ?? 'none';
    final overdue = d.oldestOverdueDays != null;
    return AppCard(
      onTap: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.headline),
                    const SizedBox(height: Space.xs),
                    Text(
                      _age,
                      key: Key('debtor-age-$key'),
                      style: AppText.secondary.copyWith(
                        color: overdue ? p.danger : p.muted,
                      ),
                    ),
                    Text(
                      _reminded,
                      key: Key('debtor-reminded-$key'),
                      style: AppText.caption.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              AmountText(
                d.totalMinor,
                key: Key('debtor-total-$key'),
                style: AppText.amountRow,
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: Space.s),
            for (final doc in d.documents)
              ListTile(
                key: Key('debt-doc-${doc.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Iconsax.document_text, size: 20),
                title: Text(
                  ReminderHe.documentLine(doc.documentType, doc.documentNumber),
                ),
                subtitle: Text(
                  doc.overdueDays > 0
                      ? DebtsHe.overdueDays(doc.overdueDays)
                      : DebtsHe.notOverdue,
                ),
                trailing: AmountText(doc.openMinor, style: AppText.amountSmall),
                onTap: () => onOpenDocument(doc.id),
              ),
            for (final e in d.debtEntries)
              ListTile(
                key: Key('debt-entry-${e.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Iconsax.book, size: 20),
                title: Text(e.note),
                subtitle: Text(
                  '${DebtsHe.bookBadge} · ${DebtsHe.bookSince(daysSince(DateTime.parse(e.debtDate), now))}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AmountText(e.amountMinor, style: AppText.amountSmall),
                    if (caps.can(Cap.docDraft) || caps.can(Cap.paymentIssue))
                      MoreMenu(
                        items: [
                          if (caps.can(Cap.paymentIssue))
                            MoreMenuItem(
                              label: DebtsHe.issueReceipt,
                              icon: Iconsax.receipt_add,
                              onSelected: () => onReceiptEntry(e),
                            ),
                          if (caps.can(Cap.docDraft))
                            MoreMenuItem(
                              label: DebtsHe.delete,
                              icon: Iconsax.trash,
                              destructive: true,
                              onSelected: () => onDeleteEntry(e),
                            ),
                        ],
                      ),
                  ],
                ),
                onTap: caps.can(Cap.docDraft) ? () => onEditEntry(e) : null,
              ),
          ],
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.xs,
            children: [
              if (caps.can(Cap.docSend))
                FilledButton.tonalIcon(
                  key: Key('debtor-remind-$key'),
                  onPressed: onRemind,
                  icon: const Icon(Iconsax.message, size: 18),
                  label: Semantics(
                    label: DebtsHe.remindA11y(name),
                    excludeSemantics: true,
                    child: const Text(DebtsHe.remind),
                  ),
                ),
              if (caps.can(Cap.paymentIssue) && d.customerId != null)
                TextButton.icon(
                  key: Key('debtor-paid-$key'),
                  onPressed: onPaid,
                  icon: const Icon(Iconsax.money_recive, size: 18),
                  label: const Text(DebtsHe.paid),
                ),
              if (d.documents.isNotEmpty)
                TextButton.icon(
                  key: Key('debtor-docs-$key'),
                  onPressed: onDocuments,
                  icon: const Icon(Iconsax.document_text, size: 18),
                  label: const Text(DebtsHe.documents),
                ),
            ],
          ),
          if (caps.can(Cap.docSend))
            Text(
              DebtsHe.nextTone(d.reminderCount),
              key: Key('debtor-tone-$key'),
              style: AppText.caption.copyWith(color: p.muted),
            ),
        ],
      ),
    );
  }
}
