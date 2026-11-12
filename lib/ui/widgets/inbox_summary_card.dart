import '../../util/labels/inbox_he.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'app_card.dart';
import 'inbox_card.dart' show InboxTone;

/// One compact, tappable row inside the home screen's "לטיפול" summary.
class InboxSummaryRow {
  const InboxSummaryRow({
    required this.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.tone = InboxTone.neutral,
    this.onDismiss,
  });

  final Key key;
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final InboxTone tone;
  final VoidCallback? onDismiss;
}

/// A single grouped home card with a title and brief, actionable summary rows.
class InboxSummaryCard extends StatelessWidget {
  const InboxSummaryCard({
    super.key,
    required this.title,
    required this.rows,
    this.moreLabel,
    this.onMore,
  });

  final String title;
  final List<InboxSummaryRow> rows;
  final String? moreLabel;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.l,
        Space.m,
        Space.l,
        Space.m,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.headline.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Space.s),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: Space.xs),
            _SummaryRow(row: rows[index]),
          ],
          if (moreLabel != null && onMore != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('home-more-cards'),
                onPressed: onMore,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, Hit.min),
                  padding: const EdgeInsets.symmetric(horizontal: Space.s),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(moreLabel!),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.row});

  final InboxSummaryRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (background, foreground) = switch (row.tone) {
      InboxTone.neutral => (const Color(0xFF68B6DF), Colors.white),
      InboxTone.attention => (const Color(0xFFFFF273), const Color(0xFF655B22)),
      InboxTone.danger => (const Color(0xFFFF8088), Colors.white),
    };

    return Semantics(
      key: row.key,
      container: true,
      button: true,
      onTap: row.onTap,
      label: row.title,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: row.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: SizedBox(
              height: row.onDismiss == null ? 48 : Hit.min,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: Hit.min,
                      end: row.onDismiss == null ? 4 : Hit.min,
                    ),
                    child: Text(
                      row.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: background,
                      child: Icon(row.icon, size: 18, color: foreground),
                    ),
                  ),
                  if (row.onDismiss != null)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(
                        tooltip: InboxHe.dismissSummary,
                        onPressed: row.onDismiss,
                        icon: Icon(
                          Icons.close_rounded,
                          color: p.muted,
                          size: 20,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: Hit.min,
                          minHeight: Hit.min,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
