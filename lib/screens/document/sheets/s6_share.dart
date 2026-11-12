// S6 · שתף (SPEC-v2 §6 sheets, §9.2, §13.5). Owner: squad C.
// WhatsApp (primary) · e-mail · copy link · PDF · PDF copy · QR for payment ·
// revoke link (BE-12). Without doc.send (accountant, viewer): PDF and PDF
// copy only — a local share sheet, nothing is sent from the server.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../api/actions_api.dart';
import '../../../api/commerce_api.dart';
import '../../../api/client.dart';
import '../../../api/models/models.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../util/allowed_urls.dart';
import '../../../util/labels/labels.dart';
import '../../../util/phone.dart';
import '../../../util/sms_composer.dart';
import '../dialogs.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

// ---- seams (tests replace these; no share sheet in a widget test) ----------

/// Hands a PDF to the iOS share sheet.
typedef PdfSharer =
    Future<void> Function(Uint8List bytes, String fileName, {String? text});

/// Hands plain text to the iOS share sheet.
typedef TextSharer = Future<void> Function(String text);

PdfSharer pdfSharer = _sharePdfFile;
TextSharer textSharer = (text) async {
  await SharePlus.instance.share(ShareParams(text: text));
};

Future<void> _sharePdfFile(
  Uint8List bytes,
  String fileName, {
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(
    '${dir.path}/${fileName.replaceAll(RegExp(r'[/\\:]'), '-')}.pdf',
  );
  await file.writeAsBytes(bytes, flush: true);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text: text,
      ),
    );
  } finally {
    // The sheet has returned; no customer data left in tmp.
    if (file.existsSync()) await file.delete();
  }
}

// ---- flows (also used by D's one-tap buttons) --------------------------------

String get _businessName => businessContext.displayName;

/// "שלח בווטסאפ" (§6.C step 6, §13.5): share-link → fixed text → wa.me (the
/// customer's chat; WhatsApp's picker without a phone). WhatsApp did not
/// open → the PDF through the share sheet. [reminder] = §6.D row 10 wording.
Future<void> sendDocumentWhatsApp(
  DocumentDetail doc,
  Customer? customer, {
  bool reminder = false,
}) async {
  final link = await createShareLink(doc);
  final text = reminder
      ? reminderWhatsAppMessage(
          customerName: customer?.name,
          documentType: doc.documentType,
          documentNumber: doc.documentNumber,
          openMinor: doc.balanceMinor,
          businessName: _businessName,
          link: link,
        )
      : whatsAppMessage(
          customerName: customer?.name,
          documentType: doc.documentType,
          documentNumber: doc.documentNumber,
          totalMinor: doc.totalMinor,
          businessName: _businessName,
          link: link,
        );
  final opened = await launchAllowed(
    whatsAppUri(phone: waPhone(customer?.phone), text: text),
  );
  if (!opened) await sharePdf(doc, text: text);
}

/// The original (or [copy]) PDF through the iOS share sheet.
Future<void> sharePdf(
  DocumentDetail doc, {
  bool copy = false,
  String? text,
}) async {
  final Uint8List bytes;
  if (copy) {
    bytes = await fetchCopyPdf(doc.id);
  } else {
    await ensureOriginal(doc);
    bytes = await fetchOriginalPdf(doc.id);
  }
  final name = docTitle(doc.documentType, doc.documentNumber);
  await pdfSharer(bytes, copy ? '$name – העתק' : name, text: text);
}

/// Opens S6. Pass [doc] / [customer] when the caller has them (D does).
/// Returns a done-message for D's toast, or null.
/// [hasLiveLink]: BE-12 timeline says a public link exists → "בטל קישור".
Future<String?> showShareSheet(
  BuildContext context, {
  required String documentId,
  DocumentDetail? doc,
  Customer? customer,
  bool hasLiveLink = false,
}) {
  return showAppSheet<String>(
    context,
    builder: (_) => ShareSheet(
      documentId: documentId,
      doc: doc,
      customer: customer,
      hasLiveLink: hasLiveLink,
    ),
  );
}

enum _Busy {
  sms,
  paymentLink,
  automatic,
  whatsapp,
  email,
  copy,
  pdf,
  pdfCopy,
  qr,
  revoke,
}

class ShareSheet extends StatefulWidget {
  const ShareSheet({
    super.key,
    required this.documentId,
    this.doc,
    this.customer,
    this.hasLiveLink = false,
  });

  final String documentId;
  final DocumentDetail? doc;
  final Customer? customer;
  final bool hasLiveLink;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  DocumentDetail? _doc;
  Customer? _customer;
  Object? _loadError;
  _Busy? _busy;
  Object? _error;
  bool _emailOpen = false, _smsOpen = false;
  String? _qrLink;
  bool _linkMade = false;
  final _email = TextEditingController();
  final _phone = TextEditingController();

  /// Kept after a successful /send so a retry only re-runs /process.
  String? _deliveryId;

