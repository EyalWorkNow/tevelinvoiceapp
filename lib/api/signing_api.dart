// Signing inside the issue flow (squad C; B imports) — SPEC-v2 §6.C step 4,
// §6.D row 6, AT-64, F7.
//
// POST /documents/:id/artifact → {signing: SIGNED | LOCKED | NOT_APPLICABLE}.
// LOCKED = the original is sealed but unsigned (document ARTIFACT_PENDING).
// Release: Face ID → the signing passphrase from the Keychain →
// POST /settings/signing/unlock {passphrase} → POST /documents/:id/sign.
// (The spec says "/artifact again"; the server refuses a second ORIGINAL, so
// the pending original is signed with /sign.)
// No passphrase saved → a one-field dialog (the caller's [PassphrasePrompt]);
// "שמור עם Face ID" stores it after a Face ID confirmation.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/session.dart';
import '../util/biometric.dart';
import 'client.dart';

final _api = ApiClient.instance;

/// What the dialog returns: the passphrase and whether to keep it on the
/// device behind Face ID.
typedef PassphraseAnswer = ({String passphrase, bool remember});

/// Shows the one-field "סיסמת החתימה" dialog; null = cancelled.
typedef PassphrasePrompt = Future<PassphraseAnswer?> Function();

/// Face ID confirmation of "שמור עם Face ID". Replaceable in tests.
Future<bool> Function(String reason) signingBiometric = (reason) async {
  final r = await Biometric.instance.unlock(reason: reason);
  return r != UnlockResult.failed;
};

/// Keychain for the saved passphrase (per business, this device only). Reads
/// are gated by the OS with the currently enrolled Face ID (biometryCurrentSet):
/// that system prompt IS the Face ID of the release; a new enrolment makes the
/// item unreadable and the dialog comes back.
FlutterSecureStorage signingStorage = const FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  ),
);

String _key() =>
    'signing_passphrase_${session.business?.businessId ?? _api.businessId ?? 'none'}';

Future<String?> _saved() async {
  try {
    final v = await signingStorage.read(key: _key());
    return v == null || v.isEmpty ? null : v;
  } on Object {
    return null;
  }
}

/// §13.8 "שכח את סיסמת החתימה מהמכשיר".
Future<void> forgetSigningPassphrase() async {
  try {
    await signingStorage.delete(key: _key());
  } on Object {
    // nothing saved
  }
}

/// Whether a passphrase is saved on this device (J1-first-time fixture).
Future<bool> hasSavedSigningPassphrase() async => await _saved() != null;

/// POST /settings/signing/unlock.
Future<void> unlockSigningSession(String passphrase) =>
    _api.post('/settings/signing/unlock', {'passphrase': passphrase});

/// Opens the signing session. Returns false when the user cancelled
/// (Face ID or the dialog). Throws ApiException for server errors other than
/// a wrong saved passphrase (which is forgotten and asked again).
Future<bool> unlockSigning({required PassphrasePrompt askPassphrase}) async {
  final saved =
      await _saved(); // the OS Face ID prompt (null = cancelled / none)
  if (saved != null) {
    try {
      await unlockSigningSession(saved);
      return true;
    } on ApiException catch (e) {
      if (e.code != 'SIGNING_ACTIVATION_INVALID') rethrow;
      await forgetSigningPassphrase();
    }
  }
  final answer = await askPassphrase();
  if (answer == null || answer.passphrase.isEmpty) return false;
  await unlockSigningSession(answer.passphrase);
  if (answer.remember && await signingBiometric('שמירת סיסמת החתימה')) {
    try {
      await signingStorage.write(key: _key(), value: answer.passphrase);
    } on Object {
      // Keychain unavailable: the dialog comes back next time.
    }
  }
  return true;
}

/// signing of POST /artifact.
enum ArtifactSigning { signed, locked, notApplicable }

ArtifactSigning _signingOf(Map<String, dynamic> json) =>
    switch (json['signing']) {
      'SIGNED' => ArtifactSigning.signed,
      'LOCKED' => ArtifactSigning.locked,
      _ => ArtifactSigning.notApplicable,
    };

/// POST /documents/:id/artifact (the ORIGINAL). An original that already
/// exists counts as done (a retry after a lost response).
Future<ArtifactSigning> createOriginalArtifact(String documentId) async {
  try {
    return _signingOf(await _api.post('/documents/$documentId/artifact'));
  } on ApiException catch (e) {
    if (e.code != 'ORIGINAL_ARTIFACT_REGENERATION_FORBIDDEN') rethrow;
    return ArtifactSigning.notApplicable;
  }
}

/// POST /documents/:id/sign (an ARTIFACT_PENDING original, session unlocked).
Future<void> signPendingOriginal(String documentId) =>
    _api.post('/documents/$documentId/sign');

/// The whole step 4 for one document: original → (LOCKED) unlock → sign.
/// [alreadySealed] = the document is ARTIFACT_PENDING (§6.D row 6): skip
/// /artifact. Returns false when the user cancelled the release; the
/// document then stays "ממתין לחתימה" (§6.D row 6/7, SIGNING_LOCKED card).
Future<bool> issueSignedOriginal(
  String documentId, {
  required PassphrasePrompt askPassphrase,
  bool alreadySealed = false,
}) async {
  if (!alreadySealed) {
    final signing = await createOriginalArtifact(documentId);
    if (signing != ArtifactSigning.locked) return true;
  }
  try {
    await signPendingOriginal(documentId);
    return true; // the session was already open
  } on ApiException catch (e) {
    if (e.code != 'SIGNING_LOCKED') rethrow;
  }
  if (!await unlockSigning(askPassphrase: askPassphrase)) return false;
  await signPendingOriginal(documentId);
  return true;
}
