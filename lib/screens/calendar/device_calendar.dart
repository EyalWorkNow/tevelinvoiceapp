// The phone's own calendars (EventKit, ios/Runner/AppDelegate.swift
// DeviceCalendar) — every account already on the iPhone: iCloud, Google,
// Outlook, Exchange. A native bridge instead of a plugin: four calls, iOS 17
// full-access API, no third-party dependency. Only start/end of busy events
// ever cross into Dart.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CalendarAccess {
  notDetermined,
  denied,
  restricted,
  writeOnly,
  full,
  unsupported,
}

CalendarAccess calendarAccessFrom(String? raw) => switch (raw) {
  'notDetermined' => CalendarAccess.notDetermined,
  'denied' => CalendarAccess.denied,
  'restricted' => CalendarAccess.restricted,
  'writeOnly' => CalendarAccess.writeOnly,
  'full' => CalendarAccess.full,
  _ => CalendarAccess.unsupported,
};

class DeviceCalendarInfo {
  const DeviceCalendarInfo({
    required this.id,
    required this.title,
    required this.account,
    required this.color,
    required this.writable,
    required this.isDefault,
  });

  factory DeviceCalendarInfo.fromMap(Map<Object?, Object?> m) =>
      DeviceCalendarInfo(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        account: m['account'] as String? ?? '',
        color: m['color'] as String? ?? '#8A948F',
        writable: m['writable'] == true,
        isDefault: m['isDefault'] == true,
      );

  final String id;
  final String title;
  final String account;
  final String color;
  final bool writable;
  final bool isDefault;
}

class DeviceInterval {
  const DeviceInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

class LocalReminder {
  const LocalReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.businessId,
  });
  final String id;
  final DateTime at;
  final String title;
  final String body;
  final String businessId;

  Map<String, Object> toMap() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    'businessId': businessId,
  };
}

/// What the sync needs from the phone; tests use a fake.
abstract class DeviceCalendarPort {
  bool get supported;
  Future<CalendarAccess> status();
  Future<CalendarAccess> requestAccess();
  Future<List<DeviceCalendarInfo>> calendars();
  Future<List<DeviceInterval>> busy(
    DateTime from,
    DateTime to,
    List<String> calendarIds,
  );

  /// Creates (or updates [eventId]) the booking's event; returns its id.
  Future<String?> upsertEvent({
    required String bookingId,
    required String? eventId,
    required String? calendarId,
    required DateTime start,
    required DateTime end,
    required String title,
    required String notes,
  });
  Future<void> deleteEvent(String eventId);
  Future<int> scheduleReminders(List<LocalReminder> items);

  /// Called when a calendar on the phone changed while the app runs.
  set onChanged(VoidCallback? callback);
}

class MethodChannelDeviceCalendar implements DeviceCalendarPort {
  MethodChannelDeviceCalendar() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _onChanged?.call();
    });
  }

  static const _channel = MethodChannel('tevel/calendar');
  VoidCallback? _onChanged;

  @override
  set onChanged(VoidCallback? callback) => _onChanged = callback;

  @override
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Future<CalendarAccess> status() async => supported
      ? calendarAccessFrom(await _channel.invokeMethod<String>('status'))
      : CalendarAccess.unsupported;

  @override
  Future<CalendarAccess> requestAccess() async => supported
      ? calendarAccessFrom(await _channel.invokeMethod<String>('requestAccess'))
      : CalendarAccess.unsupported;

  @override
  Future<List<DeviceCalendarInfo>> calendars() async {
    if (!supported) return const [];
    final raw = await _channel.invokeListMethod<Object?>('calendars') ?? [];
    return [
      for (final c in raw)
        if (c is Map) DeviceCalendarInfo.fromMap(c),
    ];
  }

  @override
  Future<List<DeviceInterval>> busy(
    DateTime from,
    DateTime to,
    List<String> calendarIds,
  ) async {
    if (!supported || calendarIds.isEmpty) return const [];
    final raw =
        await _channel.invokeListMethod<Object?>('busy', {
          'from': from.millisecondsSinceEpoch,
          'to': to.millisecondsSinceEpoch,
          'calendarIds': calendarIds,
        }) ??
        [];
    return [
      for (final b in raw)
        if (b is Map && b['start'] is int && b['end'] is int)
          DeviceInterval(
            DateTime.fromMillisecondsSinceEpoch(b['start'] as int, isUtc: true),
            DateTime.fromMillisecondsSinceEpoch(b['end'] as int, isUtc: true),
          ),
    ];
  }

  @override
  Future<String?> upsertEvent({
    required String bookingId,
    required String? eventId,
    required String? calendarId,
    required DateTime start,
    required DateTime end,
    required String title,
    required String notes,
  }) => _channel.invokeMethod<String>('upsertEvent', {
    'bookingId': bookingId,
    'eventId': ?eventId,
    'calendarId': ?calendarId,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'title': title,
    'notes': notes,
  });

  @override
  Future<void> deleteEvent(String eventId) =>
      _channel.invokeMethod<void>('deleteEvent', {'eventId': eventId});

  @override
  Future<int> scheduleReminders(List<LocalReminder> items) async => supported
      ? await _channel.invokeMethod<int>('scheduleReminders', {
              'items': [for (final i in items) i.toMap()],
            }) ??
            0
      : 0;
}
