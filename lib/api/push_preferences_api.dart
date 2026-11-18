// Notification preferences (PUSH-001, account-level — no X-Business-Id):
//   GET /mobile/push/catalogue    {categories:[{id,label,description,canDisable}], kinds:[…]}
//   GET /mobile/push/preferences  {disabledCategories, enabledKinds, quietHours}
//   PUT /mobile/push/preferences  same shape; the server refuses switching SECURITY off.
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
  );

  final Set<String> disabledCategories;
  final List<String> enabledKinds;
  final bool quietHours;

  bool isOn(String category) => !disabledCategories.contains(category);

  PushPreferences withCategory(String category, bool on) => PushPreferences(
    disabledCategories: on
        ? ({...disabledCategories}..remove(category))
        : {...disabledCategories, category},
    enabledKinds: enabledKinds,
    quietHours: quietHours,
  );

  Map<String, Object> toJson() => {
    'disabledCategories': disabledCategories.toList()..sort(),
    'enabledKinds': enabledKinds,
    'quietHours': quietHours,
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
