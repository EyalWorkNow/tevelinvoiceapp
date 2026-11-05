// A · הקמה (SPEC-v2 §6.A, owner of a new business). Owner: squad E.
//   1. "איזה עסק יש לך?" — 4 cards (+ שותפות under "עוד ▾")
//   2. name · ע.מ./ח.פ. (local checksum) · "על מה אתה בדרך כלל גובה?" (optional)
//   3. "כבר הפקת חשבוניות במקום אחר?" לא / כן → "מאיזה מספר להמשיך?" → "סיימתי"
// PUT /business/profile → PUT /sequences/:scope/start (each untouched scope)
// → PUT /business/onboarding {completed:true}. With identityLocked (documents
// exist) only the name/description step is shown.
// [newBusiness] (S14 "+ עסק נוסף", BE-40): the same 3 steps start empty and
// "סיימתי" first creates the business (POST /businesses), switches to it, then
// writes the description / numbering / onboarding into the new business.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth_api.dart';
import '../../api/models/models.dart' show Business;
import '../../api/client.dart';
import '../../api/settings_api.dart' show setStartingNumber;
import '../../router.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// S14 "+ עסק נוסף" (BE-40): A setup for another business (route /setup).
Future<void> openNewBusiness(BuildContext context) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    settings: const RouteSettings(name: '/setup'),
    builder: (_) => const OnboardingScreen(newBusiness: true),
  ),
);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.newBusiness = false});

  /// True = create another business (BE-40) instead of finishing this one.
  final bool newBusiness;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Label of the id number field for [businessType].
