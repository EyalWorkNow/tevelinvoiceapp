// וואטסאפ עסקי — small shared pieces: the status pill, the template preview
// bubble (body + the fixed footer + the opt-out button Meta shows), the
// screen header and a label/value row with the value at the row's end.

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/whatsapp_business_api.dart';
import '../../ui/ds.dart';
import '../../util/labels/status_he.dart' show Tone;
import '../../util/labels/whatsapp_business_he.dart';

Tone waTemplateTone(String status) => switch (status) {
  'APPROVED' => Tone.ok,
  'PENDING' => Tone.warn,
  'REJECTED' || 'DISABLED' => Tone.danger,
  _ => Tone.neutral,
};

Tone waRecipientTone(String status) => switch (status) {
  'READ' || 'DELIVERED' => Tone.ok,
  'SENT' || 'SENDING' => Tone.info,
  'FAILED' => Tone.danger,
  _ => Tone.neutral,
};

/// A pill like [StatusPill]: words + a tone (text colour on its tint).
class WaPill extends StatelessWidget {
  const WaPill(this.label, this.tone, {super.key});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s + 2, vertical: 2),
      decoration: BoxDecoration(
        color: p.tint(color),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppText.secondary.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// How the template reaches the customer: the body ({שם} → [sampleName]),
/// the footer "להסרה לחצו על הכפתור" and the "הסרה מרשימת התפוצה" button.
class WaBubble extends StatelessWidget {
  const WaBubble({
    super.key,
    required this.bodyText,
    this.sampleName = WaHe.sampleName,
    this.placeholder,
  });

  final String bodyText;
  final String sampleName;

  /// Shown (muted) while [bodyText] is empty.
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final empty = bodyText.trim().isEmpty;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          key: const Key('wa-bubble'),
          decoration: BoxDecoration(
            color: p.tint(p.whatsapp),
            borderRadius: const BorderRadiusDirectional.only(
              topStart: Radius.circular(4),
              topEnd: Radius.circular(16),
              bottomStart: Radius.circular(16),
              bottomEnd: Radius.circular(16),
            ),
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.m,
                  Space.m,
                  Space.m,
                  Space.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empty
                          ? (placeholder ?? '')
                          : waPreviewText(bodyText, sampleName),
                      key: const Key('wa-bubble-body'),
                      style: AppText.body.copyWith(
                        color: empty ? p.muted : p.ink,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      WaHe.footer,
                      style: AppText.secondary.copyWith(color: p.muted),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: p.line),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s + 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Iconsax.undo, size: 16, color: p.info),
                    const SizedBox(width: Space.xs),
                    Text(
                      WaHe.optOutButton,
                      style: AppText.body.copyWith(
                        color: p.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page title row (title · back), like the group / queue screens.
class WaHeader extends StatelessWidget {
  const WaHeader(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.page,
      Space.m,
      Space.page,
      Space.s,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: AppText.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppText.secondary.copyWith(
                    color: context.palette.muted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: Space.s),
        const DesignBackButton(),
      ],
    ),
  );
}

/// Label at the start, value at the row's end.
class WaValueRow extends StatelessWidget {
  const WaValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.ltrValue = false,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  /// A phone number: laid out LTR.
  final bool ltrValue;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.xs),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: AppText.body.copyWith(color: context.palette.muted),
          ),
        ),
        const SizedBox(width: Space.m),
        Flexible(
          child: Text(
            value,
            textDirection: ltrValue ? TextDirection.ltr : null,
            textAlign: TextAlign.end,
            style: valueStyle ?? AppText.body,
          ),
        ),
      ],
    ),
  );
}

/// '2026-11-26T09:05:00Z' → '26.11.2026 · 11:05' (device time).
String waDateTime(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day}.${d.month}.${d.year} · ${two(d.hour)}:${two(d.minute)}';
}
