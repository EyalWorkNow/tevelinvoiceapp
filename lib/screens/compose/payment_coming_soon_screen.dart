import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/ds.dart';

/// Placeholder for payment requests; no document is issued by this flow.
class PaymentComingSoonScreen extends StatelessWidget {
  const PaymentComingSoonScreen({super.key, this.onReturnHome});

  final VoidCallback? onReturnHome;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(Space.page),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: DesignBackButton(),
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: context.motion(650),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: child,
                            ),
                          ),
                          child: const ExcludeSemantics(
                            child: SizedBox.square(
                              dimension: 264,
                              child: CustomPaint(
                                painter: _PaymentIllustration(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'בקרוב',
                          key: const Key('payment-coming-soon'),
                          style: AppText.displayTitle.copyWith(fontSize: 42),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'דרך חדשה לבקש תשלום',
                          style: AppText.title,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'אנחנו מכינים לכם דרך פשוטה ונוחה לקבל תשלום. עוד קצת, וזה כאן.',
                          style: AppText.body.copyWith(
                            color: context.palette.muted,
                            height: 1.6,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: 240,
                          child: FilledButton(
                            key: const Key('payment-coming-soon-back'),
                            onPressed:
                                onReturnHome ??
                                () => Navigator.of(
                                  context,
                                ).popUntil((route) => route.isFirst),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 56),
                              backgroundColor: DesignTokens.lavender,
                              foregroundColor: const Color(0xFF302138),
                            ),
                            child: const Text('חזרה', style: AppText.button),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Vector artwork stays crisp at every device scale without another asset.
class _PaymentIllustration extends CustomPainter {
  const _PaymentIllustration();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 264);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(
      const Offset(132, 132),
      108,
      paint..color = DesignTokens.lavender.withValues(alpha: .08),
    );
    canvas.save();
    canvas.translate(132, 138);
    canvas.rotate(-.35);
    canvas.drawOval(
      const Rect.fromLTWH(-126, -62, 252, 124),
      paint
        ..color = DesignTokens.lavender.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
    paint.style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(132, 128);
    canvas.rotate(-.14);
    final card = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-84, -54, 168, 108),
      const Radius.circular(21),
    );
    canvas.drawShadow(Path()..addRRect(card), Colors.black, 15, false);
    paint.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEBDCFB), DesignTokens.lavender, Color(0xFFA88ACD)],
    ).createShader(card.outerRect);
    canvas.drawRRect(card, paint);
    paint.shader = null;
    paint.color = const Color(0xFF493353);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-65, -33, 28, 22),
        const Radius.circular(6),
      ),
      paint..color = const Color(0xFFFFF3BC),
    );
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-64 + i * 40, 18, 27, 5),
          const Radius.circular(3),
        ),
        paint..color = const Color(0xFF715782).withValues(alpha: .5),
      );
    }
    canvas.drawCircle(
      const Offset(48, -22),
      12,
      paint..color = Colors.white.withValues(alpha: .55),
    );
    canvas.drawCircle(
      const Offset(60, -22),
      12,
      paint..color = Colors.white.withValues(alpha: .3),
    );
    canvas.restore();

    canvas.drawCircle(
      const Offset(205, 181),
      33,
      paint..color = const Color(0xFF487C61),
    );
    canvas.drawCircle(
      const Offset(205, 177),
      33,
      paint..color = DesignTokens.green,
    );
    final text = TextPainter(
      text: const TextSpan(
        text: '₪',
        style: TextStyle(
          fontSize: 34,
          color: Color(0xFF30513D),
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(205 - text.width / 2, 177 - text.height / 2));

    for (final (center, radius, color) in [
      (const Offset(204, 52), 12.0, DesignTokens.yellow),
      (const Offset(40, 192), 8.0, DesignTokens.lavender),
    ]) {
      final star = Path();
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final length = i.isEven ? radius : radius * .3;
        final x = center.dx + math.cos(angle) * length;
        final y = center.dy + math.sin(angle) * length;
        if (i == 0) {
          star.moveTo(x, y);
        } else {
          star.lineTo(x, y);
        }
      }
      canvas.drawPath(star..close(), paint..color = color);
    }
    canvas.drawCircle(
      const Offset(66, 52),
      4,
      paint..color = DesignTokens.green,
    );
    canvas.drawCircle(
      const Offset(137, 231),
      3,
      paint..color = DesignTokens.yellow,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaymentIllustration oldDelegate) => false;
}
