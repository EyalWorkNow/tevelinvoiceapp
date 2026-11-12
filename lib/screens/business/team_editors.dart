// S13 instances for the team (§12): "הזמנה לצוות" and "חבר צוות". Owner: squad E.
// Only what the server enforces is offered: the presets + "מפיק בעצמו" (§12.4).

import 'package:flutter/material.dart';

import '../../ui/widgets/notch_notice.dart';
import '../../api/client.dart' show ApiException;
import '../../api/models/models.dart';
import '../../api/settings_api.dart' show isValidEmail;
import '../../api/team_api.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';
import '../../state/business_context.dart';
import 'sheets/s13_editor.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

List<EditorOption> _presetOptions({bool includeFull = false}) => [
  if (includeFull)
    const EditorOption(
      'accountantFull',
      PresetHe.accountantFull,
      hint: PresetHe.accountantFullHint,
    ),
  for (final p in invitablePresets)
    EditorOption(p.name, PresetHe.label(p), hint: PresetHe.hint(p)),
];

Preset _preset(Object? v) =>
    Preset.values.firstWhere((p) => p.name == v, orElse: () => Preset.employee);

EditorField _issuerField({bool initial = false}) => EditorField(
  key: 'issuer',
  label: TeamHe.issuer,
  kind: FieldKind.toggle,
  initial: initial,
  hint: TeamHe.issuerHint,
  visibleWhen: (v) => v['preset'] == Preset.employee.name,
);

/// J8 / J8b: "+ הזמן" or "הזמן רואה חשבון" → email (auto focus) → "שלח הזמנה".
Future<InviteResult?> showInviteEditor(
  BuildContext context, {
  Preset preset = Preset.employee,
}) async {
  InviteResult? result;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showEditorSheet(
    context,
    instance: 'invite',
    config: EditorConfig(
      title: preset == Preset.accountantRep
          ? TeamHe.inviteAccountant
          : TeamHe.inviteTitle,
      saveLabel: TeamHe.sendInvite,
      savedMessage: '',
      fields: [
        EditorField(
          key: 'email',
          label: TeamHe.email,
          kind: FieldKind.email,
          autofocus: true,
          required: true,
          validator: (v) =>
              isValidEmail((v as String?) ?? '') ? null : TeamHe.emailInvalid,
        ),
        EditorField(
          key: 'preset',
          label: '',
          kind: FieldKind.choice,
          initial: preset.name,
          options: _presetOptions(),
          collapsedAfter: 3,
          hint: TeamHe.more,
        ),
        _issuerField(),
      ],
      onSave: (v) async {
        result = await inviteMember(
          v.str('email'),
          _preset(v['preset']),
          issuer: v.flag('issuer'),
        );
      },
    ),
  );
  final r = result;
  if (!ok || r == null) return null;
  final url = r.shareUrl;
  messenger.showNotchNotice(
    SnackBar(
      content: const Text(TeamHe.invited),
      action: url == null
          ? null
          : SnackBarAction(
              label: TeamHe.sendWhatsAppShort,
              onPressed: () {
                final text = TeamHe.waText(businessContext.displayName, url);
                launchAllowed(
                  Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
                );
              },
            ),
    ),
    motion: NoticeMotion.sent,
  );
  return r;
}

/// S13 "חבר צוות": preset (+ "מפיק בעצמו" for an employee) → "שמור";
/// ⋯ "הסר מהעסק" (red dialog).
/// [canTransfer]: the caller is the owner and the server has BE-49.
EditorConfig memberEditor(
  BuildContext context,
  TeamMember m, {
  bool canTransfer = false,
}) {
  final current = m.preset;
  final full = current == Preset.accountantFull;
  return EditorConfig(
    title: m.name,
    subtitle: m.name == m.email ? TeamHe.memberTitle : m.email,
    fields: [
      if (m.custom)
        const EditorField(
          key: 'custom',
          label: TeamHe.customHint,
          kind: FieldKind.info,
        ),
      EditorField(
        key: 'preset',
        label: '',
        kind: FieldKind.choice,
        initial: current == Preset.employeeIssuer
            ? Preset.employee.name
            : current.name,
        options: _presetOptions(includeFull: full),
      ),
      _issuerField(initial: current == Preset.employeeIssuer),
    ],
    onSave: (v) async {
      final p = _preset(v['preset']);
      if (p == Preset.accountantFull)
        return; // existing tag kept as is (§19 q2)
      await saveMemberPreset(m, p, issuer: v.flag('issuer'));
    },
    more: [
      if (canTransfer)
        MoreMenuItem(
          label: TeamHe.transfer,
          icon: Iconsax.key,
          onSelected: () async {
            final nav = Navigator.of(context);
            if (await transferOwnershipFlow(context, m) && nav.mounted)
              nav.pop(true);
          },
        ),
      MoreMenuItem(
        label: TeamHe.remove,
        destructive: true,
        onSelected: () async {
          final nav = Navigator.of(context);
          if (!await confirmDanger(
            context,
            TeamHe.removeConfirm(m.name),
            TeamHe.removeBody,
            TeamHe.remove,
          )) {
            return;
          }
          try {
            await removeMember(m.userId);
            nav.pop(true);
          } on Object catch (e) {
            if (context.mounted) showErrorSnack(context, e);
          }
        },
      ),
    ],
  );
}

/// Red confirmation dialog (≤1 field = not a sheet, §1 F4).
Future<bool> confirmDanger(
  BuildContext context,
  String title,
  String body,
  String action,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(CommonHe.cancel),
        ),
        TextButton(
          key: const Key('confirm-danger'),
          style: TextButton.styleFrom(foregroundColor: context.palette.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// BE-49: confirm (red) → code e-mailed to the owner → one-field dialog →
/// transfer. The caller becomes שותף. Returns true when transferred.
Future<bool> transferOwnershipFlow(BuildContext context, TeamMember m) async {
  if (!await confirmDanger(
    context,
    TeamHe.transferConfirm(m.name),
    TeamHe.transferBody,
    TeamHe.transfer,
  )) {
    return false;
  }
  try {
    final sentTo = await requestOwnershipTransfer(m.userId);
    String? error;
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!context.mounted) return false;
      final code = await _askCode(context, sentTo, error);
      if (code == null) return false;
      try {
        await confirmOwnershipTransfer(m.userId, code);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showNotchNotice(
            SnackBar(content: Text(TeamHe.transferred(m.name))),
          );
        }
        return true;
      } on ApiException catch (e) {
        if (e.code != 'OWNERSHIP_CODE_INVALID') rethrow;
        error = TeamHe.transferCodeWrong;
      }
    }
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
  return false;
}

Future<String?> _askCode(BuildContext context, String? sentTo, String? error) =>
    showDialog<String>(
      context: context,
      builder: (_) => _CodeDialog(sentTo: sentTo, error: error),
    );

/// One-field dialog (not a sheet, §1 F4). Owns its controller so it outlives
/// the closing animation.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({this.sentTo, this.error});

  final String? sentTo;
  final String? error;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text(TeamHe.transferCodeTitle),
    content: TextField(
      key: const Key('transfer-code'),
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: InputDecoration(
        helperText: widget.sentTo == null
            ? null
            : AuthHe.mfaSentTo(widget.sentTo!),
        errorText: widget.error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text(CommonHe.cancel),
      ),
      TextButton(
        key: const Key('transfer-confirm'),
        style: TextButton.styleFrom(foregroundColor: context.palette.danger),
        onPressed: () => Navigator.pop(context, _code.text),
        child: const Text(TeamHe.transfer),
      ),
    ],
  );
}
