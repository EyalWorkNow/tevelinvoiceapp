// "עזרה" — the help assistant (server 0120, owner request 2026-11-18).
//   GET  /help/status   → {available, escalationEmail, kbVersion, dailyCap, remainingToday}
//   POST /help/chat     {message, conversationId?, appVersion?}
//                       → {conversationId, answer, canHelp, chips[{id,label,path,route}], …}
//                       503 HELP_ASSISTANT_UNAVAILABLE {fallbackEmail}
//                       429 RATE_LIMITED / HELP_DAILY_LIMIT
//   POST /help/escalate {conversationId?, note?, appVersion?, reason?}
//                       → 201 {ticketId, emailed, escalationEmail, contactEmail}
//                       503 HELP_ESCALATION_UNAVAILABLE, 429 HELP_ESCALATION_LIMIT
// The server sends the model only the question (e-mails / phones / id numbers
// masked) and the help corpus — never business data.

import 'client.dart';
import 'settings_api.dart' show appVersion;

/// The support address the assistant hands over to.
const String helpEscalationEmail = 'help@tevel.space';

class HelpStatus {
  const HelpStatus({
    required this.available,
    this.escalationEmail = helpEscalationEmail,
    this.remainingToday,
  });

  factory HelpStatus.fromJson(Map<String, dynamic> json) => HelpStatus(
    available: json['available'] == true,
    escalationEmail: json['escalationEmail'] as String? ?? helpEscalationEmail,
    remainingToday: (json['remainingToday'] as num?)?.toInt(),
  );

  final bool available;
  final String escalationEmail;
  final int? remainingToday;
}

/// A deep link the answer refers to: [route] is an app location from the
/// help corpus (tevel route or one of the help extras), [path] the Hebrew
/// breadcrumb ("ניהול → בקשת תשלום").
class HelpChip {
  const HelpChip({
    required this.id,
    required this.label,
    required this.route,
    this.path = '',
  });

  factory HelpChip.fromJson(Map<String, dynamic> json) => HelpChip(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    path: json['path'] as String? ?? '',
    route: json['route'] as String? ?? '',
  );

  final String id;
  final String label;
  final String path;
  final String route;
}

class HelpReply {
  const HelpReply({
    required this.conversationId,
    required this.answer,
    required this.canHelp,
    this.chips = const [],
  });

  factory HelpReply.fromJson(Map<String, dynamic> json) => HelpReply(
    conversationId: json['conversationId'] as String? ?? '',
    answer: json['answer'] as String? ?? '',
    canHelp: json['canHelp'] != false,
    chips: [
      for (final c in (json['chips'] as List? ?? const []))
        if (c is Map<String, dynamic>) HelpChip.fromJson(c),
    ].where((c) => c.route.startsWith('/') && c.label.isNotEmpty).toList(),
  );

  final String conversationId;
  final String answer;
  final bool canHelp;
  final List<HelpChip> chips;
}

/// Why the conversation goes to a person.
enum HelpEscalationReason {
  userRequest('USER_REQUEST'),
  cannotHelp('ASSISTANT_CANNOT_HELP'),
  unavailable('ASSISTANT_UNAVAILABLE');

  const HelpEscalationReason(this.wire);
  final String wire;
}

class HelpTicket {
  const HelpTicket({required this.ticketId, this.contactEmail});

  final String ticketId;

  /// Where support will answer (the member's account e-mail), if any.
  final String? contactEmail;
}

Future<HelpStatus> fetchHelpStatus() async =>
    HelpStatus.fromJson(await ApiClient.instance.get('/help/status'));

Future<HelpReply> askHelp(String message, {String? conversationId}) async =>
    HelpReply.fromJson(
      await ApiClient.instance.post('/help/chat', {
        'message': message,
        'conversationId': ?conversationId,
        'appVersion': appVersion,
      }),
    );

Future<HelpTicket> escalateHelp({
  String? conversationId,
  String? note,
  HelpEscalationReason reason = HelpEscalationReason.userRequest,
}) async {
  final json = await ApiClient.instance.post('/help/escalate', {
    'conversationId': ?conversationId,
    if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    'appVersion': appVersion,
    'reason': reason.wire,
  });
  return HelpTicket(
    ticketId: json['ticketId'] as String? ?? '',
    contactEmail: json['contactEmail'] as String?,
  );
}
