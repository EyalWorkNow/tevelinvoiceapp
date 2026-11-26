// 2611 §1 "נקודות הסבר": the first time on a screen, one bubble points at its
// main action (Home → "חשבונית", לקוחות → "+ לקוח חדש", a customer → the quick
// actions). A tap anywhere closes it. The target is found by its existing
// widget Key, so no screen (and never the bottom navbar) changes for it.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/ds.dart';
import '../../util/labels/tutorial_he.dart';
import 'tutorial_state.dart';

/// The on-screen rectangle of the first visible widget with [key], or null.
Rect? findTargetRect(Key key, {Size? screen}) {
  Rect? found;
  void visit(Element e) {
    if (found != null) return;
    if (e.widget.key == key) {
      final box = e.renderObject;
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final bounds = screen == null ? null : Offset.zero & screen;
        if (bounds == null || bounds.overlaps(rect)) {
          found = rect;
          return;
        }
      }
    }
    e.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildElements(visit);
  return found;
}

/// Shows the coach mark [id] once (when the tutorial armed it) next to the
/// widget with [target]. Nothing happens when it is not due or the target
/// is not on screen.
Future<void> maybeShowCoachMark(
  BuildContext context, {
  required String id,
  required Key target,
  required String text,
  TutorialState? state,
}) async {
  final st = state ?? tutorialState;
  if (!await st.coachDue(id)) return;
  // Let the screen settle (lists load, the page transition ends).
  await Future<void>.delayed(const Duration(milliseconds: 450));
  if (!context.mounted) return;
  final screen = MediaQuery.sizeOf(context);
  if (findTargetRect(target, screen: screen) == null) return;
  if (!await st.takeCoach(id)) return;
  if (!context.mounted) return;
  final rect = findTargetRect(target, screen: screen);
  if (rect == null) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: TutorialHe.coachDismiss,
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    pageBuilder: (dialog, _, _) => CoachMarkOverlay(
      target: rect,
      text: text,
      onClose: () => Navigator.of(dialog).pop(),
    ),
    transitionBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
}

class CoachMarkOverlay extends StatelessWidget {
  const CoachMarkOverlay({
    super.key,
    required this.target,
    required this.text,
    required this.onClose,
  });

  final Rect target;
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final size = MediaQuery.sizeOf(context);
    final hole = target.inflate(8);
    // The bubble goes on the side of the screen with more room.
    final below = hole.center.dy < size.height / 2;
    const width = 300.0;
    final left = (hole.center.dx - width / 2).clamp(
      Space.page,
      size.width - width - Space.page,
    );
    return GestureDetector(
      key: const Key('coach-mark'),
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _ScrimPainter(
                hole,
                Colors.black.withValues(alpha: .58),
                p.surface,
              ),
            ),
          ),
          Positioned(
            left: left,
            width: width,
            top: below ? hole.bottom + Space.m : null,
            bottom: below ? null : size.height - hole.top + Space.m,
            child: Semantics(
              liveRegion: true,
              label: '$text. ${TutorialHe.coachDismiss}',
              excludeSemantics: true,
              child: Material(
                color: p.surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(22),
                child: Padding(
                  padding: const EdgeInsets.all(Space.m),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text, style: AppText.body),
                      const SizedBox(height: Space.xs),
                      Text(
                        TutorialHe.coachDismiss,
                        style: AppText.caption.copyWith(color: p.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dim layer with a rounded "hole" over the target.
class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole, this.color, this.ring);

  final Rect hole;
  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()
        ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(24))),
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hole, const Radius.circular(24)),
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.color != color || old.ring != ring;
}
