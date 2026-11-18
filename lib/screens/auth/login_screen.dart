import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../api/supabase_auth.dart';
import '../../router.dart' show navigatorKey;
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../ui/widgets/error_view.dart';
import '../../ui/widgets/sheet.dart';
import '../../util/allowed_urls.dart';
import 'auth_flow.dart';
import 'contact_tevel.dart';
import 'password_recovery.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum _Busy { none, password }

/// S1 · Sign-in: e-mail + password and "שכחתי סיסמה" only.
///
/// Every account is opened by the Tevel team after a short conversation
/// (admin console → "משתמש חדש": confirmed Supabase user, a password the
/// team sets, and the business). So there is no Apple / Google sign-in and
/// no self sign-up here; people without an account get "אין לך חשבון?
/// דברו איתנו" (WhatsApp / e-mail). [sessionExpired] shows 'פג תוקף
/// ההתחברות'. On success: MFA if needed → `session.completeSignIn()` → route
/// (G2 / S2 / home), then once per account on this device a gentle,
/// optional "החלף סיסמה" suggestion (the first password was set for them).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.sessionExpired = false,
    this.mfaRequired = false,
    this.email,
  });

  /// Came here because the device token expired / was revoked.
  final bool sessionExpired;

  /// Came here because the membership now needs two-step verification and
  /// this device signed in without it (#14): says so instead of "expired".
  final bool mfaRequired;

  /// Prefilled e-mail (the account that was just signed in).
  final String? email;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  _Busy _busy = _Busy.none;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Runs one sign-in attempt; provider-specific code only produces the
  /// [SignInResult] (null = the user cancelled the system sheet).
  Future<void> _run(
    _Busy which,
    Future<SignInResult?> Function() attempt, {
    bool typedPassword = false,
  }) async {
    if (_busy != _Busy.none) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final result = await attempt();
      if (result == null || !mounted) return;
      final signedIn = await finishSignIn(context, result);
      if (signedIn && typedPassword) {
        unawaited(suggestPasswordChange(email));
      }
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.messageHe);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
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

  /// Recovery with Supabase ends signed in: finish like any other sign-in.
  Future<void> _forgot() async {
    final result = await showForgotPasswordSheet(context, _email.text);
    if (result != null && mounted) {
      await _run(_Busy.password, () async => result);
    }
  }

  void _localError(String message) {
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final idle = _busy == _Busy.none;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.xl,
                  Space.xl,
                  Space.xl,
                  Space.l,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  const SizedBox(height: Space.xl),
                  Center(
                    child: Image.asset(
                      'assets/brand/tevel_logo.png',
                      width: 220,
                      height: 66,
                      fit: BoxFit.contain,
                      semanticLabel: 'תבל',
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  const Text(
                    'ברוכים הבאים',
                    style: AppText.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'חשבוניות וקבלות בכמה נגיעות',
                    style: AppText.body.copyWith(color: p.muted),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.mfaRequired) ...[
                    const SizedBox(height: Space.l),
                    _Notice(
                      key: const Key('login-mfa-notice'),
                      icon: Iconsax.shield_tick,
                      text: BusinessHe.signInAgainForMfa,
                      color: p.warn,
                    ),
                  ] else if (widget.sessionExpired) ...[
                    const SizedBox(height: Space.l),
                    _Notice(
                      icon: Iconsax.security_time,
                      text: 'פג תוקף ההתחברות — נא להיכנס שוב',
                      color: p.warn,
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  TextField(
                    controller: _email,
                    enabled: idle,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
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
                    onSubmitted: (_) => _run(
                      _Busy.password,
                      _withPassword,
                      typedPassword: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'סיסמה',
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? AuthHe.hidePassword
                            : AuthHe.showPassword,
                        icon: Icon(
                          _showPassword ? Iconsax.eye_slash : Iconsax.eye,
                        ),
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: idle ? _forgot : null,
                      child: const Text(AuthHe.forgotPassword),
                    ),
                  ),
                  if (_error != null) ...[
                    _Notice(
                      icon: Iconsax.danger,
                      text: _error!,
                      color: p.danger,
                    ),
                    const SizedBox(height: Space.m),
                  ],
                  BigButton(
                    label: AuthHe.signIn,
                    loading: _busy == _Busy.password,
                    onPressed: idle
                        ? () => _run(
                            _Busy.password,
                            _withPassword,
                            typedPassword: true,
                          )
                        : null,
                  ),
                  const SizedBox(height: Space.l),
                  const NoAccountCta(),
                  const SizedBox(height: Space.l),
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
            child: Image.asset(
              'assets/brand/tevel_mark.png',
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.m,
        vertical: Space.m,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(text, style: AppText.body.copyWith(color: color)),
          ),
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
        Text(
          'בכניסה את/ה מסכים/ה',
          style: AppText.caption.copyWith(color: p.muted),
        ),
        TextButton(
          style: link,
          onPressed: () => openSafari(Uri.parse(termsUrl)),
          child: const Text(AuthHe.termsLink),
        ),
        TextButton(
          style: link,
          onPressed: () => openSafari(Uri.parse(privacyUrl)),
          child: const Text(AuthHe.privacyLink),
        ),
      ],
    );
  }
}

/// "שכחתי סיסמה": always the same answer (no account enumeration). With
/// Supabase Auth: a code by e-mail, then a new password in the app
/// (password_recovery.dart); returns the sign-in result for the caller to
/// finish ([signIn] false: only the password changes). Without Supabase: the
/// Tevel reset link, which opens the web app.
Future<SignInResult?> showForgotPasswordSheet(
  BuildContext context,
  String prefill, {
  bool signIn = true,
}) => showAppSheet<SignInResult>(
  context,
  builder: (_) => supabaseAuth.enabled
      ? PasswordRecoveryFlow(prefill: prefill, signIn: signIn)
      : _ForgotPassword(prefill: prefill),
);

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
          const SheetTitle(
            'בדקו את המייל',
            subtitle:
                'אם החשבון קיים, נשלח אליו מייל עם קישור לבחירת סיסמה חדשה.',
          ),
          BigButton(
            label: AuthHe.gotIt,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle(
          'איפוס סיסמה',
          subtitle: 'נשלח קישור לבחירת סיסמה חדשה',
        ),
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
        BigButton(
          label: AuthHe.sendResetLink,
          loading: _sending,
          onPressed: _send,
        ),
      ],
    );
  }
}

