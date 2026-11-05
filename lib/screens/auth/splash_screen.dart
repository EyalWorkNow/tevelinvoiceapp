import 'package:flutter/material.dart';

import '../../router.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../util/biometric.dart';
import 'app_lock.dart';
import 'auth_flow.dart';
import 'login_screen.dart' show TevelLogo;

/// S0 · Splash: Keychain token → GET /mobile/session (+ /me, profile) →
/// Face ID if enabled → G2 / S2 / home. Offline → home from cache.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _locked = false;
  bool _slow = false;

  Biometric get _bio => Biometric.instance;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _slow = true);
    });
    _start();
  }

  Future<void> _start() async {
    try {
      await session.restore();
    } on Object {
      // Keychain failure → treat as signed out.
    }
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
    return Scaffold(
      backgroundColor: p.charcoal,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TevelLogo(size: 96),
            const SizedBox(height: Space.xl),
            SizedBox.square(
              dimension: 24,
              child: AnimatedOpacity(
                opacity: _slow ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: p.accent, semanticsLabel: 'טוען'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
