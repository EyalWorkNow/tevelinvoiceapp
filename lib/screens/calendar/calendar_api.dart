// "יומן" API (server: apps/api/src/routes/v2/calendar.ts, migration 0106).
// Owner / partner only (business:configure). Busy blocks are start/end only.

import '../../api/client.dart';
import '../../api/models/json.dart';

ApiClient get _api => ApiClient.instance;

class TimeRangeHm {
  const TimeRangeHm(this.start, this.end);
  final String start; // "HH:MM"
  final String end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class DayHours {
  const DayHours(this.day, this.ranges);

  factory DayHours.fromJson(Map<String, dynamic> j) =>
      DayHours(jInt(j['day']), [
        for (final r in (j['ranges'] as List? ?? const []))
          TimeRangeHm((r as Map)['start'] as String, r['end'] as String),
      ]);

  /// 0 = Sunday … 6 = Saturday (as on the server).
  final int day;
  final List<TimeRangeHm> ranges;

  bool get open => ranges.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'day': day,
    'ranges': [for (final r in ranges) r.toJson()],
  };
}

class CalendarSettings {
  const CalendarSettings({
    required this.enabled,
    required this.slug,
    required this.bookingUrl,
    required this.weeklyHours,
    required this.slotMinutes,
    required this.bufferMinutes,
    required this.minNoticeMinutes,
    required this.maxDaysAhead,
    required this.notifyNewBooking,
    required this.reminderMinutes,
    this.meetingTitle,
    this.busySyncedAt,
  });

  factory CalendarSettings.fromJson(Map<String, dynamic> j) => CalendarSettings(
    enabled: jBool(j['enabled']),
    slug: j['slug'] as String? ?? '',
    bookingUrl: j['bookingUrl'] as String? ?? '',
    weeklyHours: [
      for (final d in (j['weeklyHours'] as List? ?? const []))
        DayHours.fromJson(d as Map<String, dynamic>),
    ],
    slotMinutes: jInt(j['slotMinutes'] ?? 30),
    bufferMinutes: jInt(j['bufferMinutes'] ?? 0),
    minNoticeMinutes: jInt(j['minNoticeMinutes'] ?? 120),
    maxDaysAhead: jInt(j['maxDaysAhead'] ?? 30),
    notifyNewBooking: j['notifyNewBooking'] != false,
    reminderMinutes: jInt(j['reminderMinutes'] ?? 15),
    meetingTitle: jStr(j['meetingTitle']),
    busySyncedAt: DateTime.tryParse(j['busySyncedAt'] as String? ?? ''),
  );

  final bool enabled;
  final String slug;
  final String bookingUrl;
  final List<DayHours> weeklyHours;
  final int slotMinutes;
  final int bufferMinutes;
  final int minNoticeMinutes;
  final int maxDaysAhead;
  final bool notifyNewBooking;
  final int reminderMinutes;
  final String? meetingTitle;
  final DateTime? busySyncedAt;
}

class Booking {
  const Booking({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.clientName,
    required this.clientPhone,
    required this.clientEmail,
    required this.sequence,
    required this.createdAt,
    this.notes,
    this.cancelledBy,
  });

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
    id: j['id'] as String,
    startsAt: DateTime.parse(j['startsAt'] as String),
    endsAt: DateTime.parse(j['endsAt'] as String),
    status: j['status'] as String? ?? 'CONFIRMED',
    clientName: j['clientName'] as String? ?? '',
    clientPhone: j['clientPhone'] as String? ?? '',
    clientEmail: j['clientEmail'] as String? ?? '',
    sequence: jInt(j['sequence'] ?? 0),
    createdAt: DateTime.parse(j['createdAt'] as String),
    notes: jStr(j['notes']),
    cancelledBy: jStr(j['cancelledBy']),
  );

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;
  final String clientName;
  final String clientPhone;
  final String clientEmail;
  final int sequence;
  final DateTime createdAt;
  final String? notes;
  final String? cancelledBy;

  bool get confirmed => status == 'CONFIRMED';
}

class BusyBlock {
  const BusyBlock(this.start, this.end, {this.mine = true});

  factory BusyBlock.fromJson(Map<String, dynamic> j) => BusyBlock(
    DateTime.parse(j['start'] as String),
    DateTime.parse(j['end'] as String),
    mine: j['mine'] != false,
  );

  final DateTime start;
  final DateTime end;
  final bool mine;

  Map<String, dynamic> toJson() => {
    'start': start.toUtc().toIso8601String(),
    'end': end.toUtc().toIso8601String(),
  };
}

class CalendarAgenda {
  const CalendarAgenda({
    required this.bookings,
    required this.busy,
    required this.enabled,
    this.notifyNewBooking = true,
    this.reminderMinutes = 15,
    this.busySyncedAt,
  });

  factory CalendarAgenda.fromJson(Map<String, dynamic> j) => CalendarAgenda(
    bookings: [
      for (final b in (j['bookings'] as List? ?? const []))
        Booking.fromJson(b as Map<String, dynamic>),
    ],
    busy: [
      for (final b in (j['busy'] as List? ?? const []))
        BusyBlock.fromJson(b as Map<String, dynamic>),
    ],
    enabled: jBool(j['enabled']),
    notifyNewBooking: j['notifyNewBooking'] != false,
    reminderMinutes: jInt(j['reminderMinutes'] ?? 15),
    busySyncedAt: DateTime.tryParse(j['busySyncedAt'] as String? ?? ''),
  );

  final List<Booking> bookings;
  final List<BusyBlock> busy;
  final bool enabled;
  final bool notifyNewBooking;
  final int reminderMinutes;
  final DateTime? busySyncedAt;
}

Future<CalendarSettings> fetchCalendarSettings() async =>
    CalendarSettings.fromJson(
      (await _api.get('/calendar/settings'))['settings']
          as Map<String, dynamic>,
    );

Future<CalendarSettings> saveCalendarSettings(
  Map<String, dynamic> patch,
) async => CalendarSettings.fromJson(
  (await _api.put('/calendar/settings', patch))['settings']
      as Map<String, dynamic>,
);

Future<CalendarSettings> regenerateCalendarLink() async =>
    CalendarSettings.fromJson(
      (await _api.post('/calendar/link/regenerate'))['settings']
          as Map<String, dynamic>,
    );

Future<CalendarAgenda> fetchCalendarAgenda(DateTime from, DateTime to) async =>
    CalendarAgenda.fromJson(
      await _api.get(
        '/calendar/agenda',
        query: {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      ),
    );

Future<void> uploadBusyBlocks(String source, List<BusyBlock> blocks) =>
    _api.put('/calendar/busy', {
      'source': source,
      'blocks': [for (final b in blocks) b.toJson()],
    });

Future<void> clearBusyBlocks(String source) =>
    _api.delete('/calendar/busy?source=${Uri.encodeQueryComponent(source)}');

Future<Booking> cancelBookingAsOwner(String id) async => Booking.fromJson(
  (await _api.post('/calendar/bookings/$id/cancel'))['booking']
      as Map<String, dynamic>,
);
