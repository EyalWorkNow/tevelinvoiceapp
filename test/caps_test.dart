import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/caps.dart';

import 'fakes/fake_api.dart';

Caps capsOf(
  Preset p, {
  Map<String, dynamic>? policy,
  bool be02 = true,
  bool readGating = false,
}) => Caps.fromMe(
  Me.fromJson(
    meJson(p, approvalPolicy: policy, be02: be02, readGating: readGating),
  ),
);

void main() {
  test('every preset is recognised from role + grants', () {
    for (final p in Preset.values) {
      expect(capsOf(p).preset, p, reason: '$p');
    }
  });

  test('§4.4 matrix: who sees what (P0, BE-02 permissions)', () {
    // cap → presets that have it
    final expected = <Cap, Set<Preset>>{
      Cap.docView: Preset.values.toSet(),
      Cap.docDraft: {
        Preset.owner,
        Preset.partner,
        Preset.employee,
        Preset.employeeIssuer,
        Preset.accountantFull,
      },
      Cap.docIssue: {
        Preset.owner,
        Preset.partner,
        Preset.employeeIssuer,
        Preset.accountantFull,
      },
      Cap.docSend: {
        Preset.owner,
        Preset.partner,
        Preset.employee,
        Preset.employeeIssuer,
        Preset.accountantFull,
      },
      Cap.docCancel: {Preset.owner, Preset.partner, Preset.accountantFull},
      Cap.approvalDecide: {Preset.owner, Preset.partner, Preset.accountantFull},
      Cap.paymentRecord: {
        Preset.owner,
        Preset.partner,
        Preset.employeeIssuer,
        Preset.accountantFull,
      },
      Cap.paymentRefund: {},
      Cap.moneyView: {
        Preset.owner,
        Preset.partner,
        Preset.accountantRep,
        Preset.accountantFull,
        Preset.viewer,
      },
      Cap.customerManage: {Preset.owner, Preset.partner, Preset.accountantFull},
      Cap.reportView: {
        Preset.owner,
        Preset.partner,
        Preset.accountantRep,
        Preset.accountantFull,
      },
      Cap.expenseCapture: {
        Preset.owner,
        Preset.partner,
        Preset.employee,
        Preset.employeeIssuer,
        Preset.accountantRep,
        Preset.accountantFull,
      },
      Cap.expenseApprove: {
        Preset.owner,
        Preset.partner,
        Preset.accountantRep,
        Preset.accountantFull,
      },
      Cap.teamManage: {Preset.owner, Preset.partner},
      Cap.settingsBusiness: {Preset.owner, Preset.partner},
      Cap.settingsDesign: {Preset.owner, Preset.partner},
      Cap.settingsNumbering: {},
      Cap.customerAccountKey: {},
      Cap.owner: {Preset.owner},
    };
    for (final e in expected.entries) {
      final actual = {
        for (final p in Preset.values)
          if (capsOf(p).can(e.key)) p,
      };
      expect(actual, e.value, reason: '${e.key}');
    }
  });

  test('tabs: ＋ and intent buttons; accountant presets get R as home', () {
    expect(capsOf(Preset.owner).showCreateTab, isTrue);
    expect(capsOf(Preset.accountantFull).showCreateTab, isTrue);
    expect(capsOf(Preset.accountantRep).showCreateTab, isFalse);
    expect(capsOf(Preset.viewer).showCreateTab, isFalse);
    expect(capsOf(Preset.accountantRep).homeIsReports, isTrue);
    expect(capsOf(Preset.accountantFull).homeIsReports, isTrue);
    expect(capsOf(Preset.accountantFull).showIntentButtons, isFalse);
    expect(capsOf(Preset.employee).showIntentButtons, isTrue);
    expect(capsOf(Preset.viewer).showIntentButtons, isFalse);
    expect(capsOf(Preset.owner).roleTag, isNull);
    expect(capsOf(Preset.employee).roleTag, Preset.employee);
  });

  test(
    '§4.8 approval: employee always submits; THRESHOLD is >= total incl. VAT (AT-43)',
    () {
      expect(capsOf(Preset.employee).approvalNeeded(BigInt.one), isTrue);
      expect(capsOf(Preset.viewer).approvalNeeded(BigInt.one), isFalse);
      final policy = {
        'mode': 'THRESHOLD',
        'thresholdMinor': '500000',
        'includesVat': true,
        'selfApprovalAllowed': false,
        'otherApproverExists': true,
      };
      final owner = capsOf(Preset.owner, policy: policy);
      expect(owner.approvalNeeded(BigInt.from(600000)), isTrue);
      expect(owner.approvalNeeded(BigInt.from(499999)), isFalse);
      expect(owner.approvalNeeded(BigInt.from(500000)), isTrue);
      // Sole approver (AT-43b): no other approver → issue directly.
      final solo = capsOf(
        Preset.owner,
        policy: {...policy, 'otherApproverExists': false},
      );
      expect(solo.approvalNeeded(BigInt.from(600000)), isFalse);
      // NONE.
      expect(
        capsOf(Preset.owner).approvalNeeded(BigInt.from(10000000)),
        isFalse,
      );
    },
  );

  test(
    'server without BE-02: role table only (fail-closed, grants unknown)',
    () {
      final issuer = capsOf(Preset.employeeIssuer, be02: false);
      expect(issuer.fromFallback, isTrue);
      expect(
        issuer.can(Cap.docIssue),
        isFalse,
      ); // the grant is invisible → hidden
      expect(issuer.can(Cap.paymentRecord), isFalse);
      expect(issuer.preset, Preset.employee);
      final rep = capsOf(Preset.accountantRep, be02: false);
      expect(rep.preset, Preset.viewer);
      expect(rep.can(Cap.expenseApprove), isFalse);
      final owner = capsOf(Preset.owner, be02: false);
      expect(owner.can(Cap.owner), isTrue);
      expect(owner.can(Cap.teamManage), isTrue);
    },
  );

  test('after BE-03 (readGating) read caps come from explicit permissions', () {
    final me = Me.fromJson({
      ...meJson(Preset.viewer, readGating: true),
      'permissions': ['document:read', 'money:read'],
    });
    final c = Caps.fromMe(me);
    expect(c.can(Cap.moneyView), isTrue);
    expect(c.can(Cap.reportView), isFalse);
    final emp = Caps.fromMe(
      Me.fromJson({
        ...meJson(Preset.employee, readGating: true),
        'permissions': ['document:read', 'document:draft:write'],
      }),
    );
    expect(emp.can(Cap.moneyView), isFalse);
    expect(emp.can(Cap.itemManage), isFalse);
    expect(Caps.none.can(Cap.docView), isFalse);
  });

  test('AT-48: no role comparison outside lib/state/caps.dart', () {
    final pattern = RegExp(
      r"role\s*(==|!=)|==\s*'(OWNER|ADMIN|ACCOUNTANT|ACCOUNTANT_REP|EMPLOYEE|READ_ONLY)'",
    );
    final offenders = <String>[];
    for (final f in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('state/caps.dart')) {
        continue;
      }
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