String taxIdLabelFor(String businessType) => switch (businessType) {
  'COMPANY' || 'NONPROFIT' => 'מספר ח.פ.',
  'PARTNERSHIP' => 'מספר שותפות / ע.מ.',
  _ => 'מספר ת.ז. / ע.מ.',
};

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  final _taxId = TextEditingController();
  final _description = TextEditingController();
  final _startNumber = TextEditingController();

  int _step = 0;
  String? _type;
  bool _showOther = false;
  bool _validate = false;
  bool? _continues = false;
  bool _saving = false;
  Object? _error;
  late final bool _locked;

  @override
  void initState() {
    super.initState();
    final profile = widget.newBusiness ? null : session.profile;
    _locked = profile?.identityLocked ?? false;
    if (profile != null) {
      // The self-signup placeholder ("העסק של …") is not a real name.
      if (!profile.legalName.startsWith('העסק של ')) _name.text = profile.legalName;
      _taxId.text = profile.taxId ?? '';
      _description.text = profile.defaultLineDescription ?? '';
      if (_locked || profile.onboardingCompleted) _type = profile.businessType;
      if (_locked) _step = 1;
      _showOther = _type == 'PARTNERSHIP';
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _taxId, _description, _startNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _lastStep => _locked ? 1 : 2;

  void _pickType(String type) {
    HapticFeedback.selectionClick();
    setState(() {
      _type = type;
      _step = 1;
    });
  }

  String? get _nameError => _validate && _name.text.trim().length < 2 ? AuthHe.nameRequired : null;

  String? get _taxIdError {
    if (!_validate || _locked) return null;
    final t = _taxId.text.trim();
    if (t.isEmpty) return AuthHe.idRequired;
    return isValidIsraeliId(t) ? null : AuthHe.idInvalid;
  }

  String? get _numberError {
    if (!_validate || _continues != true) return null;
    final n = int.tryParse(_startNumber.text.trim());
    return n == null || n < 1 || n > 999999999 ? AuthHe.numberInvalid : null;
  }

  void _next() {
    FocusScope.of(context).unfocus();
    setState(() => _validate = true);
    if (_nameError != null || _taxIdError != null) {
      HapticFeedback.heavyImpact();
      return;
    }
    if (_step < _lastStep) {
      setState(() {
        _step++;
        _validate = false;
      });
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _validate = true;
      _error = null;
    });
    if (_nameError != null || _taxIdError != null || _numberError != null) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.newBusiness) {
        final id = await createBusiness(
          businessType: _type ?? 'OSEK_MURSHE',
          legalName: _name.text,
          taxId: _taxId.text,
        );
        await session.selectBusiness(Business(businessId: id, legalName: _name.text.trim(), role: 'OWNER'));
      }
      await saveOnboardingProfile(
        legalName: _name.text,
        businessType: _type ?? 'OSEK_MURSHE',
        taxId: _taxId.text,
        defaultLineDescription: _description.text,
        includeIdentity: !_locked,
      );
      if (_continues == true) await setStartingNumber(int.parse(_startNumber.text.trim()));
      await completeOnboarding();
      HapticFeedback.mediumImpact();
      try {
        await Future.wait([session.refreshBusiness(), session.refreshAccount()]);
      } on ApiException {
        // Saved on the server; home refreshes on its own.
      }
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (widget.newBusiness) {
        resetToHome();
      } else if (nav.canPop()) {
        nav.pop();
      } else {
        resetToHome();
      }
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _back() => setState(() {
    _step--;
    _validate = false;
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showBack = _step > (_locked ? 1 : 0);
    final last = _step == _lastStep;
    return PopScope(
      canPop: !showBack && canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showBack) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: showBack
              ? IconButton(tooltip: AuthHe.back, icon: const BackButtonIcon(), onPressed: _back)
              : canPop
              ? IconButton(
                  tooltip: CommonHe.close,
                  icon: const Icon(Iconsax.close_circle),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          title: Text(_locked ? BusinessHe.profile : AuthHe.setupStep(_step + 1)),
        ),
        body: SafeArea(
          bottom: _step == 0,
          child: switch (_step) {
            0 => _typeStep(context),
            1 => _detailsStep(context),
            _ => _numberingStep(context),
          },
        ),
        bottomNavigationBar: _step == 0
            ? null
            : BottomActionArea(
                child: PrimaryButton(
                  key: const Key('setup-next'),
                  label: last ? AuthHe.finish : AuthHe.next,
                  loadingText: _saving ? AuthHe.finish : null,
                  offline: session.offline,
                  onPressed: last ? _finish : _next,
                ),
              ),
      ),
    );
  }

  Widget _typeStep(BuildContext context) {
    final p = context.palette;
    const main = ['OSEK_PATUR', 'OSEK_MURSHE', 'COMPANY', 'NONPROFIT'];
    return ListView(
      key: const ValueKey('type'),
      padding: const EdgeInsets.all(Space.page),
      children: [
        Semantics(header: true, child: const Text(AuthHe.whichBusiness, style: AppText.title)),
        const SizedBox(height: Space.xs),
        Text(AuthHe.whichBusinessHint, style: AppText.body.copyWith(color: p.muted)),
        const SizedBox(height: Space.xl),
        for (final t in [...main, if (_showOther) 'PARTNERSHIP'])
          _TypeCard(
            title: businessTypeLabels[t]!,
            subtitle: businessTypeHints[t]!,
            icon: _typeIcons[t]!,
            selected: _type == t,
            onTap: () => _pickType(t),
          ),
        if (!_showOther)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showOther = true),
              child: const Text(AuthHe.otherTypes),
            ),
          ),
      ],
    );
  }

  Widget _detailsStep(BuildContext context) {
    final p = context.palette;
    final type = _type ?? 'OSEK_MURSHE';
    return ListView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.all(Space.page),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Semantics(header: true, child: const Text(BusinessHe.profile, style: AppText.title)),
        const SizedBox(height: Space.xs),
        Text(businessTypeLabels[type] ?? type, style: AppText.body.copyWith(color: p.muted)),
        const SizedBox(height: Space.xl),
        TextField(
          controller: _name,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.organizationName],
          onChanged: (_) => _validate ? setState(() {}) : null,
          decoration: InputDecoration(labelText: AuthHe.businessName, errorText: _nameError),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _taxId,
          enabled: !_locked,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          onChanged: (_) => _validate ? setState(() {}) : null,
          decoration: InputDecoration(
            labelText: taxIdLabelFor(type),
            helperText: _locked ? BusinessHe.identityLocked : null,
            helperMaxLines: 2,
            errorText: _taxIdError,
          ),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _next(),
          decoration: const InputDecoration(labelText: AuthHe.defaultDescription, hintText: 'שירותים'),
        ),
        if (!_locked) ...[
          const SizedBox(height: Space.l),
          Text(AuthHe.identityHint, style: AppText.secondary.copyWith(color: p.muted)),
        ],
        if (_locked) _errorText(context),
      ],
    );
  }

  Widget _numberingStep(BuildContext context) {
    final p = context.palette;
    return ListView(
      key: const ValueKey('numbering'),
      padding: const EdgeInsets.all(Space.page),
      children: [
        Semantics(header: true, child: const Text(AuthHe.numberingQuestion, style: AppText.title)),
        const SizedBox(height: Space.xl),
        ChipRow<bool>(
          padding: EdgeInsets.zero,
          options: const [ChipOption(false, AuthHe.numberingNo), ChipOption(true, AuthHe.numberingYes)],
          selected: _continues,
          onSelected: (v) => setState(() => _continues = v),
        ),
        if (_continues == true) ...[
          const SizedBox(height: Space.xl),
          TextField(
            key: const Key('setup-start-number'),
            controller: _startNumber,
            autofocus: true,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            onChanged: (_) => _validate ? setState(() {}) : null,
            decoration: InputDecoration(
              labelText: AuthHe.numberingFrom,
              helperText: AuthHe.numberingHint,
              errorText: _numberError,
            ),
          ),
        ],
        const SizedBox(height: Space.l),
        Text(AuthHe.identityHint, style: AppText.secondary.copyWith(color: p.muted)),
        _errorText(context),
      ],
    );
  }

  Widget _errorText(BuildContext context) => _error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.l),
          child: Semantics(
            liveRegion: true,
            child: Text(errorTextHe(_error!), style: AppText.body.copyWith(color: context.palette.danger)),
          ),
        );
}

const Map<String, IconData> _typeIcons = {
  'OSEK_PATUR': Iconsax.user,
  'OSEK_MURSHE': Iconsax.briefcase,
  'COMPANY': Iconsax.buildings,
  'NONPROFIT': Iconsax.heart,
  'PARTNERSHIP': Iconsax.people,
};

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Semantics(
        button: true,
        selected: selected,
        label: '$title, $subtitle',
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.card),
            side: BorderSide(color: selected ? p.ink : p.line, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: selected ? p.accent : p.canvas,
                    foregroundColor: selected ? p.accentInk : p.ink,
                    child: Icon(icon),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppText.headline),
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppText.body.copyWith(color: p.muted)),
                      ],
                    ),
                  ),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Iconsax.arrow_left_2
                        : Iconsax.arrow_right_3,
                    color: p.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
