// Release replacement for the grey ErrorWidget (QA 2026-11-15): a small
// Hebrew card with one way out, instead of a dead grey screen.

import 'package:flutter/material.dart';

import '../../router.dart' show navigatorKey, resetToHome, resetToLogin;
import '../../state/session.dart';

const String safeErrorTitle = 'משהו השתבש';
const String safeErrorBack = 'חזור';

/// ErrorWidget.builder for release builds (main.dart).
Widget safeErrorWidget(FlutterErrorDetails details) => const SafeErrorCard();

/// Back to a known-good screen: the root of the stack, or a fresh shell /
/// sign-in when the root itself is broken.
void leaveBrokenScreen() {
  final nav = navigatorKey.currentState;
  if (nav != null && nav.canPop()) {
    nav.popUntil((r) => r.isFirst);
  } else if (session.status == SessionStatus.signedIn) {
    resetToHome();
  } else {
    resetToLogin();
  }
}

class SafeErrorCard extends StatelessWidget {
  const SafeErrorCard({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    // Built where the failing widget was: there may be no theme,
    // Directionality or Material above it.
    textDirection: TextDirection.rtl,
    child: ColoredBox(
      color: const Color(0xFF1C1520),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                safeErrorTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 17,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                key: const Key('safe-error-back'),
                behavior: HitTestBehavior.opaque,
                onTap: leaveBrokenScreen,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 120,
                    minHeight: 44,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6BDF1),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Text(
                    safeErrorBack,
                    style: TextStyle(
                      color: Color(0xFF302138),
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
