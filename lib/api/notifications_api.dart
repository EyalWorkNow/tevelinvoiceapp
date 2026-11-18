// Home bell (tester feedback 2026-11-18): GET /mobile/notifications,
// GET /mobile/notifications/unread-count, POST /mobile/notifications/read.
// The server derives the feed (quote viewed/accepted, sign request viewed/
// completed, payment received, document sent / not sent, ITA answers,
// bookings, collection reminders) and stores only who read what.

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models/models.dart' show jStr;

ApiClient get _api => ApiClient.instance;

/// Unread items of the selected business (the Home bell badge). -1 = unknown
/// (older server / not loaded yet): the bell shows no badge.
final ValueNotifier<int> notificationsUnread = ValueNotifier(-1);

/// Bumped when a push arrives or the inbox marks items read: listeners reload.
final ValueNotifier<int> notificationsVersion = ValueNotifier(0);
void notifyNotificationsChanged() => notificationsVersion.value++;

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.route,
    required this.occurredAt,
    required this.read,
    this.subject,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    kind: jStr(j['kind']) ?? '',
    title: jStr(j['title']) ?? '',
    route: jStr(j['route']) ?? '/home',
    occurredAt:
        DateTime.tryParse(jStr(j['occurredAt']) ?? '')?.toLocal() ??
        DateTime.now(),
    read: j['read'] == true,
    subject: jStr(j['subject']),
  );

  final String id;
  final String kind;
  final String title;
  final String route;
  final DateTime occurredAt;
  final bool read;
  final String? subject;

  AppNotification asRead() => AppNotification(
    id: id,
    kind: kind,
    title: title,
    route: route,
    occurredAt: occurredAt,
    read: true,
    subject: subject,
  );
}

class NotificationPage {
  const NotificationPage(this.items, this.unreadCount, this.nextBefore);
  final List<AppNotification> items;
  final int unreadCount;
  final String? nextBefore;
}

Future<NotificationPage> fetchNotifications({String? before}) async {
  final json = await _api.get(
    '/mobile/notifications',
    query: {'limit': '30', 'before': ?before},
  );
  final unread = (json['unreadCount'] as num?)?.toInt() ?? 0;
  notificationsUnread.value = unread;
  return NotificationPage(
    [
      for (final i in (json['items'] as List? ?? const []))
        if (i is Map<String, dynamic> && i['id'] is String)
          AppNotification.fromJson(i),
    ],
    unread,
    jStr(json['nextBefore']),
  );
}

/// Refreshes the badge only (Home, app resume, after a push). Silent on error:
/// a missing route (older server) leaves the bell without a badge.
Future<void> refreshNotificationsUnread() async {
  try {
    final json = await _api.get('/mobile/notifications/unread-count');
    notificationsUnread.value = (json['unreadCount'] as num?)?.toInt() ?? 0;
  } on Object {
    // Best effort.
  }
}

Future<void> markNotificationsRead({List<String>? ids, bool all = false}) async {
  final json = await _api.post('/mobile/notifications/read', {
    if (all) 'all': true else 'ids': ids,
  });
  notificationsUnread.value = (json['unreadCount'] as num?)?.toInt() ?? 0;
}
