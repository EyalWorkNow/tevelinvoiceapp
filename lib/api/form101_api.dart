// "טופס 101 לעובד" (server 0134, apps/api/src/routes/v2/form101.ts). The owner
// keeps a list of salaried employees (not app users) and sends each one a
// link for the tax year; the employee fills the form on the public page
// /f/:token after a one-time code, signs, and the PDF in the official layout
// comes back. Owner manages; owner + accountants read (every read is logged).
//
//   GET  /employees?taxYear=               {taxYear, items, renewable}
//   POST /employees  · PUT /employees/:id
//   POST /form101                          {employeeId, taxYear, kind, channel}
//   GET  /form101/blank?taxYear=           printable empty form (PDF)
//   POST /form101/season                   January: one prefilled form per employee
//   GET  /form101/:id · POST resend | code | cancel | send-to-accountant
//   GET  /form101/:id/pdf · /attachments/:aid

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models/json.dart';

final ApiClient _api = ApiClient.instance;

/// Bumped after every change and on a form-101 push.
final ValueNotifier<int> form101Version = ValueNotifier(0);
void notifyForm101Changed() => form101Version.value++;

/// The spec's four states (+ cancelled): נשלח · נפתח · הוחזר חתום · פג תוקף.
enum Form101Status { sent, viewed, completed, expired, cancelled }

Form101Status form101StatusOf(String? s) => switch (s) {
  'VIEWED' => Form101Status.viewed,
  'COMPLETED' => Form101Status.completed,
  'EXPIRED' => Form101Status.expired,
  'CANCELLED' => Form101Status.cancelled,
  _ => Form101Status.sent,
};

enum Form101Kind { annual, update }

enum Form101Channel { whatsapp, sms, email, share }

String form101ChannelWire(Form101Channel c) => c.name.toUpperCase();

class Form101Summary {
  const Form101Summary({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.taxYear,
    required this.kind,
    required this.status,
    required this.sentAt,
    this.viewedAt,
    this.completedAt,
    required this.expiresOn,
    this.currentStep = 0,
  });

  factory Form101Summary.fromJson(Map<String, dynamic> j) => Form101Summary(
    id: jStr(j['id']) ?? '',
    employeeId: jStr(j['employeeId']) ?? '',
    employeeName: jStr(j['employeeName']) ?? '',
    taxYear: jIntOrNull(j['taxYear']) ?? 0,
    kind: j['kind'] == 'UPDATE' ? Form101Kind.update : Form101Kind.annual,
    status: form101StatusOf(jStr(j['status'])),
    sentAt: jStr(j['sentAt']) ?? '',
    viewedAt: jStr(j['viewedAt']),
    completedAt: jStr(j['completedAt']),
    expiresOn: jStr(j['expiresOn']) ?? '',
    currentStep: jIntOrNull(j['currentStep']) ?? 0,
  );

  final String id;
  final String employeeId;
  final String employeeName;
  final int taxYear;
  final Form101Kind kind;
  final Form101Status status;
  final String sentAt;
  final String? viewedAt;
  final String? completedAt;
  final String expiresOn;
  final int currentStep;

  bool get open =>
      status == Form101Status.sent || status == Form101Status.viewed;

  /// Resend: open (a reminder) or expired (14 more days).
  bool get canResend => open || status == Form101Status.expired;
}

class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.archived = false,
    this.form101,
    this.lastCompletedYear,
  });

  factory Employee.fromJson(Map<String, dynamic> j) => Employee(
    id: jStr(j['id']) ?? '',
    fullName: jStr(j['fullName']) ?? '',
    phone: jStr(j['phone']),
    email: jStr(j['email']),
    archived: jBool(j['archived']),
    form101: j['form101'] is Map<String, dynamic>
        ? Form101Summary.fromJson(j['form101'] as Map<String, dynamic>)
        : null,
    lastCompletedYear: jIntOrNull(j['lastCompletedYear']),
  );

  final String id;
  final String fullName;
  final String? phone;
  final String? email;
  final bool archived;

  /// This tax year's form (null = not sent yet).
  final Form101Summary? form101;
  final int? lastCompletedYear;
}

class EmployeeList {
  const EmployeeList({
    required this.taxYear,
    required this.items,
    this.renewable = 0,
  });
  final int taxYear;
  final List<Employee> items;

