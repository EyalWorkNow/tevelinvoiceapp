// וואטסאפ עסקי — the server's /whatsapp-business and /whatsapp-campaigns
// routes (0136). Each business connects its OWN number through Meta Embedded
// Signup (a one-time public page opened in the in-app Safari view); messages
// leave from that number by Meta-approved MARKETING templates, to customers
// who gave marketing consent, within a monthly quota. When the platform is
// not configured (`available:false`) the app shows nothing of this, and the
// one-tap wa.me queue stays the way to send.

import 'package:flutter/foundation.dart';

import '../util/labels/whatsapp_business_he.dart';
import 'client.dart';
import 'models/json.dart';

ApiClient get _api => ApiClient.instance;

const waNotConnected = 'NOT_CONNECTED';
const waConnected = 'CONNECTED';
const waError = 'ERROR';

class WaBusinessStatus {
  const WaBusinessStatus({
    required this.available,
    required this.status,
    this.phoneDisplay,
    this.verifiedName,
    this.qualityRating,
    this.coexistence = false,
    this.monthlyQuota = 0,
    this.usedThisMonth = 0,
    this.errorMessage,
  });

  factory WaBusinessStatus.fromJson(Map<String, dynamic> j) => WaBusinessStatus(
    available: jBool(j['available']),
    status: jStr(j['status']) ?? waNotConnected,
    phoneDisplay: _blank(jStr(j['phoneDisplay'])),
    verifiedName: _blank(jStr(j['verifiedName'])),
    qualityRating: _blank(jStr(j['qualityRating'])),
    coexistence: jBool(j['coexistence']),
    monthlyQuota: jIntOrNull(j['monthlyQuota']) ?? 0,
    usedThisMonth: jIntOrNull(j['usedThisMonth']) ?? 0,
    errorMessage: _blank(jStr(j['errorMessage'])),
  );

  static const unavailable = WaBusinessStatus(
    available: false,
    status: waNotConnected,
  );

  final bool available;

  /// NOT_CONNECTED | CONNECTED | ERROR.
  final String status;
  final String? phoneDisplay;
  final String? verifiedName;

  /// GREEN | YELLOW | RED | UNKNOWN (Meta's quality rating).
  final String? qualityRating;
  final bool coexistence;
  final int monthlyQuota;

  /// Israel calendar month.
  final int usedThisMonth;
  final String? errorMessage;

  bool get connected => available && status == waConnected;
  int get quotaLeft {
    final left = monthlyQuota - usedThisMonth;
    return left < 0 ? 0 : left;
  }

  /// 0..1 for the quota bar.
  double get quotaFraction => monthlyQuota <= 0
      ? 0
      : (usedThisMonth / monthlyQuota).clamp(0.0, 1.0).toDouble();
}

class WaTemplate {
  const WaTemplate({
    required this.id,
    required this.name,
    required this.bodyText,
    required this.status,
    this.rejectedReason,
    this.createdAt,
  });

  factory WaTemplate.fromJson(Map<String, dynamic> j) => WaTemplate(
    id: jStr(j['id']) ?? '',
    name: jStr(j['name']) ?? '',
    bodyText: jStr(j['bodyText']) ?? '',
    status: jStr(j['status']) ?? 'PENDING',
    rejectedReason: _blank(jStr(j['rejectedReason'])),
    createdAt: jStr(j['createdAt']),
  );

  final String id;
  final String name;

  /// The owner's text, with `{שם}` where the first name goes.
  final String bodyText;

  /// PENDING | APPROVED | REJECTED | PAUSED | DISABLED.
  final String status;
  final String? rejectedReason;
  final String? createdAt;

  bool get approved => status == 'APPROVED';
}

class WaCampaignPreview {
  const WaCampaignPreview({
    this.recipients = 0,
    this.skippedNoConsent = 0,
    this.skippedNoPhone = 0,
    this.skippedArchived = 0,
    this.quotaLeft = 0,
    this.canSend = false,
    this.blockReason,
  });

  factory WaCampaignPreview.fromJson(Map<String, dynamic> j) =>
      WaCampaignPreview(
        recipients: jIntOrNull(j['recipients']) ?? 0,
        skippedNoConsent: jIntOrNull(j['skippedNoConsent']) ?? 0,
        skippedNoPhone: jIntOrNull(j['skippedNoPhone']) ?? 0,
        skippedArchived: jIntOrNull(j['skippedArchived']) ?? 0,
        quotaLeft: jIntOrNull(j['quotaLeft']) ?? 0,
        canSend: jBool(j['canSend']),
        blockReason: _blank(jStr(j['blockReason'])),
      );

