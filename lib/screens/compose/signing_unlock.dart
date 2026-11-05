// Signature release inside the issue flow (SPEC-v2 §6.C API step 4, F7,
// AT-10c, AT-64). Owner: squad B. The Keychain + server calls are squad C's
// lib/api/signing_api.dart (shared with D state 6 and S5); this file only
// supplies the one-field passphrase dialog of the Composer.

import 'package:flutter/material.dart';

import '../../api/signing_api.dart' as signing;
import 'compose_dialogs.dart';

/// True when the business signing session is unlocked now; false when the
/// user cancelled (the document then waits in ARTIFACT_PENDING, D state 6).
Future<bool> ensureSigningUnlocked(BuildContext context) => signing.unlockSigning(
      askPassphrase: () async {
        if (!context.mounted) return null;
        final e = await askSigningPassphrase(context);
        return e == null ? null : (passphrase: e.passphrase, remember: e.save);
      },
    );
