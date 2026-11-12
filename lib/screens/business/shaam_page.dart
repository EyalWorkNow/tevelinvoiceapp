// B · "רשות המסים וחתימה" (SPEC-v2 §13.7–13.8). Owner: squad E.
// Status in words. P0: "התחבר / חדש" = המשך במחשב (BE-42 is P2). Signing:
// status only + "שכח את סיסמת החתימה מהמכשיר"; the passphrase is released
// with Face ID inside the issue flow, never here.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/models/models.dart';
import '../../api/shaam_api.dart';
import '../../api/signing_api.dart' show forgetSigningPassphrase, hasSavedSigningPassphrase;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import 'business_template.dart';
import 'sheets/editor_configs.dart' show desktopEditor;
import 'sheets/s13_editor.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class ShaamPage extends StatefulWidget {
  const ShaamPage({super.key});

  @override
  State<ShaamPage> createState() => _ShaamPageState();
}

class _ShaamPageState extends State<ShaamPage> {
  ShaamState? _shaam;
  SigningStatus? _signing;
  bool _savedPassphrase = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object?>([
        fetchShaamStatus(),
        businessContext.can(Cap.docIssue) ? fetchSigningStatus() : Future<Object?>.value(),
        hasSavedSigningPassphrase(),
      ]);
      if (!mounted) return;
      setState(() {
        _shaam = results[0] as ShaamState;
        _signing = results[1] as SigningStatus?;
        _savedPassphrase = results[2] as bool;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  static String _status(ShaamState s) => switch (s.status) {
    'CONNECTED' => BusinessHe.shaamConnected,
    'EXPIRED' || 'REAUTH_REQUIRED' || 'REVOKED' => BusinessHe.shaamExpired,
    'DISABLED' => BusinessHe.shaamOff,
    _ => BusinessHe.shaamNotConnected,
  };

  @override
  Widget build(BuildContext context) {
    final shaam = _shaam;
    final configure = businessContext.can(Cap.settingsBusiness);
    return BusinessPage(
      title: BusinessHe.shaam,
      onRefresh: _load,
      children: [
        if (_error != null)
          SizedBox(
            height: 360,
            child: ErrorView(error: _error!, onRetry: _load),
          )
        else if (shaam == null)
          const SizedBox(height: 360, child: SkeletonList(rows: 3))
        else ...[
          Semantics(header: true, child: const Text(BusinessHe.shaamTitle, style: AppText.headline)),
          BusinessRow(
            key: const Key('shaam-status'),
            label: _status(shaam),
            value: [
              if (shaam.refreshTokenExpiresAt != null)
                BusinessHe.shaamValidUntil(formatDateHe(shaam.refreshTokenExpiresAt!.substring(0, 10))),
              if (shaam.lastVerifiedAt != null)
                BusinessHe.shaamVerified(formatDateHe(shaam.lastVerifiedAt!.substring(0, 10))),
              if (shaam.manualEntryEnabled) BusinessHe.shaamManual,
            ].join(' · '),
            icon: Iconsax.bank,
          ),
          if (configure && shaam.status != 'DISABLED')
            BusinessRow(
              key: const Key('shaam-connect'),
              label: BusinessHe.shaamConnect,
              value: CommonHe.continueOnComputer,
              icon: Iconsax.monitor,
              onTap: () => showEditorSheet(
                context,
                instance: '13.9',
                config: desktopEditor(topic: 'TAX_AUTHORITY'),
              ),
            ),
          if (_signing != null) ...[
            const RowGroupGap(),
            Semantics(header: true, child: const Text(BusinessHe.signingTitle, style: AppText.headline)),
            BusinessRow(
              key: const Key('signing-status'),
              label: !_signing!.configured
                  ? BusinessHe.signingNotConfigured
                  : _signing!.unlocked
                  ? BusinessHe.signingActive
                  : BusinessHe.signingWillUnlock,
              icon: Iconsax.edit_2,
            ),
            if (_savedPassphrase)
              BusinessRow(
                key: const Key('signing-forget'),
                label: BusinessHe.signingForget,
                icon: Iconsax.key_square,
                onTap: () async {
                  await forgetSigningPassphrase();
                  if (!context.mounted) return;
                  setState(() => _savedPassphrase = false);
                  ScaffoldMessenger.of(
                    context,
                  ).showNotchNotice(const SnackBar(content: Text(BusinessHe.signingForgotten)));
                },
              ),
          ],
        ],
      ],
    );
  }
}
