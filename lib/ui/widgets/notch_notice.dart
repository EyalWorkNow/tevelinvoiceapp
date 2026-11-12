import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Visual language for existing action feedback; no system notification access.
enum NoticeMotion {
  saved,
  document,
  sent,
  signed,
  payment,
  reminder,
  error,
  approved,
}

final notchNoticeKey = GlobalKey<NotchNoticeHostState>();

extension NotchMessenger on ScaffoldMessengerState {
  void clearNotchNotices() {
    notchNoticeKey.currentState?.clear();
    clearSnackBars();
  }

  void hideCurrentNotchNotice() {
    notchNoticeKey.currentState?.clear();
    hideCurrentSnackBar();
  }

  /// Keeps the existing snackbar content/action and the native fallback.
  void showNotchNotice(
    SnackBar notice, {
    NoticeMotion motion = NoticeMotion.saved,
  }) {
    final host = notchNoticeKey.currentState;
    if (defaultTargetPlatform != TargetPlatform.iOS || host == null) {
      showSnackBar(notice);
      return;
    }
    host.show(notice, motion: motion);
  }
}

class _Notice {
  const _Notice(this.bar, this.motion);
  final SnackBar bar;
  final NoticeMotion motion;
}

/// Lives above the Navigator so feedback survives sheets and route changes.
class NotchNoticeHost extends StatefulWidget {
  const NotchNoticeHost({super.key, required this.child});
  final Widget child;

  @override
  State<NotchNoticeHost> createState() => NotchNoticeHostState();
}

