// /me, /business/profile and /mobile/session fixtures for the 7 presets of
// SPEC-v2 §4.3/§4.4 × the 5 business types (INT). AT-52 goldens iterate these.

import 'package:invoice/api/client.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';

import 'fake_backend.dart';

const List<String> businessTypes = [
  'OSEK_PATUR',
  'OSEK_MURSHE',
  'COMPANY',
  'PARTNERSHIP',
  'NONPROFIT',
];

const List<String> _allPerms = [
  'document:read',
  'document:draft:write',
  'document:finalize',
  'document:send',
  'payment:record',
  'expense:record',
  'expense:approve',
  'business:configure',
  'membership:manage',
  'document:cancel',
  'approval:decide',
];

/// Server role + effective permissions (BE-02) of each preset (§4.3, P0).
(String role, List<String> permissions) presetGrant(Preset preset) =>
    switch (preset) {
      Preset.owner => ('OWNER', _allPerms),
      Preset.partner => ('ADMIN', _allPerms),
      Preset.employee => (
        'EMPLOYEE',
        [
          'document:read',
          'document:draft:write',
          'document:send',
          'expense:record',
        ],
      ),
      Preset.employeeIssuer => (
        'EMPLOYEE',
        [
          'document:read',
          'document:draft:write',
          'document:send',
          'expense:record',
          'document:finalize',
          'payment:record',
        ],
      ),
      Preset.accountantRep => (
        'READ_ONLY',
        ['document:read', 'expense:record', 'expense:approve'],
      ),
      Preset.accountantFull => (
        'ACCOUNTANT',
        [
          'document:read',
          'document:draft:write',
          'document:finalize',
          'document:send',
          'payment:record',
          'expense:record',
          'expense:approve',
          'document:cancel',
          'approval:decide',
        ],
      ),
      Preset.viewer => ('READ_ONLY', ['document:read']),
    };

/// GET /me. [be02] = false gives the V1 shape (no permissions / isOwner /
/// businessType) to test the fail-closed fallback.
Map<String, dynamic> meJson(
  Preset preset, {
  String businessType = 'OSEK_MURSHE',
  String userId = 'u-me',
  Map<String, dynamic>? approvalPolicy,
  bool be02 = true,
  bool onboardingCompleted = true,
  int memberCount = 3,
  bool signingUnlocked = true,
  bool readGating = false,
}) {
  final (role, perms) = presetGrant(preset);
  final policy = approvalPolicy ?? {'mode': 'NONE', 'thresholdMinor': '0'};
  return {
    'userId': userId,
    'role': role,
    'mfaEnrolled': true,
    'canFinalize': perms.contains('document:finalize'),
    'canConfigure': perms.contains('business:configure'),
    'canApproveExpenses': perms.contains('expense:approve'),
    'onboarding': {
      'completed': onboardingCompleted,
      'step': onboardingCompleted ? 7 : 1,
    },
    'approvalPolicy': policy,
    if (be02) ...{
      'isOwner': preset == Preset.owner,
      'permissions': perms,
      'businessType': businessType,
      'vatReporting': 'BIMONTHLY',
      'memberCount': memberCount,
      'shaam': {
        'status': 'CONNECTED',
        'refreshTokenExpiresAt': '2027-01-10T00:00:00Z',
        'lastVerifiedAt': '2026-10-01T00:00:00Z',
        'manualEntryEnabled': false,
        'canConfigure': perms.contains('business:configure'),
      },
      'signing': {'configured': true, 'unlocked': signingUnlocked},
      'exports': {'uniformFormatReady': false},
      'rules': {
        'exemptCeilingMinor': '12000000',
        'exemptCeilingYear': 2026,
        'yearTurnoverMinor': '0',
      },
      'enforcement': {'readGating': readGating},
    },
  };
}

/// GET /business/profile → {profile, canConfigure}.
Map<String, dynamic> profileJson({
  String businessType = 'OSEK_MURSHE',
  String legalName = 'סטודיו תבל',
  String? paymentLinkUrl = 'https://pay.example/tevel',
  String? section46ApprovalNumber,
  bool identityLocked = true,
  bool canConfigure = true,
}) => {
  'profile': {
    'legalName': legalName,
    'businessType': businessType,
    'taxId': '000000042',
    'paymentLinkUrl': paymentLinkUrl,
    'section46ApprovalNumber': section46ApprovalNumber,
    'identityLocked': identityLocked,
    'onboarding': {'completed': true},
  },
  'canConfigure': canConfigure,
};

/// GET /mobile/session with [count] businesses (first = 'b1').
Map<String, dynamic> accountJson({int count = 1, String role = 'OWNER'}) => {
  'userId': 'u-me',
  'email': 'me@tevel.test',
  'displayName': 'דנה',
  'businesses': [
    for (var i = 1; i <= count; i++)
      {'businessId': 'b$i', 'legalName': 'עסק $i', 'role': role},
  ],
};

/// Signs the app-wide [session] in as [preset] against [backend] (registers
/// /me, /business/profile, /mobile/session) and loads /me + profile through
/// the real session code. Returns the parsed account.
Future<MobileAccount> signInAs(
  FakeBackend backend,
  Preset preset, {
  String businessType = 'OSEK_MURSHE',
  int businesses = 1,
  Map<String, dynamic>? approvalPolicy,
  bool be02 = true,
  Map<String, dynamic>? profile,
}) async {
  final (role, _) = presetGrant(preset);
  backend
    ..json(
      'GET',
      '/me',
      meJson(
        preset,
        businessType: businessType,
        approvalPolicy: approvalPolicy,
        be02: be02,
      ),
    )
    ..json(
      'GET',
      '/business/profile',
      profile ?? profileJson(businessType: businessType),
    )
    ..json(
      'GET',
      '/mobile/session',
      accountJson(count: businesses, role: role),
    );
  final api = ApiClient.instance
    ..deviceToken = 'inv_${'a' * 48}'
    ..businessId = 'b1';
  final account = MobileAccount.fromJson(
    accountJson(count: businesses, role: role),
  );
  session
    ..account = account
    ..business = account.businesses.first
    ..offline = false
    ..expired = false
    ..status = SessionStatus.signedIn;
  api.businessId = 'b1';
  await session.refreshBusiness();
  return account;
}

/// Back to a signed-out app-wide session (call in setUp).
void resetSession() {
  ApiClient.instance.clearCredentials();
  session
    ..status = SessionStatus.signedOut
    ..account = null
    ..business = null
    ..me = null
    ..profile = null
    ..meFetchedAt = null
    ..offline = false
    ..expired = false;
}
