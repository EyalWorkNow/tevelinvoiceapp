// Client capabilities (SPEC-v2 §4.2). Owner: INT.
//
// Every button / tile / chip / card / row / "⋯" item asks `can(Cap.x)`.
// This is the ONLY file allowed to compare roles (AT-48, test/caps_test.dart
// greps lib/ for it). The server is the gate; hiding here is UI convenience.

import '../api/models/me.dart';

enum Cap {
  /// View + share a local PDF. `document:read`.
  docView,

  /// Drafts, quotes, new customer. `document:draft:write`.
  docDraft,

  /// Final issue. `document:finalize`.
  docIssue,

  /// "שלח לאישור" is possible (docDraft); whether a given total needs it:
  /// [Caps.approvalNeeded].
  docSubmit,

  /// Send to the customer (mail / link / WhatsApp via link). `document:send`.
  docSend,

  /// Credit / void. `document:cancel` (BE-03a; NOT canFinalize).
  docCancel,

  /// Record a payment + receipt. `payment:record && document:finalize`.
  paymentRecord,

  /// Refund. `payment:refund` (BE-03; false before).
  paymentRefund,

  /// Approve / reject others' documents. `approval:decide` (BE-03a).
  approvalDecide,

  /// Retry / manual allocation number. P0: `document:finalize`; BE-03: `allocation:request`.
  allocationRequest,

  /// Money card, balances. P0: role ≠ EMPLOYEE (UI only, §12.5); BE-03: `money:read`.
  moneyView,

  /// Edit / archive customers, statement. P0: OWNER/ADMIN/ACCOUNTANT; BE-03: `customer:manage`.
  customerManage,

  /// Customer account key. `customer:accountKey` (BE-04).
  customerAccountKey,

  /// Suppliers. P0: `expense:record`; BE-03: `supplier:manage`.
  supplierManage,

  /// Item edit. P0: docDraft; BE-03: `item:manage`.
  itemManage,

  /// Photograph an expense. `expense:record`.
  expenseCapture,

  /// Approve an expense. `expense:approve`.
  expenseApprove,

  /// Reports. P0: OWNER/ADMIN/ACCOUNTANT or the accountant preset; BE-03: `report:read`.
  reportView,

  /// Export. P0: like reportView; BE-03: `export:run`.
  reportExport,

  /// Business details, approvals, tax authority. `business:configure`.
  settingsBusiness,

  /// Numbering (after the first document). `settings:numbering` (BE-04).
  settingsNumbering,

  /// Branding. `business:configure`.
  settingsDesign,

  /// Team. `membership:manage`.
  teamManage,

  /// Delete business, sole-owner warning. `/me.isOwner`.
  owner,
}

/// What the owner picks in an invitation (§4.3), derived from role + grants.
enum Preset {
  owner,
  partner,
  employee,
  employeeIssuer,
  accountantRep,
  accountantFull,
  viewer,
}

