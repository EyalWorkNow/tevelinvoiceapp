import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../router.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../util/biometric.dart';
import 'login_screen.dart' show TevelLogo;
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Wraps the whole app (MaterialApp.builder) — spec §11:
/// * app-switcher privacy cover while the app is inactive/backgrounded
///   (amounts never show in the app switcher);
/// * Face ID / passcode lock after [Biometric.lockAfter] in the background;
/// * a bearer token refused with 403 MFA_REQUIRED (role became privileged)
///   → sign in again (API-MOBILE §5 phase 2).
///
/// Integrator hook in main.dart (MaterialApp):
///   `builder: (context, child) => AppLockGate(child: child!),`
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.lockAfter = Biometric.lockAfter,
  });

  final Widget child;

  /// Background time before Face ID is required again.
  final Duration lockAfter;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _covered = false;
  bool _locked = false;
  bool _prompting = false;
  DateTime? _backgroundAt;
  StreamSubscription<ApiEvent>? _events;

  Biometric get _bio => Biometric.instance;
  bool get _signedIn => session.status == SessionStatus.signedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session.addListener(_onSession);
    _events = ApiClient.instance.events.listen(_onApiEvent);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(_onSession);
    _events?.cancel();
    super.dispose();
  }

  void _onSession() {
    if (!_signedIn && (_locked || _covered)) {
      setState(() {
        _locked = false;
        _covered = false;
      });
    }
  }

  Future<void> _onApiEvent(ApiEvent event) async {
    if (event != ApiEvent.mfaRequired ||
        !_signedIn ||
        !ApiClient.instance.hasDeviceToken) {
      return;
    }
    await session.signOutLocally();
    resetToLogin(expired: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_prompting) return; // the Face ID sheet itself makes the app inactive
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (state != AppLifecycleState.inactive) {
          _backgroundAt ??= DateTime.now();
        }
        if (_signedIn && !_covered) setState(() => _covered = true);
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onResumed() async {
    final away = _backgroundAt;
    _backgroundAt = null;
    final due =
        away != null && DateTime.now().difference(away) >= widget.lockAfter;
    if (_signedIn && (due || _locked) && await _bio.shouldLock()) {
      if (!mounted) return;
      setState(() => _locked = true);
      await _unlock();
    } else if (mounted && _covered) {
      setState(() => _covered = false);
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final result = await _bio.unlock();
    _prompting = false;
    if (!mounted) return;
    if (result != UnlockResult.failed) {
      setState(() {
        _locked = false;
        _covered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Covered content must not reach VoiceOver (it would read and tap
        // through the lock) nor keep animating underneath.
        ExcludeSemantics(
          excluding: _locked || _covered,
          child: TickerMode(
            enabled: !_locked && !_covered,
            child: widget.child,
          ),
        ),
        if (_locked)
          LockView(onUnlock: _unlock, onSignOut: session.signOut)
        else if (_covered)
          const PrivacyCover(),
      ],
    );
  }
}

/// Plain brand cover for the app switcher snapshot.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.palette.charcoal,
    child: const Center(child: TevelLogo(size: 96)),
  );
}

/// Locked: Face ID / passcode button + sign-out escape hatch.
class LockView extends StatefulWidget {
  const LockView({super.key, required this.onUnlock, required this.onSignOut});

  final Future<void> Function() onUnlock;
  final Future<void> Function() onSignOut;

  @override
  State<LockView> createState() => _LockViewState();
}

class _LockViewState extends State<LockView> {
  String _method = 'Face ID';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Biometric.instance.methodLabel().then((m) {
      if (mounted) setState(() => _method = m);
    });
  }

  Future<void> _tap() async {
    setState(() => _busy = true);
    await widget.onUnlock();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.charcoal,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            children: [
              const Spacer(),
              const TevelLogo(size: 96),
              const SizedBox(height: Space.xl),
              Icon(Iconsax.lock, color: p.accent, size: 28),
              const SizedBox(height: Space.s),
              Text(
                'תבל נעולה',
                style: AppText.title.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              BigButton(
                label: AuthHe.unlockWith(_method),
                icon: Iconsax.smileys,
                loading: _busy,
                onPressed: _tap,
              ),
              const SizedBox(height: Space.m),
              TextButton(
                onPressed: _busy ? null : widget.onSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(Hit.min, Hit.min),
                ),
                child: const Text(AuthHe.lockSignOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
