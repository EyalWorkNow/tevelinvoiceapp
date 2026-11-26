// 0136 וואטסאפ עסקי: an in-memory /whatsapp-business + campaigns server.
//
//   final wa = installWhatsAppBusinessFakes(backend, connected: true);
//   wa.templates.add(waTemplateJson('t2', 'שלום {שם}', status: 'APPROVED'));
//   wa.campaign['status'] = 'DONE';

import 'fake_backend.dart';

Map<String, dynamic> waStatusJson({
  bool available = true,
  String status = 'CONNECTED',
  int quota = 500,
  int used = 120,
  bool coexistence = true,
  String? errorMessage,
}) => {
  'available': available,
  'status': status,
  'phoneDisplay': status == 'CONNECTED' ? '+972 50-123-4567' : null,
  'verifiedName': status == 'CONNECTED' ? 'סטודיו נועה' : null,
  'qualityRating': status == 'CONNECTED' ? 'GREEN' : null,
  'coexistence': status == 'CONNECTED' && coexistence,
  'monthlyQuota': quota,
  'usedThisMonth': used,
  'errorMessage': ?errorMessage,
};

Map<String, dynamic> waTemplateJson(
  String id,
  String body, {
  String status = 'APPROVED',
  String? rejectedReason,
}) => {
  'id': id,
  'name': 'tevel_$id',
  'bodyText': body,
  'status': status,
  'rejectedReason': ?rejectedReason,
  'createdAt': '2026-11-26T08:00:00Z',
};

Map<String, dynamic> waCampaignJson({
  String id = 'wc1',
  String status = 'SENDING',
}) => {
  'id': id,
  'groupId': 'g1',
  'templateName': 'tevel_t1',
  'bodyText': 'שלום {שם}, החל ממחר מבצע חורף: 20% הנחה על כל הטיפולים.',
  'createdAt': '2026-11-26T09:05:00Z',
  'createdBy': 'u1',
  'status': status,
  'counts': {
    'queued': status == 'SENDING' ? 1 : 0,
    'sent': 1,
    'delivered': 1,
    'read': status == 'SENDING' ? 0 : 1,
    'failed': 1,
  },
  'recipients': [
    {'customerId': 'c1', 'name': 'דנה כהן', 'status': 'DELIVERED'},
    {'customerId': 'c3', 'name': 'מיכל ברק', 'status': 'SENT'},
    {
      'customerId': 'c4',
      'name': 'יוסי אברהם',
      'status': 'FAILED',
      'errorMessage': 'המספר לא רשום בוואטסאפ',
    },
    {
      'customerId': 'c5',
      'name': 'רונית שלום',
      'status': status == 'SENDING' ? 'QUEUED' : 'READ',
    },
  ],
};

class WhatsAppBusinessFake {
  WhatsAppBusinessFake(this.status);

  Map<String, dynamic> status;
  final List<Map<String, dynamic>> templates = [
    waTemplateJson(
      't1',
      'שלום {שם}, החל ממחר מבצע חורף: 20% הנחה על כל הטיפולים.',
    ),
    waTemplateJson('t2', 'היי {שם}, נפתחו תורים לחודש הבא.', status: 'PENDING'),
    waTemplateJson(
      't3',
      'קנו עכשיו!!!',
      status: 'REJECTED',
      rejectedReason: 'תוכן פרסומי לא ברור',
    ),
  ];
  Map<String, dynamic> preview = {
    'recipients': 4,
    'skippedNoConsent': 2,
    'skippedNoPhone': 1,
    'skippedArchived': 0,
    'quotaLeft': 380,
    'canSend': true,
  };
  Map<String, dynamic> campaign = waCampaignJson();
  List<Map<String, dynamic>> campaigns = [];
  String connectUrl = 'https://invoice.crm.tevel.space/wa/connect/tok123';
}

WhatsAppBusinessFake installWhatsAppBusinessFakes(
  FakeBackend b, {
  bool connected = true,
  Map<String, dynamic>? status,
}) {
  final f = WhatsAppBusinessFake(
    status ?? waStatusJson(status: connected ? 'CONNECTED' : 'NOT_CONNECTED'),
  );
  var next = 10;
  b
    ..on('GET', '/whatsapp-business', (_) => FakeResponse(200, f.status))
    ..on(
      'POST',
      '/whatsapp-business/connect-link',
      (_) => FakeResponse(200, {
        'url': f.connectUrl,
        'expiresAt': '2026-11-26T10:15:00Z',
      }),
    )
    ..on('DELETE', '/whatsapp-business', (_) {
      f.status = waStatusJson(status: 'NOT_CONNECTED', used: 0);
      return const FakeResponse(200, {'ok': true});
    })
    ..on(
      'GET',
      '/whatsapp-business/templates',
      (_) => FakeResponse(200, {'templates': f.templates}),
    )
    ..on('POST', '/whatsapp-business/templates', (r) {
      final t = waTemplateJson(
        't${next++}',
        '${r.body['bodyText']}',
        status: 'PENDING',
      );
      f.templates.insert(0, t);
      return FakeResponse(201, {'template': t});
    })
    ..on('DELETE', '/whatsapp-business/templates/:id', (r) {
      f.templates.removeWhere((t) => t['id'] == r.params['id']);
      return const FakeResponse(200, {'ok': true});
    })
    ..on(
      'POST',
      '/customer-groups/:id/whatsapp-campaigns/preview',
      (_) => FakeResponse(200, f.preview),
    )
    ..on('POST', '/customer-groups/:id/whatsapp-campaigns', (_) {
      f.campaigns.insert(0, f.campaign);
      return FakeResponse(201, {'campaignId': f.campaign['id']});
    })
    ..on(
      'GET',
      '/customer-groups/:id/whatsapp-campaigns',
      (_) => FakeResponse(200, {'campaigns': f.campaigns}),
    )
    ..on(
      'GET',
      '/whatsapp-campaigns/:id',
      (_) => FakeResponse(200, f.campaign),
    );
  return f;
}
