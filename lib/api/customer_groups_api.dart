// V4 §8 · קבוצות לקוחות — the server's /customer-groups routes (0133).
//
// A group is a named, coloured list of customers (a customer may be in many);
// three smart groups are computed by the server (חייבים לי, לא קנו 90 יום,
// לא פעילים). Group actions run on the server: payment request to everyone
// who owes, broadcast, the same document to everyone, a personal booking link
// to each member, a statement to each. Each action is previewed first, then
// run once under an Idempotency-Key (a retry of the same confirm reuses the
// key, so nothing is sent or issued twice). WhatsApp leaves only by the
// owner's tap (a queue of run items), never automatically.

import 'client.dart';
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

/// Smart group keys (also their ids in the path).
const smartOwes = 'OWES';
const smartNoPurchase = 'NO_PURCHASE_90';
const smartInactive = 'INACTIVE';

/// The colour keys a custom group may take (server contract).
const groupColorKeys = <String>[
  'blue',
  'green',
  'orange',
  'pink',
  'purple',
  'yellow',
  'teal',
  'red',
];

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.color,
    required this.memberCount,
    this.smart,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
    id: jStr(j['id']) ?? '',
    name: jStr(j['name']) ?? '',
    color: jStr(j['color']) ?? 'blue',
    memberCount: jIntOrNull(j['memberCount']) ?? 0,
    smart: jStr(j['smart']),
  );

  final String id;
  final String name;
  final String color;
  final int memberCount;

  /// OWES | NO_PURCHASE_90 | INACTIVE; null for a custom group.
  final String? smart;

  bool get isSmart => smart != null;
}

class GroupList {
  const GroupList({
    required this.groups,
    required this.smart,
    this.maxGroups = 50,
    this.maxMembers = 500,
  });

  factory GroupList.fromJson(Map<String, dynamic> j) {
    final limits = jMap(j['limits']);
    return GroupList(
      groups: _groups(j['groups']),
      smart: _groups(j['smart']),
      maxGroups: jIntOrNull(limits['maxGroups']) ?? 50,
      maxMembers: jIntOrNull(limits['maxMembers']) ?? 500,
    );
  }

  final List<GroupSummary> groups;
  final List<GroupSummary> smart;
  final int maxGroups;
  final int maxMembers;
}

List<GroupSummary> _groups(Object? v) => [
  if (v is List)
    for (final g in v)
      if (g is Map) GroupSummary.fromJson(Map<String, dynamic>.from(g)),
];

class GroupMember {
  const GroupMember({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.balanceMinor,
    this.archived = false,
    this.marketingConsent = false,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
    id: jStr(j['id']) ?? '',
    name: jStr(j['name']) ?? '',
    phone: _blank(jStr(j['phone'])),
    email: _blank(jStr(j['email'])),
    balanceMinor: jBigOrNull(j['balanceMinor']),
    archived: jBool(j['archived']),
    marketingConsent: jBool(j['marketingConsent']),
  );

  final String id;
  final String name;
  final String? phone;
  final String? email;

  /// Null when amounts are hidden (no money.view).
  final BigInt? balanceMinor;
  final bool archived;
  final bool marketingConsent;
}

String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s;

class GroupStatus {
  const GroupStatus({
    this.members = 0,
    this.active = 0,
    this.owing = 0,
    this.owingMinor,
    this.noPhone = 0,
    this.noEmail = 0,
    this.inactive = 0,
  });

  factory GroupStatus.fromJson(Map<String, dynamic> j) => GroupStatus(
    members: jIntOrNull(j['members']) ?? 0,
    active: jIntOrNull(j['active']) ?? 0,
    owing: jIntOrNull(j['owing']) ?? 0,
    owingMinor: jBigOrNull(j['owingMinor']),
    noPhone: jIntOrNull(j['noPhone']) ?? 0,
    noEmail: jIntOrNull(j['noEmail']) ?? 0,
    inactive: jIntOrNull(j['inactive']) ?? 0,
  );

  final int members;
  final int active;
  final int owing;

  /// Null when amounts are hidden.
  final BigInt? owingMinor;
  final int noPhone;
  final int noEmail;
  final int inactive;
}

/// "N מתוך M קבעו" — the latest booking-invite run of the group.
class InviteProgress {
  const InviteProgress({
    required this.runId,
    required this.sent,
    required this.booked,
  });

  static InviteProgress? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return InviteProgress(
      runId: jStr(j['runId']) ?? '',
      sent: jIntOrNull(j['sent']) ?? 0,
      booked: jIntOrNull(j['booked']) ?? 0,
    );
  }

  final String runId;
  final int sent;
  final int booked;
}

class GroupDetail {
  const GroupDetail({
    required this.group,
    required this.status,
    required this.members,
    this.invites,
  });

