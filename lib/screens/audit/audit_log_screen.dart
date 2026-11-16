// C5 · "יומן פעולות" (QA 2026-11-16 persona 05 pain 3, persona 06): who did
// what in the business, from the server's append-only audit chain
// (GET /audit-events). Owner, partner and accountants only — the row in B
// shows only for them, and the server refuses everyone else (audit:read).
//
// One timeline, newest first, grouped by Israel day; filter chips
// הכל / מסמכים / תשלומים / צוות והרשאות / הגדרות; plain Hebrew sentences;
// a quiet "שינוי רגיש" marker on approvals switched off, role / permission
// changes and bank details; tap opens the document, quote, customer or team.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/money_text.dart' show moneyText;
import '../../ui/theme.dart';
import '../../ui/widgets/chip_row.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/error_view.dart';
import '../../ui/widgets/skeleton.dart';
import '../../util/labels/audit_he.dart';
import '../../util/labels/common_he.dart' show formatDateHe;
import 'audit_api.dart';
import 'audit_sentence.dart';

/// Opens the activity log.
Future<void> openAuditLog(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => const AuditLogScreen(),
    settings: const RouteSettings(name: '/business/audit'),
  ),
);

/// Who may open it (server: OWNER, ADMIN, ACCOUNTANT, ACCOUNTANT_REP).
/// The row is shown exactly when the server would answer: `audit:read`
/// (owner, partner, full / representing accountant — a READ_ONLY member on
/// the representing-accountant preset does not have it).
bool canViewAuditLog(Caps caps) => caps.can(Cap.auditView);

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  AuditFilter? _filter;
  List<AuditEvent>? _items;
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
      final page = await fetchAuditEvents(filter: _filter);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
      });
    } catch (e) {
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
      final page = await fetchAuditEvents(filter: _filter, cursor: cursor);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _cursor = page.nextCursor;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _select(AuditFilter? f) {
    _filter = f;
    unawaited(_load());
  }

  void _open(AuditEvent e) {
    final docId = e.documentId;
    final id = e.entityId;
    if (docId != null) {
      unawaited(openDocument(context, docId));
    } else if (e.entityType == 'quote' && id != null) {
      unawaited(openQuote(context, id));
    } else if (e.entityType == 'customer' && id != null) {
      unawaited(openPerson(context, id));
    } else if (e.entityType == 'member' &&
        businessContext.can(Cap.teamManage)) {
      unawaited(openBusinessSection(context, BusinessSection.team));
    }
  }

  bool _tappable(AuditEvent e) =>
      e.documentId != null ||
      ((e.entityType == 'quote' || e.entityType == 'customer') &&
          e.entityId != null) ||
      (e.entityType == 'member' && businessContext.can(Cap.teamManage));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text(AuditHe.title)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.s,
                Space.page,
                Space.m,
              ),
              child: Text(
                AuditHe.intro,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
            ChipRow<AuditFilter?>(
              key: const Key('audit-chips'),
              options: const [
                ChipOption(null, AuditHe.chipAll),
                ChipOption(AuditFilter.documents, AuditHe.chipDocuments),
                ChipOption(AuditFilter.payments, AuditHe.chipPayments),
                ChipOption(AuditFilter.team, AuditHe.chipTeam),
                ChipOption(AuditFilter.settings, AuditHe.chipSettings),
              ],
              selected: _filter,
              onSelected: _select,
            ),
            const SizedBox(height: Space.m),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final error = _error;
    if (error != null && (_items == null || _items!.isEmpty)) {
      if (error is ApiException && error.status == 403) {
        return const EmptyState(
          key: Key('audit-forbidden'),
          icon: Iconsax.lock,
          title: AuditHe.forbidden,
        );
      }
      return ErrorView(error: error, onRetry: () => unawaited(_load()));
    }
    final items = _items;
    if (items == null) return const SkeletonList();
    if (items.isEmpty) {
      return const EmptyState(
        key: Key('audit-empty'),
        icon: Iconsax.note_2,
        title: AuditHe.empty,
        message: AuditHe.emptyHint,
      );
    }
    final rows = <Widget>[];
    String? day;
    for (final e in items) {
      if (e.day != day) {
        day = e.day;
        rows.add(_DayHeader(day));
      }
      rows.add(
        AuditRow(
          key: Key('audit-row-${e.id}'),
          event: e,
          onTap: _tappable(e) ? () => _open(e) : null,
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
                    key: const Key('audit-more'),
                    onPressed: () => unawaited(_more()),
                    child: const Text(AuditHe.loadMore),
                  ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('audit-list'),
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
    final now = DateTime.now();
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final label = day == iso(now)
        ? AuditHe.today
        : day == iso(now.subtract(const Duration(days: 1)))
        ? AuditHe.yesterday
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

/// One event: an icon by kind, the sentence, time and before→after.
class AuditRow extends StatelessWidget {
  const AuditRow({super.key, required this.event, this.onTap});

  final AuditEvent event;
  final VoidCallback? onTap;

  IconData get _icon => switch (event.category) {
    'documents' => Iconsax.document_text,
    'payments' => Iconsax.money_recive,
    'team' => Iconsax.profile_2user,
    'settings' => Iconsax.setting_2,
    _ => Iconsax.activity,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String money(BigInt m) => moneyText(context, m);
    final sentence = auditSentence(event, money: money);
    final detail = auditDetailLine(event, money: money);
    return Semantics(
      button: onTap != null,
      label: event.sensitive ? '${AuditHe.sensitive}. $sentence' : null,
      child: InkWell(
        onTap: onTap,
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
                    Text(sentence, style: AppText.body),
                    if (detail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          detail,
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                      ),
                    if (event.sensitive)
                      Padding(
                        key: const Key('audit-sensitive'),
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Iconsax.danger, size: 14, color: p.warn),
                            const SizedBox(width: Space.xs),
                            ExcludeSemantics(
                              child: Text(
                                AuditHe.sensitive,
                                style: AppText.secondary.copyWith(
                                  color: p.warn,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
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
