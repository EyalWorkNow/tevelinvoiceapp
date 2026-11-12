import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/environment.dart';

void main() {
  test('production API uses a public HTTPS origin and normalizes slash', () {
    expect(
      productionApiUri('https://invoice.crm.tevel.space/').toString(),
      'https://invoice.crm.tevel.space',
    );
  });
  for (final value in [
    'http://invoice.crm.tevel.space',
    'http://127.0.0.1:3031',
    'https://127.0.0.1',
    'https://[::1]',
    'https://10.0.0.1',
    'https://localhost',
    'https://server.local',
    'https://api.internal',
    'https://user:password@example.com',
    'https://example.com/api',
    'https://example.com?token=secret',
    'https://example.com#fragment',
    'https://example.com:3031',
  ]) {
    test('release rejects unsafe endpoint $value', () {
      expect(() => productionApiUri(value), throwsFormatException);
    });
  }
}
