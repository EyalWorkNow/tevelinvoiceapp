// A · הזמנה (invitation states table, SPEC-v2 §6.A). Owner: squad E.
// Reached from the invitation e-mail: the universal link
// https://<host>/m/invite/:token, or tevel://invite/:token from its landing
// page ("פתח באפליקציה"), see router.dart (AUTH-INVITE-RESET 2026-11-15).
//
// valid, no account   → "הוזמנת ל-{עסק} כ{preset}" → name + new password →
//                       Supabase sign-up with the INVITED e-mail → (if
//                       "Confirm email" is on: the 6-digit code from the
//                       e-mail) → the server accepts and links the identity
// valid, has account  → its password (Supabase app password, or the Tevel
//                       password) → accept (no Apple / Google: owner
//                       2026-11-18, password accounts only)
// INVITATION_EMAIL_MISMATCH → "ההזמנה נשלחה ל-x, התחברת כ-y"
// MEMBER_EXISTS       → "אתה כבר חבר ב-{עסק}" → "למסך הכניסה"
// expired / revoked   → "ההזמנה כבר לא בתוקף. בקשו מ{מזמין} לשלוח הזמנה חדשה"
//                       (no name from the server → "ממי ששלח לכם אותה")
// preset needs MFA    → finishSignIn runs the MFA step before anything else.
// Without Supabase (older builds): the Tevel password only, as before.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../api/models/models.dart';
import '../../api/supabase_auth.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import 'auth_flow.dart';
import '../tutorial/tutorial_state.dart';
import 'login_screen.dart' show TevelLogo, showForgotPasswordSheet;
import 'password_recovery.dart' show passwordPolicyErrorHe;

enum _Busy { none, password, code }