  final int recipients;
  final int skippedNoConsent;
  final int skippedNoPhone;
  final int skippedArchived;
  final int quotaLeft;
  final bool canSend;

  /// A code (QUOTA_EXCEEDED, …) or a Hebrew sentence; see [waBlockText].
  final String? blockReason;
}

class WaCounts {
  const WaCounts({
    this.queued = 0,
    this.sent = 0,
    this.delivered = 0,
    this.read = 0,
    this.failed = 0,
  });

  factory WaCounts.fromJson(Map<String, dynamic> j) => WaCounts(
    queued: jIntOrNull(j['queued']) ?? 0,
    sent: jIntOrNull(j['sent']) ?? 0,
    delivered: jIntOrNull(j['delivered']) ?? 0,
    read: jIntOrNull(j['read']) ?? 0,
    failed: jIntOrNull(j['failed']) ?? 0,
  );

  final int queued;
  final int sent;
  final int delivered;
  final int read;
  final int failed;

  int get total => queued + sent + delivered + read + failed;

  /// Accepted by Meta (sent, delivered or read).
  int get accepted => sent + delivered + read;
}

class WaRecipient {
  const WaRecipient({
    required this.customerId,
    required this.name,
    required this.status,
    this.errorMessage,
  });

  factory WaRecipient.fromJson(Map<String, dynamic> j) => WaRecipient(
    customerId: jStr(j['customerId']) ?? '',
    name: jStr(j['name']) ?? '',
    status: jStr(j['status']) ?? 'QUEUED',
    errorMessage: _blank(jStr(j['errorMessage'])),
  );

  final String customerId;
  final String name;

  /// QUEUED | SENT | DELIVERED | READ | FAILED.
  final String status;

  /// Hebrew (the server maps Meta's codes).
  final String? errorMessage;
}

class WaCampaign {
  const WaCampaign({
    required this.id,
    required this.groupId,
    required this.templateName,
    required this.status,
    required this.counts,
    this.bodyText,
    this.createdAt,
    this.createdBy,
    this.recipients = const [],
  });

  factory WaCampaign.fromJson(Map<String, dynamic> j) => WaCampaign(
    id: jStr(j['id']) ?? '',
    groupId: jStr(j['groupId']) ?? '',
    templateName: jStr(j['templateName']) ?? '',
    bodyText: jStr(j['bodyText']),
    createdAt: jStr(j['createdAt']),
    createdBy: jStr(j['createdBy']),
    status: jStr(j['status']) ?? 'SENDING',
    counts: WaCounts.fromJson(jMap(j['counts'])),
    recipients: [
      for (final r in _list(j['recipients']))
        if (r is Map) WaRecipient.fromJson(Map<String, dynamic>.from(r)),
    ],
  );

  final String id;
  final String groupId;
  final String templateName;
  final String? bodyText;
  final String? createdAt;
  final String? createdBy;

  /// SENDING | DONE.
  final String status;
  final WaCounts counts;
  final List<WaRecipient> recipients;

  bool get sending => status == 'SENDING';
}

// ---- shared status ---------------------------------------------------------

/// The current business's status (null = unknown / unavailable), shared by
/// the ניהול list, "עוד הגדרות" and חיבורים ושליחה. [refreshWaStatus] fills it.
final ValueNotifier<WaBusinessStatus?> waStatus = ValueNotifier(null);

/// Fetches the status into [waStatus]. Any failure (an older server, offline,
/// 403) means "don't show it".
Future<WaBusinessStatus> refreshWaStatus() async {
  try {
    final s = await fetchWaStatus();
    waStatus.value = s;
    return s;
  } on Object {
    waStatus.value = null;
    return WaBusinessStatus.unavailable;
  }
}

// ---- calls -----------------------------------------------------------------

Future<WaBusinessStatus> fetchWaStatus() async =>
    WaBusinessStatus.fromJson(await _api.get('/whatsapp-business'));

/// The one-time Embedded Signup page (15 minutes).
Future<Uri> createWaConnectLink() async {
  final j = await _api.post('/whatsapp-business/connect-link');
  final url = jStr(j['url']);
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null) {
    throw ApiException(0, 'BAD_RESPONSE', WaHe.errorFallback);
  }
  return uri;
}

