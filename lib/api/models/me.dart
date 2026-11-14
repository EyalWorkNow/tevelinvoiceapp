// GET /me (business-scoped, camelCase) — extended by BE-02 (spec §4.2, §14).
// Owner: INT. Capabilities are computed from this in lib/state/caps.dart;
// nothing here compares roles (AT-48).

import 'json.dart';

/// `/me.approvalPolicy` (§4.8). The threshold compares to total_minor
/// INCLUDING VAT, `>=`.
class ApprovalPolicy {
  const ApprovalPolicy({
    required this.mode,
    BigInt? thresholdMinor,
    this.includesVat = true,
    this.selfApprovalAllowed = true,
    this.otherApproverExists = false,
  }) : _threshold = thresholdMinor;

  factory ApprovalPolicy.fromJson(Map<String, dynamic> json) => ApprovalPolicy(
    mode: jStr(json['mode']) ?? 'NONE',
    thresholdMinor: jBig(json['thresholdMinor']),
    includesVat: json['includesVat'] != false,
    selfApprovalAllowed: json['selfApprovalAllowed'] != false,
    otherApproverExists: jBool(json['otherApproverExists']),
  );

  static const none = ApprovalPolicy(mode: 'NONE');

  /// NONE | THRESHOLD
  final String mode;
  final BigInt? _threshold;

  /// Total INCLUDING VAT from which approval is needed (0 when NONE).
  BigInt get thresholdMinor => _threshold ?? BigInt.zero;
  final bool includesVat;
  final bool selfApprovalAllowed;
  final bool otherApproverExists;

  bool get isThreshold => mode == 'THRESHOLD';
}

/// `/me.shaam` — same field names as GET /shaam/status (BE-02).
class ShaamState {
  const ShaamState({
    required this.status,
    this.refreshTokenExpiresAt,
    this.lastVerifiedAt,
    this.manualEntryEnabled = false,
    this.canConfigure = false,
  });

  factory ShaamState.fromJson(Map<String, dynamic> json) => ShaamState(
    status: jStr(json['status']) ?? 'UNKNOWN',
    refreshTokenExpiresAt: jStr(json['refreshTokenExpiresAt']),
    lastVerifiedAt: jStr(json['lastVerifiedAt']),
    manualEntryEnabled: jBool(json['manualEntryEnabled']),
    canConfigure: jBool(json['canConfigure']),
  );

  final String status;
  final String? refreshTokenExpiresAt;
  final String? lastVerifiedAt;
  final bool manualEntryEnabled;
  final bool canConfigure;
}

/// `/me.rules` (exempt-dealer ceiling, BE-02).
class BusinessRules {
  const BusinessRules({
    this.exemptCeilingMinor,
    this.exemptCeilingYear,
    this.yearTurnoverMinor,
  });

  factory BusinessRules.fromJson(Map<String, dynamic> json) => BusinessRules(
    exemptCeilingMinor: jBigOrNull(json['exemptCeilingMinor']),
    exemptCeilingYear: jIntOrNull(json['exemptCeilingYear']),
    yearTurnoverMinor: jBigOrNull(json['yearTurnoverMinor']),
  );

  final BigInt? exemptCeilingMinor;
  final int? exemptCeilingYear;
  final BigInt? yearTurnoverMinor;
}

/// GET /me. V1 fields (canFinalize, canConfigure, canApproveExpenses) stay;
/// BE-02 adds the rest. Every BE-02 field is optional so the app keeps working
/// against a server without BE-02 ([hasEffectivePermissions] = false).
class Me {
  const Me({
    required this.userId,
    required this.role,
    this.isOwner,
    this.permissions,
    this.mfaEnrolled = false,
    this.onboardingCompleted = false,
    this.onboardingStep,
    this.canFinalize = false,
    this.canConfigure = false,
    this.canApproveExpenses = false,
    this.businessType,
    this.vatReporting,
    this.memberCount,
    this.approvalPolicy = ApprovalPolicy.none,
    this.shaam,
    this.signingConfigured = false,
    this.signingUnlocked = false,
    this.uniformFormatReady = false,
    this.rules = const BusinessRules(),
    this.readGating = false,
    this.raw = const {},
  });

  factory Me.fromJson(Map<String, dynamic> json) {
    final onboarding = jMap(json['onboarding']);
    final signing = jMap(json['signing']);
    return Me(
      userId: json['userId'] as String,
      role: json['role'] as String,
      isOwner: json.containsKey('isOwner') ? jBool(json['isOwner']) : null,
      permissions: json['permissions'] is List
          ? jStrings(json['permissions'])
          : null,
      mfaEnrolled: jBool(json['mfaEnrolled']),
      onboardingCompleted: jBool(onboarding['completed']),
      onboardingStep: jIntOrNull(onboarding['step']),
      canFinalize: jBool(json['canFinalize']),
      canConfigure: jBool(json['canConfigure']),
      canApproveExpenses: jBool(json['canApproveExpenses']),
      businessType: jStr(json['businessType']),
      vatReporting: jStr(json['vatReporting']),
      memberCount: jIntOrNull(json['memberCount']),
      approvalPolicy: ApprovalPolicy.fromJson(jMap(json['approvalPolicy'])),
      shaam: json['shaam'] is Map<String, dynamic>
          ? ShaamState.fromJson(json['shaam'] as Map<String, dynamic>)
          : null,
      signingConfigured: jBool(signing['configured']),
      signingUnlocked: jBool(signing['unlocked']),
      uniformFormatReady: jBool(jMap(json['exports'])['uniformFormatReady']),
      rules: BusinessRules.fromJson(jMap(json['rules'])),
      readGating: jBool(jMap(json['enforcement'])['readGating']),
      raw: json,
    );
  }

  final String userId;

  /// OWNER | ADMIN | ACCOUNTANT | EMPLOYEE | READ_ONLY (| ACCOUNTANT_REP after BE-04).
  /// Read ONLY by lib/state/caps.dart.
  final String role;

  /// Null before BE-02 (caps.dart then falls back on the OWNER role).
  final bool? isOwner;

  /// Effective permissions (role ∪ grants). Null = server without BE-02.
  final List<String>? permissions;
  final bool mfaEnrolled;
  final bool onboardingCompleted;
  final int? onboardingStep;
  final bool canFinalize;
  final bool canConfigure;
  final bool canApproveExpenses;

  /// OSEK_PATUR | OSEK_MURSHE | COMPANY | PARTNERSHIP | NONPROFIT (null before BE-02 →
  /// take it from /business/profile).
  final String? businessType;

  /// MONTHLY | BIMONTHLY (null before BE-02).
  final String? vatReporting;
  final int? memberCount;
  final ApprovalPolicy approvalPolicy;
  final ShaamState? shaam;
  final bool signingConfigured;
  final bool signingUnlocked;
  final bool uniformFormatReady;
  final BusinessRules rules;

  /// True after BE-03 (server hides amounts from roles without money:read).
  final bool readGating;

  /// The JSON as received (cached by the session for offline starts).
  final Map<String, dynamic> raw;

  bool get hasEffectivePermissions => permissions != null;

  Map<String, dynamic> toJson() => raw;
}