class NotchNoticeHostState extends State<NotchNoticeHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _expand = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
    reverseDuration: const Duration(milliseconds: 280),
  );
  late final _ink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  final _queue = Queue<_Notice>();
  _Notice? _active;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void show(SnackBar bar, {NoticeMotion motion = NoticeMotion.saved}) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _queue.add(_Notice(bar, motion));
    if (_active == null) _next();
  }

  void _next() {
    if (!mounted || _queue.isEmpty) return;
    setState(() => _active = _queue.removeFirst());
    final reduce = MediaQuery.disableAnimationsOf(context);
    _expand.forward(from: reduce ? 1 : 0);
    _ink.forward(from: reduce ? 1 : 0);
    if (!reduce) HapticFeedback.lightImpact();
    _active!.bar.onVisible?.call();
    final accessible = MediaQuery.accessibleNavigationOf(context);
    // Actions remain available to VoiceOver users until explicitly dismissed.
    if (!accessible || _active!.bar.action == null) {
      final requested = _active!.bar.duration;
      _timer = Timer(
        requested < const Duration(seconds: 5)
            ? const Duration(seconds: 5)
            : requested,
        dismiss,
      );
    }
  }

  void clear() {
    _timer?.cancel();
    _queue.clear();
    _expand.stop();
    _ink.stop();
    _closing = false;
    setState(() => _active = null);
  }

  Future<void> dismiss() async {
    if (_active == null || _closing) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) {
      await _expand.reverse();
    }
    if (!mounted) return;
    setState(() => _active = null);
    _closing = false;
    _next();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _expand.dispose();
    _ink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = _active;
    final width = math.min(MediaQuery.sizeOf(context).width - 32, 380.0);
    final content = notice?.bar.content;
    final text = content is Text
        ? TextPainter(
            text: TextSpan(
              text: content.data,
              children: [if (content.textSpan != null) content.textSpan!],
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )
        : null;
    text?.layout(maxWidth: width - 148);
    final height = math.max(
      142.0,
      54 + (text?.height ?? 60.0) + (notice?.bar.action == null ? 0 : 44),
    );
    text?.dispose();
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (notice != null)
          Positioned(
            top:
                MediaQuery.orientationOf(context) == Orientation.portrait &&
                    MediaQuery.viewPaddingOf(context).top >= 44
                ? 11
                : MediaQuery.viewPaddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedBuilder(
                animation: Listenable.merge([_expand, _ink]),
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(_expand.value);
                  final recoil =
                      math.sin(_expand.value * math.pi * 2) *
                      .018 *
                      (1 - _expand.value);
                  final glow = math.sin(_ink.value * math.pi);
                  return Transform.scale(
                    scaleX: 1 + recoil,
                    scaleY: 1 - recoil,
                    alignment: Alignment.topCenter,
                    child: GestureDetector(
                      onVerticalDragEnd: (details) {
                        if ((details.primaryVelocity ?? 0) < -80) dismiss();
                      },
                      child: Container(
                        key: const Key('notch-notice'),
                        width: 126 + (width - 126) * t,
                        height: 37 + (height - 37) * t,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(27 + 9 * t),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .12 * t),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent(
                                notice.motion,
                              ).withValues(alpha: .14 * glow * t),
                              blurRadius: 28 + 14 * glow,
                              spreadRadius: -3,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .28 * t),
                              blurRadius: 22,
                              offset: const Offset(0, 9),
                            ),
                          ],
                        ),
                        child: CustomPaint(
                          foregroundPainter: _IslandAura(
                            _accent(notice.motion),
                            _ink.value,
                          ),
                          child: OverflowBox(
                            alignment: Alignment.topCenter,
                            maxWidth: width,
                            minWidth: width,
                            maxHeight: height,
                            minHeight: height,
                            child: Opacity(
                              opacity: ((t - .35) / .65).clamp(0, 1),
                              child: _NoticeBody(
                                notice: notice,
                                progress: _ink.value,
                                onClose: dismiss,
                                onAction: () {
                                  if (_closing) return;
                                  dismiss();
                                  notice.bar.action?.onPressed();
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

Color _accent(NoticeMotion motion) => switch (motion) {
  NoticeMotion.saved ||
  NoticeMotion.payment ||
  NoticeMotion.approved => DesignTokens.green,
  NoticeMotion.document || NoticeMotion.signed => DesignTokens.lavender,
  NoticeMotion.sent => DesignTokens.yellow,
  NoticeMotion.reminder => DesignTokens.pink,
  NoticeMotion.error => DesignTokens.coral,
};

class _NoticeBody extends StatelessWidget {
  const _NoticeBody({
    required this.notice,
    required this.progress,
    required this.onClose,
    required this.onAction,
  });
  final _Notice notice;
  final double progress;
  final VoidCallback onClose;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = _accent(notice.motion);
    final action = notice.bar.action;
    return Material(
      color: Colors.transparent,
      child: Padding(
        // Leave the physical camera cutout completely clear.
        padding: const EdgeInsets.fromLTRB(18, 42, 18, 12),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 64,
                child: CustomPaint(
                  key: ValueKey(notice.motion),
                  painter: _NoticeGlyph(notice.motion, color, progress),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        fontFamily: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.fontFamily,
                      ),
                      overflow: TextOverflow.ellipsis,
                      child: notice.bar.content,
                    ),
                    if (action != null)
                      SizedBox(
                        height: 44,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: color,
                            alignment: AlignmentDirectional.centerStart,
                          ),
                          onPressed: onAction,
                          child: Text(action.label),
                        ),
                      ),
                  ],
                ),
              ),
              Semantics(
                label: MaterialLocalizations.of(context).closeButtonTooltip,
                child: IconButton(
                  onPressed: onClose,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A finite light sweep and small energy marks, below the physical camera.
class _IslandAura extends CustomPainter {
  const _IslandAura(this.color, this.progress);
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height < 90 || progress >= 1) return;
    final pulse = math.sin(progress * math.pi);
    final y = size.height - 8;
    final x = 28 + (size.width - 56) * progress;
    final rect = Rect.fromLTWH(x - 34, y - 1, 68, 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: pulse * .9),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
    for (final direction in [-1.0, 1.0]) {
      final center = Offset(
        size.width / 2 + direction * (30 + 100 * progress),
        y - 5,
      );
      canvas.drawCircle(
        center,
        1.2,
        Paint()..color = color.withValues(alpha: pulse * .45),
      );
    }
  }

  @override
  bool shouldRepaint(_IslandAura old) =>
      old.progress != progress || old.color != color;
}

/// Choreographed in three beats: anticipation, action, and a settling flourish.
class _NoticeGlyph extends CustomPainter {
  const _NoticeGlyph(this.motion, this.color, this.progress);
  final NoticeMotion motion;
  final Color color;
  final double progress;

  double _phase(double start, double end) =>
      ((progress - start) / (end - start)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final arrive = Curves.easeOutBack.transform(_phase(.05, .55));
    final ink = Curves.easeOutCubic.transform(_phase(.18, .72));
    final flourish = _phase(.38, .95);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final halo = Rect.fromCircle(center: Offset.zero, radius: 25);
    canvas.drawCircle(
      Offset.zero,
      25,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: .20), color.withValues(alpha: .035)],
        ).createShader(halo),
    );

    switch (motion) {
      case NoticeMotion.document:
        // A page feeds out, lines print, then the seal lands with a little kick.
        canvas.save();
        canvas.translate(0, 16 * (1 - arrive));
        canvas.rotate(-.22 * (1 - arrive));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-12, -18, 24, 32),
            const Radius.circular(4),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, -18)
            ..lineTo(4, -10)
            ..lineTo(12, -10),
          paint,
        );
        for (var i = 0; i < 3; i++) {
          final line = ((_phase(.15, .6) * 3) - i).clamp(0.0, 1.0);
          canvas.drawLine(
            Offset(-7, -5 + i * 6),
            Offset(-7 + 13 * line, -5 + i * 6),
            paint,
          );
        }
        canvas.restore();
        final stamp = Curves.elasticOut.transform(_phase(.40, .85));
        canvas.save();
        canvas.translate(10, 12);
        canvas.scale(.2 + .8 * stamp);
        _check(canvas, ink, paint, radius: 10);
        canvas.restore();
        _sparks(canvas, flourish, paint);
      case NoticeMotion.sent:
        // Bank into a curved flight path; the contrail dissolves behind it.
        final fly = Curves.easeInOutCubic.transform(_phase(.06, .60));
        final trail = Path()
          ..moveTo(-24, 18)
          ..cubicTo(-6, 26, -24, -13, 8, -8);
        canvas.drawPath(
          trail,
          Paint()
            ..color = color.withValues(alpha: .55 * (1 - flourish))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
        canvas.save();
        canvas.translate(-20 * (1 - fly), 18 * (1 - fly));
        canvas.rotate(-.55 * math.sin(fly * math.pi));
        canvas.scale(.65 + .35 * arrive);
        canvas.drawPath(
          Path()
            ..moveTo(-16, -2)
            ..lineTo(16, -14)
            ..lineTo(5, 17)
            ..lineTo(-1, 4)
            ..close(),
          paint,
        );
        canvas.drawLine(const Offset(-1, 4), const Offset(16, -14), paint);
        canvas.restore();
        _sparks(canvas, flourish, paint, count: 5);
      case NoticeMotion.signed:
        // The nib follows the actual signature instead of merely fading in.
        final path = Path()
          ..moveTo(-20, 8)
          ..cubicTo(-3, -25, 12, -15, -6, 4)
          ..cubicTo(-15, 20, 4, -5, 5, 3)
          ..quadraticBezierTo(9, 14, 20, -4);
        final metric = path.computeMetrics().first;
        canvas.drawPath(metric.extractPath(0, metric.length * ink), paint);
        if (ink < 1) {
          final nib = metric.getTangentForOffset(metric.length * ink);
          if (nib != null) {
            canvas.save();
            canvas.translate(nib.position.dx, nib.position.dy);
            canvas.rotate(-.6);
            canvas.drawPath(
              Path()
                ..moveTo(0, 0)
                ..lineTo(-3, -8)
                ..lineTo(3, -8)
                ..close(),
              Paint()
                ..color = color
                ..style = PaintingStyle.fill,
            );
            canvas.restore();
          }
        }
        canvas.drawLine(
          const Offset(-18, 18),
          Offset(-18 + 36 * _phase(.62, .9), 18),
          paint
            ..strokeWidth = 1
            ..color = color.withValues(alpha: .6),
        );
        _sparks(canvas, flourish, Paint()..color = color, count: 4);
      case NoticeMotion.payment:
        // A spinning coin drops, squashes at impact, and releases a small burst.
        final flip = _phase(.05, .62);
        canvas.save();
        canvas.translate(0, -24 * (1 - arrive));
        canvas.scale(
          .18 + .82 * math.cos(flip * math.pi * 3).abs(),
          1 + math.sin(arrive * math.pi) * .08,
        );
        canvas.drawCircle(
          Offset.zero,
          17,
          Paint()..color = color.withValues(alpha: .13),
        );
        canvas.drawCircle(Offset.zero, 17, paint);
        canvas.drawArc(
          const Rect.fromLTWH(-13, -13, 26, 26),
          -1.8,
          1.1,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        final text = TextPainter(
          text: TextSpan(
            text: '₪',
            style: TextStyle(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
        text.dispose();
        canvas.restore();
        _sparks(canvas, flourish, paint, count: 9);
      case NoticeMotion.reminder:
        // A weighted bell swings from its top, with two traveling sound waves.
        final ring = _phase(.08, .78);
        canvas.save();
        canvas.translate(0, -15);
        canvas.rotate(math.sin(ring * math.pi * 7) * .42 * (1 - ring));
        canvas.translate(0, 15);
        canvas.drawPath(
          Path()
            ..moveTo(-13, 9)
            ..lineTo(-10, 4)
            ..lineTo(-10, -5)
            ..cubicTo(-10, -20, 10, -20, 10, -5)
            ..lineTo(10, 4)
            ..lineTo(13, 9)
            ..close(),
          paint,
        );
        canvas.drawArc(
          const Rect.fromLTWH(-4, 10, 8, 8),
          0,
          math.pi,
          false,
          paint,
        );
        canvas.restore();
        for (var i = 0; i < 2; i++) {
          final wave = (_phase(.15, .85) * 2 - i * .5).clamp(0.0, 1.0);
          final rect = Rect.fromCircle(
            center: const Offset(0, -3),
            radius: 17 + wave * 10,
          );
          final wavePaint = Paint()
            ..color = color.withValues(alpha: math.sin(wave * math.pi) * .7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawArc(rect, -.7, 1.1, false, wavePaint);
          canvas.drawArc(rect, math.pi - .4, 1.1, false, wavePaint);
        }
      case NoticeMotion.error:
        final shake = _phase(.12, .7);
        canvas.translate(math.sin(shake * math.pi * 7) * 6 * (1 - shake), 0);
        canvas.drawArc(
          Rect.fromCircle(center: Offset.zero, radius: 17),
          -.8,
          math.pi * 2 * ink,
          false,
          paint,
        );
        canvas.drawLine(const Offset(0, -9), const Offset(0, 3), paint);
        canvas.drawCircle(const Offset(0, 10), 1, Paint()..color = color);
      // The warning settles into a calm, legible state.
      case NoticeMotion.saved:
        canvas.save();
        canvas.scale(.4 + .6 * arrive);
        _check(canvas, ink, paint, radius: 17);
        canvas.restore();
        _sparks(canvas, flourish, paint, count: 6);
      case NoticeMotion.approved:
        // Approval has its own celebratory seal, distinct from document signing.
        canvas.save();
        canvas.rotate((1 - arrive) * -.45);
        canvas.scale(.3 + .7 * arrive);
        final seal = Path();
        for (var i = 0; i < 24; i++) {
          final angle = -math.pi / 2 + i * math.pi / 12;
          final radius = i.isEven ? 20.0 : 17.0;
          final point = Offset(
            math.cos(angle) * radius,
            math.sin(angle) * radius,
          );
          if (i == 0) {
            seal.moveTo(point.dx, point.dy);
          } else {
            seal.lineTo(point.dx, point.dy);
          }
        }
        seal.close();
        canvas.drawPath(seal, Paint()..color = color.withValues(alpha: .15));
        canvas.drawPath(seal, paint);
        _check(canvas, ink, paint, radius: 11);
        canvas.restore();
        _sparks(canvas, flourish, paint, count: 10);
    }
  }

  void _sparks(Canvas canvas, double t, Paint paint, {int count = 7}) {
    final alpha = math.sin(t * math.pi);
    if (alpha <= 0) return;
    for (var i = 0; i < count; i++) {
      final angle = i * math.pi * 2 / count - .7;
      final radius = 16 + 12 * Curves.easeOutCubic.transform(t);
      final at = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      final spark = Paint()
        ..color = (i.isEven ? color : Colors.white).withValues(
          alpha: alpha * .85,
        )
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final delta = Offset(math.cos(angle) * 2, math.sin(angle) * 2);
      canvas.drawLine(at - delta, at + delta, spark);
    }
  }

  void _check(Canvas canvas, double p, Paint paint, {double radius = 9}) {
    canvas.drawCircle(Offset.zero, radius, Paint()..color = Colors.black);
    canvas.drawCircle(Offset.zero, radius, paint);
    final path = Path()
      ..moveTo(-radius * .45, 0)
      ..lineTo(-radius * .08, radius * .35)
      ..lineTo(radius * .5, -radius * .35);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * p), paint);
  }

  @override
  bool shouldRepaint(_NoticeGlyph old) =>
      old.progress != progress || old.motion != motion || old.color != color;
}
