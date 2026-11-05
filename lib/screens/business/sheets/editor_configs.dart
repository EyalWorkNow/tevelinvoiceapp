// S13 settings instances (SPEC-v2 §13): 13.1 פרטי העסק · 13.2 מיתוג ·
// 13.3 מספור · 13.6 אישורים · 13.9 המשך במחשב. Owner: squad E.
// Each loader reads the current values, then returns the form.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../../../api/auth_api.dart' show isValidIsraeliId;
import '../../../api/branding_api.dart';
import '../../../api/client.dart' show ApiException;
import '../../../api/reports_api.dart' show reportsAvailable;
import '../../../api/models/models.dart';
import '../../../api/settings_api.dart';
import '../../../api/team_api.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../state/session.dart';
import '../../../router.dart' show navigatorKey;
import '../../../ui/ds.dart' show MoreMenuItem;
import '../../../util/labels/labels.dart';
import '../../reports/reports_screen.dart' show periodFor;
import 's13_editor.dart';

typedef EditorLoaderFn = Future<EditorConfig> Function();

/// Loader for a settings instance id; null when unknown.
EditorLoaderFn? editorLoaderFor(String instance) => switch (instance) {
  '13.1' => profileEditor,
  '13.2' => brandingEditor,
  '13.3' => () async => numberingEditor(),
  '13.6' => approvalsEditor,
  '13.9' => () async => desktopEditor(),
  _ => null,
};

/// Gallery picker (tests replace it).
Future<Uint8List?> Function() logoPicker = () async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
  );
  return file?.readAsBytes();
};

String? _emailError(Object? v) {
  final s = (v as String?)?.trim() ?? '';
  return s.isEmpty || isValidEmail(s) ? null : TeamHe.emailInvalid;
}

String? _phoneError(Object? v) {
  final s = (v as String?)?.trim() ?? '';
  return s.isEmpty || isValidIsraeliPhone(s) ? null : 'מספר טלפון לא תקין';
}

// ---- 13.1 פרטי העסק -----------------------------------------------------------

/// "% מקדמות" in basis points ("2.5" → 250); null when not a percentage.
int? advanceBasisPoints(String raw) {
  final v = double.tryParse(raw.trim().replaceAll('%', ''));
  if (v == null || v < 0 || v > 100) return null;
  return (v * 100).round();
}

String _percent(Object? bp) {
  final n = int.tryParse('$bp');
  if (n == null) return '';
  final whole = n ~/ 100;
  final frac = n % 100;
  return frac == 0
      ? '$whole'
      : '$whole.${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
}

/// §13.1. P1/P2 extras appear only when the server has them: BE-13 copy to
/// me, BE-22 accountant automation, BE-18 advances %, BE-43 type change (⋯).
Future<EditorConfig> profileEditor() async {
  final profile = session.profile;
  final locked0 = profile?.identityLocked ?? true;
  final exempt0 = profile?.businessType == 'OSEK_PATUR';
  Future<T?> optional<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } on Object {
      return null; // an optional extra never blocks the form
    }
  }

  final extras = await Future.wait<Object?>([
    optional(fetchCcOwnerEmail),
    optional(fetchAccountantAutomation),
    optional(() => reportsAvailable(periodFor(PeriodKey.current))),
    if (locked0 && exempt0)
      optional(() => serverHasPost('/business/type-change')),
  ]);
  final cc = extras[0] as bool?;
  final automation = extras[1] as AccountantAutomation?;
  final advances = extras[2] == true;
  final typeChange = extras.length > 3 && extras[3] == true;
  return _profileConfig(
    cc: cc,
    automation: automation,
    advances: advances,
    typeChange: typeChange,
  );
}

