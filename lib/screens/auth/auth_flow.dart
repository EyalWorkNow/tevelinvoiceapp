// A · the sign-in gate (SPEC-v2 §6.A). Owner: squad E.
// provider → MFA (blocking step) → device token → /me + profile →
//   no business → NoBusinessScreen · several → S14 (required) ·
//   setup not done: owner → setup, others → SetupPendingScreen · else home.

import 'package:flutter/material.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/labels.dart';
import '../business/delete_account_screen.dart';
import '../business/sheets/s14_switch.dart';
import 'mfa_sheet.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// After a provider answered (login / Apple / Google / invitation): MFA if
/// needed, trade the cookie session for a device token, then route. Returns
/// false when the user backed out of the MFA step. Throws [ApiException].
Future<bool> finishSignIn(BuildContext context, SignInResult result) async {
  if (result.mfaRequired) {
    if (!await showMfaStep(context)) return false;
  }
  try {
    await _completeSignIn();
  } on ApiException catch (e) {
    // MFA is required for this member (role or a finalize/payment grant,
    // BE-03a) but the session is not verified: verify an enrolled method, or
    // enrol an e-mail code first (API-MOBILE §5 "Enrollment").
    if (e.code != 'MFA_REQUIRED' || !context.mounted) rethrow;
    final enrolled = await _hasMfaMethod();
    if (!context.mounted || !await showMfaStep(context, enroll: !enrolled)) return false;
    await _completeSignIn();
  }
  if (context.mounted) await routeSignedIn(context);
  return true;
}

Future<bool> _hasMfaMethod() async {
  try {
    final m = await fetchMfaMethods();
    return m.totp || m.email;
  } on ApiException {
    return false;
  }
}

/// completeSignIn() stores the token before loading /me + profile; if only
/// that last load fails we are signed in anyway and routing retries it.
Future<void> _completeSignIn() async {
  try {
    await session.completeSignIn();
  } on ApiException {
    if (session.status != SessionStatus.signedIn) rethrow;
  }
}

/// Signed in (fresh or restored): pick a business, set up, or go home.
Future<void> routeSignedIn(BuildContext context) async {
  if (session.hasNoBusiness) {
    _resetTo(const NoBusinessScreen(), '/gate/no-business');
    return;
  }
  if (session.needsBusinessPick) {
    final picked = await showSwitchBusinessSheet(context, required: true);
    if (picked == null) return; // the picker stays the only way forward
  }
  if (session.business != null && session.me == null && !session.offline) {
    try {
      await session.refreshBusiness();
    } on ApiException catch (e) {
      if (e.code == 'MFA_REQUIRED') {
        // A token minted before this member needed MFA (e.g. just got
        // "מפיק בעצמו"): sign in again through the MFA step.
        await session.signOutLocally();
        resetToLogin(expired: true);
        return;
      }
      // 401 already signed us out; offline → home from cache.
      if (!e.isNetwork) {
        if (e.status == 401) return;
        if (context.mounted) showErrorSnack(context, e);
      }
    }
  }
  final me = session.me;
  if (me != null && !me.onboardingCompleted && !session.offline) {
    if (businessContext.can(Cap.owner)) {
      resetToSetup();
    } else {
      _resetTo(const SetupPendingScreen(), '/gate/setup-pending');
    }
    return;
  }
  resetToHome();
}

void _resetTo(Widget screen, String name) => navigatorKey.currentState?.pushAndRemoveUntil(
  MaterialPageRoute(
    builder: (_) => screen,
    settings: RouteSettings(name: name),
  ),
  (_) => false,
);

/// A member (not the owner) of a business whose setup is not finished.
class SetupPendingScreen extends StatefulWidget {
  const SetupPendingScreen({super.key});

  @override
  State<SetupPendingScreen> createState() => _SetupPendingScreenState();
}

class _SetupPendingScreenState extends State<SetupPendingScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    try {
      await session.refreshBusiness();
      if (mounted && (session.me?.onboardingCompleted ?? false)) await routeSignedIn(context);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => _GateMessage(
    icon: Iconsax.timer,
    title: BusinessHe.setupPending(BusinessHe.setupPendingOwner),
    body: BusinessHe.setupPendingBody,
    primary: PrimaryButton(
      key: const Key('setup-pending-retry'),
      label: CommonHe.retry,
      loadingText: _checking ? CommonHe.retry : null,
      onPressed: _retry,
    ),
    links: [
      if (session.businesses.length > 1)
        TextButton(
          onPressed: () async {
            if (await showSwitchBusinessSheet(context, required: true) != null && context.mounted) {
              await routeSignedIn(context);
            }
          },
          child: const Text(BusinessHe.switchBusiness),
        ),
      TextButton(onPressed: session.signOut, child: const Text(BusinessHe.signOut)),
    ],
  );
}

/// Signed in, but no business membership (invitation revoked, business
/// closed). Explain + check again + continue on the computer (mail to self,
/// F6 (א)) + sign out + delete account (5.1.1(v)).
class NoBusinessScreen extends StatefulWidget {
  const NoBusinessScreen({super.key});

  @override
  State<NoBusinessScreen> createState() => _NoBusinessScreenState();
}

class _NoBusinessScreenState extends State<NoBusinessScreen> {
  bool _checking = false;

  Future<void> _recheck() async {
    setState(() => _checking = true);
    try {
      await session.refreshAccount();
      if (!mounted) return;
      if (!session.hasNoBusiness) await routeSignedIn(context);
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _desktop() async {
    final to = session.account?.email ?? '';
    final subject = Uri.encodeComponent('תבל — להמשך במחשב: פתיחת עסק');
    final body = Uri.encodeComponent('https://invoice.crm.tevel.space/app/');
    await launchAllowed(Uri.parse('mailto:$to?subject=$subject&body=$body'));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _GateMessage(
      icon: Iconsax.shop,
      title: BusinessHe.noBusinessTitle,
      body: BusinessHe.noBusinessBody(ltrIsolate(session.account?.email ?? '')),
      primary: PrimaryButton(
        key: const Key('no-business-recheck'),
        label: BusinessHe.checkAgain,
        loadingText: _checking ? BusinessHe.checkAgain : null,
        onPressed: _recheck,
      ),
      links: [
        TextButton(onPressed: _desktop, child: const Text(CommonHe.continueOnComputer)),
        TextButton(onPressed: session.signOut, child: const Text(BusinessHe.signOut)),
        // 5.1.1(v): B is out of reach without a business; deletion needs only the token.
        TextButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
          style: TextButton.styleFrom(foregroundColor: p.danger),
          child: const Text(BusinessHe.deleteAccount),
        ),
      ],
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.icon,
    required this.title,
    required this.body,
    required this.primary,
    this.links = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget primary;
  final List<Widget> links;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.all(Space.xl),
          children: [
            const SizedBox(height: Space.xxl),
            Icon(icon, size: 64, color: p.muted),
            const SizedBox(height: Space.l),
            Semantics(
              header: true,
              child: Text(title, style: AppText.title, textAlign: TextAlign.center),
            ),
            const SizedBox(height: Space.s),
            Text(
              body,
              style: AppText.body.copyWith(color: p.muted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.xl),
            for (final l in links) Center(child: l),
          ],
        ),
      ),
      bottomNavigationBar: BottomActionArea(child: primary),
    );
  }
}
