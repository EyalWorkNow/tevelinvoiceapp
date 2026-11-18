// B·חשבון (SPEC-v2 §13.11–13.15). Owner: squad E. Every member sees it.
// Face ID · הסתר סכומים · אימות דו-שלבי · יציאה / יציאה מכל המכשירים ·
// פרטיות, תנאים, תמיכה (in-app Safari whitelist, F6) · גרסה · מחק חשבון (red,
// last; the sole owner first sees what closes, §13.15).

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../api/auth_api.dart' show MfaMethods, fetchMfaMethods;
import '../../api/models/models.dart';
import '../../api/settings_api.dart';
import '../../api/team_api.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/cache.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/biometric.dart';
import '../../util/error_log.dart';
import '../../util/labels/labels.dart';
import 'business_template.dart';
import 'business_data_page.dart';
import 'sheets/s13_editor.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'team_editors.dart' show confirmDanger;
import '../signature/signature_screen.dart' show openSignatureScreen;
import '../help/help_screen.dart' show openHelpScreen;

/// GET /auth/mfa/methods. Tests replace it.
Future<MfaMethods> Function() loadMfaMethods = fetchMfaMethods;

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.header});

  final Widget? header;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool? _faceIdAvailable;
  bool _faceId = true;
  bool _busy = false;

  /// The member's real second factors (GET /auth/mfa/methods); null = not
  /// loaded / unavailable (FIXB wiring audit: the row used to say "קוד במייל"
  /// whatever was enrolled).
  MfaMethods? _mfa;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrefs());
    unawaited(_loadMfa());
  }

  Future<void> _loadMfa() async {
    try {
      final m = await loadMfaMethods();
      if (mounted) setState(() => _mfa = m);
    } on Object {
      // Offline / older server: the row shows no value rather than a guess.
    }
  }

  Future<void> _loadPrefs() async {
    final available = await Biometric.instance.isAvailable();
    final enabled = await Biometric.instance.isEnabled();
    if (mounted) {
      setState(() {
        _faceIdAvailable = available;
        _faceId = enabled;
      });
    }
  }

  /// "שלח יומן תקלות": the local error log through the share sheet.
  Future<void> _sendErrorLog() async {
    try {
      final shared = await shareErrorLog(
        header:
            'Tevel $appVersion · ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}',
      );
      if (!shared && mounted) {
        ScaffoldMessenger.of(context).showNotchNotice(
          const SnackBar(content: Text(BusinessHe.errorLogEmpty)),
        );
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    }
    if (mounted) setState(() {});
  }

  /// Always asks (QA 2026-11-16 owner/188: one tap signed out).
  Future<void> _signOut() async {
    final pending = await AppCache.hasPending();
    if (!mounted) return;
    if (!await confirmDanger(
      context,
      BusinessHe.signOutConfirm,
      pending ? BusinessHe.signOutPendingBody : BusinessHe.signOutBody,
      BusinessHe.signOut,
    )) {
      return;
    }
    if (!mounted) return;
    await session.signOut();
  }

  Future<void> _signOutAll() async {
    if (!await confirmDanger(
      context,
      BusinessHe.signOutAllConfirm,
      BusinessHe.signOutAllBody,
      BusinessHe.signOutAll,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await logoutAllDevices();
      await session.signOutLocally();
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (businessContext.can(Cap.owner)) {
      List<TeamMember> others = const [];
      var anotherOwner = false;
      try {
        final team = await fetchTeam();
        others = [
          for (final m in team.active)
            if (!m.isSelf) m,
        ];
        anotherOwner = others.any((m) => m.isOwner);
      } on Object {
        // Offline / no team access: still warn, without names.
      }
      if (!anotherOwner) {
        var canTransfer = false;
        if (others.isNotEmpty) {
          try {
            canTransfer = await serverHasPost('/business/ownership/transfer');
          } on Object {
            canTransfer = false;
          }
        }
        if (!mounted) return;
        final go = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            settings: const RouteSettings(
              name: '/business/account/delete-warning',
            ),
            builder: (_) =>
                SoleOwnerWarning(members: others, canTransfer: canTransfer),
          ),
        );
        if (go != true || !mounted) return;
      }
    }
    if (mounted) await openDeleteAccount(context);
  }

  @override
  Widget build(BuildContext context) {
    final email = session.account?.email ?? '';
    final open = session.offline || _busy ? null : true;
    return BusinessPage(
      title: BusinessHe.account,
      header: widget.header,
      children: [
        BusinessRow(
          label: BusinessHe.signedInAs,
          value: ltrIsolate(email),
          icon: Iconsax.sms,
        ),
        if (businessContext.can(Cap.owner))
          BusinessRow(
            label: 'פרטי ההרשמה, תעודת העסק וייצוא מלא',
            icon: Icons.folder_zip_outlined,
            onTap: session.offline
                ? null
                : () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const BusinessDataPage(),
                    ),
                  ),
          ),
        BusinessRow(
          key: const Key('account-signature'),
          label: SignatureHe.title,
          icon: Iconsax.edit_2,
          onTap: session.offline ? null : () => openSignatureScreen(context),
        ),
        const RowGroupGap(),
        if (_faceIdAvailable == true)
          SwitchListTile.adaptive(
            key: const Key('account-faceid'),
            contentPadding: EdgeInsets.zero,
            title: const Text(BusinessHe.faceId, style: AppText.body),
            value: _faceId,
            onChanged: (v) async {
              setState(() => _faceId = v);
              await Biometric.instance.setEnabled(v);
            },
          ),
        ValueListenableBuilder<bool>(
          valueListenable: hideAmounts,
          builder: (context, hidden, _) => SwitchListTile.adaptive(
            key: const Key('account-hide-amounts'),
            contentPadding: EdgeInsets.zero,
            title: const Text(BusinessHe.hideAmounts, style: AppText.body),
            value: hidden,
            onChanged: setHideAmounts,
          ),
        ),
        BusinessRow(
          key: const Key('account-2fa'),
          label: BusinessHe.twoFactor,
          value: _mfa == null ? null : BusinessHe.twoFactorState(_mfa!),
          icon: Iconsax.shield_tick,
        ),
        if (businessContext.caps.can(Cap.settingsBusiness) ||
            businessContext.caps.can(Cap.reportView))
          BusinessRow(
            key: const Key('account-2fa-app'),
            label: BusinessHe.twoFactorApp,
            value: _mfa?.totp == true
                ? BusinessHe.twoFactorAppOn(_mfa!.recoveryCodesRemaining)
                : CommonHe.continueOnComputer,
            icon: Iconsax.mobile,
            onTap: open == null
                ? null
                : () => showEditorSheet(context, instance: '13.9'),
          ),
        const RowGroupGap(),
        BusinessRow(
          label: BusinessHe.privacy,
          icon: Iconsax.shield_security,
          onTap: () => openSafari(Uri.parse(privacyUrl)),
        ),
        BusinessRow(
          label: BusinessHe.terms,
          icon: Iconsax.document_text,
          onTap: () => openSafari(Uri.parse(termsUrl)),
        ),
        BusinessRow(
          key: const Key('account-help'),
          label: HelpHe.rowLabel,
          value: HelpHe.rowHint,
          icon: Iconsax.message_question,
          onTap: () => openHelpScreen(context),
        ),
        // Owner 2026-11-18: "תמיכה" opens the help chat too; a human (e-mail) is one tap
        // away inside it ("העבר לנציג").
        BusinessRow(
          key: const Key('account-support'),
          label: BusinessHe.support,
          icon: Iconsax.support,
          onTap: () => openHelpScreen(context),
        ),
        BusinessRow(
          label: BusinessHe.version,
          value: ltrIsolate(appVersion),
          icon: Iconsax.info_circle,
        ),
        BusinessRow(
          key: const Key('account-error-log'),
          label: BusinessHe.sendErrorLog,
          value: ErrorLog.instance.entries.isEmpty
              ? null
              : BusinessHe.errorLogCount(ErrorLog.instance.entries.length),
          icon: Iconsax.warning_2,
          onTap: _sendErrorLog,
        ),
        const RowGroupGap(),
        BusinessRow(
          key: const Key('account-signout'),
          label: BusinessHe.signOut,
          icon: Iconsax.logout,
          onTap: _busy ? null : _signOut,
        ),
        BusinessRow(
          key: const Key('account-signout-all'),
          label: BusinessHe.signOutAll,
          icon: Iconsax.devices,
          onTap: open == null ? null : _signOutAll,
        ),
        BusinessRow(
          key: const Key('account-delete'),
          label: BusinessHe.deleteAccount,
          icon: Iconsax.trash,
          destructive: true,
          onTap: open == null ? null : _delete,
        ),
      ],
    );
  }
}