  /// Employees with last year's form and none yet this year (January re-send).
  final int renewable;
}

class Form101Event {
  const Form101Event({
    required this.type,
    required this.occurredAt,
    this.channel,
    this.ip,
    this.detail,
    this.actorName,
  });
  factory Form101Event.fromJson(Map<String, dynamic> j) => Form101Event(
    type: jStr(j['type']) ?? '',
    occurredAt: jStr(j['occurredAt']) ?? '',
    channel: jStr(j['channel']),
    ip: jStr(j['ip']),
    detail: jStr(j['detail']),
    actorName: jStr(j['actorName']),
  );
  final String type;
  final String occurredAt;
  final String? channel;
  final String? ip;
  final String? detail;
  final String? actorName;
}

class Form101Attachment {
  const Form101Attachment({
    required this.id,
    required this.kind,
    required this.contentType,
    required this.byteSize,
  });
  factory Form101Attachment.fromJson(Map<String, dynamic> j) =>
      Form101Attachment(
        id: jStr(j['id']) ?? '',
        kind: jStr(j['kind']) ?? '',
        contentType: jStr(j['contentType']) ?? '',
        byteSize: jIntOrNull(j['byteSize']) ?? 0,
      );
  final String id;
  final String kind;
  final String contentType;
  final int byteSize;
  bool get isPdf => contentType == 'application/pdf';
}

class Form101Detail {
  const Form101Detail({
    required this.summary,
    this.employeePhone,
    this.employeeEmail,
    this.verifiedTo,
    this.completedSignerName,
    this.retainUntil,
    this.prefilled = false,
    this.codePending = false,
    this.code,
    this.events = const [],
    this.attachments = const [],
  });

  factory Form101Detail.fromJson(Map<String, dynamic> j) => Form101Detail(
    summary: Form101Summary.fromJson(j),
    employeePhone: jStr(j['employeePhone']),
    employeeEmail: jStr(j['employeeEmail']),
    verifiedTo: jStr(j['verifiedTo']),
    completedSignerName: jStr(j['completedSignerName']),
    retainUntil: jStr(j['retainUntil']),
    prefilled: j['prefilledFrom'] != null,
    codePending: jBool(j['codePending']),
    code: jStr(j['code']),
    events: [
      for (final e in (j['events'] is List ? j['events'] as List : const []))
        if (e is Map<String, dynamic>) Form101Event.fromJson(e),
    ],
    attachments: [
      for (final a
          in (j['attachments'] is List ? j['attachments'] as List : const []))
        if (a is Map<String, dynamic>) Form101Attachment.fromJson(a),
    ],
  );

  final Form101Summary summary;
  final String? employeePhone;
  final String? employeeEmail;
  final String? verifiedTo;
  final String? completedSignerName;
  final String? retainUntil;
  final bool prefilled;
  final bool codePending;

  /// The pending one-time code (owner only; null once the employee used it).
  final String? code;
  final List<Form101Event> events;
  final List<Form101Attachment> attachments;
}

/// A send / resend: the link to share, the code to send separately.
class Form101Sent {
  const Form101Sent({
    required this.url,
    required this.code,
    required this.emailed,
    required this.detail,
  });
  final String url;
  final String code;
  final bool emailed;
  final Form101Detail detail;
}

class SeasonItem {
  const SeasonItem({
    required this.employeeId,
    required this.employeeName,
    this.phone,
    this.email,
    required this.channel,
    required this.url,
    required this.code,
    required this.emailed,
    required this.prefilled,
  });
  factory SeasonItem.fromJson(Map<String, dynamic> j) => SeasonItem(
    employeeId: jStr(j['employeeId']) ?? '',
    employeeName: jStr(j['employeeName']) ?? '',
    phone: jStr(j['phone']),
    email: jStr(j['email']),
    channel: switch (j['channel']) {
      'EMAIL' => Form101Channel.email,
      'WHATSAPP' => Form101Channel.whatsapp,
      'SMS' => Form101Channel.sms,
      _ => Form101Channel.share,
    },
    url: jStr(j['url']) ?? '',
    code: jStr(j['code']) ?? '',
    emailed: jBool(j['emailed']),
    prefilled: jBool(j['prefilled']),
  );
  final String employeeId;
  final String employeeName;
  final String? phone;
  final String? email;
  final Form101Channel channel;
  final String url;
  final String code;
  final bool emailed;
  final bool prefilled;
}

