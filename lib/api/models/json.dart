// Shared JSON readers for every model file (INT). Money is BigInt agorot,
// never double. The server mixes snake_case and camelCase; each model reads
// exactly what its endpoint returns.

BigInt jBig(Object? v) => v == null ? BigInt.zero : BigInt.parse(v.toString());
BigInt? jBigOrNull(Object? v) => v == null ? null : BigInt.parse(v.toString());
String? jStr(Object? v) => v?.toString();
int jInt(Object? v) => v is int ? v : int.parse(v.toString());
int? jIntOrNull(Object? v) => v == null ? null : jInt(v);
bool jBool(Object? v) => v == true;
Map<String, dynamic> jMap(Object? v) =>
    v is Map<String, dynamic> ? v : const {};
List<String> jStrings(Object? v) => [
  for (final e in (v is List ? v : const [])) e.toString(),
];

/// First present key among [keys] (for rows that come in both casings).
Object? jPick(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    if (json.containsKey(k)) return json[k];
  }
  return null;
}
