// Accountant sheets (spec features 2, 5, 8):
//   "＋ הוספת לקוח" → contact + role → POST access-requests → share (WhatsApp /
//   "נשלח מייל" / copy link); pending request actions; the office-name sheet
//   ("אני רו״ח ומלווה עסקים", profile settings); "תזכורת לבעלים" (wa.me).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../api/accountant_api.dart';
import '../../../api/client.dart';
import '../../../state/accountant_store.dart';
import '../../../state/caps.dart' show isFullAccountantRole;
import '../../../state/session.dart';
import '../../../ui/ds.dart';
import '../../../ui/widgets/notch_notice.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/labels/labels.dart';
import '../../../util/phone.dart';

/// "＋ הוספת לקוח". Reloads [accountantStore] after a request was sent.
Future<void> showAddClientSheet(BuildContext context) async {
  await showAppSheet<void>(context, builder: (_) => const AddClientSheet());
  unawaited(accountantStore.load());
}

class AddClientSheet extends StatefulWidget {
  const AddClientSheet({super.key, this.sent, this.contact});

  /// Opens straight on the share step (a resend).
  final AccessRequestSent? sent;
  final String? contact;

  @override
  State<AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<AddClientSheet> {
  final _contact = TextEditingController();
  String _role = 'ACCOUNTANT_REP';
  String? _fieldError;
  bool _busy = false;
  late AccessRequestSent? _sent = widget.sent;

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  String get _sentContact => widget.contact ?? _contact.text.trim();

  Future<void> _send() async {
    if (_busy) return;
    final contact = _contact.text.trim();
    if (!isValidAccessContact(contact)) {
      setState(() => _fieldError = AccountantHe.contactInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _fieldError = null;
    });
    try {
      final sent = await createAccessRequest(contact: contact, role: _role);
      if (mounted) setState(() => _sent = sent);
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _fieldError = e.status == 429
              ? AccountantHe.rateLimited
              : e.messageHe,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _whatsapp() async {
    final sent = _sent!;
    final phone = sent.emailed ? null : waPhone(_sentContact);
    await launchAllowed(
      whatsAppUri(
        phone: phone,
        text: sent.whatsappText.isEmpty ? sent.link : sent.whatsappText,
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _sent!.link));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showNotchNotice(const SnackBar(content: Text(AccountantHe.linkCopied)));
  }

  @override
  Widget build(BuildContext context) =>
      _sent == null ? _form(context) : _share(context);

  Widget _form(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('add-client-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(
          AccountantHe.addClientTitle,
          subtitle: AccountantHe.addClientHint,
        ),
        TextField(
          key: const Key('add-client-contact'),
          controller: _contact,
          keyboardType: TextInputType.emailAddress,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: AccountantHe.contactLabel,
            errorText: _fieldError,
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _send(),
        ),
        const SizedBox(height: Space.l),
        Text(AccountantHe.roleLabel, style: AppText.headline),
        const SizedBox(height: Space.s),
        RoleToggle(value: _role, onChanged: (r) => setState(() => _role = r)),
        const SizedBox(height: Space.s),
        Text(
          isFullAccountantRole(_role)
              ? AccountantHe.roleFullHint
              : AccountantHe.roleRepHint,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          key: const Key('add-client-send'),
          label: AccountantHe.send,
          loadingText: _busy ? AccountantHe.sending : null,
          offline: session.offline,
          onPressed: _send,
        ),
      ],
    );
  }

  Widget _share(BuildContext context) {
    final p = context.palette;
    final sent = _sent!;
    return Column(
      key: const Key('add-client-share'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(AccountantHe.sentTitle),
        if (sent.emailed)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Row(
              children: [
                Icon(Iconsax.sms_tracking, color: p.ok),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    AccountantHe.emailedTo(ltrIsolate(_sentContact)),
                    key: const Key('add-client-emailed'),
                    style: AppText.body,
                  ),
                ),
              ],
            ),
          ),
        // One PrimaryButton per sheet (F2): the form's "שליחת בקשה" was it.
        FilledButton.icon(
          key: const Key('add-client-whatsapp'),
          style: FilledButton.styleFrom(
            backgroundColor: p.whatsapp,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(Hit.min + 8),
          ),
          onPressed: () => unawaited(_whatsapp()),
          icon: const Icon(Iconsax.message),
          label: const Text(AccountantHe.sendWhatsapp),
        ),
        const SizedBox(height: Space.s),
        if (sent.link.isNotEmpty)
          TextButton.icon(
            key: const Key('add-client-copy'),
            onPressed: _copy,
            icon: const Icon(Iconsax.copy),
            label: const Text(AccountantHe.copyLink),
          ),
        TextButton(
          key: const Key('add-client-done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AccountantHe.done),
        ),
      ],
    );
  }
}

