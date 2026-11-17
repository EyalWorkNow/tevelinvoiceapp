// Customer timeline (ציר זמן), manual notes and payment terms (server 0110:
// apps/api/src/routes/v2/customer-timeline.ts).
//
//   GET    /customers/:id/timeline?cursor=&limit=&sources=   {items, nextCursor, sources}
//   POST   /customers/:id/notes {body}                       {note}
//   PATCH  /customer-notes/:id {body}                        {note}   (author only)
//   DELETE /customer-notes/:id                               (author only)
//   GET|PUT /settings/payment-terms   {paymentTerms, paymentTermsDays, preferredPaymentMethod}
//   PATCH  /customers/:id {paymentTerms, paymentTermsDays, preferredPaymentMethod}

import 'client.dart';
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

/// The source filter chips (server keys).
enum TimelineSource {
  documents,
  quotes,
  payments,
  debts,
  reminders,
  recurring,
  corrections,
  notes,

  /// Integration 2026-11-17: client self-bookings (0106), owner / partner only.
  calendar,
}

class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.kind,
    required this.at,
    required this.atIsrael,
    this.actorId,
    this.actorName,
    this.createdBy,
    this.amountMinor,
    this.amountHidden = false,
    this.linkType,
    this.linkId,
    this.mine = false,
    this.data = const {},
  });

  factory TimelineItem.fromJson(Map<String, dynamic> j) {
    final actor = jMap(j['actor']);
    final link = jMap(j['link']);
    return TimelineItem(
      id: jStr(j['id']) ?? '',
      kind: jStr(j['kind']) ?? '',
      at: jStr(j['at']) ?? '',
      atIsrael: jStr(j['atIsrael']) ?? '',
      actorId: jStr(actor['id']),
      actorName: jStr(actor['name']),
      createdBy: jStr(j['createdBy']),
      amountMinor: jBigOrNull(j['amountMinor']),
      // The access layer may null an amount without the flag: a null amount
      // with a kind that carries one is hidden too.
      amountHidden: j['amountHidden'] == true,
      linkType: jStr(link['type']),
      linkId: jStr(link['id']),
      mine: j['mine'] == true,
      data: jMap(j['data']),
    );
  }

  final String id;
  final String kind;

  /// ISO-8601 UTC.
  final String at;

  /// Israel wall clock, "YYYY-MM-DD HH:MM".
  final String atIsrael;
  final String? actorId;
  final String? actorName;
  final String? createdBy;
  final BigInt? amountMinor;
  final bool amountHidden;

  /// document | quote | debtEntry | customerNote (null = not tappable).
  final String? linkType;
  final String? linkId;

  /// A note the viewer wrote (edit / delete).
  final bool mine;
  final Map<String, dynamic> data;

  String get day => atIsrael.length >= 10 ? atIsrael.substring(0, 10) : '';
  String get time => atIsrael.length >= 16 ? atIsrael.substring(11, 16) : '';
  String? str(String key) => jStr(data[key]);
  String? get noteBody => str('body');
}

class TimelinePage {
  const TimelinePage(this.items, this.nextCursor, this.sources);

  factory TimelinePage.fromJson(Map<String, dynamic> j) => TimelinePage(
    [
      for (final i in (j['items'] as List? ?? const []))
        if (i is Map<String, dynamic>) TimelineItem.fromJson(i),
    ],
    jStr(j['nextCursor']),
    [
      for (final s in (j['sources'] as List? ?? const []))
        if (s is String) s,
    ],
  );

  final List<TimelineItem> items;
  final String? nextCursor;

  /// Source keys the viewer may read (hides chips for the rest).
  final List<String> sources;
}

Future<TimelinePage> fetchCustomerTimeline(
  String customerId, {
  String? cursor,
  TimelineSource? source,
  int limit = 30,
}) async => TimelinePage.fromJson(
  await _api.get(
    '/customers/$customerId/timeline',
    query: {
      'limit': '$limit',
      'cursor': ?cursor,
      if (source != null) 'sources': source.name,
    },
  ),
);

Future<void> addCustomerNote(String customerId, String body) =>
    _api.post('/customers/$customerId/notes', {'body': body});

Future<void> updateCustomerNote(String noteId, String body) =>
    _api.patch('/customer-notes/$noteId', {'body': body});

Future<void> deleteCustomerNote(String noteId) =>
    _api.delete('/customer-notes/$noteId');

/// Terms + preferred method: a customer's own, or the business default.
class PaymentTermsValue {
  const PaymentTermsValue({this.code, this.days, this.method});

  factory PaymentTermsValue.fromJson(Map<String, dynamic> j) =>
      PaymentTermsValue(
        code: jStr(j['paymentTerms']),
        days: jIntOrNull(j['paymentTermsDays']),
        method: jStr(j['preferredPaymentMethod']),
      );

  final String? code;
  final int? days;
  final String? method;

  Map<String, dynamic> toJson() => {
    'paymentTerms': code,
    if (code == 'EOM_DAYS' || code == 'NET_DAYS') 'paymentTermsDays': days,
    'preferredPaymentMethod': method,
  };
}

Future<PaymentTermsValue> fetchBusinessPaymentTerms() async =>
    PaymentTermsValue.fromJson(await _api.get('/settings/payment-terms'));

Future<PaymentTermsValue> saveBusinessPaymentTerms(PaymentTermsValue v) async =>
    PaymentTermsValue.fromJson(
      await _api.put('/settings/payment-terms', v.toJson()),
    );

Future<void> saveCustomerPaymentTerms(String customerId, PaymentTermsValue v) =>
    _api.patch('/customers/$customerId', v.toJson());