/// Key of "the change-password suggestion was shown" for [email].
String _suggestedKey(String email) =>
    'password_change_suggested:${email.trim().toLowerCase()}';

const _suggestPrefs = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

/// After a password sign-in, once per account on this device: the Tevel team
/// set that first password, so suggest (never require) a password of their
/// own. "החלף סיסמה" runs the "שכחתי סיסמה" flow without signing in again
/// (a code by e-mail → new password). The server has no "must change
/// password" flag; this is the gentle alternative.
Future<void> suggestPasswordChange(String email) async {
  if (email.isEmpty) return;
  try {
    if (await _suggestPrefs.read(key: _suggestedKey(email)) == '1') return;
    await _suggestPrefs.write(key: _suggestedKey(email), value: '1');
  } on Object {
    return; // no storage → never nag on every sign-in
  }
  await WidgetsBinding.instance.endOfFrame;
  final context = navigatorKey.currentContext;
  if (context == null ||
      !context.mounted ||
      session.status != SessionStatus.signedIn ||
      session.business == null) {
    return;
  }
  final change = await showAppSheet<bool>(
    context,
    builder: (sheet) => Column(
      key: const Key('password-change-suggestion'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Iconsax.key, size: 48, color: sheet.palette.info),
        const SizedBox(height: Space.l),
        const SheetTitle(
          AuthHe.suggestPasswordTitle,
          subtitle: AuthHe.suggestPasswordBody,
        ),
        BigButton(
          key: const Key('password-change-accept'),
          label: AuthHe.changePassword,
          onPressed: () => Navigator.of(sheet).pop(true),
        ),
        const SizedBox(height: Space.s),
        TextButton(
          key: const Key('password-change-later'),
          onPressed: () => Navigator.of(sheet).pop(false),
          child: const Text(AuthHe.notNow),
        ),
      ],
    ),
  );
  final now = navigatorKey.currentContext;
  if (change == true && now != null && now.mounted) {
    await showForgotPasswordSheet(now, email, signIn: false);
  }
}