/// רו״ח מייצג (default) / רו״ח מלא.
class RoleToggle extends StatelessWidget {
  const RoleToggle({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    key: const Key('role-toggle'),
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: 'ACCOUNTANT_REP', label: Text(AccountantHe.roleRep)),
      ButtonSegment(value: 'ACCOUNTANT', label: Text(AccountantHe.roleFull)),
    ],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

/// "שליחה שוב": a new link (the old one is void) → the share step.
Future<void> resendRequest(BuildContext context, AccessRequest r) async {
  try {
    final sent = await resendAccessRequest(r.id);
    if (!context.mounted) return;
    await showAppSheet<void>(
      context,
      builder: (_) => AddClientSheet(sent: sent, contact: r.contact),
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      if (e.status == 429) {
        ScaffoldMessenger.of(context).showNotchNotice(
          const SnackBar(content: Text(AccountantHe.rateLimited)),
          motion: NoticeMotion.error,
        );
      } else {
        showErrorSnack(context, e);
      }
    }
  }
  unawaited(accountantStore.load());
}

Future<void> cancelRequest(BuildContext context, AccessRequest r) async {
  try {
    await cancelAccessRequest(r.id);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showNotchNotice(const SnackBar(content: Text(AccountantHe.cancelled)));
    }
  } on ApiException catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
  unawaited(accountantStore.load());
}

/// The office name (feature 5). Returns the saved name, null = dismissed.
Future<String?> showOfficeNameSheet(BuildContext context, {String? initial}) =>
    showAppSheet<String>(
      context,
      builder: (_) => OfficeNameSheet(initial: initial),
    );

class OfficeNameSheet extends StatefulWidget {
  const OfficeNameSheet({super.key, this.initial});

  final String? initial;

  @override
  State<OfficeNameSheet> createState() => _OfficeNameSheetState();
}

class _OfficeNameSheetState extends State<OfficeNameSheet> {
  late final _name = TextEditingController(text: widget.initial ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 80) {
      setState(() => _error = AccountantHe.officeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await saveAccountantProfile(name);
      accountantStore.markAccountant(saved);
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.messageHe);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('office-sheet'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SheetTitle(
        AccountantHe.officeTitle,
        subtitle: AccountantHe.officeHint,
      ),
      TextField(
        key: const Key('office-name'),
        controller: _name,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: AccountantHe.officeLabel,
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      const SizedBox(height: Space.l),
      PrimaryButton(
        key: const Key('office-save'),
        label: AccountantHe.officeSave,
        loadingText: _busy ? AccountantHe.officeSave : null,
        offline: session.offline,
        onPressed: _save,
      ),
    ],
  );
}

/// The parts of "תזכורת לבעלים" built from the client's task counts.
List<String> reminderParts(AccountantTasks t) => [
  if (t.paymentsWithoutReceipt > 0)
    AccountantHe.paymentsWithoutReceipt(t.paymentsWithoutReceipt),
  if (t.taxInvoicesDue > 0) AccountantHe.taxInvoicesDue(t.taxInvoicesDue),
  if (t.expensesToApprove > 0) AccountantHe.expenses(t.expensesToApprove),
  if (t.numberingGaps > 0) AccountantHe.numberingGaps(t.numberingGaps),
  if (t.correctionsAnswered > 0)
    AccountantHe.correctionsAnswered(t.correctionsAnswered),
];

/// True when the row can offer "תזכורת לבעלים".
bool canRemindOwner(AccountantClient c) =>
    waPhone(c.ownerPhone) != null && reminderParts(c.tasks).isNotEmpty;

/// wa.me to the owner's phone with the counts (feature 8).
Future<void> remindOwner(AccountantClient c) => launchAllowed(
  whatsAppUri(
    phone: waPhone(c.ownerPhone),
    text: AccountantHe.reminderText(c.legalName, reminderParts(c.tasks)),
  ),
);
