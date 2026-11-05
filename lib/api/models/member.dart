// Team members and invitations (GET /business/members) — squad E. §6.B·צוות, §12.
// A member's preset is derived through caps.dart (the only place that compares
// roles, AT-48): role + grants → Me → Caps.fromMe(...).preset.

import '../../state/caps.dart';
import 'json.dart';
import 'me.dart';

/// The 4 presets an owner can pick in an invitation (§4.3), in display order.
const List<Preset> invitablePresets = [Preset.employee, Preset.partner, Preset.accountantRep, Preset.viewer];

/// Server role + explicit grants for a preset (P0, §4.3; BE-41 sends both).
/// [issuer] only matters for [Preset.employee] ("מפיק בעצמו").
(String role, List<String> grants) presetToServer(Preset preset, {bool issuer = false}) => switch (preset) {
  Preset.partner => ('ADMIN', const []),
  Preset.employee || Preset.employeeIssuer => (
    'EMPLOYEE',
    // + allocation:request (BE-03: retry / manual allocation number is gated on it).
    issuer || preset == Preset.employeeIssuer ? const ['document:finalize', 'payment:record', 'allocation:request'] : const [],
  ),
  Preset.accountantRep => ('READ_ONLY', const ['expense:record', 'expense:approve']),
  Preset.viewer => ('READ_ONLY', const []),
  Preset.accountantFull => ('ACCOUNTANT', const []),
  Preset.owner => ('OWNER', const []),
};

/// Preset of a server role + explicit grants (same derivation as the app's own caps).
Preset presetOf(String role, List<String> grants) => Caps.fromMe(
  Me(userId: '', role: role, permissions: {...?rolePermissionsFallback[role], ...grants}.toList()),
).preset;

/// True when [grants] are not exactly what [presetOf] implies (§12.4 "מותאם אישית").
bool hasCustomGrants(String role, List<String> grants) {
  final base = (rolePermissionsFallback[role] ?? const <String>[]).toSet();
  // ACCOUNTANT_REP (BE-04) already holds the accountant grants in its role.
  final expected = presetToServer(presetOf(role, grants)).$2.toSet().difference(base);
  // A pre-BE-03 self-issuer (no allocation:request yet) is still the preset.
  final extra = grants.toSet().difference(base)
    ..addAll(expected.contains('allocation:request') ? const ['allocation:request'] : const []);
  return extra.length != expected.length || !extra.containsAll(expected);
}

class TeamMember {
  const TeamMember({
    required this.userId,
    required this.email,
    this.displayName,
    required this.role,
    this.grants = const [],
    this.revoked = false,
    this.lastLoginAt,
    this.isSelf = false,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
    userId: json['userId'] as String,
    email: jStr(json['email']) ?? '',
    displayName: jStr(json['displayName']),
    role: json['role'] as String,
    grants: jStrings(json['permissions']),
    revoked: json['revokedAt'] != null,
    lastLoginAt: jStr(json['lastLoginAt']),
    isSelf: jBool(json['isSelf']),
  );

  final String userId;
  final String email;
  final String? displayName;

  /// Server role — read only through [preset] (caps.dart).
  final String role;

  /// Explicit extra grants (business_memberships.permissions).
  final List<String> grants;
  final bool revoked;
  final String? lastLoginAt;
  final bool isSelf;

  String get name => (displayName ?? '').trim().isEmpty ? email : displayName!.trim();
  Preset get preset => presetOf(role, grants);
  bool get custom => hasCustomGrants(role, grants);
  bool get isOwner => preset == Preset.owner;

  /// Effective permissions (role ∪ grants).
  Set<String> get effective => {...?rolePermissionsFallback[role], ...grants};

  /// Holds `approval:decide` (counts as an approver, §13.6).
  bool get canApprove => effective.contains('approval:decide');
}

class TeamInvitation {
  const TeamInvitation({
    required this.id,
    required this.email,
    required this.role,
    this.grants = const [],
    this.invitedBy,
    required this.expiresAt,
  });

  factory TeamInvitation.fromJson(Map<String, dynamic> json) => TeamInvitation(
    id: json['id'] as String,
    email: jStr(json['email']) ?? '',
    role: json['role'] as String,
    grants: jStrings(json['permissions']),
    invitedBy: jStr(json['invitedBy']),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );

  final String id;
  final String email;
  final String role;
  final List<String> grants;
  final String? invitedBy;
  final DateTime expiresAt;

  Preset get preset => presetOf(role, grants);

  /// Whole days left (floor), 0 = expires within a day.
  int daysLeft(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? 0 : d.inDays;
  }
}

/// GET /business/members.
class TeamList {
  const TeamList({this.members = const [], this.invitations = const [], this.expired = const []});

  factory TeamList.fromJson(Map<String, dynamic> json) => TeamList(
    members: [
      for (final m in (json['members'] as List? ?? const [])) TeamMember.fromJson(m as Map<String, dynamic>),
    ],
    invitations: [
      for (final i in (json['invitations'] as List? ?? const []))
        TeamInvitation.fromJson(i as Map<String, dynamic>),
    ],
    expired: [
      for (final i in (json['expiredInvitations'] as List? ?? const []))
        TeamInvitation.fromJson(i as Map<String, dynamic>),
    ],
  );

  final List<TeamMember> members;
  final List<TeamInvitation> invitations;

  /// BE-41: expired in the last 30 days ("פג תוקף · שלח שוב").
  final List<TeamInvitation> expired;

  List<TeamMember> get active => [
    for (final m in members)
      if (!m.revoked) m,
  ];

  /// Active members other than the caller who may approve documents (§13.6).
  List<TeamMember> get otherApprovers => [
    for (final m in active)
      if (!m.isSelf && m.canApprove) m,
  ];
}

/// POST /business/members/invite and /business/invitations/:id/resend.
class InviteResult {
  const InviteResult({required this.invitationId, this.inviteUrl, this.link, this.grantsStored});

  factory InviteResult.fromJson(Map<String, dynamic> json) => InviteResult(
    invitationId: jStr(json['invitationId']) ?? '',
    inviteUrl: jStr(json['inviteUrl']),
    link: jStr(json['link']),
    grantsStored: json['permissions'] is List ? jStrings(json['permissions']) : null,
  );

  final String invitationId;

  /// BE-41 universal link (for "שלח קישור בווטסאפ").
  final String? inviteUrl;

  /// V1 web link (fallback).
  final String? link;

  /// Grants the server stored on the invitation; null = server without BE-41.
  final List<String>? grantsStored;

  String? get shareUrl => inviteUrl ?? link;
}

/// GET /auth/invite/:token (public preview).
class InvitationPreview {
  const InvitationPreview({
    required this.email,
    required this.role,
    this.grants = const [],
    required this.businessName,
    required this.inviterName,
    required this.accountExists,
  });

  factory InvitationPreview.fromJson(Map<String, dynamic> json) => InvitationPreview(
    email: jStr(json['email']) ?? '',
    role: jStr(json['role']) ?? 'EMPLOYEE',
    grants: jStrings(json['permissions']),
    businessName: jStr(json['businessName']) ?? '',
    inviterName: jStr(json['inviterName']) ?? '',
    accountExists: jBool(json['accountExists']),
  );

  final String email;
  final String role;
  final List<String> grants;
  final String businessName;
  final String inviterName;
  final bool accountExists;

  Preset get preset => presetOf(role, grants);
}
