import 'package:flutter/material.dart';

import '../../util/labels/status_he.dart' as labels;
import '../../util/status_map.dart';
import '../theme.dart';

/// Status in words + colour (spec V2 F10, §15.5, AT-91). Accepts only the
/// §15.5 enums from `util/status_map.dart`; words and tones come from
/// `util/labels/status_he.dart`. "נשלח"/"נצפה" are attributes shown beside
/// the pill (see DocRow), never a status.
class StatusPill extends StatelessWidget {
  const StatusPill.doc(DocStatus this.docStatus, {super.key})
    : quoteStatus = null;

  const StatusPill.quote(QuoteListStatus this.quoteStatus, {super.key})
    : docStatus = null;

  final DocStatus? docStatus;
  final QuoteListStatus? quoteStatus;

  String get label => docStatus != null
      ? labels.docStatusLabels[docStatus]!
      : labels.quoteStatusLabels[quoteStatus]!;

  labels.Tone get _tone => docStatus != null
      ? labels.docStatusTones[docStatus]!
      : labels.quoteStatusTones[quoteStatus]!;

  bool get isOverdue => docStatus == DocStatus.overdue;

  bool get isCancelled => docStatus == DocStatus.cancelled;

  /// Text colour; the background is `palette.tint(color)`.
  Color colorIn(AppPalette p) => p.tone(_tone);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = colorIn(p);
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