/// Invitation codes that end the invitation (shown as the "ask again" state).
const Set<String> _deadInvitation = {
  'INVITATION_INVALID',
  'INVITATION_EXPIRED',
  'INVITATION_REVOKED',
};

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.token});

  final String token;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  InvitationPreview? _invite;
  Object? _loadError;
  String? _fieldError;
  String? _codeNotice;
  bool _memberExists = false;
  _Busy _busy = _Busy.none;

  /// Waiting for the sign-up confirmation code. The chosen password stays in
  /// memory until the account is created (it also becomes the web password).
  bool _awaitingCode = false;
  String? _pendingPassword;

  bool get _supabase => supabaseAuth.enabled;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _password.dispose();
    _name.dispose();
    _code.dispose();
    _pendingPassword = null;
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final invite = await fetchInvitation(widget.token);
      if (mounted) setState(() => _invite = invite);
    } on Object catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// One attempt; [step] returns false when it stopped to wait for the code.
  Future<void> _attempt(_Busy which, Future<bool> Function() step) async {
    if (_busy != _Busy.none) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = which;
      _fieldError = null;
      _codeNotice = null;
    });
    try {
      if (!await step() || !mounted) return;
      _pendingPassword = null;
      // 2611 §1: a member who just joined gets the tutorial (their version).
      await tutorialState.arm();
      if (!mounted) return;
      await finishSignIn(
        context,
        const SignInResult(mfaRequired: false, businesses: []),
      );
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  void _showError(ApiException e) {
    final invite = _invite!;
    setState(() {
      if (e.code == 'MEMBER_EXISTS') {
        _memberExists = true;
      } else if (_deadInvitation.contains(e.code)) {
        _loadError = e;
      } else if (e.code == 'INVITATION_EMAIL_MISMATCH') {
        final signedIn = e.details['signedInEmail'];
        _fieldError = AuthHe.emailMismatch(
          ltrIsolate(invite.email),
          signedIn is String && signedIn.isNotEmpty
              ? ltrIsolate(signedIn)
              : AuthHe.appleHiddenEmail,
        );
      } else {
        _fieldError = e.messageHe;
      }
    });
  }

  Future<void> _accept({
    String? password,
    String? supabaseAccessToken,
    String? displayName,
  }) {
    final invite = _invite!;
    final name = displayName ?? (invite.accountExists ? null : _name.text);
    return acceptInvitation(
      widget.token,
      password: password,
      supabaseAccessToken: supabaseAccessToken,
      displayName: name,
    );
  }

  Future<void> _join() async {
    final invite = _invite!;
    final password = _password.text;
    final local = invite.accountExists
        ? (password.isEmpty ? AuthHe.passwordRequired : null)
        : passwordPolicyErrorHe(password);
    if (local != null) {
      setState(() => _fieldError = local);
      return;
    }
    await _attempt(_Busy.password, () async {
      if (!_supabase) {
        await _accept(password: password);
        return true;
      }
      return invite.accountExists
          ? _joinExisting(invite, password)
          : _joinNew(invite, password);
    });
  }

  /// New account: the Supabase account of the invited e-mail (created now,
  /// or left over from an earlier attempt with the same password).
  Future<bool> _joinNew(InvitationPreview invite, String password) async {
    String? token;
    try {
      token = await supabaseAuth.passwordToken(invite.email, password);
    } on ApiException catch (e) {
      if (e.code == 'SUPABASE_EMAIL_NOT_CONFIRMED') {
        await supabaseAuth.resendSignUpCode(invite.email);
        _askForCode(password);
        return false;
      }
      if (e.code != 'INVALID_CREDENTIALS') rethrow;
      final signUp = await supabaseAuth.signUp(invite.email, password);
      if (signUp.needsEmailCode) {
        _askForCode(password);
        return false;
      }
      token = signUp.accessToken;
    }
    await _accept(supabaseAccessToken: token, password: password);
    return true;
  }

  /// Existing account: its app (Supabase) password when it has one; else the
  /// password is its Tevel password, which the server checks.
  Future<bool> _joinExisting(InvitationPreview invite, String password) async {
    String? token;
    try {
      token = await supabaseAuth.passwordToken(invite.email, password);
    } on ApiException catch (e) {
      if (e.code != 'INVALID_CREDENTIALS' &&
          e.code != 'SUPABASE_EMAIL_NOT_CONFIRMED') {
        rethrow;
      }
    }
    await _accept(supabaseAccessToken: token, password: password);
    return true;
  }

  void _askForCode(String password) {
    _pendingPassword = password;
    _code.clear();
    if (mounted) setState(() => _awaitingCode = true);
  }

  Future<void> _verifyCode() async {
    final code = _code.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6,10}$').hasMatch(code)) {
      setState(() => _fieldError = AuthHe.recoveryCodeFormat);
      return;
    }
    await _attempt(_Busy.code, () async {
      final token = await supabaseAuth.verifyCode(
        _invite!.email,
        code,
        recovery: false,
      );
      await _accept(supabaseAccessToken: token, password: _pendingPassword);
      return true;
    });
  }

  Future<void> _resendCode() => _attempt(_Busy.code, () async {
    await supabaseAuth.resendSignUpCode(_invite!.email);
    if (mounted) setState(() => _codeNotice = AuthHe.codeSentAgain);
    return false;
  });

  Future<void> _forgot() async {
    await showForgotPasswordSheet(context, _invite!.email, signIn: false);
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    if (_loadError != null) {
      final e = _loadError;
      final dead = e is ApiException && _deadInvitation.contains(e.code);
      return Scaffold(
        appBar: AppBar(),
        body: dead
            ? EmptyState(
                icon: Iconsax.calendar_remove,
                title: (invite?.inviterName ?? '').isEmpty
                    ? AuthHe.expiredAskAgainUnknown
                    : AuthHe.expiredAskAgain(invite!.inviterName),
                actionLabel: AuthHe.toSignIn,
                onAction: resetToLogin,
              )
            : ErrorView(error: e!, onRetry: _load),
      );
    }
    if (invite == null) {
      return Scaffold(appBar: AppBar(), body: const SkeletonList(rows: 3));
    }
    if (_memberExists) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Iconsax.tick_circle,
          title: AuthHe.alreadyMember(invite.businessName),
          actionLabel: AuthHe.toSignIn,
          onAction: resetToLogin,
        ),
      );
    }
    if (_awaitingCode) return _codeStep(invite);
    return _form(invite);
  }

  Widget _header(InvitationPreview invite) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: TevelLogo(size: 64)),
        const SizedBox(height: Space.xl),
        Semantics(
          header: true,
          child: Text(
            AuthHe.invitedTo(
              invite.businessName,
              PresetHe.label(invite.preset),
            ),
            style: AppText.title,
            textAlign: TextAlign.center,
          ),
        ),
        if (invite.inviterName.isNotEmpty)
          Text(
            AuthHe.invitedBy(invite.inviterName),
            style: AppText.body.copyWith(color: p.muted),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: Space.s),
        Text(
          PresetHe.hint(invite.preset),
          style: AppText.secondary.copyWith(color: p.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        InviteEmailLine(invite.email, style: AppText.headline),
      ],
    );
  }

  Widget _form(InvitationPreview invite) {
    final p = context.palette;
    final idle = _busy == _Busy.none;
    return Scaffold(
      key: const ValueKey('invite-form'),
      appBar: AppBar(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            _header(invite),
            const SizedBox(height: Space.l),
            Text(
              invite.accountExists
                  ? AuthHe.joinWithPassword
                  : AuthHe.createPassword,
              style: AppText.headline,
            ),
            if (_supabase) ...[
              const SizedBox(height: Space.xs),
              Text(
                invite.accountExists
                    ? AuthHe.inviteExistingHint
                    : AuthHe.inviteNewAccountHint,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ],
            const SizedBox(height: Space.s),
            if (!invite.accountExists) ...[
              TextField(
                key: const Key('invite-name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: AuthHe.displayName,
                ),
              ),
              const SizedBox(height: Space.m),
            ],
            TextField(
              key: const Key('invite-password'),
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              autofillHints: [
                invite.accountExists
                    ? AutofillHints.password
                    : AutofillHints.newPassword,
              ],
              onSubmitted: (_) => _join(),
              decoration: InputDecoration(
                labelText: AuthHe.password,
                helperText: invite.accountExists
                    ? null
                    : AuthHe.passwordPolicyLong,
                helperMaxLines: 2,
                errorText: _fieldError,
                errorMaxLines: 4,
              ),
            ),
            if (invite.accountExists)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: idle ? _forgot : null,
                  child: const Text(AuthHe.forgotPassword),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionArea(
        child: PrimaryButton(
          key: const Key('invite-join'),
          label: invite.accountExists
              ? AuthHe.signInJoin
              : AuthHe.createAccountJoin,
          loadingText: _busy == _Busy.password
              ? (invite.accountExists
                    ? AuthHe.signInJoin
                    : AuthHe.createAccountJoin)
              : null,
          onPressed: _join,
        ),
      ),
    );
  }

  Widget _codeStep(InvitationPreview invite) {
    final p = context.palette;
    return Scaffold(
      key: const ValueKey('invite-code-step'),
      appBar: AppBar(
        leading: BackButton(
          onPressed: () => setState(() {
            _awaitingCode = false;
            _pendingPassword = null;
            _fieldError = null;
          }),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            Icon(Iconsax.sms_tracking, size: 56, color: p.accent),
            const SizedBox(height: Space.l),
            Semantics(
              header: true,
              child: Text(
                AuthHe.confirmEmailTitle,
                style: AppText.title,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: Space.s),
            Text(
              AuthHe.confirmEmailSent,
              style: AppText.body.copyWith(color: p.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xs),
            InviteEmailLine(invite.email, style: AppText.headline),
            const SizedBox(height: Space.xl),
            TextField(
              key: const Key('invite-code'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              textDirection: TextDirection.ltr,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onSubmitted: (_) => _verifyCode(),
              decoration: InputDecoration(
                labelText: AuthHe.recoveryCodeLabel,
                helperText: _codeNotice ?? AuthHe.confirmEmailHint,
                helperMaxLines: 2,
                errorText: _fieldError,
                errorMaxLines: 4,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _busy == _Busy.none ? _resendCode : null,
                child: const Text(AuthHe.mfaResend),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionArea(
        child: PrimaryButton(
          key: const Key('invite-verify'),
          label: AuthHe.verifyCode,
          loadingText: _busy == _Busy.code ? AuthHe.verifyCode : null,
          onPressed: _verifyCode,
        ),
      ),
    );
  }
}

/// An e-mail address on a line of its own: LTR-isolated, never wrapped
/// (a wrap at "-" or "." reorders the pieces in an RTL paragraph), scaled
/// down when longer than the screen.
class InviteEmailLine extends StatelessWidget {
  const InviteEmailLine(this.email, {super.key, this.style});

  final String email;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(
      ltrIsolate(email),
      key: const Key('invite-email'),
      style: style,
      maxLines: 1,
      softWrap: false,
      textDirection: TextDirection.ltr,
    ),
  );
}
