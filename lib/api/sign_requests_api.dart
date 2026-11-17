// "מסמך לחתימה" (server 0116, apps/api/src/routes/v2/sign-requests.ts).
//
//   POST /sign-requests?title=            raw PDF (≤ 10 MB, ≤ 50 pages) → DRAFT
//   GET  /sign-requests?status=           {items, total}
//   GET  /sign-requests/:id               {signRequest}
//   PUT  /sign-requests/:id               DRAFT only; fields replace-all
//   POST /sign-requests/:id/send          {channel} → {url, signRequest}
//   POST /sign-requests/:id/remind        {channel} → {url} (a new link)
//   POST /sign-requests/:id/cancel        → {signRequest}
//   GET  /sign-requests/:id/pages/:n      PNG of page n (the editor background)
//   GET  /sign-requests/:id/original|completed   PDF

import 'package:flutter/foundation.dart';

import 'client.dart';
import 'models/json.dart';
import 'models/sign_request.dart';

export 'models/sign_request.dart';

final ApiClient _api = ApiClient.instance;

/// Bumped after every change and on a sign-request push, so the list and
/// the open detail reload.
final ValueNotifier<int> signRequestsVersion = ValueNotifier(0);
void notifySignRequestsChanged() => signRequestsVersion.value++;

/// Send channel of POST send / remind.
enum SignChannel { email, whatsapp, share }

String signChannelWire(SignChannel c) => c.name.toUpperCase();

SignRequest _view(Map<String, dynamic> json) =>
    SignRequest.fromJson(jMap(json['signRequest']));

Future<List<SignRequest>> fetchSignRequests({SignStatus? status}) async {
  final json = await _api.get(
    '/sign-requests',
    query: {
      'limit': '200',
      if (status != null) 'status': signStatusWire(status),
    },
  );
  return [
    for (final r in (json['items'] is List ? json['items'] as List : const []))
      if (r is Map<String, dynamic>) SignRequest.fromJson(r),
  ];
}

Future<SignRequest> fetchSignRequest(String id) async =>
    _view(await _api.get('/sign-requests/$id'));

Future<SignRequest> createSignRequest(Uint8List pdf, String title) async {
  final json = await _api.postRaw(
    '/sign-requests',
    pdf,
    'application/pdf',
    query: {'title': title},
  );
  notifySignRequestsChanged();
  return _view(json);
}

/// PUT: only the given keys change; [fields] replaces every field.
Future<SignRequest> updateSignRequest(
  String id, {
  String? title,
  String? signerName,
  String? signerEmail,
  String? signerPhone,
  String? customerId,
  String? message,
  String? expiresOn,
  bool setDetails = false,
  bool? notifyOnView,
  List<SignField>? fields,
}) async {
  String? t(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();
  final json = await _api.put('/sign-requests/$id', {
    if (title != null) 'title': title.trim(),
    if (setDetails) ...{
      'signerName': t(signerName),
      'signerEmail': t(signerEmail),
      'signerPhone': t(signerPhone),
      'customerId': t(customerId),
      'message': t(message),
      'expiresOn': t(expiresOn),
    },
    'notifyOnView': ?notifyOnView,
    if (fields != null) 'fields': [for (final f in fields) f.toJson()],
  });
  notifySignRequestsChanged();
  return _view(json);
}

Future<({String url, SignRequest signRequest, bool emailed})> sendSignRequest(
  String id,
  SignChannel channel, {
  bool notifyOnView = false,
}) async {
  final json = await _api.post('/sign-requests/$id/send', {
    'channel': signChannelWire(channel),
    'notifyOnView': notifyOnView,
  });
  notifySignRequestsChanged();
  return (
    url: json['url'] as String? ?? '',
    signRequest: _view(json),
    emailed: json['emailed'] == true,
  );
}

Future<({String url, bool emailed})> remindSignRequest(
  String id,
  SignChannel channel,
) async {
  final json = await _api.post('/sign-requests/$id/remind', {
    'channel': signChannelWire(channel),
  });
  notifySignRequestsChanged();
  return (url: json['url'] as String? ?? '', emailed: json['emailed'] == true);
}

Future<SignRequest> cancelSignRequest(String id) async {
  final json = await _api.post('/sign-requests/$id/cancel');
  notifySignRequestsChanged();
  return _view(json);
}

Future<Uint8List> fetchSignPage(String id, int page) =>
    _api.getBytes('/sign-requests/$id/pages/$page');

Future<Uint8List> fetchSignPdf(String id, {required bool completed}) =>
    _api.getBytes('/sign-requests/$id/${completed ? 'completed' : 'original'}');