  @override
  void initState() {
    super.initState();
    _doc = widget.doc;
    _customer = widget.customer;
    _linkMade = widget.hasLiveLink;
    _phone.text = _customer?.phone ?? '';
    _email.text = _customer?.email ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = _doc ?? await fetchDocumentDetail(widget.documentId);
      Customer? customer = _customer;
      if (customer == null && doc.customerId != null) {
        try {
          customer = await fetchCustomerById(doc.customerId!);
        } on ApiException {
          customer = null; // the message just goes without a name / phone
        }
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _customer = customer;
        _loadError = null;
        if (_email.text.isEmpty) _email.text = customer?.email ?? '';
      });
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _canSend => businessContext.can(Cap.docSend);
  bool get _offline => businessContext.offline;

  Future<void> _run(_Busy action, Future<String?> Function() work) async {
    if (_busy != null) return;
    setState(() {
      _busy = action;
      _error = null;
    });
    try {
      final done = await work();
      if (!mounted) return;
      if (done != null) Navigator.of(context).pop(done);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String?> _sendEmail() async {
    final doc = _doc!;
    final recipient = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(recipient)) {
      throw ApiException(422, 'EMAIL', DocumentHe.emailInvalid);
    }
    if (_deliveryId == null) {
      await ensureOriginal(doc);
      final payUrl = doc.balanceMinor > BigInt.zero
          ? businessContext.profile?.paymentLinkUrl
          : null;
      try {
        _deliveryId = await sendDocumentEmail(
          doc.id,
          recipient,
          paymentUrl: payUrl,
        );
      } on ApiException catch (e) {
        if (e.code != 'CONSENT_REQUIRED' ||
            doc.customerId == null ||
            !mounted) {
          rethrow;
        }
        final agreed = await askEmailConsent(context);
        if (agreed == null) return null;
        if (!agreed) {
          await sendDocumentWhatsApp(doc, _customer);
          return '';
        }
        await recordConsent(doc.customerId!);
        _deliveryId = await sendDocumentEmail(
          doc.id,
          recipient,
          paymentUrl: payUrl,
        );
      }
    }
    final status = await processDelivery(_deliveryId!);
    return switch (status) {
      'SENT' => DocumentHe.emailSent,
      'RETRY_SCHEDULED' => DocumentHe.emailQueued,
      _ => throw ApiException(502, 'DELIVERY_FAILED', DocumentHe.emailFailed),
    };
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    if (doc == null) {
      return SizedBox(
        height: 240,
        child: _loadError == null
            ? const SkeletonList(rows: 3)
            : ErrorView(error: _loadError!, onRetry: _load),
      );
    }
    final p = context.palette;
    final subtitle =
        '${docTitle(doc.documentType, doc.documentNumber)} · ${moneyText(context, doc.totalMinor)}';
    return PopScope(
      canPop: _busy == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(DocumentHe.shareTitle, subtitle: subtitle),
          if (_canSend) ...[
            PrimaryButton(
              key: const Key('s6-qr'),
              label: BusinessHe.scanInvoiceAction,
              icon: Iconsax.scan_barcode,
              offline: _offline,
              loadingText: _busy == _Busy.qr ? BusinessHe.preparingLink : null,
              onPressed: () => _run(_Busy.qr, () async {
                final link = _qrLink ?? await createShareLink(doc);
                _linkMade = true;
                if (mounted) setState(() => _qrLink = link);
                return null;
              }),
            ),
            ..._qrRows(doc),
            _row(
              Iconsax.message,
              'קבלה למספר טלפון',
              const Key('s6-sms'),
              () => setState(() => _smsOpen = !_smsOpen),
            ),
            if (_smsOpen)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('s6-phone-field'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'מספר הטלפון של הלקוח',
                    ),
                  ),
                  const Text(
                    'תיפתח הודעת SMS עם הקישור. יש לאשר את השליחה במכשיר.',
                    style: AppText.secondary,
                  ),
                  TextButton(
                    key: const Key('s6-sms-send'),
                    onPressed: _offline || _busy != null
                        ? null
                        : () => _run(_Busy.sms, () async {
                            final number = waPhone(_phone.text);
                            if (number == null) {
                              throw ApiException(
                                422,
                                'CUSTOMER_PHONE_INVALID',
                                BusinessHe.validPhoneRequired,
                              );
                            }
                            final link = await createShareLink(doc);
                            final result = await smsComposer(
                              '+$number',
                              DocumentHe.customerSms(_businessName, link),
                            );
                            if (result == 'SENT') {
                              return BusinessHe.messageSentFromDevice;
                            }
                            if (result == 'UNAVAILABLE') {
                              throw ApiException(
                                503,
                                'SMS_UNAVAILABLE',
                                BusinessHe.smsUnavailable,
                              );
                            }
                            if (result == 'FAILED') {
                              throw ApiException(
                                502,
                                'SMS_FAILED',
                                BusinessHe.smsFailed,
                              );
                            }
                            return null;
                          }),
                    child: const Text(BusinessHe.openingMessage),
                  ),
                ],
              ),
            _row(
              Iconsax.message,
              DocumentHe.sendWhatsApp,
              const Key('s6-whatsapp'),
              () => _run(_Busy.whatsapp, () async {
                await sendDocumentWhatsApp(doc, _customer);
                return '';
              }),
            ),
            const SizedBox(height: Space.s),
            _row(
              Icons.send_rounded,
              'שליחה אוטומטית ללקוח',
              const Key('s6-automatic'),
              () => _run(_Busy.automatic, () async {
                final result = await dispatchDocument(doc.id);
                return result.message;
              }),
              busy: _busy == _Busy.automatic,
              subtitle: 'במייל או ב־WhatsApp, לפי פרטי הלקוח',
            ),
            _row(
              Iconsax.sms,
              DocumentHe.email,
              const Key('s6-email'),
              () => setState(() => _emailOpen = !_emailOpen),
            ),
            if (_emailOpen) _emailForm(),
            if (businessContext.can(Cap.paymentRecord) &&
                doc.balanceMinor > BigInt.zero)
              _row(
                Iconsax.card,
                'קישור תשלום בקארדקום',
                const Key('s6-cardcom'),
                () => _run(_Busy.paymentLink, () async {
                  final link = await createCustomerPaymentLink(doc.id);
                  await textSharer('לתשלום ל$_businessName:\n$link');
                  return 'קישור התשלום מוכן לשיתוף';
                }),
                busy: _busy == _Busy.paymentLink,
              ),
            _row(
              Iconsax.link,
              DocumentHe.copyLink,
              const Key('s6-copy'),
              () => _run(_Busy.copy, () async {
                await Clipboard.setData(
                  ClipboardData(text: await createShareLink(doc)),
                );
                _linkMade = true;
                return DocumentHe.linkCopied;
              }),
              busy: _busy == _Busy.copy,
            ),
          ] else
            PrimaryButton(
              key: const Key('s6-pdf-primary'),
              label: DocumentHe.pdf,
              icon: Iconsax.document_text,
              offline: _offline,
              loadingText: _busy == _Busy.pdf ? DocumentHe.pdf : null,
              onPressed: () => _run(_Busy.pdf, () async {
                await sharePdf(doc);
                return '';
              }),
            ),
          if (_canSend)
            _row(
              Iconsax.document_text,
              DocumentHe.pdf,
              const Key('s6-pdf'),
              () => _run(_Busy.pdf, () async {
                await sharePdf(doc);
                return '';
              }),
              busy: _busy == _Busy.pdf,
            ),
          _row(
            Iconsax.copy,
            DocumentHe.pdfCopy,
            const Key('s6-pdf-copy'),
            () => _run(_Busy.pdfCopy, () async {
              await sharePdf(doc, copy: true);
              return '';
            }),
            busy: _busy == _Busy.pdfCopy,
          ),

