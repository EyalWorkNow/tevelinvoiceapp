import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../api/settings_api.dart' show rememberAppleSignIn;
import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../ui/widgets/error_view.dart';
import '../../ui/widgets/sheet.dart';
import '../../util/allowed_urls.dart';
import 'auth_flow.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum _Busy { none, apple, password }

/// S1 · Sign-in: Apple, email+password, forgot password.
///
/// No Google button yet: POST /auth/google accepts only a Firebase ID token,
/// so it needs firebase_core + firebase_auth (signInWithCredential →
/// getIdToken), GoogleService-Info.plist and the reversed-client-id URL scheme
/// in Info.plist (APP-STORE.md checklist #10). `signInWithGoogle` in
/// auth_api.dart is ready for that token.
/// [sessionExpired] shows 'פג תוקף ההתחברות'. On success: MFA if needed →
/// `session.completeSignIn()` → route (G2 / S2 / home).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.sessionExpired = false});

  /// Came here because the device token expired / was revoked.
  final bool sessionExpired;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  _Busy _busy = _Busy.none;
  bool _showPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _email.text = 'test@test.com';
      _password.text = '123123123';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _run(_Busy.password, _withPassword);
        }
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Runs one sign-in attempt; provider-specific code only produces the
  /// [SignInResult] (null = the user cancelled the system sheet).
  Future<void> _run(_Busy which, Future<SignInResult?> Function() attempt) async {
    if (_busy != _Busy.none) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      final result = await attempt();
      if (result == null || !mounted) return;
      await finishSignIn(context, result);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.messageHe);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  Future<SignInResult?> _apple() async {
    final AuthorizationCredentialAppleID cred;
    try {
      cred = await SignInWithApple.getAppleIDCredential(
          scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName]);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      _localError('הכניסה עם Apple לא הושלמה — נסו שוב');
      return null;
    } on SignInWithAppleException {
      _localError('הכניסה עם Apple לא זמינה במכשיר הזה');
      return null;
    }
    final token = cred.identityToken;
    if (token == null) {
      _localError('הכניסה עם Apple לא הושלמה — נסו שוב');
      return null;
    }
    final name = [cred.givenName, cred.familyName]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' ');
    final result = await signInWithApple(token, fullName: name);
    await rememberAppleSignIn(); // account deletion must then revoke the Apple grant
    return result;
  }

  Future<SignInResult?> _withPassword() async {
    final email = _email.text.trim();
    if (!isValidEmail(email)) {
      _localError('נא להזין כתובת מייל תקינה');
      return null;
    }
    if (_password.text.isEmpty) {
      _localError('נא להזין סיסמה');
      _passwordFocus.requestFocus();
      return null;
    }
    return signInWithPassword(email, _password.text);
  }

  void _appleTap() {
    if (_busy != _Busy.none) return;
    HapticFeedback.lightImpact();
    _run(_Busy.apple, _apple);
  }

  void _localError(String message) {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idle = _busy == _Busy.none;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.l),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  const SizedBox(height: Space.xl),
                  const Center(child: TevelLogo(size: 72)),
                  const SizedBox(height: Space.xl),
                  const Text('ברוכים הבאים', style: AppText.title, textAlign: TextAlign.center),
                  const SizedBox(height: Space.xs),
                  Text('חשבוניות וקבלות בכמה נגיעות',
                      style: AppText.body.copyWith(color: p.muted), textAlign: TextAlign.center),
                  if (widget.sessionExpired) ...[
                    const SizedBox(height: Space.l),
                    _Notice(
                        icon: Iconsax.security_time,
                        text: 'פג תוקף ההתחברות — נא להיכנס שוב',
                        color: p.warn),
                  ],
                  const SizedBox(height: Space.xl),
                  Semantics(
                    button: true,
                    label: 'המשך עם Apple',
                    excludeSemantics: true,
                    onTap: idle ? _appleTap : null,
                    child: SizedBox(
                      height: Hit.bigButton,
                      child: _busy == _Busy.apple
                          ? _ProviderSpinner(dark: !dark)
                          : SignInWithAppleButton(
                              text: 'המשך עם Apple',
                              height: Hit.bigButton,
                              style: dark
                                  ? SignInWithAppleButtonStyle.white
                                  : SignInWithAppleButtonStyle.black,
                              borderRadius: const BorderRadius.all(Radius.circular(Radii.button)),
                              onPressed: _appleTap,
                            ),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      child: Text('או', style: AppText.caption.copyWith(color: p.muted)),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: Space.xl),
                  TextField(
                    controller: _email,
                    enabled: idle,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _passwordFocus.requestFocus(),
                    decoration: const InputDecoration(labelText: 'אימייל'),
                  ),
                  const SizedBox(height: Space.m),
                  TextField(
                    controller: _password,
                    focusNode: _passwordFocus,
                    enabled: idle,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.go,
                    autofillHints: const [AutofillHints.password],
                    textDirection: TextDirection.ltr,
                    onSubmitted: (_) => _run(_Busy.password, _withPassword),
                    decoration: InputDecoration(
                      labelText: 'סיסמה',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? AuthHe.hidePassword : AuthHe.showPassword,
                        icon: Icon(_showPassword
                            ? Iconsax.eye_slash
                            : Iconsax.eye),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: idle ? () => showForgotPasswordSheet(context, _email.text) : null,
                      child: const Text(AuthHe.forgotPassword),
                    ),
                  ),
                  if (_error != null) ...[
                    _Notice(icon: Iconsax.danger, text: _error!, color: p.danger),
                    const SizedBox(height: Space.m),
                  ],
                  BigButton(
                    label: AuthHe.signIn,
                    loading: _busy == _Busy.password,
                    onPressed: idle ? () => _run(_Busy.password, _withPassword) : null,
                  ),
                  const SizedBox(height: Space.xl),
                  const _LegalLinks(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand mark: lime "תבל" on a charcoal rounded square (no image asset yet).
class TevelLogo extends StatelessWidget {
  const TevelLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'תבל',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.charcoal,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: p.accent.withValues(alpha: 0.25)),
        ),
        child: FittedBox(
          child: Padding(
            padding: EdgeInsets.all(size * 0.14),
            child: Image.asset('assets/brand/tevel_mark.png',
                width: size, height: size, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }
}

class _ProviderSpinner extends StatelessWidget {
  const _ProviderSpinner({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: dark ? Colors.white : Colors.black),
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: Space.s),
              Expanded(child: Text(text, style: AppText.body.copyWith(color: color))),
            ],
          ),
        ),
      );
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = TextButton.styleFrom(
      minimumSize: const Size(Hit.min, Hit.min),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      textStyle: AppText.caption.copyWith(decoration: TextDecoration.underline),
    );
    // The Hebrew prefixes (ל / ול) live inside the links so they never split.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('בכניסה את/ה מסכים/ה', style: AppText.caption.copyWith(color: p.muted)),
        TextButton(
            style: link, onPressed: () => openSafari(Uri.parse(termsUrl)), child: const Text(AuthHe.termsLink)),
        TextButton(
            style: link,
            onPressed: () => openSafari(Uri.parse(privacyUrl)),
            child: const Text(AuthHe.privacyLink)),
      ],
    );
  }
}

