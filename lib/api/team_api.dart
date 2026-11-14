// Team & permissions (B·צוות, S13 "חבר צוות") — squad E. SPEC-v2 §12.
//
// GET  /business/members                          → TeamList
// POST /business/members/invite {email, role, permissions[]}   (BE-41 stores grants)
// POST /business/invitations/:id/resend                         (BE-41)
// POST /business/invitations/:id/revoke
// PUT  /business/members/:userId/role {role}  then  PUT …/permissions {permissions[]}
// POST /business/members/:userId/revoke
//
// P0 fallback (server without BE-41 ignores `permissions` on invite): the
// accountant grants are remembered on this device and applied with
// PUT …/permissions the first time the owner opens B·צוות after the
// accountant joined (§12.1; the row shows "משלים הגדרה…" until then).

import '../state/cache.dart';
import '../state/caps.dart';
import '../state/session.dart';
import 'client.dart';
import 'models/models.dart';

final _api = ApiClient.instance;

Future<TeamList> fetchTeam() async =>
    TeamList.fromJson(await _api.get('/business/members'));

// Not 'pending_…': AppCache treats that prefix as an unfinished money
// operation (kept on expiry, sign-out warning). Grants are not money.
String _pendingKey() => 'team_grants_${session.business?.businessId ?? ''}';

/// Pre-fix name; read once and removed.
String _legacyKey() => 'pending_grants_${session.business?.businessId ?? ''}';

Future<Map<String, dynamic>?> _readPending() async {
  final current = await AppCache.read(_pendingKey());
  if (current is Map<String, dynamic>) return current;
  final legacy = await AppCache.read(_legacyKey());
  if (legacy != null) await AppCache.remove(_legacyKey());
  if (legacy is Map<String, dynamic> && legacy.isNotEmpty) {
    await AppCache.write(_pendingKey(), legacy);
    return legacy;
  }
  return null;
}

Future<void> _writePending(Map<String, dynamic> map) => map.isEmpty
    ? AppCache.remove(_pendingKey())
    : AppCache.write(_pendingKey(), map);

/// Invites [email] as [preset]. Sends the grants (BE-41); a server that did
/// not store them gets them later via [completePendingGrants].
Future<InviteResult> inviteMember(
  String email,
  Preset preset, {
  bool issuer = false,
}) async {
  final address = email.trim().toLowerCase();
  Future<Map<String, dynamic>> send((String, List<String>) target) =>
      _api.post('/business/members/invite', {
        'email': address,
        'role': target.$1,
        if (target.$2.isNotEmpty) 'permissions': target.$2,
      });
  final (role, grants) = presetToServer(preset, issuer: issuer);
  final (json, asRep) = await _withRepFallback(
    preset,
    () => send(accountantRepTarget),
    () => send((role, grants)),
  );
  final result = InviteResult.fromJson(json);
  if (!asRep && grants.isNotEmpty && result.grantsStored == null) {
    await _rememberPending(address, grants);
  }
  return result;
}

Future<void> _rememberPending(String email, List<String> grants) async {
  try {
    final map = Map<String, dynamic>.of(await _readPending() ?? const {});
    map[email] = grants;
    await _writePending(map);
  } on Object {
    // Best effort; the owner can still pick the preset on the member.
  }
}

/// Emails whose grants are still to be applied (rows show "משלים הגדרה…").
Future<Set<String>> pendingGrantEmails() async {
  try {
    return (await _readPending())?.keys.toSet() ?? <String>{};
  } on Object {
    return <String>{};
  }
}

/// Applies remembered grants to members who joined since. Returns true when
/// anything was written (the caller reloads the list).
Future<bool> completePendingGrants(TeamList team) async {
  Map<String, dynamic> pending;
  try {
    final current = await _readPending();
    if (current == null || current.isEmpty) return false;
    pending = Map<String, dynamic>.of(current);
  } on Object {
    return false;
  }
  var changed = false;
  for (final m in team.active) {
    final grants = pending[m.email.toLowerCase()];
    if (grants is! List) continue;
    final want = [for (final g in grants) g.toString()];
    if (!m.grants.toSet().containsAll(want)) {
      await _api.put('/business/members/${m.userId}/permissions', {
        'permissions': {...m.grants, ...want}.toList(),
      });
      changed = true;
    }
    pending.remove(m.email.toLowerCase());
  }
  await _writePending(pending);
  return changed;
}