          if (_canSend && _linkMade)
            _row(
              Iconsax.link_circle,
              DocumentHe.revokeLink,
              const Key('s6-revoke'),
              () => _run(_Busy.revoke, () async {
                await revokeShareLink(doc.id);
                return DocumentHe.linkRevoked;
              }),
              busy: _busy == _Busy.revoke,
              color: p.danger,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.m),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  errorTextHe(_error!),
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A document QR is independent of payment-provider configuration.
  List<Widget> _qrRows(DocumentDetail doc) => [
    if (_qrLink != null) ...[
      const SizedBox(height: 16),
      Center(
        child: Semantics(
          label: 'סרקו כדי לפתוח את החשבונית',
          child: Container(
            key: const Key('s6-qr-image'),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(16),
            child: QrImageView(data: _qrLink!, size: 220),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'סורקים במצלמה ומקבלים את המסמך בטלפון',
          textAlign: TextAlign.center,
          style: AppText.secondary,
        ),
      ),
    ],
  ];

  Widget _emailForm() => Padding(
    padding: const EdgeInsets.only(bottom: Space.s),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('s6-email-field'),
            controller: _email,
            autofocus: _email.text.isEmpty,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(hintText: DocumentHe.emailHint),
          ),
        ),
        const SizedBox(width: Space.s),
        TextButton(
          key: const Key('s6-email-send'),
          onPressed: _offline || _busy != null
              ? null
              : () => _run(_Busy.email, _sendEmail),
          child: _busy == _Busy.email
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(DocumentHe.sendEmail),
        ),
      ],
    ),
  );

  Widget _row(
    IconData icon,
    String label,
    Key key,
    VoidCallback onTap, {
    bool busy = false,
    String? subtitle,
    Color? color,
  }) {
    final p = context.palette;
    return ListTile(
      key: key,
      minTileHeight: Hit.row,
      contentPadding: EdgeInsets.zero,
      leading: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: color ?? p.ink),
      title: Text(label, style: AppText.body.copyWith(color: color ?? p.ink)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: AppText.secondary.copyWith(color: p.muted)),
      onTap: _offline || _busy != null ? null : onTap,
    );
  }
}
