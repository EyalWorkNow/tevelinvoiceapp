// Quote detail: "פרטי חתימה" for the business — who sent it and when, the
// hand-drawn and digital (PAdES) signatures, and the customer's acceptance.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/models/models.dart';
import '../../ui/ds.dart';
import '../../util/labels/signature_he.dart';

/// The customer accepted: GET /quotes/:id/pdf is the signed & approved copy.
bool quoteSignedApproved(Quote q) =>
    q.signature?.acceptance != null || q.status == 'ACCEPTED';

/// ISO timestamp → '17.11.2026 · 14:05' (device time).
String formatDateTimeHe(String? iso) {
  if (iso == null) return '';
  final t = DateTime.tryParse(iso);
  if (t == null) return iso;
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.day}.${l.month}.${l.year} · ${two(l.hour)}:${two(l.minute)}';
}

class QuoteSignatureSection extends StatelessWidget {
  const QuoteSignatureSection({super.key, required this.signature});

  final QuoteSignature signature;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = signature;
    final digital = s.digital;
    final acceptance = s.acceptance;
    final muted = AppText.secondary.copyWith(color: p.muted);
    return AppCard(
      key: const Key('quote-signature'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Iconsax.edit_2, size: 20, color: p.ink),
              const SizedBox(width: Space.s),
              const Text(SignatureHe.section, style: AppText.headline),
            ],
          ),
          const SizedBox(height: Space.s),
          _Row(
            label: SignatureHe.sentBy,
            value: s.sentByName == null && s.sentAt == null
                ? SignatureHe.notSent
                : [
                    ?s.sentByName,
                    if (s.sentAt != null) formatDateTimeHe(s.sentAt),
                  ].join(' · '),
          ),
          _Row(
            key: const Key('sig-handwritten'),
            label: SignatureHe.handwritten,
            value: s.handwritten
                ? SignatureHe.handwrittenYes
                : SignatureHe.handwrittenNo,
            ok: s.handwritten,
          ),
          _Row(
            key: const Key('sig-digital'),
            label: SignatureHe.digital,
            value: digital == null
                ? SignatureHe.digitalNone
                : [
                    digital.level == 'CERTIFIED'
                        ? SignatureHe.digitalCertified
                        : SignatureHe.digitalSecure,
                    if (digital.signedAt != null)
                      formatDateTimeHe(digital.signedAt),
                  ].join(' · '),
            ok: digital != null,
          ),
          if (digital?.certSubject != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28, bottom: 2),
              child: Text(
                '${SignatureHe.certSubject}: ${digital!.certSubject}',
                style: muted,
              ),
            ),
          if (digital?.certSerial != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28, bottom: 2),
              child: Text(
                '${SignatureHe.certSerial}: ${digital!.certSerial}',
                style: muted,
                textDirection: TextDirection.rtl,
              ),
            ),
          _Row(
            key: const Key('sig-acceptance'),
            label: SignatureHe.acceptance,
            value: acceptance == null
                ? SignatureHe.waiting
                : [
                    if (acceptance.fullName.isNotEmpty) acceptance.fullName,
                    if (acceptance.acceptedAt != null)
                      formatDateTimeHe(acceptance.acceptedAt),
                  ].join(' · '),
            ok: acceptance != null,
          ),
          if (acceptance?.drawnSignaturePng != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 28, top: 4),
              child: Semantics(
                image: true,
                label: SignatureHe.customerSignature,
                child: Container(
                  key: const Key('sig-customer-drawn'),
                  height: 80,
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line),
                  ),
                  child: Image.memory(
                    acceptance!.drawnSignaturePng!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.value, this.ok});

  final String label;
  final String value;

  /// null = no mark; true ✓; false ✗ (muted).
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: ok == null
                ? null
                : Icon(
                    ok! ? Icons.check_circle_rounded : Icons.cancel_outlined,
                    size: 18,
                    color: ok! ? p.ok : p.muted,
                  ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: value, style: AppText.body),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
