// 0134 "עובדים וטופס 101" (spec 2026-11-25 §10, route /business/employees —
// also the target of the form-101 pushes). The salaried employees of the
// business (not app users — those are "צוות והרשאות") with this tax year's
// form state: נשלח · נפתח · הוחזר חתום · פג תוקף. The owner adds employees and
// sends the form (WhatsApp / SMS / e-mail / share); the one-time code goes in a
// separate SMS. In January (or whenever last year's forms exist without this
// year's) one tap re-sends to everyone, prefilled. A blank form prints for an
// employee without a smartphone. The accountants see the list read-only.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../api/form101_api.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';
import '../../util/phone.dart';
import '../document/pdf_viewer_screen.dart';
import '../document/sheets/s6_share.dart' show textSharer;
import 'form101_screen.dart';

/// Loads the list. Tests replace it.
Future<EmployeeList> Function({int? taxYear}) loadEmployees = fetchEmployees;

/// "Today" for the tax-year chips. Tests replace it.
DateTime Function() form101Today = DateTime.now;

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The pill of a form state (or "לא נשלח").
class Form101Pill extends StatelessWidget {
  const Form101Pill(this.status, {super.key});
  final Form101Status? status;

  static Tone toneOf(Form101Status? s) => switch (s) {
    Form101Status.completed => Tone.ok,
    Form101Status.sent || Form101Status.viewed => Tone.info,
    Form101Status.expired => Tone.danger,
    Form101Status.cancelled || null => Tone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.tone(toneOf(status));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s + 2, vertical: 2),
      decoration: BoxDecoration(
        color: p.tint(color),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        status == null ? Form101He.notSent : Form101He.status(status!),
        maxLines: 1,
        style: AppText.secondary.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  EmployeeList? _data;
  Object? _error;
  late int _year = form101Today().year;
  bool _busy = false;

  bool get _manage => businessContext.can(Cap.employeeFormsManage);

  /// Last year, this year, and in December next year too.
  List<int> get _years {
    final now = form101Today();
    return [now.year - 1, now.year, if (now.month == 12) now.year + 1];
  }

  @override
  void initState() {
    super.initState();
    form101Version.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    form101Version.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final data = await loadEmployees(taxYear: _year);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _add() async {
    final e = await showEmployeeEditor(context);
    if (e == null || !mounted) return;
    await showSendForm101Sheet(context, employee: e, taxYear: _year);
  }

  Future<void> _blank() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await fetchBlankForm101(_year);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(
            bytes: bytes,
            title: '${Form101He.blankPdf} $_year',
          ),
          fullscreenDialog: true,
        ),
      );
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _season() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await sendForm101Season(_year);
      if (!mounted) return;
      await showSeasonQueue(context, r.items, taxYear: r.taxYear);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Employee e) async {
    final f = e.form101;
    if (f != null) {
      await openForm101(context, f.id);
      return;
    }
    if (!_manage) return;
    await showEmployeeActions(context, e, taxYear: _year);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = _data;
    final active = [
      for (final e in data?.items ?? const <Employee>[])
        if (!e.archived) e,
    ];
    final Widget body;
    if (_error != null && data == null) {
      body = ErrorView(error: _error!, onRetry: _reload);
    } else if (data == null) {
      body = const SkeletonList(rows: 4);
    } else {
      body = RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          key: const Key('employees-list'),
          padding: EdgeInsets.fromLTRB(
            0,
            Space.s,
            0,
            MediaQuery.paddingOf(context).bottom + Space.xl,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: Text(
                _manage ? Form101He.intro : Form101He.viewOnly,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
            const SizedBox(height: Space.m),
            ChipRow<int>(
              key: const Key('employees-years'),
              options: [
                for (final y in _years) ChipOption(y, Form101He.yearChip(y)),
              ],
              selected: _year,
              onSelected: (y) {
                setState(() {
                  _year = y;
                  _data = null;
                });
                unawaited(_reload());
              },
            ),
            const SizedBox(height: Space.m),
            if (_manage && data.renewable > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  0,
                  Space.page,
                  Space.m,
                ),
                child: AppCard(
                  key: const Key('employees-season'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Iconsax.calendar_tick, color: p.info),
                          const SizedBox(width: Space.s),
                          Expanded(
                            child: Text(
                              Form101He.seasonTitle(_year),
                              style: AppText.title,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        Form101He.seasonBody(data.renewable),
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                      const SizedBox(height: Space.m),
                      SizedBox(
                        width: double.infinity,
                        height: Hit.primary,
                        child: FilledButton.icon(
                          key: const Key('employees-season-send'),
                          onPressed: _busy ? null : () => unawaited(_season()),
                          icon: const Icon(Iconsax.send_2),
                          label: const Text(Form101He.seasonSend),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (active.isEmpty)
              EmptyState(
                icon: Iconsax.people,
                title: Form101He.emptyTitle,
                message: Form101He.emptyHint,
                actionLabel: _manage ? Form101He.addEmployee : null,
                onAction: _manage ? () => unawaited(_add()) : null,
              ),
            for (final e in active)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  0,
                  Space.page,
                  Space.s,
                ),
                child: _EmployeeRow(
                  employee: e,
                  onTap: () => unawaited(_open(e)),
                ),
              ),
            const SizedBox(height: Space.s),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              child: ListTile(
                key: const Key('employees-blank'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Iconsax.printer),
                title: Text(Form101He.blankPdf, style: AppText.body),
                subtitle: Text(
                  Form101He.blankHint,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
                onTap: _busy ? null : () => unawaited(_blank()),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text(Form101He.title)),
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: _manage && active.isNotEmpty
          ? BottomActionArea(
              key: const Key('employees-bottom'),
              child: PrimaryButton(
                label: Form101He.addEmployee,
                icon: Iconsax.user_add,
                onPressed: () => unawaited(_add()),
              ),
            )
          : null,
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.onTap});

  final Employee employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = employee;
    final subtitle = [
      if ((e.phone ?? '').isNotEmpty) formatPhoneHe(e.phone),
      if (e.form101 == null && e.lastCompletedYear != null)
        Form101He.lastYear(e.lastCompletedYear!),
    ].join(' · ');
    return AppCard(
      key: Key('employee-row-${e.id}'),
      onTap: onTap,
      child: Row(
        children: [
          PersonAvatar(name: e.fullName),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.fullName,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppText.secondary.copyWith(color: p.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.s),
          Form101Pill(e.form101?.status),
        ],
      ),
    );
  }
}

// ─── sheets ──────────────────────────────────────────────────────────────────

/// Edit (or, with no [initial], create) an employee. Returns the saved one.
Future<Employee?> showEmployeeEditor(
  BuildContext context, {
  Employee? initial,
}) => showAppSheet<Employee>(
  context,
  builder: (context) => _EmployeeEditor(initial: initial),
);

class _EmployeeEditor extends StatefulWidget {
  const _EmployeeEditor({this.initial});
  final Employee? initial;

  @override
  State<_EmployeeEditor> createState() => _EmployeeEditorState();
}

class _EmployeeEditorState extends State<_EmployeeEditor> {
  late final _name = TextEditingController(text: widget.initial?.fullName);
  late final _phone = TextEditingController(text: widget.initial?.phone);
  late final _mail = TextEditingController(text: widget.initial?.email);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _mail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool? archived}) async {
    final name = _name.text.trim();
    if (name.length < 2) return setState(() => _error = Form101He.nameRequired);
    if (_phone.text.trim().isEmpty && _mail.text.trim().isEmpty) {
      return setState(() => _error = Form101He.contactRequired);
    }
    if (_mail.text.trim().isNotEmpty && !_emailRe.hasMatch(_mail.text.trim())) {
      return setState(() => _error = Form101He.needEmail);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final initial = widget.initial;
      final saved = initial == null
          ? await createEmployee(
              fullName: name,
              phone: _phone.text,
              email: _mail.text,
            )
          : await updateEmployee(
              initial.id,
              fullName: name,
              phone: _phone.text,
              email: _mail.text,
              archived: archived,
            );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ApiException ? e.messageHe : Form101He.sendFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget field(
      TextEditingController c,
      String label,
      String key, {
      TextInputType? type,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: TextField(
        key: Key(key),
        controller: c,
        keyboardType: type,
        textDirection: type == null ? null : TextDirection.ltr,
        decoration: InputDecoration(labelText: label),
      ),
    );
    final initial = widget.initial;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(Form101He.editTitle),
          field(_name, Form101He.fullName, 'employee-name'),
          field(
            _phone,
            Form101He.phone,
            'employee-phone',
            type: TextInputType.phone,
          ),
          field(
            _mail,
            Form101He.email,
            'employee-email',
            type: TextInputType.emailAddress,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(
                _error!,
                key: const Key('employee-error'),
                style: AppText.secondary.copyWith(color: p.danger),
              ),
            ),
          SizedBox(
            height: Hit.primary,
            child: FilledButton(
              key: const Key('employee-save'),
              onPressed: _saving ? null : () => unawaited(_save()),
              child: const Text(Form101He.save),
            ),
          ),
          if (initial != null) ...[
            const SizedBox(height: Space.s),
            TextButton(
              key: const Key('employee-archive'),
              onPressed: _saving
                  ? null
                  : () => unawaited(_save(archived: !initial.archived)),
              child: Text(
                initial.archived ? Form101He.restore : Form101He.markLeft,
                style: TextStyle(color: initial.archived ? null : p.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An employee with no form this year: send / edit.
Future<void> showEmployeeActions(
  BuildContext context,
  Employee e, {
  required int taxYear,
}) async {
  final action = await showAppSheet<String>(
    context,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(e.fullName, subtitle: formatPhoneHe(e.phone)),
        for (final (key, icon, label) in [
          ('send', Iconsax.send_2, Form101He.send),
          if (e.lastCompletedYear != null)
            ('update', Iconsax.refresh, Form101He.sendUpdate),
          ('edit', Iconsax.edit_2, Form101He.editTitle),
        ])
          ListTile(
            key: Key('employee-action-$key'),
            leading: Icon(icon),
            title: Text(label, style: AppText.body),
            minTileHeight: Hit.min + 8,
            onTap: () => Navigator.of(context).pop(key),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'send':
      await showSendForm101Sheet(context, employee: e, taxYear: taxYear);
    case 'update':
      await showSendForm101Sheet(
        context,
        employee: e,
        taxYear: taxYear,
        kind: Form101Kind.update,
      );
    case 'edit':
      await showEmployeeEditor(context, initial: e);
  }
}

/// Opens the channel for a link message (WhatsApp / SMS / share; e-mail is
/// sent by the server).
Future<void> dispatchForm101Link(
  Form101Channel channel, {
  required String? phone,
  required String text,
}) async {
  final wa = waPhone(phone);
  switch (channel) {
    case Form101Channel.whatsapp:
      await launchAllowed(whatsAppUri(phone: wa, text: text));
    case Form101Channel.sms:
      if (wa != null) await launchAllowed(smsUri(phone: wa, text: text));
    case Form101Channel.share:
      await textSharer(text);
    case Form101Channel.email:
      break;
  }
}

/// Year + kind are given; the owner picks the channel. Sends, opens the
/// channel, then shows the one-time code (to send by SMS).
Future<void> showSendForm101Sheet(
  BuildContext context, {
  required Employee employee,
  required int taxYear,
  Form101Kind kind = Form101Kind.annual,
}) async {
  final hasPhone = waPhone(employee.phone) != null;
  final hasMail = (employee.email ?? '').isNotEmpty;
  final channel = await showAppSheet<Form101Channel>(
    context,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          kind == Form101Kind.update ? Form101He.sendUpdate : Form101He.send,
          subtitle:
              '${employee.fullName} · ${Form101He.year} $taxYear'
              '${kind == Form101Kind.update ? '\n${Form101He.updateHint}' : ''}',
        ),
        for (final (ch, icon, label, ok) in [
          (
            Form101Channel.whatsapp,
            Iconsax.message,
            Form101He.viaWhatsApp,
            hasPhone,
          ),
          (
            Form101Channel.sms,
            Iconsax.message_text,
            Form101He.viaSms,
            hasPhone,
          ),
          (Form101Channel.email, Iconsax.sms, Form101He.viaEmail, hasMail),
          (Form101Channel.share, Iconsax.share, Form101He.viaShare, true),
        ])
          if (ok)
            ListTile(
              key: Key('form101-channel-${ch.name}'),
              leading: Icon(
                icon,
                color: ch == Form101Channel.whatsapp
                    ? context.palette.whatsapp
                    : null,
              ),
              title: Text(label, style: AppText.body),
              minTileHeight: Hit.min + 8,
              onTap: () => Navigator.of(context).pop(ch),
            ),
      ],
    ),
  );
  if (channel == null || !context.mounted) return;
  try {
    final sent = await sendForm101(
      employeeId: employee.id,
      taxYear: taxYear,
      kind: kind,
      channel: channel,
    );
    await dispatchForm101Link(
      channel,
      phone: employee.phone,
      text: Form101He.linkText(businessContext.displayName, taxYear, sent.url),
    );
    if (!context.mounted) return;
    await showForm101CodeSheet(
      context,
      code: sent.code,
      phone: employee.phone,
      emailed: sent.emailed,
    );
  } on ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showNotchNotice(
      SnackBar(
        content: Text(
          e.code == 'FORM101_ALREADY_SENT'
              ? Form101He.alreadySent
              : e.messageHe,
        ),
      ),
    );
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

/// The one-time code after a send, with "send by SMS" and copy.
Future<void> showForm101CodeSheet(
  BuildContext context, {
  required String code,
  required String? phone,
  bool emailed = false,
}) => showAppSheet<void>(
  context,
  builder: (context) {
    final p = context.palette;
    final wa = waPhone(phone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle(Form101He.codeTitle),
        Text(Form101He.codeBody, style: AppText.body),
        const SizedBox(height: Space.m),
        Container(
          key: const Key('form101-code'),
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          decoration: BoxDecoration(
            color: p.tint(p.info),
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Text(
            code.split('').join(' '),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: AppText.headline.copyWith(letterSpacing: 4),
          ),
        ),
        const SizedBox(height: Space.m),
        if (wa != null)
          SizedBox(
            height: Hit.primary,
            child: FilledButton.icon(
              key: const Key('form101-code-sms'),
              onPressed: () => unawaited(
                launchAllowed(
                  smsUri(
                    phone: wa,
                    text: Form101He.codeText(businessContext.displayName, code),
                  ),
                ),
              ),
              icon: const Icon(Iconsax.message_text),
              label: const Text(Form101He.sendCodeSms),
            ),
          ),
        const SizedBox(height: Space.s),
        SizedBox(
          height: Hit.primary,
          child: OutlinedButton.icon(
            key: const Key('form101-code-copy'),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: code)));
              unawaited(HapticFeedback.lightImpact());
              ScaffoldMessenger.of(context).showNotchNotice(
                const SnackBar(content: Text(Form101He.copied)),
              );
            },
            icon: const Icon(Iconsax.copy),
            label: const Text(Form101He.copyCode),
          ),
        ),
        if (emailed) ...[
          const SizedBox(height: Space.s),
          Text(
            Form101He.codeEmailHint,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ],
      ],
    );
  },
);

/// January: the forms were created (e-mailed where possible); one tap per
/// remaining employee opens WhatsApp with the link, then the code by SMS.
Future<void> showSeasonQueue(
  BuildContext context,
  List<SeasonItem> items, {
  required int taxYear,
}) => showAppSheet<void>(
  context,
  builder: (context) => _SeasonQueue(items: items, taxYear: taxYear),
);

class _SeasonQueue extends StatefulWidget {
  const _SeasonQueue({required this.items, required this.taxYear});
  final List<SeasonItem> items;
  final int taxYear;

  @override
  State<_SeasonQueue> createState() => _SeasonQueueState();
}

class _SeasonQueueState extends State<_SeasonQueue> {
  final Set<String> _done = {};

  Future<void> _send(SeasonItem i) async {
    await dispatchForm101Link(
      waPhone(i.phone) != null ? Form101Channel.whatsapp : Form101Channel.share,
      phone: i.phone,
      text: Form101He.linkText(
        businessContext.displayName,
        widget.taxYear,
        i.url,
      ),
    );
    if (!mounted) return;
    setState(() => _done.add(i.employeeId));
    await showForm101CodeSheet(context, code: i.code, phone: i.phone);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final emailed = widget.items.where((i) => i.emailed).length;
    final left = widget.items.length - emailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          Form101He.seasonQueueTitle,
          subtitle: Form101He.seasonQueueHint(emailed, left),
        ),
        for (final i in widget.items)
          ListTile(
            key: Key('season-${i.employeeId}'),
            contentPadding: EdgeInsets.zero,
            leading: PersonAvatar(name: i.employeeName),
            title: Text(i.employeeName, style: AppText.body),
            subtitle: i.emailed ? null : Text(formatPhoneHe(i.phone)),
            trailing: i.emailed
                ? Text(
                    Form101He.seasonEmailed,
                    style: AppText.secondary.copyWith(color: p.ok),
                  )
                : _done.contains(i.employeeId)
                ? Text(
                    Form101He.seasonSentWa,
                    style: AppText.secondary.copyWith(color: p.ok),
                  )
                : IconButton(
                    key: Key('season-send-${i.employeeId}'),
                    icon: Icon(Iconsax.send_2, color: p.whatsapp),
                    onPressed: () => unawaited(_send(i)),
                  ),
          ),
        const SizedBox(height: Space.m),
        SizedBox(
          height: Hit.primary,
          child: FilledButton(
            key: const Key('season-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(Form101He.done),
          ),
        ),
      ],
    );
  }
}
