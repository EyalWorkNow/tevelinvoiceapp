import 'package:flutter/material.dart';

import '../../router.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../util/biometric.dart';
import 'app_lock.dart';
import 'auth_flow.dart';

/// S0 · Splash: Keychain token → GET /mobile/session (+ /me, profile) →
/// Face ID if enabled → G2 / S2 / home. Offline → home from cache.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  bool _locked = false;
  bool _slow = false;
  late final AnimationController _intro;
  late final AnimationController _pulse;
  late final Stopwatch _visibleFor;

  static const _minimumSplashTime = Duration(milliseconds: 1050);

  Biometric get _bio => Biometric.instance;

  @override
  void initState() {
    super.initState();
    _visibleFor = Stopwatch()..start();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 920),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    )..repeat(reverse: true);
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _slow = true);
    });
    _start();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _finishIntro() async {
    final remaining = _minimumSplashTime - _visibleFor.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  Future<void> _start() async {
    try {
      await session.restore();
    } on Object {
      // Keychain failure → treat as signed out.
    }
    await _finishIntro();
    if (!mounted) return;
    if (session.status != SessionStatus.signedIn) {
      resetToLogin(expired: session.expired);
      return;
    }
    if (await _bio.shouldLock()) {
      if (await _bio.unlock() == UnlockResult.failed) {
        if (mounted) setState(() => _locked = true);
        return;
      }
    }
    if (mounted) await routeSignedIn(context);
  }

  Future<void> _retryUnlock() async {
    if (await _bio.unlock() == UnlockResult.failed || !mounted) return;
    setState(() => _locked = false);
    await routeSignedIn(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return LockView(onUnlock: _retryUnlock, onSignOut: session.signOut);
    }
    final p = context.palette;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: p.charcoal,
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: p.charcoal,
          gradient: RadialGradient(
            center: const Alignment(0, -0.12),
            radius: 1.05,
            colors: [p.surface.withValues(alpha: 0.78), p.charcoal],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_intro, _pulse]),
              builder: (context, _) {
                final entrance = reduceMotion
                    ? 1.0
                    : Curves.easeOutBack.transform(_intro.value);
                final brandProgress = reduceMotion
                    ? 1.0
                    : Curves.easeOutCubic.transform(
                        ((_intro.value - 0.28) / 0.72)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                      );
                final pulse = reduceMotion ? 0.0 : _pulse.value;
                final pulseScale = 0.985 + pulse * 0.025;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: (0.84 + entrance * 0.16) * pulseScale,
                      child: Opacity(
                        opacity: reduceMotion ? 1 : _intro.value,
                        child: Container(
                          width: 264,
                          height: 142,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(72),
                            gradient: RadialGradient(
                              colors: [
                                p.accent.withValues(
                                  alpha: 0.10 + pulse * 0.045,
                                ),
                                p.surface.withValues(alpha: 0.12),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.58, 1],
                            ),
                          ),
                          child: Image.asset(
                            'assets/brand/tevel_logo.png',
                            width: 218,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            semanticLabel: 'תבל',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    Opacity(
                      opacity: brandProgress,
                      child: Transform.translate(
                        offset: Offset(0, (1 - brandProgress) * 8),
                        child: Text(
                          'העסק שלך, מסודר.',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: p.onCharcoalMuted,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.15,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.xl),
                    SizedBox.square(
                      dimension: 22,
                      child: AnimatedOpacity(
                        opacity: _slow ? 1 : 0,
                        duration: const Duration(milliseconds: 240),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: p.accent,
                          semanticsLabel: 'טוען',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
