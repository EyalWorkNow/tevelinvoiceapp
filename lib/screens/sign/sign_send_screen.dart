// Send a DRAFT sign request: who signs (an existing customer or typed
// details), an optional message and link expiry, then e-mail (the server
// mails the link), WhatsApp (wa.me with the link) or the share sheet.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/models/customer.dart';
import '../../api/models/payment.dart' show isoDay;
import '../../api/sign_requests_api.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/sign_he.dart';
import '../../util/phone.dart';
import '../document/sheets/s6_share.dart' show textSharer;
import '../people/sheets/s2_customer.dart';
import 'sign_common.dart';

/// S2 customer picker. Tests replace it.
Future<Customer?> Function(BuildContext context) pickSignCustomer = (c) =>
    showCustomerSheet(c, openExistingCard: false);

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// Days a link lives when the owner does not choose (server default).
const int defaultSignExpiryDays = 30;

class SignSendScreen extends StatefulWidget {
  const SignSendScreen({super.key, required this.request, this.today});
  final SignRequest request;

  /// Injected clock (tests).
  final DateTime Function()? today;

  @override
  State<SignSendScreen> createState() => _SignSendScreenState();
}

class _SignSendScreenState extends State<SignSendScreen> {
  late final _name = TextEditingController(text: widget.request.signerName);
  late final _mail = TextEditingController(text: widget.request.signerEmail);
  late final _phone = TextEditingController(text: widget.request.signerPhone);
  late final _message = TextEditingController(text: widget.request.message);
  late String? _customerId = widget.request.customerId;
  late bool _notifyOnView = widget.request.notifyOnView;
  late String _expiresOn =
      widget.request.expiresOn ??
      isoDay(_now().add(const Duration(days: defaultSignExpiryDays)));
  SignChannel? _sending;
  String? _error;

  DateTime _now() => (widget.today ?? DateTime.now)();

  @override
  void dispose() {
    for (final c in [_name, _mail, _phone, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final c = await pickSignCustomer(context);
    if (c == null || !mounted) return;
    setState(() {
      _customerId = c.id;
      _name.text = c.name;
      _mail.text = c.email ?? '';
      _phone.text = c.phone ?? '';
      _error = null;
    });
  }

  Future<void> _pickExpiry() async {
    final now = _now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_expiresOn) ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) setState(() => _expiresOn = isoDay(picked));
  }

  String? _validate(SignChannel channel) {
    if (_name.text.trim().length < 2) return SignHe.nameRequired;
    if (channel == SignChannel.email && !_email.hasMatch(_mail.text.trim())) {
      return SignHe.emailRequired;
    }
    if (channel == SignChannel.whatsapp && waPhone(_phone.text) == null) {
      return SignHe.phoneRequired;
    }
    return null;
  }

  Future<void> _send(SignChannel channel) async {
    final problem = _validate(channel);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _sending = channel;
      _error = null;
    });
    try {
      await updateSignRequest(
        widget.request.id,
        setDetails: true,
        signerName: _name.text,
        signerEmail: _mail.text,
        signerPhone: _phone.text,
        customerId: _customerId,
        message: _message.text,
        expiresOn: _expiresOn,
        notifyOnView: _notifyOnView,
      );
      final sent = await sendSignRequest(
        widget.request.id,
        channel,
        notifyOnView: _notifyOnView,
      );
      final text = SignHe.shareText(widget.request.title, sent.url);
      switch (channel) {
        case SignChannel.email:
          break;
        case SignChannel.whatsapp:
          await launchAllowed(
            whatsAppUri(phone: waPhone(_phone.text), text: text),
          );
        case SignChannel.share:
          await textSharer(text);
      }
      if (!mounted) return;
      if (channel == SignChannel.email && !sent.emailed) {
        // The request is SENT; the owner shares the link another way.
        signToast(context, SignHe.emailFailed, motion: NoticeMotion.error);
        await textSharer(text);
        if (!mounted) return;
      } else {
        signToast(
          context,
          channel == SignChannel.email ? SignHe.sentEmail : SignHe.sent,
          motion: NoticeMotion.sent,
        );
      }
      await openSignRequest(context, widget.request.id, replace: true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = signErrorText(e, SignHe.uploadFailed));
      }
    } finally {
      if (mounted) setState(() => _sending = null);
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
      int maxLines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: TextField(
        key: Key(key),
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        textDirection: type == null ? null : TextDirection.ltr,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) {
          if (key == 'sign-name') _customerId = null;
        },
      ),
    );
    Widget channelButton(SignChannel ch, IconData icon, String label) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: OutlinedButton(
              key: Key('sign-send-${ch.name}'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, Hit.primary + 8),
                padding: const EdgeInsets.symmetric(vertical: Space.s),
              ),
              onPressed: _sending == null ? () => unawaited(_send(ch)) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sending == ch
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          icon,
                          color: ch == SignChannel.whatsapp ? p.whatsapp : null,
                        ),
                  const SizedBox(height: Space.xs),
                  Text(label, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SignHeader(SignHe.sendTitle),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.xl,
                ),
                children: [
                  Text(
                    widget.request.title,
                    style: AppText.headline,
                    maxLines: 2,
                  ),
                  const SizedBox(height: Space.l),
                  Text(SignHe.signerSection, style: AppText.title),
                  const SizedBox(height: Space.s),
                  OutlinedButton.icon(
                    key: const Key('sign-pick-customer'),
                    onPressed: () => unawaited(_pickCustomer()),
                    icon: const Icon(Iconsax.profile_2user),
                    label: const Text(SignHe.pickCustomer),
                  ),
                  const SizedBox(height: Space.m),
                  field(_name, SignHe.signerName, 'sign-name'),
                  field(
                    _mail,
                    SignHe.signerEmail,
                    'sign-email',
                    type: TextInputType.emailAddress,
                  ),
                  field(
                    _phone,
                    SignHe.signerPhone,
                    'sign-phone',
                    type: TextInputType.phone,
                  ),
                  field(_message, SignHe.message, 'sign-message', maxLines: 3),
                  ListTile(
                    key: const Key('sign-expiry'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Iconsax.calendar_1),
                    title: const Text(SignHe.expiry),
                    subtitle: Text(SignHe.expiryOn(formatDateHe(_expiresOn))),
                    onTap: () => unawaited(_pickExpiry()),
                  ),
                  SwitchListTile(
                    key: const Key('sign-notify-view'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(SignHe.notifyOnView),
                    value: _notifyOnView,
                    onChanged: (v) => setState(() => _notifyOnView = v),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s),
                      child: Text(
                        _error!,
                        key: const Key('sign-send-error'),
                        style: AppText.secondary.copyWith(color: p.danger),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page - Space.xs,
                Space.s,
                Space.page - Space.xs,
                Space.m,
              ),
              child: Row(
                children: [
                  channelButton(
                    SignChannel.email,
                    Iconsax.sms,
                    SignHe.sendEmail,
                  ),
                  channelButton(
                    SignChannel.whatsapp,
                    Iconsax.message,
                    SignHe.sendWhatsApp,
                  ),
                  channelButton(
                    SignChannel.share,
                    Iconsax.share,
                    SignHe.sendShare,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
