// Automatic collection reminders, "תזכורות גבייה אוטומטיות" (server 0111).
//
//   GET  /settings/reminders               the ladder (steps, wording, channels, summary)
//   PUT  /settings/reminders               a partial change (owner / partner)
//   GET  /collection-reminders/ready       today's WhatsApp batch (one tap each)
//   POST /collection-reminders/:id/sent    {channel} the chat / share sheet opened
//   POST /collection-reminders/:id/dismiss not sending this one
//   GET  /collection-reminders?customerId=|documentId=   the ledger (timeline)
//   GET  /collection-reminders/holds?customerId=|documentId=  {onHold}
//   PUT  /collection-reminders/holds       {customerId|documentId, onHold}
//
// E-mail reminders leave from the server by themselves; only WhatsApp needs a
// tap (no WhatsApp Cloud API in production). An older server without the
// routes answers 404 NOT_FOUND: every read here returns null / empty then.

import 'client.dart';
import 'customers_api.dart' show isMissingRoute;
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

/// The placeholders the owner may put in a template (server list).
const List<String> reminderPlaceholders = [
  '{לקוח}',
  '{עסק}',
  '{מסמך}',
  '{מספר}',
  '{סכום}',
  '{תאריך}',
  '{קישור}',
];

class LadderStep {
  const LadderStep({
    required this.offsetDays,
    this.enabled = true,
    this.template,
  });

  factory LadderStep.fromJson(Map<String, dynamic> j) => LadderStep(
    offsetDays: jIntOrNull(j['offsetDays']) ?? 0,
    enabled: j['enabled'] != false,
    template: jStr(j['template']),
  );

  /// Days from the due date: −3 before, 0 on the day, 7 a week after.
  final int offsetDays;
  final bool enabled;

  /// The owner's wording; null = the default for this kind of step.
  final String? template;

  LadderStep copyWith({
    int? offsetDays,
    bool? enabled,
    String? template,
    bool clearTemplate = false,
  }) => LadderStep(
    offsetDays: offsetDays ?? this.offsetDays,
    enabled: enabled ?? this.enabled,
    template: clearTemplate ? null : (template ?? this.template),
  );

  Map<String, dynamic> toJson() => {
    'offsetDays': offsetDays,
    'enabled': enabled,
    'template': template,
  };
}

class CollectionSettings {
  const CollectionSettings({
    required this.enabled,
    required this.steps,
    required this.maxPerDocument,
    required this.email,
    required this.whatsapp,
    required this.dailySummary,
    this.defaultBefore = '',
    this.defaultOnDue = '',
    this.defaultAfter = '',
  });

