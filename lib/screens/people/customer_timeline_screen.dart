// P2 · "ציר זמן" (0110): everything that happened with one customer, newest
// first, grouped by Israel day — documents (issued / sent / viewed /
// cancelled), quotes, payments, the debt book, reminders, monthly charges,
// correction requests and manual notes (GET /customers/:id/timeline).
//
// What the member may not read never arrives (the server filters by role);
// an amount the member may not see arrives as null + amountHidden and shows
// as "—", never ₪0. A row opens its document / quote; the member's own note
// opens edit / delete. "הוסף הערה" writes a note (managers and drafters).
// Minimal notifications: nothing here pushes anything.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/customer_timeline_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/israel_date.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/timeline_he.dart';
import '../../util/still_here.dart';
import '../../ui/widgets/notch_notice.dart';

/// Opens the timeline of [customerId].
Future<void> openCustomerTimeline(
  BuildContext context, {
  required String customerId,
  required String customerName,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => CustomerTimelineScreen(
      customerId: customerId,
      customerName: customerName,
    ),
    settings: RouteSettings(name: '/person/$customerId/timeline'),
  ),
);

/// Who may write a note (server: customer:manage or document:draft:write).
bool canWriteCustomerNote(Caps caps) =>
    caps.can(Cap.customerManage) || caps.can(Cap.docDraft);

class CustomerTimelineScreen extends StatefulWidget {
  const CustomerTimelineScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final String customerId;
  final String customerName;

  @override
  State<CustomerTimelineScreen> createState() => _CustomerTimelineScreenState();
}

class _CustomerTimelineScreenState extends State<CustomerTimelineScreen> {
  TimelineSource? _source;
  List<TimelineItem>? _items;
  List<String> _sources = const [];
  String? _cursor;
  Object? _error;
  bool _loadingMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _items = null;
      _error = null;
      _cursor = null;
    });
    try {
      final page = await fetchCustomerTimeline(
        widget.customerId,
        source: _source,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        if (_source == null) _sources = page.sources;
      });
    } on Object catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() => _error = e);
    }
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await fetchCustomerTimeline(
        widget.customerId,
        source: _source,
        cursor: cursor,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _cursor = page.nextCursor;
      });
    } on Object catch (e) {
      if (mounted && gen == _generation) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _select(TimelineSource? s) {
    _source = s;
    unawaited(_load());
  }

  Future<void> _addNote() async {
    final saved = await showNoteSheet(context, customerId: widget.customerId);
    if (saved == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showNotchNotice(const SnackBar(content: Text(TimelineHe.noteSaved)));
      unawaited(_load());
    }
  }

  Future<void> _open(TimelineItem item) async {
    final id = item.linkId;
    if (id == null) return;
    switch (item.linkType) {
      case 'document':
        await openDocument(context, id);
      case 'quote':
        await openQuote(context, id);
      case 'debtEntry':
        if (businessContext.can(Cap.moneyView)) await openDebts(context);
      case 'customerNote':
        if (item.mine) await _noteActions(item);
    }
  }

  bool _tappable(TimelineItem i) =>
      i.linkId != null &&
      switch (i.linkType) {
        'document' || 'quote' => true,
        'debtEntry' => businessContext.can(Cap.moneyView),
        'customerNote' => i.mine,
        _ => false,
      };

  Future<void> _noteActions(TimelineItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('note-edit'),
              leading: const Icon(Iconsax.edit),
              title: const Text(TimelineHe.noteEdit),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              key: const Key('note-delete'),
              leading: Icon(Iconsax.trash, color: context.palette.danger),
              title: Text(
                TimelineHe.noteDelete,
                style: TextStyle(color: context.palette.danger),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      final saved = await showNoteSheet(
        context,
        customerId: widget.customerId,
        noteId: item.linkId,
        initial: item.noteBody,
      );
      if (saved == true && mounted) unawaited(_load());
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text(TimelineHe.noteDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('note-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text(TimelineHe.noteDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteCustomerNote(item.linkId!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showNotchNotice(const SnackBar(content: Text(TimelineHe.noteDeleted)));
      unawaited(_load());
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final canNote = canWriteCustomerNote(businessContext.caps);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.m,
                Space.page,
                Space.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        TimelineHe.title,
                        style: AppText.displayTitle,
                      ),
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                0,
                Space.page,
                Space.m,
              ),
              child: Text(
                widget.customerName,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
            if (_sources.length > 1)
              ChipRow<TimelineSource?>(
                key: const Key('timeline-chips'),
                options: [
                  const ChipOption(null, TimelineHe.chipAll),
                  for (final s in TimelineSource.values)
                    if (_sources.contains(s.name))
                      ChipOption(s, TimelineHe.chips[s.name] ?? s.name),
                ],
                selected: _source,
                onSelected: _select,
              ),
            const SizedBox(height: Space.s),
            Expanded(child: _body(context)),
            if (canNote)
              BottomActionArea(
                child: OutlinedButton.icon(
                  key: const Key('timeline-add-note'),
                  onPressed: businessContext.offline ? null : _addNote,
                  icon: const Icon(Iconsax.note_add, size: 18),
                  label: const Text(TimelineHe.addNote),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final error = _error;
    if (error != null && (_items == null || _items!.isEmpty)) {
      return ErrorView(error: error, onRetry: () => unawaited(_load()));
    }
    final items = _items;
    if (items == null) return const SkeletonList();
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _source == null
                ? const EmptyState(
                    key: Key('timeline-empty'),
                    icon: Iconsax.clock,
                    title: TimelineHe.empty,
                    message: TimelineHe.emptyHint,
                  )
                : EmptyState(
                    key: const Key('timeline-empty-filtered'),
                    icon: Iconsax.clock,
                    title: TimelineHe.emptyFiltered(
                      TimelineHe.chips[_source!.name] ?? _source!.name,
                    ),
                    message: TimelineHe.emptyFilteredHint,
                  ),
          ],
        ),
      );
    }
    final rows = <Widget>[];
    String? day;
    for (final i in items) {
      if (i.day != day) {
        day = i.day;
        rows.add(_DayHeader(day));
      }
      rows.add(
        TimelineRow(
          key: Key('timeline-row-${i.id}'),
          item: i,
          onTap: _tappable(i) ? () => unawaited(_open(i)) : null,
        ),
      );
    }
    if (_cursor != null || _loadingMore) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator.adaptive()
                : TextButton(
                    key: const Key('timeline-more'),
                    onPressed: () => unawaited(_more()),
                    child: const Text(TimelineHe.loadMore),
                  ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('timeline-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
        children: rows,
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);

  final String day;

  @override
  Widget build(BuildContext context) {
    final today = israelTodayDate();
    final label = day == isoDate(today)
        ? TimelineHe.today
        : day == isoDate(DateTime(today.year, today.month, today.day - 1))
        ? TimelineHe.yesterday
        : formatDateHe(day);
    return Padding(
      padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: AppText.secondary.copyWith(color: context.palette.muted),
        ),
      ),
    );
  }
}

