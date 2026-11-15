// "שכחתי סיסמה" with Supabase Auth: a 6-digit recovery code by e-mail, no
// deep link (AUTH-INVITE-RESET 2026-11-15).
//
// email → "אם הכתובת רשומה, נשלח קוד" (same answer for every address)
//       → code → recovery session (memory only) → "סיסמה חדשה"
//       → updateUser(password) → sign in with the same session (or, inside an
//         invitation, back to the invitation with the new password).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/big_button.dart';
import '../../util/labels/labels.dart';

enum _Step { email, code, password, done }

/// Local mirror of the server's password policy (packages/security
/// checkPasswordPolicy): one Tevel rule for the app and the web.
String? passwordPolicyErrorHe(String password) {
  if (password.length < 12 || password.length > 200) {
    return AuthHe.passwordPolicyLong;
  }
  if (password.split('').toSet().length < 4) return AuthHe.passwordPolicyLong;
  return null;
}

/// The recovery steps. [signIn] true: after the new password the result of
/// the Tevel exchange is popped (the caller runs finishSignIn). False (inside
/// an invitation): pops null and the invitation continues with the password.
class PasswordRecoveryFlow extends StatefulWidget {
  const PasswordRecoveryFlow({
    super.key,
    required this.prefill,
    this.signIn = true,
  });

  final String prefill;
  final bool signIn;

  @override
  State<PasswordRecoveryFlow> createState() => _PasswordRecoveryFlowState();
}

class _PasswordRecoveryFlowState extends State<PasswordRecoveryFlow> {
  late final _email = TextEditingController(text: widget.prefill.trim());
  final _code = TextEditingController();
  final _password = TextEditingController();
  _Step _step = _Step.email;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  String? _notice;
  String? _doneBody;

  /// The recovery session's access token: memory only, dropped on dispose.
  String? _recoveryToken;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _recoveryToken = null;
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.messageHe);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send({bool again = false}) async {
    if (!isValidEmail(_email.text)) {
      setState(() => _error = AuthHe.emailInvalid);
      return;
    }
    await _guard(() async {
      await requestPasswordReset(_email.text);
      if (!mounted) return;
      setState(() {
        _step = _Step.code;
        if (again) _notice = AuthHe.recoveryCodeResent;
      });
    });
  }

  Future<void> _verify() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      setState(() => _error = AuthHe.recoveryCodeFormat);
      return;
    }
    await _guard(() async {
      final token = await verifyRecoveryCode(_email.text, code);
      if (!mounted) return;
      setState(() {
        _recoveryToken = token;
        _step = _Step.password;
      });
    });
  }

  Future<void> _save() async {
    final policy = passwordPolicyErrorHe(_password.text);
    if (policy != null) {
      setState(() => _error = policy);
      return;
    }
    final token = _recoveryToken;
    if (token == null) return;
    await _guard(() async {
      if (!widget.signIn) {
        await setRecoveredPassword(token, _password.text);
        _recoveryToken = null;
        if (mounted) {
          setState(() {
            _step = _Step.done;
            _doneBody = AuthHe.recoveryDoneInvite;
          });
        }
        return;
      }
      try {
        await setRecoveredPassword(token, _password.text);
      } on ApiException catch (e) {
        if (e.code == 'SUPABASE_TOKEN_INVALID' && mounted) {
          // The recovery session expired: start over with a new code.
          setState(() {
            _recoveryToken = null;
            _code.clear();
            _step = _Step.email;
          });
        }
        rethrow;
      }
      try {
        final result = await signInWithSupabase(token);
        _recoveryToken = null;
        if (mounted) Navigator.of(context).pop(result);
      } on ApiException catch (e) {
        // The password changed; only the Tevel sign-in did not follow.
        _recoveryToken = null;
        if (mounted) {
          setState(() {
            _step = _Step.done;
            _doneBody = '${AuthHe.recoveryDoneSignIn} ${e.messageHe}';
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final children = switch (_step) {
      _Step.email => [
        const SheetTitle(
          AuthHe.passwordResetTitle,
          subtitle: AuthHe.recoveryEmailHint,
        ),
        TextField(
          key: const Key('recovery-email'),
          controller: _email,
          autofocus: widget.prefill.isEmpty,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(
            labelText: AuthHe.email,
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.l),
        BigButton(
          key: const Key('recovery-send'),
          label: AuthHe.sendCode,
          loading: _busy,
          onPressed: _send,
        ),
      ],
      _Step.code => [
        SheetTitle(
          AuthHe.recoveryCodeTitle,
          subtitle: AuthHe.recoveryCodeSent(ltrIsolate(_email.text.trim())),
        ),
        TextField(
          key: const Key('recovery-code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          onSubmitted: (_) => _verify(),
          decoration: InputDecoration(
            labelText: AuthHe.recoveryCodeLabel,
            helperText: _notice,
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: Space.l),
        BigButton(
          key: const Key('recovery-verify'),
          label: AuthHe.verifyCode,
          loading: _busy,
          onPressed: _verify,
        ),
        TextButton(
          onPressed: _busy ? null : () => _send(again: true),
          child: const Text(AuthHe.mfaResend),
        ),
      ],
      _Step.password => [
        const SheetTitle(
          AuthHe.newPasswordTitle,
          subtitle: AuthHe.passwordPolicyLong,
        ),
        TextField(
          key: const Key('recovery-password'),
          controller: _password,
          autofocus: true,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.newPassword],
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: AuthHe.newPasswordTitle,
            errorText: _error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showPassword
                  ? AuthHe.hidePassword
                  : AuthHe.showPassword,
              icon: Icon(_showPassword ? Iconsax.eye_slash : Iconsax.eye),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        BigButton(
          key: const Key('recovery-save'),
          label: AuthHe.savePassword,
          loading: _busy,
          onPressed: _save,
        ),
      ],
      _Step.done => [
        Icon(Iconsax.tick_circle, size: 48, color: p.ok),
        const SizedBox(height: Space.l),
        SheetTitle(AuthHe.recoveryDoneTitle, subtitle: _doneBody),
        BigButton(
          label: AuthHe.gotIt,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