  factory GroupDetail.fromJson(Map<String, dynamic> j) => GroupDetail(
    group: GroupSummary.fromJson(jMap(j['group'])),
    status: GroupStatus.fromJson(jMap(j['status'])),
    members: [
      if (j['members'] is List)
        for (final m in j['members'] as List)
          if (m is Map) GroupMember.fromJson(Map<String, dynamic>.from(m)),
    ],
    invites: InviteProgress.fromJson(j['invites']),
  );

  final GroupSummary group;
  final GroupStatus status;
  final List<GroupMember> members;
  final InviteProgress? invites;
}

/// The action kinds (path segment ↔ server kind).
enum GroupActionKind {
  paymentRequest('payment-request', 'PAYMENT_REQUEST'),
  broadcast('broadcast', 'BROADCAST'),
  document('document', 'DOCUMENT'),
  bookingInvite('booking-invite', 'BOOKING_INVITE'),
  statement('statement', 'STATEMENT');

  const GroupActionKind(this.path, this.server);
  final String path;
  final String server;
}

class GroupPreview {
  const GroupPreview({
    this.recipients = 0,
    this.email = 0,
    this.whatsapp = 0,
    this.documents = 0,
    this.totalMinor,
    this.perDocumentMinor,
    this.notOwing = 0,
    this.inactive = 0,
    this.noContact = 0,
    this.noConsent = 0,
    this.noEmail = 0,
  });

  factory GroupPreview.fromJson(Map<String, dynamic> j) {
    final s = jMap(j['skipped']);
    return GroupPreview(
      recipients: jIntOrNull(j['recipients']) ?? 0,
      email: jIntOrNull(j['email']) ?? 0,
      whatsapp: jIntOrNull(j['whatsapp']) ?? 0,
      documents: jIntOrNull(j['documents']) ?? 0,
      totalMinor: jBigOrNull(j['totalMinor']),
      perDocumentMinor: jBigOrNull(j['perDocumentMinor']),
      notOwing: jIntOrNull(s['notOwing']) ?? 0,
      inactive: jIntOrNull(s['inactive']) ?? 0,
      noContact: jIntOrNull(s['noContact']) ?? 0,
      noConsent: jIntOrNull(s['noConsent']) ?? 0,
      noEmail: jIntOrNull(s['noEmail']) ?? 0,
    );
  }

  final int recipients;
  final int email;
  final int whatsapp;
  final int documents;
  final BigInt? totalMinor;
  final BigInt? perDocumentMinor;
  final int notOwing;
  final int inactive;
  final int noContact;
  final int noConsent;
  final int noEmail;

  /// Members who will NOT get it for lack of a way to reach them / consent
  /// ("3 לא יקבלו"). Not-owing and inactive members are expected skips.
  int get unreachable => noContact + noConsent + noEmail;
}

class GroupRunItem {
  const GroupRunItem({
    required this.id,
    required this.customerId,
    required this.name,
    required this.channel,
    required this.status,
    this.reason,
    this.phone,
    this.text,
    this.link,
    this.documentId,
    this.documentNumber,
    this.amountMinor,
  });

  factory GroupRunItem.fromJson(Map<String, dynamic> j) => GroupRunItem(
    id: jStr(j['id']) ?? '',
    customerId: jStr(j['customerId']) ?? '',
    name: jStr(j['name']) ?? '',
    channel: jStr(j['channel']) ?? 'NONE',
    status: jStr(j['status']) ?? 'SKIPPED',
    reason: jStr(j['reason']),
    phone: _blank(jStr(j['phone'])),
    text: jStr(j['text']),
    link: jStr(j['link']),
    documentId: jStr(j['documentId']),
    documentNumber: jStr(j['documentNumber']),
    amountMinor: jBigOrNull(j['amountMinor']),
  );

  final String id;
  final String customerId;
  final String name;

  /// EMAIL | WHATSAPP | NONE.
  final String channel;

  /// SENT | QUEUED | DONE | DISMISSED | SKIPPED | FAILED.
  final String status;
  final String? reason;
  final String? phone;
  final String? text;
  final String? link;
  final String? documentId;
  final String? documentNumber;
  final BigInt? amountMinor;

  bool get queued => channel == 'WHATSAPP' && status == 'QUEUED';

  GroupRunItem withStatus(String s) => GroupRunItem(
    id: id,
    customerId: customerId,
    name: name,
    channel: channel,
    status: s,
    reason: reason,
    phone: phone,
    text: text,
    link: link,
    documentId: documentId,
    documentNumber: documentNumber,
    amountMinor: amountMinor,
  );
}

class GroupRun {
  const GroupRun({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.items,
    this.email = 0,
    this.whatsapp = 0,
    this.whatsappSent = 0,
    this.skipped = 0,
    this.failed = 0,
    this.documents = 0,
    this.totalMinor,
  });

