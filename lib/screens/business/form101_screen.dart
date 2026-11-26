// 0134 one form 101 (spec §10): its state (נשלח · נפתח · הוחזר חתום · פג
// תוקף), the signed PDF in the official layout (view / share), "שלח לרואה
// החשבון" in one tap, the attachments, and the trail — when it was sent,
// opened, which phone / e-mail the employee verified with, and every view.
// Open forms: send again (new link + code, 14 more days), a fresh code by SMS,
// cancel. Signed forms: send a mid-year update form.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart' show ApiException;
import '../../api/form101_api.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/labels.dart';
import '../../util/phone.dart';
import '../document/pdf_viewer_screen.dart';
import '../document/sheets/s6_share.dart' show pdfSharer;
import '../sign/sign_request_screen.dart' show signTimeHe;
import 'employees_screen.dart';

/// Loads one form. Tests replace it.
Future<Form101Detail> Function(String id) loadForm101 = fetchForm101;

Future<void> openForm101(BuildContext context, String id) => Navigator.of(
  context,
).push<void>(MaterialPageRoute<void>(builder: (_) => Form101Screen(id: id)));

class Form101Screen extends StatefulWidget {
  const Form101Screen({super.key, required this.id});
  final String id;

  @override
  State<Form101Screen> createState() => _Form101ScreenState();
}

class _Form101ScreenState extends State<Form101Screen> {
  Form101Detail? _d;
  Object? _error;
  bool _busy = false;

  bool get _manage => businessContext.can(Cap.employeeFormsManage);

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final d = await loadForm101(widget.id);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _notice(String text) => ScaffoldMessenger.of(
    context,
  ).showNotchNotice(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        _notice(
          e.code == 'ACCOUNTANT_EMAIL_MISSING'
              ? Form101He.noAccountant
              : e.messageHe,
        );
      }
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Employee get _employee {
    final d = _d!;
    return Employee(
      id: d.summary.employeeId,
      fullName: d.summary.employeeName,
      phone: d.employeePhone,
      email: d.employeeEmail,
    );
  }

