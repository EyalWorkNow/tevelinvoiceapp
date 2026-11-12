// "רשות המסים וחתימה" status page (§13.7–13.8) — squad E. Read-only in P0:
// connecting/renewing is "המשך במחשב" until BE-42; the signing passphrase is
// released inside the issue flow (C's signing_api.dart), never here.

import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

/// GET /shaam/status (same field names as /me.shaam, BE-02).
Future<ShaamState> fetchShaamStatus() async =>
    ShaamState.fromJson(await _api.get('/shaam/status'));

/// GET /settings/signing → what the status line needs.
class SigningStatus {
  const SigningStatus({
    required this.available,
    required this.configured,
    required this.unlocked,
  });

  factory SigningStatus.fromJson(Map<String, dynamic> json) => SigningStatus(
    available: json['available'] != false,
    configured: json['identity'] != null,
    unlocked: (json['session'] as Map<String, dynamic>?)?['unlocked'] == true,
  );

  /// Signing is wired on this server.
  final bool available;

  /// An ACTIVE signing identity exists.
  final bool configured;

  /// The business signing session is open right now.
  final bool unlocked;
}

Future<SigningStatus> fetchSigningStatus() async =>
    SigningStatus.fromJson(await _api.get('/settings/signing'));