/// P0 accountants (READ_ONLY + expense grants, invited before BE-04) have no
/// report:read / export:run on a read-gated server, so their reports home is
/// empty. B·צוות offers the move to ACCOUNTANT_REP (§12.1); it runs only after
/// the owner confirms (it adds grants and makes MFA mandatory), never on view.
/// Returns true when the member is now ACCOUNTANT_REP; false on a pre-BE-04
/// server (the member is left as is).
Future<bool> migrateP0Accountant(TeamMember m) async {
  if (_repRoleSupported == false) return false;
  final (_, asRep) = await _withRepFallback(
    Preset.accountantRep,
    () => saveMemberRole(m, accountantRepTarget),
    () async {}, // pre-BE-04 server: leave the member as is
  );
  return asRep;
}

/// False once this server refused ACCOUNTANT_REP: no upgrade offer to show.
bool get accountantRepMaybeSupported => _repRoleSupported != false;

/// Active members still in the P0 accountant shape: the accountant preset
/// carried by explicit expense grants (ACCOUNTANT_REP holds them in its role,
/// so it has none). No role comparison here (AT-48).
List<TeamMember> p0Accountants(TeamList team) => [
  for (final m in team.active)
    if (!m.isSelf &&
        m.preset == Preset.accountantRep &&
        m.grants.contains('expense:approve'))
      m,
];

Future<void> saveMemberRole(
  TeamMember member,
  (String, List<String>) target,
) async {
  await _api.put('/business/members/${member.userId}/role', {
    'role': target.$1,
  });
  await _api.put('/business/members/${member.userId}/permissions', {
    'permissions': target.$2,
  });
}

/// BE-41: new token, fresh 7 days, e-mail sent again.
Future<InviteResult> resendInvitation(String invitationId) async =>
    InviteResult.fromJson(
      await _api.post('/business/invitations/$invitationId/resend'),
    );

Future<void> revokeInvitation(String invitationId) async {
  await _api.post('/business/invitations/$invitationId/revoke');
}

/// §12.3: PUT role, then PUT the preset's grants (same role is a no-op on the
/// server). Grants outside the preset ("מותאם אישית") are replaced — the
/// editor only saves after the owner picked a preset.
Future<void> saveMemberPreset(
  TeamMember member,
  Preset preset, {
  bool issuer = false,
}) async {
  await _withRepFallback(
    preset,
    () => saveMemberRole(member, accountantRepTarget),
    () => saveMemberRole(member, presetToServer(preset, issuer: issuer)),
  );
}

// ---- BE-04: the representing accountant role ---------------------------------

/// The accountant preset after BE-04: its own server role, no extra grants.
const (String, List<String>) accountantRepTarget = (
  'ACCOUNTANT_REP',
  <String>[],
);

/// null = not tried yet; false = this server refused ACCOUNTANT_REP (pre-BE-04).
bool? _repRoleSupported;

/// Test hook.
void resetAccountantRepProbe() => _repRoleSupported = null;

/// For the accountant preset tries the BE-04 role first and falls back to the
/// P0 shape (READ_ONLY + expense grants) when the server rejects the role.
/// Returns (result, usedRepRole).
Future<(T, bool)> _withRepFallback<T>(
  Preset preset,
  Future<T> Function() asRep,
  Future<T> Function() asP0,
) async {
  if (preset == Preset.accountantRep && _repRoleSupported != false) {
    try {
      final r = await asRep();
      _repRoleSupported = true;
      return (r, true);
    } on ApiException catch (e) {
      if (!(e.status == 400 || e.status == 422) || _repRoleSupported == true) {
        rethrow;
      }
      _repRoleSupported = false;
    }
  }
  return (await asP0(), false);
}

// ---- BE-49: ownership transfer -------------------------------------------------

/// Step 1: e-mails a 6-digit code to the owner. Returns the masked address.
Future<String?> requestOwnershipTransfer(String toUserId) async {
  final json = await _api.post('/business/ownership/transfer', {
    'toUserId': toUserId,
  });
  return json['sentTo'] as String?;
}

/// Step 2: with the code the member becomes OWNER and the caller ADMIN.
/// Reloads /me (the caller's capabilities change).
Future<void> confirmOwnershipTransfer(String toUserId, String code) async {
  await _api.post('/business/ownership/transfer', {
    'toUserId': toUserId,
    'code': code.trim(),
  });
  await session.refreshBusiness();
  await session.refreshAccount();
}

Future<void> removeMember(String userId) async {
  await _api.post('/business/members/$userId/revoke');
}