Future<EmployeeList> fetchEmployees({int? taxYear}) async {
  final json = await _api.get(
    '/employees',
    query: {if (taxYear != null) 'taxYear': '$taxYear'},
  );
  return EmployeeList(
    taxYear: jIntOrNull(json['taxYear']) ?? DateTime.now().year,
    renewable: jIntOrNull(json['renewable']) ?? 0,
    items: [
      for (final e
          in (json['items'] is List ? json['items'] as List : const []))
        if (e is Map<String, dynamic>) Employee.fromJson(e),
    ],
  );
}

String? _t(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();

Future<Employee> createEmployee({
  required String fullName,
  String? phone,
  String? email,
}) async {
  final json = await _api.post('/employees', {
    'fullName': fullName.trim(),
    'phone': _t(phone),
    'email': _t(email),
  });
  notifyForm101Changed();
  return Employee.fromJson(jMap(json['employee']));
}

Future<Employee> updateEmployee(
  String id, {
  required String fullName,
  String? phone,
  String? email,
  bool? archived,
}) async {
  final json = await _api.put('/employees/$id', {
    'fullName': fullName.trim(),
    'phone': _t(phone),
    'email': _t(email),
    'archived': ?archived,
  });
  notifyForm101Changed();
  return Employee.fromJson(jMap(json['employee']));
}

Form101Sent _sent(Map<String, dynamic> json) => Form101Sent(
  url: jStr(json['url']) ?? '',
  code: jStr(json['code']) ?? '',
  emailed: jBool(json['emailed']),
  detail: Form101Detail.fromJson(jMap(json['form101'])),
);

Future<Form101Sent> sendForm101({
  required String employeeId,
  required int taxYear,
  required Form101Kind kind,
  required Form101Channel channel,
}) async {
  final json = await _api.post('/form101', {
    'employeeId': employeeId,
    'taxYear': taxYear,
    'kind': kind == Form101Kind.update ? 'UPDATE' : 'ANNUAL',
    'channel': form101ChannelWire(channel),
  });
  notifyForm101Changed();
  return _sent(json);
}

Future<List<Form101Summary>> fetchForm101History(String employeeId) async {
  final json = await _api.get(
    '/form101',
    query: {'employeeId': employeeId, 'limit': '50'},
  );
  return [
    for (final r in (json['items'] is List ? json['items'] as List : const []))
      if (r is Map<String, dynamic>) Form101Summary.fromJson(r),
  ];
}

Future<Form101Detail> fetchForm101(String id) async =>
    Form101Detail.fromJson(jMap((await _api.get('/form101/$id'))['form101']));

Future<Form101Sent> resendForm101(String id, Form101Channel channel) async {
  final json = await _api.post('/form101/$id/resend', {
    'channel': form101ChannelWire(channel),
  });
  notifyForm101Changed();
  return _sent(json);
}

Future<String> newForm101Code(String id) async =>
    jStr((await _api.post('/form101/$id/code'))['code']) ?? '';

Future<void> cancelForm101(String id) async {
  await _api.post('/form101/$id/cancel');
  notifyForm101Changed();
}

Future<String> sendForm101ToAccountant(String id) async =>
    jStr((await _api.post('/form101/$id/send-to-accountant'))['sentTo']) ?? '';

Future<Uint8List> fetchForm101Pdf(String id) =>
    _api.getBytes('/form101/$id/pdf');

Future<Uint8List> fetchForm101Attachment(String id, String attachmentId) =>
    _api.getBytes('/form101/$id/attachments/$attachmentId');

Future<Uint8List> fetchBlankForm101(int taxYear) =>
    _api.getBytes('/form101/blank', query: {'taxYear': '$taxYear'});

Future<({int taxYear, List<SeasonItem> items, int skipped})> sendForm101Season(
  int taxYear,
) async {
  final json = await _api.post('/form101/season', {'taxYear': taxYear});
  notifyForm101Changed();
  return (
    taxYear: jIntOrNull(json['taxYear']) ?? taxYear,
    items: [
      for (final r
          in (json['items'] is List ? json['items'] as List : const []))
        if (r is Map<String, dynamic>) SeasonItem.fromJson(r),
    ],
    skipped:
        (json['skipped'] is List ? json['skipped'] as List : const []).length,
  );
}