/// One event: an icon by kind, the sentence, time · who, and the amount
/// ("—" when the member may not see it).
class TimelineRow extends StatelessWidget {
  const TimelineRow({super.key, required this.item, this.onTap});

  final TimelineItem item;
  final VoidCallback? onTap;

  IconData get _icon {
    final k = item.kind;
    if (k == 'note') return Iconsax.note_2;
    if (k == 'portal.message') return Iconsax.message_text;
    if (k.startsWith('quote.')) return Iconsax.document_favorite;
    if (k.startsWith('payment.')) return Iconsax.money_recive;
    if (k.startsWith('debt.')) return Iconsax.note_add;
    if (k.startsWith('reminder.')) return Iconsax.notification_bing;
    if (k.startsWith('recurring.')) return Iconsax.calendar_tick;
    if (k.startsWith('correction.')) return Iconsax.edit_2;
    if (k.startsWith('calendar.')) return Iconsax.calendar_2;
    if (k == 'document.sent') return Iconsax.send_2;
    if (k == 'document.viewed') return Iconsax.eye;
    return Iconsax.document_text;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sentence = timelineSentence(item.kind, item.data);
    final detail = [
      item.time,
      if (item.kind == 'note' || item.actorName != null) ?item.actorName,
      // #12: the card's "פתק" (edited there, read-only here).
      if (item.kind == 'note' && item.data['source'] == 'customerCard')
        TimelineHe.fromCustomerCard,
      if (item.kind == 'note' && item.data['edited'] == true)
        TimelineHe.noteEdited,
    ].where((s) => s.isNotEmpty).join(' · ');
    // A credit note reduces what the customer owes: shown with a minus.
    final raw = item.amountMinor;
    final amount = raw != null && item.data['documentType'] == 'CREDIT_DOCUMENT'
        ? -raw.abs()
        : raw;
    final voided = item.kind == 'payment.voided' || item.kind == 'debt.deleted';
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(Space.m),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(_icon, size: 20, color: p.muted),
              ),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sentence,
                      style: AppText.body,
                      maxLines:
                          item.kind == 'note' || item.kind == 'portal.message'
                          ? 6
                          : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (amount != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: Space.s),
                  child: AmountText(amount, color: voided ? p.muted : null),
                )
              else if (item.amountHidden)
                Padding(
                  key: const Key('timeline-amount-hidden'),
                  padding: const EdgeInsetsDirectional.only(start: Space.s),
                  child: Semantics(
                    label: TimelineHe.hiddenAmount,
                    excludeSemantics: true,
                    child: Text(
                      '—',
                      style: AppText.amountRow.copyWith(color: p.muted),
                    ),
                  ),
                ),
              // No chevron after an amount: amounts share the row's end
              // edge whether the row opens something or not (2026-11-23).
              if (onTap != null && amount == null && !item.amountHidden)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    top: 2,
                    start: Space.s,
                  ),
                  child: Icon(Iconsax.arrow_left_2, size: 16, color: p.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "הוסף הערה" / edit. Returns true when saved.
Future<bool?> showNoteSheet(
  BuildContext context, {
  required String customerId,
  String? noteId,
  String? initial,
}) => showAppSheet<bool>(
  context,
  builder: (_) =>
      NoteSheet(customerId: customerId, noteId: noteId, initial: initial),
);

class NoteSheet extends StatefulWidget {
  const NoteSheet({
    super.key,
    required this.customerId,
    this.noteId,
    this.initial,
  });

  final String customerId;
  final String? noteId;
  final String? initial;

  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _text.text.trim();
    if (body.isEmpty) return setState(() => _error = TimelineHe.noteEmpty);
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      if (widget.noteId == null) {
        await addCustomerNote(widget.customerId, body);
      } else {
        await updateCustomerNote(widget.noteId!, body);
      }
      if (mounted && stillHere(context)) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('note-sheet'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SheetTitle(
        widget.noteId == null ? TimelineHe.addNote : TimelineHe.editNoteTitle,
      ),
      TextField(
        key: const Key('note-text'),
        controller: _text,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        maxLength: 2000,
        decoration: InputDecoration(
          hintText: TimelineHe.noteHint,
          errorText: _error,
        ),
      ),
      const SizedBox(height: Space.s),
      PrimaryButton(
        key: const Key('note-save'),
        label: TimelineHe.noteSave,
        loadingText: _saving ? TimelineHe.noteSave : null,
        onPressed: _save,
      ),
    ],
  );
}
