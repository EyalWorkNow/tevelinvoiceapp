// A · הזמנה (invitation states table, SPEC-v2 §6.A). Owner: squad E.
// Reached by the universal link /m/invite/:token after BE-00 §5 (not a §5
// route; until then the invite link opens the web page).
//
// valid, signed out  → "הוזמנת ל-{עסק} כ{preset}" → password ("יש לי סיסמה")
//                      or a new password ("צור סיסמה") → "הצטרף"
// INVALID_CREDENTIALS → message under the field + "שכחתי סיסמה"
// MEMBER_EXISTS       → "אתה כבר חבר ב-{עסק}" → "פתח" (sign in)
// expired / revoked   → "ההזמנה כבר לא בתוקף. בקש מ-{מזמין} לשלוח שוב"
// preset needs MFA    → finishSignIn runs the MFA step before anything else.
// Apple/Google join: the server accepts only a Firebase Google token on
// /accept (no Apple) and the app has no Firebase — not offered.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../api/models/models.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import 'auth_flow.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'login_screen.dart' show showForgotPasswordSheet, TevelLogo;

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.token});

  final String token;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _password = TextEditingController();
  final _name = TextEditingController();
  InvitationPreview? _invite;
  Object? _loadError;
  String? _fieldError;
  bool _memberExists = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _password.dispose();
    _name.dispose();
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

  Future<void> _join() async {
    final invite = _invite!;
    if (!invite.accountExists && _password.text.length < 12) {
      setState(() => _fieldError = AuthHe.passwordPolicy);
      return;
    }
    if (_password.text.isEmpty) {
      setState(() => _fieldError = 'נא להזין סיסמה');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _joining = true;
      _fieldError = null;
    });
    try {
      await acceptInvitation(
        widget.token,
        password: _password.text,
        displayName: invite.accountExists ? null : _name.text,
      );
      if (!mounted) return;
      await finishSignIn(
        context,
        const SignInResult(mfaRequired: false, businesses: []),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'MEMBER_EXISTS') {
          _memberExists = true;
        } else if (e.code.startsWith('INVITATION_')) {
          _loadError = e;
        } else {
          _fieldError = e.messageHe;
        }
      });
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;
    final p = context.palette;
    if (_loadError != null) {
      final e = _loadError;
      final dead = e is ApiException && e.code.startsWith('INVITATION_');
      return Scaffold(
        appBar: AppBar(),
        body: dead
            ? EmptyState(
                icon: Iconsax.calendar_remove,
                title: AuthHe.expiredAskAgain(
                  (invite?.inviterName ?? '').isEmpty
                      ? AuthHe.inviterFallback
                      : invite!.inviterName,
                ),
                actionLabel: CommonHe.open,
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
          actionLabel: CommonHe.open,
          onAction: resetToLogin,
        ),
      );
    }
    final presetLabel = PresetHe.label(invite.preset);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            const Center(child: TevelLogo(size: 64)),
            const SizedBox(height: Space.xl),
            Semantics(
              header: true,
              child: Text(
                AuthHe.invitedTo(invite.businessName, presetLabel),
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
            Text(
              ltrIsolate(invite.email),
              style: AppText.headline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.l),
            Text(
              invite.accountExists
                  ? AuthHe.joinWithPassword
                  : AuthHe.createPassword,
              style: AppText.headline,
            ),
            const SizedBox(height: Space.s),
            if (!invite.accountExists) ...[
              TextField(
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
                helperText: invite.accountExists ? null : AuthHe.passwordPolicy,
                errorText: _fieldError,
                errorMaxLines: 3,
              ),
            ),
            if (invite.accountExists)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () =>
                      showForgotPasswordSheet(context, invite.email),
                  child: const Text(AuthHe.forgotPassword),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionArea(
        child: PrimaryButton(
          key: const Key('invite-join'),
          label: AuthHe.join,
          loadingText: _joining ? AuthHe.join : null,
          onPressed: _join,
        ),
      ),
    );
  }
}