Future<void> disconnectWa() async {
  await _api.delete('/whatsapp-business');
}

Future<List<WaTemplate>> fetchWaTemplates() async => [
  for (final t in _list(
    await _api.getAny('/whatsapp-business/templates'),
    'templates',
  ))
    if (t is Map) WaTemplate.fromJson(Map<String, dynamic>.from(t)),
];

Future<WaTemplate> createWaTemplate(String bodyText) async {
  final j = await _api.post('/whatsapp-business/templates', {
    'bodyText': bodyText.trim(),
  });
  return WaTemplate.fromJson(j['template'] is Map ? jMap(j['template']) : j);
}

Future<void> deleteWaTemplate(String id) async {
  await _api.delete('/whatsapp-business/templates/$id');
}

Future<WaCampaignPreview> previewWaCampaign(
  String groupId,
  String templateId,
) async => WaCampaignPreview.fromJson(
  await _api.post('/customer-groups/$groupId/whatsapp-campaigns/preview', {
    'templateId': templateId,
  }),
);

/// Starts the campaign once ([idempotencyKey]: one per confirm). Returns its id.
Future<String> startWaCampaign(
  String groupId,
  String templateId, {
  required String idempotencyKey,
}) async {
  final j = await _api.post('/customer-groups/$groupId/whatsapp-campaigns', {
    'templateId': templateId,
  }, idempotencyKey);
  return jStr(j['campaignId']) ?? jStr(jMap(j['campaign'])['id']) ?? '';
}

Future<List<WaCampaign>> fetchGroupWaCampaigns(String groupId) async => [
  for (final c in _list(
    await _api.getAny('/customer-groups/$groupId/whatsapp-campaigns'),
    'campaigns',
  ))
    if (c is Map) WaCampaign.fromJson(Map<String, dynamic>.from(c)),
];

Future<WaCampaign> fetchWaCampaign(String id) async {
  final j = await _api.get('/whatsapp-campaigns/$id');
  return WaCampaign.fromJson(j['campaign'] is Map ? jMap(j['campaign']) : j);
}

// ---- pure logic (tested) ---------------------------------------------------

const waNameToken = '{שם}';

/// What one customer reads: `{שם}` → their first name.
String waPreviewText(String bodyText, String customerName) {
  final first = customerName.trim().split(RegExp(r'\s+')).first;
  return bodyText.replaceAll(waNameToken, first);
}

/// The body as Meta stores it: `{שם}` → `{{1}}` (the server does the same).
String waMetaBody(String bodyText) => bodyText.replaceAll(waNameToken, '{{1}}');

/// Hebrew for a campaign error (409 codes), else the client's message.
String waErrorText(Object e) {
  if (e is ApiException) return waCodeText(e.code) ?? e.messageHe;
  return WaHe.errorFallback;
}

String? waCodeText(String code) => switch (code) {
  'QUOTA_EXCEEDED' => WaHe.errQuota,
  'TEMPLATE_NOT_APPROVED' => WaHe.errNotApproved,
  'WHATSAPP_NOT_CONNECTED' => WaHe.errNotConnected,
  'DEMO_BUSINESS' => WaHe.errDemo,
  'DUPLICATE_CAMPAIGN' || 'CAMPAIGN_DUPLICATE' => WaHe.errDuplicate,
  _ => null,
};

/// The preview's [WaCampaignPreview.blockReason] in Hebrew.
String? waBlockText(String? reason) {
  if (reason == null) return null;
  return waCodeText(reason) ??
      (RegExp(r'[א-ת]').hasMatch(reason) ? reason : WaHe.errorFallback);
}

/// The preview's lines, in order.
List<String> waPreviewLines(WaCampaignPreview p) => [
  if (p.recipients > 0) WaHe.recipients(p.recipients) else WaHe.nobody,
  if (p.skippedNoConsent > 0) WaHe.skippedNoConsent(p.skippedNoConsent),
  if (p.skippedNoPhone > 0) WaHe.skippedNoPhone(p.skippedNoPhone),
  if (p.skippedArchived > 0) WaHe.skippedArchived(p.skippedArchived),
  WaHe.quotaAfter(p.quotaLeft),
];

List<Object?> _list(Object? v, [String? key]) {
  if (v is List) return v;
  if (v is Map && key != null && v[key] is List) return v[key] as List;
  return const [];
}

String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s;