EditorConfig _profileConfig({
  bool? cc,
  AccountantAutomation? automation,
  bool advances = false,
  bool typeChange = false,
}) {
  final profile = session.profile;
  final raw = profile?.raw ?? const <String, dynamic>{};
  final locked = profile?.identityLocked ?? true;
  final type = profile?.businessType ?? 'OSEK_MURSHE';
  final exempt = profile?.isVatExempt ?? false;
  final address = raw['address'] is Map ? raw['address'] as Map : const {};
  final bank = raw['bank'] is Map ? raw['bank'] as Map : const {};
  final accountant = raw['accountant'] is Map
      ? raw['accountant'] as Map
      : const {};
  String? s(Object? v) => v?.toString();
  return EditorConfig(
    title: BusinessHe.profile,
    fields: [
      EditorField(
        key: 'legalName',
        label: 'שם משפטי',
        section: 'זהות העסק',
        initial: profile?.legalName,
        required: true,
      ),
      EditorField(
        key: 'tradingName',
        label: 'שם מסחרי (לא חובה)',
        initial: profile?.tradingName,
      ),
      EditorField(
        key: 'businessType',
        label: 'סוג העסק',
        kind: FieldKind.choice,
        initial: type,
        readOnly: locked,
        options: [
          for (final e in businessTypeLabels.entries)
            if (!locked || e.key == type) EditorOption(e.key, e.value),
        ],
      ),
      EditorField(
        key: 'taxId',
        label: type == 'COMPANY' || type == 'NONPROFIT'
            ? 'ח.פ.'
            : 'ע.מ. / ת.ז.',
        kind: FieldKind.number,
        initial: profile?.taxId,
        readOnly: locked,
        validator: (v) => locked || isValidIsraeliId((v as String?) ?? '')
            ? null
            : AuthHe.idInvalid,
      ),
      if (locked)
        const EditorField(
          key: 'locked',
          label: BusinessHe.identityLocked,
          kind: FieldKind.info,
        ),
      EditorField(
        key: 'street',
        label: 'רחוב ומספר',
        section: 'פרטי קשר',
        initial: s(address['street']),
      ),
      EditorField(key: 'city', label: 'עיר', initial: s(address['city'])),
      EditorField(
        key: 'phone',
        label: 'טלפון',
        kind: FieldKind.phone,
        initial: profile?.phone,
        validator: _phoneError,
      ),
      EditorField(
        key: 'email',
        label: 'אימייל',
        kind: FieldKind.email,
        initial: profile?.email,
        validator: _emailError,
      ),
      if (!exempt)
        EditorField(
          key: 'vatReporting',
          label: 'דיווח מע״מ',
          section: 'חשבוניות ומיסוי',
          kind: FieldKind.choice,
          initial: s(raw['vatReporting']) ?? 'BIMONTHLY',
          options: const [
            EditorOption('MONTHLY', 'חודשי'),
            EditorOption('BIMONTHLY', 'דו-חודשי'),
          ],
        ),
      EditorField(
        key: 'withholdingFileNumber',
        label: 'תיק ניכויים',
        section: 'חשבוניות ומיסוי',
        kind: FieldKind.number,
        initial: s(raw['withholdingFileNumber']),
      ),
      if (type == 'NONPROFIT')
        EditorField(
          key: 'section46ApprovalNumber',
          label: 'מספר אישור סעיף 46',
          initial: profile?.section46ApprovalNumber,
        ),
      if (advances)
        EditorField(
          key: 'advanceRate',
          label: BusinessHe.advanceRate,
          section: 'חשבוניות ומיסוי',
          initial: _percent(raw['advanceRateBasisPoints']),
          validator: (x) {
            final t = '${x ?? ''}'.trim();
            return t.isEmpty || advanceBasisPoints(t) != null
                ? null
                : BusinessHe.advanceRateInvalid;
          },
        ),
      EditorField(
        key: 'paymentTerms',
        label: 'תנאי תשלום (למשל שוטף+30)',
        initial: s(raw['paymentTerms']),
      ),
      EditorField(
        key: 'defaultLineDescription',
        label: 'תיאור ברירת מחדל לשורה',
        initial: profile?.defaultLineDescription,
      ),
      EditorField(
        key: 'bankName',
        label: 'בנק',
        section: 'פרטי תשלום',
        initial: s(bank['name']),
      ),
      EditorField(
        key: 'bankBranch',
        label: 'סניף',
        kind: FieldKind.number,
        initial: s(bank['branch']),
      ),
      EditorField(
        key: 'bankAccount',
        label: 'חשבון',
        kind: FieldKind.number,
        initial: s(bank['account']),
      ),
      EditorField(
        key: 'paymentLinkUrl',
        label: 'קישור תשלום',
        section: 'פרטי תשלום',
        kind: FieldKind.url,
        initial: profile?.paymentLinkUrl,
        hint: 'הקישור שיופיע ב-QR ובהודעה ללקוח',
        validator: (v) => paymentLinkError((v as String?) ?? ''),
      ),
      EditorField(
        key: 'accountantName',
        label: 'רואה החשבון – שם',
        section: 'רואה החשבון',
        initial: s(accountant['name']),
      ),
      EditorField(
        key: 'accountantEmail',
        label: 'רואה החשבון – מייל',
        kind: FieldKind.email,
        initial: s(accountant['email']),
        validator: _emailError,
      ),
      if (automation != null) ...[
        EditorField(
          key: 'autoEvery',
          label: BusinessHe.accountantAuto,
          kind: FieldKind.choice,
          initial: automation.every ?? 'OFF',
          options: const [
            EditorOption('OFF', BusinessHe.accountantAutoOff),
            EditorOption('MONTH', BusinessHe.accountantAutoMonth),
            EditorOption('BIMONTH', BusinessHe.accountantAutoBimonth),
          ],
          validator: (_) => null,
        ),
        EditorField(
          key: 'autoDay',
          label: BusinessHe.accountantAutoDay,
          kind: FieldKind.number,
          initial: '${automation.dayOfMonth}',
          visibleWhen: (v) => v['autoEvery'] != 'OFF',
          validator: (x) {
            final n = int.tryParse('$x');
            return n == null || n < 1 || n > 28 ? 'יום בין 1 ל-28' : null;
          },
        ),
        EditorField(
          key: 'autoForward',
          label: BusinessHe.accountantForward,
          kind: FieldKind.toggle,
          initial: automation.forwardEveryDocument,
        ),
      ],
      if (cc != null)
        EditorField(
          key: 'ccOwner',
          label: BusinessHe.ccOwner,
          kind: FieldKind.toggle,
          initial: cc,
          hint: BusinessHe.ccOwnerHint,
        ),
    ],
    more: [
      if (typeChange)
        MoreMenuItem(
          label: BusinessHe.typeChange,
          onSelected: () {
            final context = navigatorKey.currentContext;
            if (context != null) {
              showEditorSheet(
                context,
                instance: 'typeChange',
                config: typeChangeEditor(),
              );
            }
          },
        ),
    ],
    onSave: (v) async {
      final autoOn = automation != null && v['autoEvery'] != 'OFF';
      if ((autoOn || v.flag('autoForward')) &&
          v.orNull('accountantEmail') == null) {
        throw ApiException(422, 'VALIDATION', BusinessHe.accountantEmailNeeded);
      }
      final street = v.str('street');
      final city = v.str('city');
      final bankFull =
          v.str('bankName').isNotEmpty &&
          v.str('bankBranch').isNotEmpty &&
          v.str('bankAccount').isNotEmpty;
      final changes = <String, dynamic>{
        'legalName': v.str('legalName'),
        'tradingName': v.orNull('tradingName'),
        if (!locked) 'businessType': v['businessType'],
        if (!locked) 'taxId': v.str('taxId'),
        'address': street.isEmpty && city.isEmpty
            ? null
            : {'street': street, 'number': '', 'city': city},
        'phone': v.orNull('phone'),
        'email': v.orNull('email'),
        if (!exempt) 'vatReporting': v['vatReporting'],
        'withholdingFileNumber': v.orNull('withholdingFileNumber'),
        if (type == 'NONPROFIT')
          'section46ApprovalNumber': v.orNull('section46ApprovalNumber'),
        'paymentTerms': v.orNull('paymentTerms'),
        'defaultLineDescription': v.orNull('defaultLineDescription'),
        'bank': bankFull
            ? {
                'name': v.str('bankName'),
                'branch': v.str('bankBranch'),
                'account': v.str('bankAccount'),
              }
            : null,
        'paymentLinkUrl': v.orNull('paymentLinkUrl'),
        'accountant': v.str('accountantName').isEmpty
            ? null
            : {
                'name': v.str('accountantName'),
                'email': v.orNull('accountantEmail'),
              },
      };
      if (advances) {
        final t = v.str('advanceRate');
        changes['advanceRateBasisPoints'] = t.isEmpty
            ? null
            : advanceBasisPoints(t);
      }
      await saveBusinessProfile(changes);
      if (cc != null && v.flag('ccOwner') != cc) {
        await saveCcOwnerEmail(v.flag('ccOwner'));
      }
      if (automation != null) {
        final next = AccountantAutomation(
          every: v['autoEvery'] == 'OFF' ? null : v['autoEvery'] as String?,
          dayOfMonth: int.tryParse(v.str('autoDay')) ?? automation.dayOfMonth,
          forwardEveryDocument: v.flag('autoForward'),
        );
        if (next.toJson().toString() != automation.toJson().toString()) {
          await saveAccountantAutomation(next);
        }
      }
    },
  );
}