  factory CollectionSettings.fromJson(Map<String, dynamic> j) {
    final channels = j['channels'] is Map
        ? (j['channels'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final defaults = j['defaultTemplates'] is Map
        ? (j['defaultTemplates'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final steps = j['steps'] is List
        ? [
            for (final s in j['steps'] as List)
              if (s is Map) LadderStep.fromJson(s.cast<String, dynamic>()),
          ]
        : <LadderStep>[];
    return CollectionSettings(
      enabled: j['enabled'] == true,
      steps: steps.isEmpty ? defaultLadder : steps,
      maxPerDocument: jIntOrNull(j['maxPerDocument']) ?? 3,
      email: channels['email'] != false,
      whatsapp: channels['whatsapp'] != false,
      dailySummary: j['dailySummary'] != false,
      defaultBefore: jStr(defaults['before']) ?? '',
      defaultOnDue: jStr(defaults['onDue']) ?? '',
      defaultAfter: jStr(defaults['after']) ?? '',
    );
  }

  static const defaultLadder = [
    LadderStep(offsetDays: -3),
    LadderStep(offsetDays: 0),
    LadderStep(offsetDays: 7),
  ];

  final bool enabled;
  final List<LadderStep> steps;
  final int maxPerDocument;
  final bool email;
  final bool whatsapp;
  final bool dailySummary;
  final String defaultBefore;
  final String defaultOnDue;
  final String defaultAfter;

  /// The wording a step uses when the owner did not write one.
  String defaultFor(int offsetDays) => offsetDays < 0
      ? defaultBefore
      : offsetDays == 0
      ? defaultOnDue
      : defaultAfter;
}

/// GET /settings/reminders; null = not on this server.
Future<CollectionSettings?> fetchCollectionSettings() async {
  try {
    return CollectionSettings.fromJson(await _api.get('/settings/reminders'));
  } on Object catch (e) {
    if (isMissingRoute(e)) return null;
    rethrow;
  }
}

/// PUT /settings/reminders with only the fields that changed.
Future<CollectionSettings> saveCollectionSettings({
  bool? enabled,
  List<LadderStep>? steps,
  int? maxPerDocument,
  bool? email,
  bool? whatsapp,
  bool? dailySummary,
}) async => CollectionSettings.fromJson(
  await _api.put('/settings/reminders', {
    'enabled': ?enabled,
    if (steps != null) 'steps': [for (final s in steps) s.toJson()],
    'maxPerDocument': ?maxPerDocument,
    if (email != null || whatsapp != null)
      'channels': {'email': ?email, 'whatsapp': ?whatsapp},
    'dailySummary': ?dailySummary,
  }),
);

/// One automatic reminder (a ledger row).
class CollectionReminder {
  const CollectionReminder({
    required this.id,
    required this.offsetDays,
    required this.channel,
    required this.status,
    required this.messageText,
    this.customerId,
    this.customerName,
    this.documentId,
    this.documentType,
    this.documentNumber,
    this.debtEntryId,
    this.dueDate,
    this.phone,
    this.openMinor,
    this.paymentUrl,
    this.sentAt,
    this.createdAt,
  });

  factory CollectionReminder.fromJson(Map<String, dynamic> j) =>
      CollectionReminder(
        id: j['id'] as String,
        offsetDays: jIntOrNull(j['offsetDays']) ?? 0,
        channel: jStr(j['channel']) ?? 'EMAIL',
        status: jStr(j['status']) ?? 'READY',
        messageText: jStr(j['messageText']) ?? '',
        customerId: jStr(j['customerId']),
        customerName: jStr(j['customerName']),
        documentId: jStr(j['documentId']),
        documentType: jStr(j['documentType']),
        documentNumber: jStr(j['documentNumber']),
        debtEntryId: jStr(j['debtEntryId']),
        dueDate: jStr(j['dueDate']),
        phone: jStr(j['phone']),
        openMinor: jBigOrNull(j['openMinor']),
        paymentUrl: jStr(j['paymentUrl']),
        sentAt: DateTime.tryParse(jStr(j['sentAt']) ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(jStr(j['createdAt']) ?? '')?.toLocal(),
      );

  final String id;
  final int offsetDays;

  /// EMAIL | WHATSAPP.
  final String channel;

  /// READY | SENDING | SENT | UNKNOWN | DISMISSED | CANCELLED.
  final String status;

  /// The server's wording; {קישור} stays for the phone's own share link.
  final String messageText;
  final String? customerId;
  final String? customerName;
  final String? documentId;
  final String? documentType;
  final String? documentNumber;
  final String? debtEntryId;
  final String? dueDate;
  final String? phone;
  final BigInt? openMinor;
  final String? paymentUrl;
  final DateTime? sentAt;
  final DateTime? createdAt;
}

/// The owner's batch; empty on an older server.
Future<List<CollectionReminder>> fetchReadyReminders() async {
  try {
    final json = await _api.get('/collection-reminders/ready');
    return [
      for (final r in (json['reminders'] as List? ?? const []))
        if (r is Map) CollectionReminder.fromJson(r.cast<String, dynamic>()),
    ];
  } on Object catch (e) {
    if (isMissingRoute(e)) return const [];
    rethrow;
  }
}

/// The ledger of one customer / document, newest first.
Future<List<CollectionReminder>> fetchCollectionHistory({
  String? customerId,
  String? documentId,
}) async {
  try {
    final json = await _api.get(
      '/collection-reminders',
      query: {'customerId': ?customerId, 'documentId': ?documentId},
    );
    return [
      for (final r in (json['reminders'] as List? ?? const []))
        if (r is Map) CollectionReminder.fromJson(r.cast<String, dynamic>()),
    ];
  } on Object catch (e) {
    if (isMissingRoute(e)) return const [];
    rethrow;
  }
}

Future<void> markCollectionReminderSent(String id, String channel) async {
  await _api.post('/collection-reminders/$id/sent', {'channel': channel});
}

Future<void> dismissCollectionReminder(String id) async {
  await _api.post('/collection-reminders/$id/dismiss', const {});
}

/// "אל תשלח תזכורות ללקוח הזה" / a paused document; null = not on this server.
Future<bool?> fetchReminderHold({
  String? customerId,
  String? documentId,
}) async {
  try {
    final json = await _api.get(
      '/collection-reminders/holds',
      query: {'customerId': ?customerId, 'documentId': ?documentId},
    );
    return json['onHold'] == true;
  } on Object catch (e) {
    if (isMissingRoute(e)) return null;
    rethrow;
  }
}

Future<void> saveReminderHold({
  String? customerId,
  String? documentId,
  required bool onHold,
}) async {
  await _api.put('/collection-reminders/holds', {
    'customerId': ?customerId,
    'documentId': ?documentId,
    'onHold': onHold,
  });
}