/// §13.15: the only owner deletes the account → what closes, who loses access.
class SoleOwnerWarning extends StatelessWidget {
  const SoleOwnerWarning({
    super.key,
    required this.members,
    this.canTransfer = false,
  });

  /// BE-49: offer "העבר בעלות" (→ B·צוות, ⋯ on the member) before deleting.
  final bool canTransfer;

  /// Active members other than the caller in the current business.
  final List<TeamMember> members;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final current = session.business?.businessId;
    final otherOwned = [
      for (final b in session.businesses)
        if (b.businessId != current &&
            presetOf(b.role, const []) == Preset.owner)
          b.legalName,
    ];
    final names = members.map((m) => m.name).join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text(BusinessHe.soleOwnerTitle)),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Space.page),
          children: [
            Icon(Iconsax.warning_2, size: 48, color: p.danger),
            const SizedBox(height: Space.l),
            Text(
              BusinessHe.soleOwnerBody(
                businessContext.displayName,
                members.length,
                names,
              ),
              style: AppText.body,
            ),
            for (final name in otherOwned) ...[
              const SizedBox(height: Space.m),
              Text(BusinessHe.soleOwnerOther(name), style: AppText.body),
            ],
            if (canTransfer) ...[
              const SizedBox(height: Space.l),
              Text(BusinessHe.transferInstead, style: AppText.body),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('delete-transfer'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    openBusinessSection(context, BusinessSection.team);
                  },
                  child: const Text(TeamHe.transfer),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomActionArea(
        child: PrimaryButton(
          key: const Key('delete-anyway'),
          label: BusinessHe.deleteAnyway,
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
    );
  }
}
