// "תזכורות מוכנות לשליחה" — the owner's daily WhatsApp batch (server 0111).
//
// E-mail reminders already left from the server by themselves; what waits
// here are the customers without an e-mail. One tap per customer opens
// WhatsApp with the server's message (the owner's wording), the phone's own
// share link in place of {קישור}; the send is recorded on the server (ledger
// + the phone reminder log, so every device sees "last reminded"). A paid
// document never appears (the server filters on every read).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/collection_reminders_api.dart';
import '../../api/inbox_api.dart' show shareLinkFor;
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/collection_he.dart';
import '../../util/labels/document_he.dart' show docTypeLabel;
import '../../util/money.dart';
import '../../util/phone.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/still_here.dart';
import '../document/sheets/s6_share.dart' show textSharer;

/// Loads the batch (tests replace it).
Future<List<CollectionReminder>> Function() loadReadyReminders =
    fetchReadyReminders;

/// The text that leaves: {קישור} → [link]; no link → that line is dropped.
String fillReminderLink(String text, String? link) {
  if (link != null && link.isNotEmpty) return text.replaceAll('{קישור}', link);
  return text
      .split('\n')
      .where((l) => !l.contains('{קישור}'))
      .join('\n')
      .trim();
}

Future<void> openCollectionBatch(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const CollectionBatchScreen()));

class CollectionBatchScreen extends StatefulWidget {
  const CollectionBatchScreen({super.key});

  @override
  State<CollectionBatchScreen> createState() => _CollectionBatchScreenState();
}

class _CollectionBatchScreenState extends State<CollectionBatchScreen> {
  List<CollectionReminder>? _items;
  Object? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final items = await loadReadyReminders();
      if (mounted) setState(() => _items = items);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _drop(String id) =>
      setState(() => _items = [...?_items?.where((r) => r.id != id)]);

  Future<void> _send(CollectionReminder r) async {
    setState(() => _busy.add(r.id));
    try {
      String? link;
      if (r.documentId != null) {
        try {
          link = await shareLinkFor(r.documentId!);
        } on Object {
          link = r.paymentUrl; // the message still goes, with the payment page
        }
      } else {
        link = r.paymentUrl;
      }
      if (!mounted || !stillHere(context)) return;
      final text = fillReminderLink(r.messageText, link);
      final wa = waPhone(r.phone);
      var opened = false;
      if (wa != null) {
        opened = await launchAllowed(whatsAppUri(phone: wa, text: text));
      }
      if (!opened) await textSharer(text);
      await markCollectionReminderSent(r.id, opened ? 'WHATSAPP' : 'SHARE');
      if (!mounted) return;
      _drop(r.id);
      ScaffoldMessenger.of(context).showNotchNotice(
        const SnackBar(content: Text(CollectionHe.sentNotice)),
        motion: NoticeMotion.reminder,
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  Future<void> _skip(CollectionReminder r) async {
    setState(() => _busy.add(r.id));
    try {
      await dismissCollectionReminder(r.id);
      if (!mounted) return;
      _drop(r.id);
      ScaffoldMessenger.of(context).showNotchNotice(
        const SnackBar(content: Text(CollectionHe.skippedNotice)),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      key: const Key('collection-batch'),
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
                      child: Text(
                        CollectionHe.batchTitle,
                        style: AppText.displayTitle,
                      ),
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            OfflineBanner(visible: session.offline),
            Expanded(
              child: items == null
                  ? (_error != null
                        ? ErrorView(error: _error!, onRetry: _load)
                        : const SingleChildScrollView(child: SkeletonList()))
                  : RefreshIndicator(onRefresh: _load, child: _list(items)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(List<CollectionReminder> items) {
    final p = context.palette;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: Space.xxl),
          EmptyState(
            key: Key('collection-batch-empty'),
            icon: Iconsax.tick_circle,
            title: CollectionHe.batchEmpty,
            message: CollectionHe.batchEmptyBody,
          ),
        ],
      );
    }
    return ListView(
      key: const Key('collection-batch-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        Space.xl,
      ),
      children: [
        Text(
          CollectionHe.batchHint,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.m),
        for (final r in items) ...[
          _ReminderCard(
            key: Key('collection-item-${r.id}'),
            reminder: r,
            busy: _busy.contains(r.id) || session.offline,
            onSend: () => unawaited(_send(r)),
            onSkip: () => unawaited(_skip(r)),
          ),
          const SizedBox(height: Space.m),
        ],
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    super.key,
    required this.reminder,
    required this.busy,
    required this.onSend,
    required this.onSkip,
  });

  final CollectionReminder reminder;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = reminder;
    final name = r.customerName ?? '';
    final what = r.documentId == null
        ? CollectionHe.debtLine
        : [
            docTypeLabel(r.documentType ?? ''),
            if ((r.documentNumber ?? '').isNotEmpty) 'מס׳ ${r.documentNumber}',
          ].join(' ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.headline),
                    const SizedBox(height: Space.xs),
                    Text(
                      '$what · ${CollectionHe.stepLabel(r.offsetDays)}',
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              if (r.openMinor != null)
                Text(
                  formatMoney(r.openMinor!),
                  style: AppText.amountCard,
                  textDirection: TextDirection.ltr,
                ),
            ],
          ),
          const SizedBox(height: Space.m),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: CollectionHe.sendA11y(name),
                  button: true,
                  excludeSemantics: true,
                  child: FilledButton.icon(
                    key: Key('collection-send-${r.id}'),
                    onPressed: busy ? null : onSend,
                    icon: const Icon(Iconsax.message),
                    label: const Text(CollectionHe.send),
                  ),
                ),
              ),
              const SizedBox(width: Space.s),
              TextButton(
                key: Key('collection-skip-${r.id}'),
                onPressed: busy ? null : onSkip,
                child: const Text(CollectionHe.skip),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