// ---- BE-43 מעבר מפטור למורשה (⋯ in 13.1) ---------------------------------------

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Effective date: today, the 1st of next month, or the 1st of next year.
EditorConfig typeChangeEditor({DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final nextMonth = DateTime(n.year, n.month + 1);
  final nextYear = DateTime(n.year + 1);
  return EditorConfig(
    title: BusinessHe.typeChangeTitle,
    subtitle: BusinessHe.typeChangeBody,
    saveLabel: BusinessHe.typeChangeSave,
    savedMessage: BusinessHe.typeChangeSaved,
    fields: [
      EditorField(
        key: 'from',
        label: BusinessHe.typeChangeFrom,
        kind: FieldKind.choice,
        initial: _iso(nextMonth),
        options: [
          EditorOption(_iso(today), BusinessHe.typeChangeToday),
          EditorOption(_iso(nextMonth), BusinessHe.typeChangeNextMonth),
          EditorOption(_iso(nextYear), BusinessHe.typeChangeNextYear),
        ],
      ),
    ],
    onSave: (v) =>
        requestBusinessTypeChange('OSEK_MURSHE', v['from'] as String),
  );
}

// ---- 13.2 מיתוג ---------------------------------------------------------------

Future<EditorConfig> brandingEditor() async {
  final current = await fetchBranding();
  final initialLogo = current.logoBytes;
  return EditorConfig(
    title: BusinessHe.branding,
    fields: [
      EditorField(
        key: 'logo',
        label: BusinessHe.brandingPickLogo,
        kind: FieldKind.logo,
        initial: initialLogo,
        hint: BusinessHe.brandingRemoveLogo,
        pickLogo: logoPicker,
      ),
      EditorField(
        key: 'color',
        label: BusinessHe.brandingColor,
        kind: FieldKind.colors,
        initial: current.accentColor,
        options: [for (final c in brandColors) EditorOption(c, c)],
      ),
    ],
    onSave: (v) async {
      final logo = v['logo'];
      String? logoUri;
      if (!identical(logo, initialLogo) && logo is Uint8List) {
        logoUri = logo.isEmpty ? '' : logoDataUriFrom(logo);
        if (logoUri == null) throw StateError('not an image');
      }
      await saveBranding(
        current,
        logoDataUri: logoUri,
        accentColor: v['color'] as String?,
      );
    },
  );
}

// ---- 13.3 מספור (accountant rep after BE-04) ----------------------------------

EditorConfig numberingEditor() => EditorConfig(
  title: BusinessHe.numbering,
  fields: [
    EditorField(
      key: 'next',
      label: AuthHe.numberingFrom,
      kind: FieldKind.number,
      autofocus: true,
      required: true,
      hint: AuthHe.numberingHint,
      validator: (v) {
        final n = int.tryParse((v as String?) ?? '');
        return n == null || n < 1 || n > 999999999
            ? AuthHe.numberInvalid
            : null;
      },
    ),
  ],
  onSave: (v) async => setStartingNumber(int.parse(v.str('next'))),
);

// ---- 13.6 אישורים -------------------------------------------------------------

Future<EditorConfig> approvalsEditor() async {
  final policy = businessContext.me?.approvalPolicy ?? ApprovalPolicy.none;
  var otherExists = policy.otherApproverExists;
  var name = BusinessHe.approvalsOtherMember;
  if (businessContext.can(Cap.teamManage)) {
    final approvers = (await fetchTeam()).otherApprovers;
    otherExists = approvers.isNotEmpty;
    if (approvers.length == 1) name = approvers.first.name;
  }
  return EditorConfig(
    title: BusinessHe.approvals,
    fields: [
      EditorField(
        key: 'enabled',
        label: BusinessHe.approvalsSwitch,
        kind: FieldKind.toggle,
        initial: policy.isThreshold,
      ),
      EditorField(
        key: 'threshold',
        label: BusinessHe.approvalsThreshold,
        kind: FieldKind.money,
        initial: policy.thresholdMinor,
        visibleWhen: (v) => v.flag('enabled'),
        validator: (x) =>
            x is BigInt && x > BigInt.zero ? null : 'נא להזין סכום',
      ),
      // Shown only when another approver exists (§13.6 validation, BE-37).
      if (otherExists)
        EditorField(
          key: 'notSelf',
          label: BusinessHe.approvalsSelf(name),
          kind: FieldKind.toggle,
          initial: !policy.selfApprovalAllowed,
          visibleWhen: (v) => v.flag('enabled'),
        ),
    ],
    onSave: (v) => saveApprovalPolicy(
      enabled: v.flag('enabled'),
      thresholdMinor: v.money('threshold'),
      selfApprovalAllowed: !(otherExists && v.flag('notSelf')),
    ),
  );
}

// ---- 13.9 המשך במחשב ----------------------------------------------------------

/// Topics this member may open (same gates as the server's BE-35 list).
List<String> desktopTopicsFor(Caps caps) => [
  if (caps.can(Cap.docDraft)) 'MORE_DOCUMENT_TYPES',
  if (caps.can(Cap.settingsBusiness)) ...[
    'INVENTORY',
    'ADVANCED_BRANDING',
    'MESSAGE_TEMPLATES',
    'TAX_AUTHORITY',
    'BUSINESS_TYPE_CHANGE',
    'CSV_IMPORT',
    'CUSTOMER_MERGE',
    'SIGNING_CERTIFICATE',
  ],
  if (caps.can(Cap.teamManage)) 'CUSTOM_PERMISSIONS',
  if (caps.can(Cap.docCancel)) 'RECEIPT_CANCEL',
  if (caps.can(Cap.settingsBusiness) || caps.can(Cap.expenseApprove)) ...[
    'UNIFORM_FORMAT',
    'BOOKKEEPING_CERTIFICATES',
  ],
  'LOGIN_EMAIL_CHANGE',
  if (caps.can(Cap.settingsBusiness)) 'API_INTEGRATIONS',
];

/// [topic] preselects one (e.g. TAX_AUTHORITY from the רשות המסים page).
EditorConfig desktopEditor({String? topic}) {
  final topics = desktopTopicsFor(businessContext.caps);
  return EditorConfig(
    title: BusinessHe.desktop,
    subtitle: BusinessHe.desktopIntro,
    saveLabel: BusinessHe.desktopSend,
    savedMessage: BusinessHe.desktopSent,
    fields: [
      EditorField(
        key: 'topic',
        label: '',
        kind: FieldKind.choice,
        initial: topic ?? topics.first,
        options: [
          for (final t in topics)
            EditorOption(
              t,
              desktopTopics[t] ?? t,
              icon: switch (t) {
                'MORE_DOCUMENT_TYPES' => Icons.description_outlined,
                'INVENTORY' => Icons.inventory_2_outlined,
                'ADVANCED_BRANDING' => Icons.palette_outlined,
                'MESSAGE_TEMPLATES' => Icons.chat_bubble_outline_rounded,
                'TAX_AUTHORITY' => Icons.account_balance_outlined,
                'BUSINESS_TYPE_CHANGE' => Icons.storefront_outlined,
                'CSV_IMPORT' => Icons.upload_file_outlined,
                'CUSTOMER_MERGE' => Icons.people_outline_rounded,
                'SIGNING_CERTIFICATE' => Icons.draw_outlined,
                'CUSTOM_PERMISSIONS' => Icons.admin_panel_settings_outlined,
                'RECEIPT_CANCEL' => Icons.cancel_outlined,
                'UNIFORM_FORMAT' => Icons.cloud_upload_outlined,
                'BOOKKEEPING_CERTIFICATES' => Icons.verified_outlined,
                'LOGIN_EMAIL_CHANGE' => Icons.mail_outline_rounded,
                _ => Icons.extension_outlined,
              },
            ),
        ],
      ),
    ],
    onSave: (v) {
      final t = v['topic'] as String;
      return sendWebHandoff(t, desktopTopics[t] ?? t);
    },
  );
}
