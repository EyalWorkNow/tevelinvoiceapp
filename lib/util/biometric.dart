import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Outcome of a Face ID / passcode prompt.
enum UnlockResult {
  success,

  /// User cancelled or failed: stay locked.
  failed,

  /// The device cannot lock (no passcode set, no hardware): let the user in.
  unavailable,
}

/// Optional Face ID / device passcode gate after 5 minutes in the background.
/// It is opt-in in settings and the preference survives sign-out.
class Biometric {
  Biometric._();
  static final Biometric instance = Biometric._();

  /// Lock again after this long in the background.
  static const Duration lockAfter = Duration(minutes: 5);

  static const _kEnabled = 'biometric_enabled';

  /// Replaceable in tests.
  LocalAuthentication auth = LocalAuthentication();
  FlutterSecureStorage storage = const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Device has Face ID / Touch ID or at least a passcode.
  Future<bool> isAvailable() async {
    try {
      return await auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  /// "Face ID" or "קוד המכשיר" for labels.
  Future<String> methodLabel() async {
    try {
      final types = await auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return 'Face ID';
      if (types.contains(BiometricType.fingerprint)) return 'Touch ID';
    } on Object {
      // fall through
    }
    return 'קוד המכשיר';
  }

  Future<bool> isEnabled() async {
    try {
      return await storage.read(key: _kEnabled) == '1';
    } on Object {
      return false;
    }
  }

  Future<void> setEnabled(bool enabled) =>
      storage.write(key: _kEnabled, value: enabled ? '1' : '0');

  /// Enabled in settings AND the device can actually lock.
  Future<bool> shouldLock() async => await isEnabled() && await isAvailable();

  /// System prompt (Face ID, falls back to the device passcode).
  Future<UnlockResult> unlock({String reason = 'פתיחת תבל'}) async {
    try {
      final ok = await auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      return ok ? UnlockResult.success : UnlockResult.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.noCredentialsSet => UnlockResult.unavailable,
        _ => UnlockResult.failed,
      };
    } on PlatformException {
      return UnlockResult.failed;
    }
  }
}
