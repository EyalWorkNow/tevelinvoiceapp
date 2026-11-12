// Sign-in account, business memberships and the business profile (INT).
// Sources: /auth/login, /auth/my-businesses, /mobile/session, /business/profile.

import 'json.dart';

/// A business the user belongs to: {businessId, legalName, role}.
class Business {
  const Business({
    required this.businessId,
    required this.legalName,
    required this.role,
  });

  factory Business.fromJson(Map<String, dynamic> json) => Business(
    businessId: json['businessId'] as String,
    legalName: json['legalName'] as String,
    role: json['role'] as String,
  );

  final String businessId;
  final String legalName;

  /// OWNER | ADMIN | ACCOUNTANT | EMPLOYEE | READ_ONLY — display only (role tag
  /// in S14); capabilities come from /me via caps.dart.
  final String role;

  Map<String, dynamic> toJson() => {
    'businessId': businessId,
    'legalName': legalName,
    'role': role,
  };
}

/// GET /mobile/session (CONTRACT C).
class MobileAccount {
  const MobileAccount({
    required this.userId,
    required this.email,
    this.displayName,
    required this.businesses,
  });

  factory MobileAccount.fromJson(Map<String, dynamic> json) => MobileAccount(
    userId: json['userId'] as String,
    email: json['email'] as String,
    displayName: jStr(json['displayName']),
    businesses: [
      for (final b in (json['businesses'] as List? ?? const []))
        Business.fromJson(b as Map<String, dynamic>),
    ],
  );

  final String userId;
  final String email;
  final String? displayName;
  final List<Business> businesses;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'email': email,
    'displayName': displayName,
    'businesses': [for (final b in businesses) b.toJson()],
  };
}

/// GET /business/profile → {profile, canConfigure} (camelCase). Readable by
/// every signed-in member (§4.2).
class BusinessProfile {
  const BusinessProfile({
    required this.legalName,
    this.tradingName,
    required this.businessType,
    this.taxId,
    this.phone,
    this.email,
    this.paymentLinkUrl,
    required this.identityLocked,
    required this.onboardingCompleted,
    required this.raw,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> profile) =>
      BusinessProfile(
        legalName: jStr(profile['legalName']) ?? '',
        tradingName: jStr(profile['tradingName']),
        businessType: jStr(profile['businessType']) ?? 'OSEK_MURSHE',
        taxId: jStr(profile['taxId']),
        phone: jStr(profile['phone']),
        email: jStr(profile['email']),
        paymentLinkUrl: jStr(profile['paymentLinkUrl']),
        identityLocked: profile['identityLocked'] == true,
        onboardingCompleted: jMap(profile['onboarding'])['completed'] == true,
        raw: profile,
      );

  final String legalName;
  final String? tradingName;

  /// OSEK_PATUR | OSEK_MURSHE | COMPANY | PARTNERSHIP | NONPROFIT
  final String businessType;
  final String? taxId;
  final String? phone;
  final String? email;

  /// CONTRACT G: static payment link (https) used for the QR / WhatsApp.
  final String? paymentLinkUrl;

  /// Tax id + type are frozen after the first finalized document.
  final bool identityLocked;
  final bool onboardingCompleted;

  /// Every other profile field (address, bank, accountant…) as returned.
  final Map<String, dynamic> raw;

  /// Section 46 approval number (NONPROFIT; 405 donation receipts need it).
  String? get section46ApprovalNumber => jStr(raw['section46ApprovalNumber']);

  /// BE-25 default line description (null → "שירותים").
  String? get defaultLineDescription => jStr(raw['defaultLineDescription']);

  /// Accountant e-mail for "שלח לרו״ח" (§11).
  String? get accountantEmail => jStr(jMap(raw['accountant'])['email']);

  /// No VAT on documents (עוסק פטור / עמותה).
  bool get isVatExempt =>
      businessType == 'OSEK_PATUR' || businessType == 'NONPROFIT';

  String get displayName => tradingName ?? legalName;

  Map<String, dynamic> toJson() => raw;
}
