// C5 · GET /audit-events (server: apps/api/src/routes/v2/audit-log.ts).
//   ?category=documents|payments|team|settings  &cursor=  &limit=
// → {items: [...], nextCursor}. Owner / partner / accountants only (audit:read).

import '../../api/client.dart';
import '../../api/models/json.dart';

/// The filter chips of the screen; null = everything.
enum AuditFilter { documents, payments, team, settings }

class AuditChange {
  const AuditChange(this.field, this.before, this.after);

  factory AuditChange.fromJson(Map<String, dynamic> j) =>
      AuditChange(jStr(j['field']) ?? '', jStr(j['before']), jStr(j['after']));

  final String field;
  final String? before;
  final String? after;
}

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.type,
    required this.category,
    required this.at,
    required this.atIsrael,
    this.actorKind = 'USER',
    this.actorId,
    this.actorName,
    this.actorEmail,
    this.entity = const {},
    this.sensitive = false,
    this.changes = const [],
    this.detail = const {},
  });

  factory AuditEvent.fromJson(Map<String, dynamic> j) {
    final actor = jMap(j['actor']);
    return AuditEvent(
      id: jStr(j['id']) ?? '',
      type: jStr(j['type']) ?? '',
      category: jStr(j['category']) ?? 'other',
      at: jStr(j['at']) ?? '',
      atIsrael: jStr(j['atIsrael']) ?? '',
      actorKind: jStr(actor['kind']) ?? 'USER',
      actorId: jStr(actor['id']),
      actorName: jStr(actor['name']),
      actorEmail: jStr(actor['email']),
      entity: jMap(j['entity']),
      sensitive: j['sensitive'] == true,
      changes: [
        for (final c in (j['changes'] as List? ?? const []))
          if (c is Map<String, dynamic>) AuditChange.fromJson(c),
      ],
      detail: jMap(j['detail']),
    );
  }

  final String id;
  final String type;
  final String category;

  /// ISO-8601 UTC.
  final String at;

  /// Israel wall clock, "YYYY-MM-DD HH:MM".
  final String atIsrael;
  final String actorKind;
  final String? actorId;
  final String? actorName;

  /// Only for a viewer who manages the team.
  final String? actorEmail;
  final Map<String, dynamic> entity;
  final bool sensitive;
  final List<AuditChange> changes;
  final Map<String, dynamic> detail;

  String get entityType => jStr(entity['type']) ?? '';
  String? get documentId => jStr(entity['documentId']);
  String? get documentType => jStr(entity['documentType']);
  String? get documentNumber => jStr(entity['documentNumber']);
  String? get customerName => jStr(entity['customerName']);
  String? get quoteNumber => jStr(entity['quoteNumber']);
  String? get memberName => jStr(entity['memberName']);
  String? get memberEmail => jStr(entity['memberEmail']);
  String? get entityId => jStr(entity['id']);
  String get day => atIsrael.length >= 10 ? atIsrael.substring(0, 10) : '';
  String get time => atIsrael.length >= 16 ? atIsrael.substring(11, 16) : '';
}

class AuditPage {
  const AuditPage(this.items, this.nextCursor);

  factory AuditPage.fromJson(Map<String, dynamic> j) => AuditPage([
    for (final i in (j['items'] as List? ?? const []))
      if (i is Map<String, dynamic>) AuditEvent.fromJson(i),
  ], jStr(j['nextCursor']));

  final List<AuditEvent> items;
  final String? nextCursor;
}

Future<AuditPage> fetchAuditEvents({
  AuditFilter? filter,
  String? cursor,
  int limit = 50,
}) async => AuditPage.fromJson(
  await ApiClient.instance.get(
    '/audit-events',
    query: {
      'limit': '$limit',
      if (filter != null) 'category': filter.name,
      'cursor': ?cursor,
    },
  ),
);