  Future<void> _pdf({bool share = false}) => _run(() async {
    final d = _d!;
    final bytes = await fetchForm101Pdf(d.summary.id);
    final title =
        '${Form101He.detailTitle(d.summary.employeeName)} ${d.summary.taxYear}';
    if (!mounted) return;
    if (share) {
      await pdfSharer(bytes, title);
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(bytes: bytes, title: title),
          fullscreenDialog: true,
        ),
      );
    }
    unawaited(_reload());
  });

  Future<void> _attachment(Form101Attachment a) => _run(() async {
    final bytes = await fetchForm101Attachment(widget.id, a.id);
    if (!mounted) return;
    final title = Form101He.attachment(a.kind);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => a.isPdf
            ? PdfViewerScreen(bytes: bytes, title: title)
            : Scaffold(
                appBar: AppBar(title: Text(title)),
                body: InteractiveViewer(
                  child: Center(child: Image.memory(bytes)),
                ),
              ),
        fullscreenDialog: true,
      ),
    );
    unawaited(_reload());
  });

  Future<void> _toAccountant() => _run(() async {
    final to = await sendForm101ToAccountant(widget.id);
    if (mounted) _notice(Form101He.sentToAccountant(to));
    unawaited(_reload());
  });

  Future<void> _resend() async {
    final d = _d!;
    final e = _employee;
    final hasPhone = waPhone(e.phone) != null;
    final channel = await showAppSheet<Form101Channel>(
      context,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(Form101He.resend, subtitle: Form101He.resendHint),
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
            (
              Form101Channel.email,
              Iconsax.sms,
              Form101He.viaEmail,
              (e.email ?? '').isNotEmpty,
            ),
            (Form101Channel.share, Iconsax.share, Form101He.viaShare, true),
          ])
            if (ok)
              ListTile(
                key: Key('form101-resend-${ch.name}'),
                leading: Icon(icon),
                title: Text(label, style: AppText.body),
                minTileHeight: Hit.min + 8,
                onTap: () => Navigator.of(context).pop(ch),
              ),
        ],
      ),
    );
    if (channel == null || !mounted) return;
    await _run(() async {
      final sent = await resendForm101(d.summary.id, channel);
      await dispatchForm101Link(
        channel,
        phone: e.phone,
        text: Form101He.linkText(
          businessContext.displayName,
          d.summary.taxYear,
          sent.url,
        ),
      );
      if (!mounted) return;
      setState(() => _d = sent.detail);
      await showForm101CodeSheet(
        context,
        code: sent.code,
        phone: e.phone,
        emailed: sent.emailed,
      );
    });
  }

  Future<void> _code() => _run(() async {
    final d = _d!;
    final code = d.code ?? await newForm101Code(d.summary.id);
    if (!mounted) return;
    await showForm101CodeSheet(context, code: code, phone: d.employeePhone);
    unawaited(_reload());
  });

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(Form101He.cancelTitle),
        content: const Text(Form101He.cancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text(Form101He.cancelNo),
          ),
          TextButton(
            key: const Key('form101-cancel-yes'),
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text(Form101He.cancelYes),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await cancelForm101(widget.id);
      if (mounted) _notice(Form101He.cancelled);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          d == null
              ? Form101He.title
              : Form101He.detailTitle(d.summary.employeeName),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: d == null
              ? ListView(
                  children: [
                    if (_error != null)
                      ErrorView(error: _error!, onRetry: _reload)
                    else
                      const SkeletonList(rows: 4),
                  ],
                )
              : _body(context, d),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Form101Detail d) {
    final p = context.palette;
    final s = d.summary;
    final muted = AppText.secondary.copyWith(color: p.muted);
    Widget action(
      String key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool primary = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: SizedBox(
        width: double.infinity,
        height: Hit.primary,
        child: primary
            ? FilledButton.icon(
                key: Key(key),
                onPressed: _busy ? null : onTap,
                icon: Icon(icon),
                label: Text(label),
              )
            : OutlinedButton.icon(
                key: Key(key),
                onPressed: _busy ? null : onTap,
                icon: Icon(icon, color: color),
                label: Text(label, style: TextStyle(color: color)),
              ),
      ),
    );
    return ListView(
      key: const Key('form101-detail'),
      padding: const EdgeInsets.fromLTRB(
        Space.page,
        Space.s,
        Space.page,
        Space.xl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.employeeName,
                      style: AppText.title,
                      maxLines: 2,
                    ),
                  ),
                  Form101Pill(s.status),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(Form101He.kindLine(s.kind, s.taxYear), style: AppText.body),
              if ((d.employeePhone ?? '').isNotEmpty)
                Text(formatPhoneHe(d.employeePhone), style: muted),
              if (s.open) ...[
                Text(
                  Form101He.expiresOn(formatDateHe(s.expiresOn)),
                  style: muted,
                ),
                if (s.currentStep > 0)
                  Text(Form101He.stepOf(s.currentStep), style: muted),
              ],
              if (s.status == Form101Status.completed && d.retainUntil != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    Form101He.retain(formatDateHe(d.retainUntil)),
                    style: muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.l),
        if (s.status == Form101Status.completed) ...[
          action(
            'form101-view',
            Iconsax.document_text,
            Form101He.viewPdf,
            () => unawaited(_pdf()),
            primary: true,
          ),
          if (_manage)
            action(
              'form101-accountant',
              Iconsax.send_2,
              Form101He.toAccountant,
              () => unawaited(_toAccountant()),
            ),
          action(
            'form101-share',
            Iconsax.share,
            Form101He.sharePdf,
            () => unawaited(_pdf(share: true)),
          ),
          if (_manage)
            action(
              'form101-update',
              Iconsax.refresh,
              Form101He.sendUpdate,
              () => unawaited(
                showSendForm101Sheet(
                  context,
                  employee: _employee,
                  taxYear: s.taxYear,
                  kind: Form101Kind.update,
                ),
              ),
            ),
        ],
        if (_manage && s.canResend)
          action(
            'form101-resend',
            Iconsax.send_2,
            Form101He.resend,
            () => unawaited(_resend()),
            primary: true,
          ),
        if (_manage && s.open)
          action(
            'form101-code',
            Iconsax.key,
            Form101He.sendCodeSms,
            () => unawaited(_code()),
          ),
        if (_manage && s.canResend)
          action(
            'form101-cancel',
            Iconsax.close_circle,
            Form101He.cancel,
            () => unawaited(_cancel()),
            color: p.danger,
          ),
        if (d.attachments.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(Form101He.attachments, style: AppText.title),
          const SizedBox(height: Space.s),
          for (final a in d.attachments)
            ListTile(
              key: Key('form101-att-${a.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.isPdf ? Iconsax.document : Iconsax.gallery),
              title: Text(Form101He.attachment(a.kind), style: AppText.body),
              onTap: _busy ? null : () => unawaited(_attachment(a)),
            ),
        ],
        if (d.events.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          Text(Form101He.audit, style: AppText.title),
          const SizedBox(height: Space.s),
          for (final e in d.events)
            Padding(
              key: Key('form101-event-${e.type}'),
              padding: const EdgeInsets.only(bottom: Space.m),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 10, color: p.muted),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Form101He.event(e), style: AppText.body),
                        Text(
                          [
                            signTimeHe(e.occurredAt),
                            if ((e.ip ?? '').isNotEmpty) 'IP ${e.ip}',
                          ].join(' · '),
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
