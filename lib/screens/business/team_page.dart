// B·צוות (SPEC-v2 §6.B, §12). Owner: squad E.
// "+ הזמן" (primary) · "הזמן רואה חשבון" · members (name · email · preset tag)
// · pending invitations ("ממתין · פג בעוד N ימים", ⋯ שלח שוב / שלח קישור
// בווטסאפ / בטל הזמנה) · expired ("פג תוקף", ⋯ שלח שוב).
// Tap a member → S13 "חבר צוות". No ⋯ on the owner or on yourself; a
// partner (ADMIN) sees no actions on the owner.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/models/models.dart';
import '../../api/settings_api.dart' show serverHasPost;
import '../../api/team_api.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';
import 'business_template.dart';
import 'sheets/s13_editor.dart';
import 'team_editors.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key, this.now});

  /// Clock for "פג בעוד N ימים" (tests).
  final DateTime Function()? now;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  TeamList? _team;
  Set<String> _pending = const {};
  List<TeamMember> _upgrades = const [];
  Object? _error;

  /// BE-49 is on the server and the caller is the owner.
  bool _canTransfer = false;

  /// One action at a time: a second tap on "שלח שוב" / "+ הזמן" while the
  /// first is in flight does nothing (no duplicate e-mails or sheets).
  bool _busy = false;

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      var team = await fetchTeam();
      if (await completePendingGrants(team)) team = await fetchTeam();
      final gated = businessContext.me?.readGating ?? false;
      // P0 accountants: offered (not applied) — the owner confirms each move
      // to ACCOUNTANT_REP; nothing is written on a screen view.
      final upgrades =
          gated &&
              businessContext.can(Cap.teamManage) &&
              accountantRepMaybeSupported
          ? p0Accountants(team)
          : const <TeamMember>[];
      final pending = await pendingGrantEmails();
      var canTransfer = false;
      if (businessContext.can(Cap.owner)) {
        try {
          canTransfer = await serverHasPost('/business/ownership/transfer');
        } on Object {
          canTransfer = false;
        }
      }
      if (mounted) {
        setState(() {
          _team = team;
          _pending = pending;
          _upgrades = upgrades;
          _canTransfer = canTransfer;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _invite({Preset preset = Preset.employee}) => _guarded(() async {
    final result = await showInviteEditor(context, preset: preset);
    if (result != null) await _load();
  });

  Future<void> _openMember(TeamMember m) => _guarded(() async {
    if (await showEditorSheet(
      context,
      instance: 'member',
      config: memberEditor(context, m, canTransfer: _canTransfer),
    )) {
      await _load();
    }
  });

  /// One-line confirm, then P0 accountant → ACCOUNTANT_REP (§12.1).
  Future<void> _upgrade(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(TeamHe.upgradeConfirm(m.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            key: const Key('confirm-upgrade'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(TeamHe.upgrade),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _act(() async {
      final asRep = await migrateP0Accountant(m);
      if (mounted) {
        final text = asRep ? TeamHe.upgraded : TeamHe.upgradeUnsupported;
        ScaffoldMessenger.of(
          context,
        ).showNotchNotice(SnackBar(content: Text(text)));
      }
    }, '');
  }

  Future<void> _act(Future<void> Function() action, String done) =>
      _guarded(() async {
        try {
          await action();
          if (mounted && done.isNotEmpty) {
            ScaffoldMessenger.of(
              context,
            ).showNotchNotice(SnackBar(content: Text(done)));
          }
          await _load();
        } on Object catch (e) {
          if (mounted) showErrorSnack(context, e);
        }
      });

  List<MoreMenuItem> _invitationMenu(
    TeamInvitation i, {
    required bool expired,
  }) => [
    MoreMenuItem(
      label: TeamHe.resend,
      icon: Iconsax.refresh,
      onSelected: () => _act(() async => resendInvitation(i.id), TeamHe.resent),
    ),
    if (!expired)
      MoreMenuItem(
        label: TeamHe.sendWhatsApp,
        icon: Iconsax.messages_1,
        onSelected: () => _act(() async {
          final r = await resendInvitation(i.id);
          final url = r.shareUrl;
          if (url == null) return;
          final text = TeamHe.waText(businessContext.displayName, url);
          await launchAllowed(
            Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
          );
        }, TeamHe.resent),
      ),
    if (!expired)
      MoreMenuItem(
        label: TeamHe.revokeInvite,
        destructive: true,
        onSelected: () async {
          if (await confirmDanger(
            context,
            TeamHe.revokeInviteConfirm,
            i.email,
            TeamHe.revokeInvite,
          )) {
            await _act(() => revokeInvitation(i.id), TeamHe.revokeInvite);
          }
        },
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final team = _team;
    final offline = session.offline;
    final idle = !offline && !_busy;
    return BusinessPage(
      title: BusinessHe.team,
      onRefresh: _load,
      bottom: team == null
          ? null
          : BottomActionArea(
              child: PrimaryButton(
                key: const Key('team-invite'),
                label: TeamHe.invite,
                offline: offline,
                onPressed: _invite,
              ),
            ),
      children: [
        if (_error != null)
          SizedBox(
            height: 360,
            child: ErrorView(error: _error!, onRetry: _load),
          )
        else if (team == null)
          const SizedBox(height: 360, child: SkeletonList(rows: 4))
        else ...[
          BusinessRow(
            key: const Key('team-invite-accountant'),
            label: TeamHe.inviteAccountant,
            icon: Iconsax.calculator,
            onTap: idle ? () => _invite(preset: Preset.accountantRep) : null,
          ),
          const RowGroupGap(),
          for (final m in _upgrades)
            BusinessRow(
              key: Key('upgrade-${m.userId}'),
              label: TeamHe.upgradeConfirm(m.name),
              icon: Iconsax.shield_tick,
              onTap: idle ? () => _upgrade(m) : null,
            ),
          for (final m in team.active) _memberRow(m),
          for (final i in team.invitations) _invitationRow(i, expired: false),
          for (final i in team.expired) _invitationRow(i, expired: true),
          if (team.active.length <= 1 &&
              team.invitations.isEmpty &&
              team.expired.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: Space.xl),
              child: EmptyState(
                icon: Iconsax.user_add,
                title: TeamHe.empty,
                message: TeamHe.emptyHint,
              ),
            ),
        ],
      ],
    );
  }

  Widget _memberRow(TeamMember m) {
    final viewerIsOwner = businessContext.can(Cap.owner);
    // §6.B קצה: never on yourself or the owner; a partner sees no actions on the owner.
    final editable = !m.isSelf && !m.isOwner && (viewerIsOwner || !m.isOwner);
    final tag = m.custom
        ? TeamHe.custom
        : _pending.contains(m.email.toLowerCase())
        ? TeamHe.completing
        : PresetHe.label(m.preset);
    return BusinessRow(
      key: Key('member-${m.userId}'),
      label: m.isSelf ? '${m.name} ${TeamHe.you}' : m.name,
      value: m.name == m.email ? tag : '${ltrIsolate(m.email)} · $tag',
      icon: Iconsax.user,
      onTap: editable && !session.offline && !_busy
          ? () => _openMember(m)
          : null,
    );
  }

  Widget _invitationRow(TeamInvitation i, {required bool expired}) {
    final now = widget.now?.call() ?? DateTime.now();
    final status = expired ? TeamHe.expired : TeamHe.pending(i.daysLeft(now));
    return BusinessRow(
      key: Key('invitation-${i.id}'),
      label: ltrIsolate(i.email),
      value: '${PresetHe.label(i.preset)} · $status',
      icon: Iconsax.sms,
      trailing: session.offline || _busy
          ? null
          : MoreMenu(items: _invitationMenu(i, expired: expired)),
    );
  }
}