  factory GroupRun.fromJson(Map<String, dynamic> j) {
    final c = jMap(j['counts']);
    return GroupRun(
      id: jStr(j['id']) ?? '',
      groupId: jStr(j['groupId']) ?? '',
      kind: jStr(j['kind']) ?? '',
      items: [
        if (j['items'] is List)
          for (final i in j['items'] as List)
            if (i is Map) GroupRunItem.fromJson(Map<String, dynamic>.from(i)),
      ],
      email: jIntOrNull(c['email']) ?? 0,
      whatsapp: jIntOrNull(c['whatsapp']) ?? 0,
      whatsappSent: jIntOrNull(c['whatsappSent']) ?? 0,
      skipped: jIntOrNull(c['skipped']) ?? 0,
      failed: jIntOrNull(c['failed']) ?? 0,
      documents: jIntOrNull(c['documents']) ?? 0,
      totalMinor: jBigOrNull(j['totalMinor']),
    );
  }

  final String id;
  final String groupId;
  final String kind;
  final List<GroupRunItem> items;
  final int email;
  final int whatsapp;
  final int whatsappSent;
  final int skipped;
  final int failed;
  final int documents;
  final BigInt? totalMinor;

  List<GroupRunItem> get queue => [
    for (final i in items)
      if (i.queued) i,
  ];
}

// ---- calls -----------------------------------------------------------------

Future<GroupList> fetchGroups() async =>
    GroupList.fromJson(await _api.get('/customer-groups'));

Future<GroupSummary> createGroup({
  required String name,
  required String color,
}) async {
  final j = await _api.post('/customer-groups', {
    'name': name.trim(),
    'color': color,
  });
  return GroupSummary.fromJson(jMap(j['group']));
}

Future<GroupSummary> updateGroup(
  String id, {
  String? name,
  String? color,
}) async {
  final j = await _api.patch('/customer-groups/$id', {
    'name': ?name?.trim(),
    'color': ?color,
  });
  return GroupSummary.fromJson(jMap(j['group']));
}

Future<void> deleteGroup(String id) async {
  await _api.delete('/customer-groups/$id');
}

Future<GroupDetail> fetchGroup(String id) async =>
    GroupDetail.fromJson(await _api.get('/customer-groups/$id'));

/// Returns the group's new member count.
Future<int> addGroupMembers(String id, List<String> customerIds) async {
  final j = await _api.post('/customer-groups/$id/members', {
    'customerIds': customerIds,
  });
  return jIntOrNull(j['memberCount']) ?? 0;
}

Future<int> removeGroupMember(String id, String customerId) async {
  final j = await _api.delete('/customer-groups/$id/members/$customerId');
  return jIntOrNull(j['memberCount']) ?? 0;
}

Future<List<GroupSummary>> fetchCustomerGroups(String customerId) async =>
    _groups((await _api.get('/customers/$customerId/groups'))['groups']);

Future<List<GroupSummary>> saveCustomerGroups(
  String customerId,
  List<String> groupIds,
) async => _groups(
  (await _api.put('/customers/$customerId/groups', {
    'groupIds': groupIds,
  }))['groups'],
);

Future<void> setMarketingConsent(String customerId, bool granted) async {
  await _api.patch('/customers/$customerId', {'marketingConsent': granted});
}

Future<GroupPreview> previewGroupAction(
  String groupId,
  GroupActionKind kind,
  Map<String, Object?> params,
) async => GroupPreview.fromJson(
  await _api.post(
    '/customer-groups/$groupId/actions/${kind.path}/preview',
    params,
  ),
);

/// Runs the action once. [idempotencyKey]: one per confirm — a retry of the
/// same confirm passes the same key (the server answers with the first run).
Future<GroupRun> runGroupAction(
  String groupId,
  GroupActionKind kind,
  Map<String, Object?> params, {
  required String idempotencyKey,
}) async {
  final j = await _api.post(
    '/customer-groups/$groupId/actions/${kind.path}',
    params,
    idempotencyKey,
  );
  return GroupRun.fromJson(jMap(j['run']));
}

Future<GroupRun> fetchGroupRun(String runId) async => GroupRun.fromJson(
  jMap((await _api.get('/customer-group-runs/$runId'))['run']),
);

Future<void> markGroupItemSent(String runId, String itemId) async {
  await _api.post('/customer-group-runs/$runId/items/$itemId/sent');
}

Future<void> dismissGroupItem(String runId, String itemId) async {
  await _api.post('/customer-group-runs/$runId/items/$itemId/dismiss');
}

/// The broadcast text for one customer: {שם} → their first name.
String personalizeBroadcast(String text, String customerName) {
  final first = customerName.trim().split(RegExp(r'\s+')).first;
  return text.replaceAll('{שם}', first);
}
