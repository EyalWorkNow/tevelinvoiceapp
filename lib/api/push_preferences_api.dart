// Notification preferences (PUSH-001, account-level — no X-Business-Id):
//   GET /mobile/push/catalogue    {categories:[{id,label,description,canDisable}], kinds:[…]}
//   GET /mobile/push/preferences  {disabledCategories, enabledKinds, quietHours}
//   PUT /mobile/push/preferences  same shape; the server refuses switching SECURITY off.
// disabledKinds (accountant pushes, 2026-11-22): per-kind mute; sent only once
// the server returned it or the user muted a kind (older servers never see it).
// PUT replaces the whole record, so enabledKinds and quietHours are sent back
// exactly as read.

import 'client.dart';

ApiClient get _api => ApiClient.instance;

class PushCategory {
  const PushCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.canDisable,
  });

  factory PushCategory.fromJson(Map<String, dynamic> j) => PushCategory(
    id: j['id'] as String,
    label: j['label'] as String? ?? j['id'] as String,
    description: j['description'] as String? ?? '',
    canDisable: j['canDisable'] != false,
  );

  final String id;
  final String label;
  final String description;
  final bool canDisable;
}

class PushPreferences {
  const PushPreferences({
    this.disabledCategories = const {},
    this.enabledKinds = const [],
    this.quietHours = true,
    this.disabledKinds = const {},
    this.servesKinds = false,
  });

  factory PushPreferences.fromJson(Map<String, dynamic> j) => PushPreferences(
    disabledCategories: {
      for (final c in (j['disabledCategories'] as List? ?? const []))
        if (c is String) c,
    },
    enabledKinds: [
      for (final k in (j['enabledKinds'] as List? ?? const []))
        if (k is String) k,
    ],
    quietHours: j['quietHours'] != false,
    disabledKinds: {
      for (final k in (j['disabledKinds'] as List? ?? const []))
        if (k is String) k,
    },
    servesKinds: j.containsKey('disabledKinds'),
  );

  final Set<String> disabledCategories;

  /// Muted push kinds (ACCOUNTANT_*).
  final Set<String> disabledKinds;

  /// The server's preferences carry disabledKinds.
  final bool servesKinds;

  bool kindOn(String kind) => !disabledKinds.contains(kind);

  PushPreferences withKind(String kind, bool on) => PushPreferences(
    disabledCategories: disabledCategories,
    enabledKinds: enabledKinds,
    quietHours: quietHours,
    disabledKinds: on
        ? ({...disabledKinds}..remove(kind))
        : {...disabledKinds, kind},
    servesKinds: servesKinds,
  );
  final List<String> enabledKinds;
  final bool quietHours;

  bool isOn(String category) => !disabledCategories.contains(category);

  PushPreferences withCategory(String category, bool on) => PushPreferences(
    disabledCategories: on
        ? ({...disabledCategories}..remove(category))
        : {...disabledCategories, category},
    enabledKinds: enabledKinds,
    quietHours: quietHours,
    disabledKinds: disabledKinds,
    servesKinds: servesKinds,
  );

  Map<String, Object> toJson() => {
    'disabledCategories': disabledCategories.toList()..sort(),
    'enabledKinds': enabledKinds,
    'quietHours': quietHours,
    if (servesKinds || disabledKinds.isNotEmpty)
      'disabledKinds': disabledKinds.toList()..sort(),
  };
}

Future<List<PushCategory>> fetchPushCategories() async {
  final j = await _api.get('/mobile/push/catalogue');
  return [
    for (final c in (j['categories'] as List? ?? const []))
      PushCategory.fromJson((c as Map).cast<String, dynamic>()),
  ];
}

Future<PushPreferences> fetchPushPreferences() async =>
    PushPreferences.fromJson(await _api.get('/mobile/push/preferences'));

Future<PushPreferences> savePushPreferences(PushPreferences p) async =>
    PushPreferences.fromJson(
      await _api.put('/mobile/push/preferences', p.toJson()),
    );

/// §30A marketing consent (invoice#61, 0123): GET/PUT
/// /mobile/push/marketing-consent {granted, text?}. Default off; only the user
/// can switch it on.
class MarketingConsent {
  const MarketingConsent({required this.granted, this.text = ''});

  factory MarketingConsent.fromJson(Map<String, dynamic> j) => MarketingConsent(
    granted: j['granted'] == true,
    text: j['text'] is String ? j['text'] as String : '',
  );

  final bool granted;

  /// The server's consent wording (versioned there); may be empty.
  final String text;
}

/// null: a server without the endpoint (404) — the switch is hidden.
Future<MarketingConsent?> fetchMarketingConsent() async {
  try {
    return MarketingConsent.fromJson(
      await _api.get('/mobile/push/marketing-consent'),
    );
  } on ApiException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

Future<MarketingConsent> saveMarketingConsent(bool granted) async =>
    MarketingConsent.fromJson(
      await _api.put('/mobile/push/marketing-consent', {'granted': granted}),
    );

/// A tap on a push carrying `pushId` (invoice#61 "opened" metrics). Fire and
/// forget: 404/422/429 and other answers are ignored; a network error is
/// retried once.
Future<void> reportPushOpened(String pushId) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await _api.post('/mobile/push/opened', {'pushId': pushId});
      return;
    } on ApiException catch (e) {
      if (e.status != 0) return; // answered (404/422/429/…) → drop
    } on Object {
      return;
    }
  }
}