/// "שכחתי סיסמה": always the same answer (no account enumeration); the reset
/// link opens the web app.
Future<void> showForgotPasswordSheet(BuildContext context, String prefill) =>
    showAppSheet<void>(context, builder: (_) => _ForgotPassword(prefill: prefill));

class _ForgotPassword extends StatefulWidget {
  const _ForgotPassword({required this.prefill});

  final String prefill;

  @override
  State<_ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<_ForgotPassword> {
  late final _email = TextEditingController(text: widget.prefill.trim());
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = 'נא להזין כתובת מייל תקינה');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await requestPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = errorTextHe(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_sent) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Iconsax.sms_tracking, size: 48, color: p.ok),
          const SizedBox(height: Space.l),
          const SheetTitle('בדקו את המייל',
              subtitle: 'אם החשבון קיים, נשלח אליו מייל עם קישור לבחירת סיסמה חדשה.'),
          BigButton(label: AuthHe.gotIt, onPressed: () => Navigator.of(context).pop()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle('איפוס סיסמה', subtitle: 'נשלח קישור לבחירת סיסמה חדשה'),
        TextField(
          controller: _email,
          autofocus: widget.prefill.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(labelText: 'אימייל', errorText: _error),
        ),
        const SizedBox(height: Space.l),
        BigButton(label: AuthHe.sendResetLink, loading: _sending, onPressed: _send),
      ],
    );
  }
}