/// Server role table (packages/security/src/rbac.ts ROLE_PERMISSIONS + BE-03a).
/// Used ONLY when /me has no `permissions` (server without BE-02): grants are
/// then unknown, so this is fail-closed (role permissions only).
const Map<String, List<String>> rolePermissionsFallback = {
  'OWNER': _all,
  'ADMIN': _all,
  'ACCOUNTANT': [
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
  'EMPLOYEE': [
    'document:read',
    'document:draft:write',
    'document:send',
    'expense:record',
  ],
  'READ_ONLY': ['document:read'],
  'ACCOUNTANT_REP': [
    'document:read',
    'expense:record',
    'expense:approve',
    'money:read',
    'report:read',
    'export:run',
    'allocation:request',
    'settings:numbering',
    'customer:accountKey',
  ],
};

const List<String> _all = [
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

/// Immutable capability set for one user in one business.
class Caps {
  Caps._(this._caps, this.preset, this.approvalPolicy, this.fromFallback);

  /// No business / signed out / /me older than 24h: nothing is shown.
  static final Caps none = Caps._(
    const {},
    Preset.viewer,
    ApprovalPolicy.none,
    true,
  );

  factory Caps.fromMe(Me me) {
    final role = me.role;
    final perms =
        (me.permissions ?? rolePermissionsFallback[role] ?? const <String>[])
            .toSet();
    bool has(String p) => perms.contains(p);
    final gated =
        me.readGating; // BE-03 is live: read permissions are explicit.

    final Preset preset;
    if (role == 'OWNER') {
      preset = Preset.owner;
    } else if (role == 'ADMIN') {
      preset = Preset.partner;
    } else if (role == 'ACCOUNTANT') {
      preset = Preset.accountantFull;
    } else if (role == 'ACCOUNTANT_REP' ||
        (role == 'READ_ONLY' && has('expense:approve'))) {
      preset = Preset.accountantRep;
    } else if (role == 'EMPLOYEE') {
      preset = has('document:finalize') && has('payment:record')
          ? Preset.employeeIssuer
          : Preset.employee;
    } else {
      preset = Preset.viewer;
    }
    final managerRole =
        role == 'OWNER' || role == 'ADMIN' || role == 'ACCOUNTANT';
    final docDraft = has('document:draft:write');
    final reportView = gated
        ? has('report:read')
        : managerRole || preset == Preset.accountantRep;

    final caps = <Cap>{
      if (has('document:read')) Cap.docView,
      if (docDraft) Cap.docDraft,
      if (has('document:finalize')) Cap.docIssue,
      if (docDraft) Cap.docSubmit,
      if (has('document:send')) Cap.docSend,
      if (has('document:cancel')) Cap.docCancel,
      if (has('payment:record') && has('document:finalize')) Cap.paymentRecord,
      if (has('payment:refund')) Cap.paymentRefund,
      if (has('approval:decide')) Cap.approvalDecide,
      if (gated ? has('allocation:request') : has('document:finalize'))
        Cap.allocationRequest,
      if (gated ? has('money:read') : role != 'EMPLOYEE') Cap.moneyView,
      if (gated ? has('customer:manage') : managerRole) Cap.customerManage,
      if (has('customer:accountKey')) Cap.customerAccountKey,
      if (gated ? has('supplier:manage') : has('expense:record'))
        Cap.supplierManage,
      if (gated ? has('item:manage') : docDraft) Cap.itemManage,
      if (has('expense:record')) Cap.expenseCapture,
      if (has('expense:approve')) Cap.expenseApprove,
      if (reportView) Cap.reportView,
      if (gated ? has('export:run') : reportView) Cap.reportExport,
      if (has('business:configure')) Cap.settingsBusiness,
      if (has('settings:numbering')) Cap.settingsNumbering,
      if (has('business:configure')) Cap.settingsDesign,
      if (has('membership:manage')) Cap.teamManage,
      if (me.isOwner ?? role == 'OWNER') Cap.owner,
    };
    return Caps._(caps, preset, me.approvalPolicy, !me.hasEffectivePermissions);
  }

  final Set<Cap> _caps;
  final Preset preset;
  final ApprovalPolicy approvalPolicy;

  /// True when computed from the role table (no BE-02 permissions).
  final bool fromFallback;

  bool can(Cap cap) => _caps.contains(cap);

  /// All granted caps (tests, debugging).
  Set<Cap> get all => Set.unmodifiable(_caps);

  /// §4.8: a document of [totalMinor] (INCLUDING VAT) goes to "שלח לאישור"
  /// instead of "הפק". Same comparison as the server: `>=`.
  bool approvalNeeded(BigInt totalMinor) {
    if (!can(Cap.docDraft)) return false;
    if (!can(Cap.docIssue)) return true;
    final p = approvalPolicy;
    return p.isThreshold &&
        totalMinor >= p.thresholdMinor &&
        !p.selfApprovalAllowed &&
        p.otherApproverExists;
  }

  /// Accountant presets see Reports (R) as their home tab (§4.4).
  bool get homeIsReports =>
      preset == Preset.accountantRep || preset == Preset.accountantFull;

  /// The ＋ tab exists only when S1 has a tile (§4.5): every tile needs docDraft.
  bool get showCreateTab => can(Cap.docDraft);

  /// "קיבלתי תשלום" / "בקש תשלום" on H.
  bool get showIntentButtons => can(Cap.docDraft) && !homeIsReports;

  /// Role tag on H for non-owners ("עובד"); null for the owner.
  Preset? get roleTag => preset == Preset.owner ? null : preset;
}
