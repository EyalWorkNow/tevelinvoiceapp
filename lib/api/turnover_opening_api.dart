// Stage A · A6 — "מחזור מתחילת השנה לפני תבל" (עוסק פטור only).
// GET/PUT /business/turnover-opening {taxYear, amountMinor} (server migration 0098).

import 'client.dart';
import 'customers_api.dart' show isMissingRoute;

final _api = ApiClient.instance;

/// The opening turnover of [year]: null amount = not entered;
/// null result = this server has no such route (field hidden).
Future<({int taxYear, BigInt? amountMinor})?> fetchTurnoverOpening(
  int year,
) async {
  try {
    final json = await _api.get(
      '/business/turnover-opening',
      query: {'year': '$year'},
    );
    final raw = json['amountMinor'];
    return (
      taxYear: year,
      amountMinor: raw == null ? null : BigInt.parse(raw.toString()),
    );
  } on ApiException catch (e) {
    if (isMissingRoute(e)) return null;
    rethrow;
  }
}

Future<void> saveTurnoverOpening(int year, BigInt amountMinor) async {
  await _api.put('/business/turnover-opening', {
    'taxYear': year,
    'amountMinor': amountMinor.toString(),
  });
}
