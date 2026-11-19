import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// fresh password confirmation, typed "מחק", then
/// POST /mobile/account/delete {confirm:"DELETE"} and a local wipe → login.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _hasProof => _password.text.isNotEmpty;
  bool get _typed => _confirm.text.trim() == deleteConfirmWord;

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await deleteAccount(password: _password.text);
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
          padding: const EdgeInsets.fromLTRB(
            Space.page,
            Space.s,
            Space.page,
            Space.xl,
          ),
          children: [
            Text(
              'המחיקה סופית ואי אפשר לבטל אותה.',
              style: AppText.title.copyWith(color: p.danger),
            ),
            const SizedBox(height: Space.l),
            _Box(
              icon: Iconsax.trash,
              color: p.danger,
              title: 'מה יימחק',
              lines: const [
                'החשבון שלך: אימייל, שם וסיסמה',
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
              'כדי לאשר שזו הבקשה שלך, הזינו את הסיסמה שבה אתם נכנסים לתבל.',
              style: AppText.caption.copyWith(color: p.muted),
            ),
            const SizedBox(height: Space.m),
            TextField(
              key: const Key('delete-password'),
              controller: _password,
              enabled: !_deleting,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              textDirection: TextDirection.ltr,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'סיסמה',
                suffixIcon: IconButton(
                  tooltip: _showPassword
                      ? AuthHe.hidePassword
                      : AuthHe.showPassword,
                  onPressed: _deleting
                      ? null
                      : () => setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.xl),
            Text('להמשך, הקלידו "$deleteConfirmWord"', style: AppText.headline),
            const SizedBox(height: Space.s),
            TextField(
              key: const Key('delete-confirm'),
              controller: _confirm,
              enabled: !_deleting,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(hintText: deleteConfirmWord),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.m),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: AppText.body.copyWith(color: p.danger),
                ),
              ),
            ],
            if (offline) ...[
              const SizedBox(height: Space.m),
              Text(
                'אין חיבור — אפשר למחוק רק כשיש אינטרנט.',
                style: AppText.caption.copyWith(color: p.warn),
              ),
            ],
            const SizedBox(height: Space.xl),
            BigButton(
              label: AuthHe.deleteForever,
              variant: BigButtonVariant.danger,
              loading: _deleting,
              onPressed: _typed && _hasProof && !offline && !_deleting
                  ? _delete
                  : null,
            ),
            const SizedBox(height: Space.s),
            TextButton(
              onPressed: _deleting ? null : () => Navigator.pop(context),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(Hit.min),
              ),
              child: const Text(AuthHe.notNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.icon,
    required this.color,
    required this.title,
    required this.lines,
  });

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
