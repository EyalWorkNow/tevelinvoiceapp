import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../api/client.dart';
import '../../api/settings_api.dart';
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../ui/widgets/error_view.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// The word the user types to confirm.
const String deleteConfirmWord = 'מחק';

/// Delete account (App Store 5.1.1(v)): what is deleted vs. kept by law, a
/// fresh proof of identity (password or Apple), typed "מחק", then
/// POST /mobile/account/delete {confirm:"DELETE"} and a local wipe → login.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _appleToken;

  /// One-time code from the same Apple sheet; the server revokes the Apple
  /// grant with it (App Store 5.1.1(v)).
  String? _appleCode;

  /// This device signed in with Apple: the Apple step is required (a password
  /// proves identity but gives no code to revoke).
  bool _appleAccount = false;
  bool _appleBusy = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    usedAppleSignIn().then((v) {
      if (mounted && v) setState(() => _appleAccount = true);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasProof =>
      _appleAccount ? _appleToken != null : (_password.text.isNotEmpty || _appleToken != null);
  bool get _typed => _confirm.text.trim() == deleteConfirmWord;

  Future<void> _verifyWithApple() async {
    setState(() {
      _appleBusy = true;
      _error = null;
    });
    try {
      final credential = await SignInWithApple.getAppleIDCredential(scopes: const []);
      if (!mounted) return;
      setState(() {
        _appleToken = credential.identityToken;
        _appleCode = credential.authorizationCode;
        _password.clear();
      });
    } on SignInWithAppleAuthorizationException catch (e) {
      if (mounted && e.code != AuthorizationErrorCode.canceled) {
        setState(() => _error = 'אימות Apple נכשל — נסו שוב');
      }
    } on Object {
      if (mounted) setState(() => _error = 'אימות Apple אינו זמין במכשיר הזה');
    } finally {
      if (mounted) setState(() => _appleBusy = false);
    }
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await deleteAccount(
        password: _password.text.isEmpty ? null : _password.text,
        appleIdentityToken: _password.text.isEmpty ? _appleToken : null,
        appleAuthorizationCode: _appleCode,
      );
      HapticFeedback.heavyImpact();
      // Everything server-side is revoked; wipe the device. main.dart then
      // resets the stack to the login screen.
      await session.signOutLocally();
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _deleting = false;
        _error = deleteAccountErrorHe(e);
        // An Apple proof is single-use within 10 minutes; ask for a new one.
        if (e.code == 'REAUTH_FAILED') {
          _appleToken = null;
          _appleCode = null;
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = errorTextHe(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final offline = session.offline;
    return Scaffold(
      appBar: AppBar(title: const Text('מחיקת חשבון')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.s, Space.page, Space.xl),
          children: [
            Text('המחיקה סופית ואי אפשר לבטל אותה.', style: AppText.title.copyWith(color: p.danger)),
            const SizedBox(height: Space.l),
            _Box(
              icon: Iconsax.trash,
              color: p.danger,
              title: 'מה יימחק',
              lines: const [
                'החשבון שלך: אימייל, שם, סיסמה וחיבור Apple / Google',
                'החיבור מכל המכשירים — הטלפון הזה והדפדפנים',
                'הגישה שלך לכל העסקים',
              ],
            ),
            const SizedBox(height: Space.m),
            _Box(
              icon: Iconsax.box,
              color: p.info,
              title: 'מה נשמר על פי חוק',
              lines: const [
                'מסמכים חשבונאיים — חשבוניות, קבלות, זיכויים ותשלומים — נשמרים 7 שנים, '
                    'כמו שמחייבות הוראות ניהול פנקסי חשבונות',
                'אם את/ה הבעלים היחידים של עסק, העסק ייסגר. המסמכים שלו יישמרו',
              ],
            ),
            const SizedBox(height: Space.xl),
            Text('אימות זהות', style: AppText.headline),
            const SizedBox(height: Space.xs),
            Text(
              _appleAccount
                  ? 'החשבון מחובר ל-Apple — אמתו עם Apple כדי שגם החיבור ל-Apple יבוטל.'
                  : 'הזינו את הסיסמה, או אמתו עם Apple אם נכנסתם כך.',
              style: AppText.caption.copyWith(color: p.muted),
            ),
            const SizedBox(height: Space.m),
            if (_appleToken == null && !_appleAccount)
              TextField(
                controller: _password,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(labelText: 'סיסמה'),
              )
            else if (_appleToken != null)
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Icon(Iconsax.shield_tick, color: p.ok),
                    const SizedBox(width: Space.s),
                    Expanded(
                      child: Text('אומת עם Apple', style: AppText.body.copyWith(color: p.ok)),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _appleToken = null;
                        _appleCode = null;
                      }),
                      child: const Text(CommonHe.cancel),
                    ),
                  ],
                ),
              ),
            if (_appleToken == null) ...[
              const SizedBox(height: Space.s),
              BigButton(
                label: AuthHe.verifyWithApple,
                icon: Iconsax.apple,
                variant: BigButtonVariant.secondary,
                loading: _appleBusy,
                onPressed: _deleting ? null : _verifyWithApple,
              ),
            ],
            const SizedBox(height: Space.xl),
            Text('להמשך, הקלידו "$deleteConfirmWord"', style: AppText.headline),
            const SizedBox(height: Space.s),
            TextField(
              controller: _confirm,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(hintText: deleteConfirmWord),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.m),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: AppText.body.copyWith(color: p.danger)),
              ),
            ],
            if (offline) ...[
              const SizedBox(height: Space.m),
              Text('אין חיבור — אפשר למחוק רק כשיש אינטרנט.', style: AppText.caption.copyWith(color: p.warn)),
            ],
            const SizedBox(height: Space.xl),
            BigButton(
              label: AuthHe.deleteForever,
              variant: BigButtonVariant.danger,
              loading: _deleting,
              onPressed: _typed && _hasProof && !offline ? _delete : null,
            ),
            const SizedBox(height: Space.s),
            TextButton(
              onPressed: _deleting ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(Hit.min)),
              child: const Text(AuthHe.notNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.icon, required this.color, required this.title, required this.lines});

  final IconData icon;
  final Color color;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.button),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: Space.s),
              Expanded(child: Text(title, style: AppText.headline)),
            ],
          ),
          const SizedBox(height: Space.s),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: AppText.body.copyWith(color: p.muted)),
                  Expanded(child: Text(line, style: AppText.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
