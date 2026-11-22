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

/// A vacation / blocked range of Israel dates ('YYYY-MM-DD'), inclusive.
class BlockedRange {
  const BlockedRange(this.from, this.to);

  factory BlockedRange.fromJson(Map<String, dynamic> j) =>
      BlockedRange(j['from'] as String, j['to'] as String);

  final String from;
  final String to;

  Map<String, dynamic> toJson() => {'from': from, 'to': to};
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
    this.requireApproval = false,
    this.blockedDates = const [],
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
    requireApproval: j['requireApproval'] == true,
    blockedDates: [
      for (final r in (j['blockedDates'] as List? ?? const []))
        BlockedRange.fromJson(r as Map<String, dynamic>),
    ],
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
  final bool requireApproval;
  final List<BlockedRange> blockedDates;
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
    this.expiresAt,
    this.customerId,
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
    expiresAt: DateTime.tryParse(j['expiresAt'] as String? ?? ''),
    customerId: jStr(j['customerId']),
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

  /// Only for PENDING: the slot is held until then (then DECLINED).
  final DateTime? expiresAt;
  final String? customerId;

  bool get confirmed => status == 'CONFIRMED';
  bool get pending => status == 'PENDING';

  /// CANCELLED or DECLINED (a declined request shows like a cancelled one).
  bool get closed => !confirmed && !pending;
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

Future<Booking> _bookingAction(String id, String action) async =>
    Booking.fromJson(
      (await _api.post('/calendar/bookings/$id/$action'))['booking']
          as Map<String, dynamic>,
    );

/// PENDING → CONFIRMED (409 BOOKING_NOT_PENDING).
Future<Booking> approveBooking(String id) => _bookingAction(id, 'approve');

/// PENDING → DECLINED (409 BOOKING_NOT_PENDING).
Future<Booking> declineBooking(String id) => _bookingAction(id, 'decline');

/// Blocks the booking's phone + e-mail; their upcoming bookings are cancelled.
Future<Booking> blockBookingClient(String id) => _bookingAction(id, 'block');

class BlockedContact {
  const BlockedContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    this.createdAt,
  });

  factory BlockedContact.fromJson(Map<String, dynamic> j) => BlockedContact(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    email: j['email'] as String? ?? '',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String phone;
  final String email;
  final DateTime? createdAt;
}

Future<List<BlockedContact>> fetchBlockedContacts() async => [
  for (final c
      in ((await _api.get('/calendar/blocked'))['contacts'] as List? ??
          const []))
    BlockedContact.fromJson(c as Map<String, dynamic>),
];

Future<void> unblockContact(String id) => _api.delete('/calendar/blocked/$id');

class FreeSlot {
  const FreeSlot({
    required this.start,
    required this.end,
    required this.date,
    required this.time,
  });

  factory FreeSlot.fromJson(Map<String, dynamic> j) => FreeSlot(
    start: j['start'] as String,
    end: j['end'] as String,
    date: j['date'] as String? ?? '',
    time: j['time'] as String? ?? '',
  );

  /// ISO instants (sent back to the server as is).
  final String start;
  final String end;

  /// Israel date 'YYYY-MM-DD' and time 'HH:MM'.
  final String date;
  final String time;
}

class FreeSlots {
  const FreeSlots(this.enabled, this.slots);
  final bool enabled;
  final List<FreeSlot> slots;
}

Future<FreeSlots> fetchFreeSlots({int limit = 12}) async {
  final j = await _api.get('/calendar/free-slots', query: {'limit': '$limit'});
  return FreeSlots(jBool(j['enabled']), [
    for (final s in (j['slots'] as List? ?? const []))
      FreeSlot.fromJson(s as Map<String, dynamic>),
  ]);
}

class CalendarInvite {
  const CalendarInvite(this.link, this.whatsappText);
  final String link;
  final String whatsappText;
}

/// A personal booking link for [customerId] (7 days, one booking), optionally
/// limited to up to 3 suggested [slots] (ISO starts).
Future<CalendarInvite> createCalendarInvite(
  String customerId, {
  List<String> slots = const [],
}) async {
  final j = await _api.post('/calendar/invites', {
    'customerId': customerId,
    if (slots.isNotEmpty) 'slots': slots,
  });
  return CalendarInvite(
    j['link'] as String? ?? '',
    j['whatsappText'] as String? ?? j['link'] as String? ?? '',
  );
}

/// The owner books [start] for the customer (CONFIRMED). 409 SLOT_TAKEN.
Future<Booking> bookForCustomer(String customerId, String start) async =>
    Booking.fromJson(
      (await _api.post('/calendar/bookings', {
            'customerId': customerId,
            'start': start,
          }))['booking']
          as Map<String, dynamic>,
    );
