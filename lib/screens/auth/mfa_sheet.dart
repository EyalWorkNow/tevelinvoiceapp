import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/auth_api.dart';
import '../../api/client.dart';
import '../../ui/ds.dart';
import '../../ui/app_page_route.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// A · MFA as a blocking step (SPEC-v2 §6.A): a full-screen page, default an
/// e-mail code with no method choice ("שלחנו קוד ל-…" → 6 digits, auto focus,
/// paste / one-time-code autofill). TOTP and recovery codes stay available as
/// small links when the account has them. [enroll] = first-time e-mail
/// enrollment (owners, partners, accountants, self-issuers — BE-03a).
/// Returns true once the cookie session is MFA-satisfied.
Future<bool> showMfaStep(BuildContext context, {bool enroll = false}) async {
  // Verified-but-dismissed (closed the recovery codes) still counts.
  var verified = false;
  final ok = await Navigator.of(context).push<bool>(
    AppPageRoute<bool>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: '/gate/mfa'),
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.page,
                        72,
                        Space.page,
                        72,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: MfaSheet(
                            enroll: enroll,
                            onVerified: () => verified = true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: Space.s,
                end: Space.s,
                child: IconButton(
                  tooltip: CommonHe.close,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(verified),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok ?? verified;
}

enum _Mode { email, totp, recovery }

/// Public for widget tests; open it with [showMfaStep].
class MfaSheet extends StatefulWidget {
  const MfaSheet({super.key, required this.enroll, this.onVerified});

  final bool enroll;

  /// Called the moment the server accepted the code.
  final VoidCallback? onVerified;

  @override
  State<MfaSheet> createState() => _MfaSheetState();
}

class _MfaSheetState extends State<MfaSheet> {
  final _code = TextEditingController();
  final _focus = FocusNode();

  bool _starting = true;
  Object? _startError;
  MfaMethods? _methods;
  _Mode _mode = _Mode.email;
  String? _sentTo;
  DateTime? _resendAt;
  Timer? _ticker;
  bool _sending = false;
  bool _verifying = false;
  bool _locked = false;
  String? _error;
  List<String>? _recoveryCodes;

  MfaPurpose get _purpose =>
      widget.enroll ? MfaPurpose.enroll : MfaPurpose.login;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      if (!widget.enroll) {
        final methods = await fetchMfaMethods();
        _methods = methods;
        _mode = methods.useEmail || !methods.totp ? _Mode.email : _Mode.totp;
      }
      if (_mode == _Mode.email) await _send(initial: true);
      if (mounted) setState(() => _starting = false);
      _focus.requestFocus();
    } on ApiException catch (e) {
      if (mounted) setState(() => _startError = e);
    }
  }

  /// Sends (or re-sends) the e-mail code. A throttled first send means a code
  /// is already on its way — keep going.
  Future<void> _send({bool initial = false}) async {
    if (!initial) setState(() => _sending = true);
    try {
      final sent = await sendEmailCode(_purpose);
      _sentTo = sent.sentTo;
      _startCountdown(sent.resendAfterSeconds);
      if (!initial && mounted) {
        setState(() => _error = null);
        _code.clear();
        _focus.requestFocus();
      }
    } on ApiException catch (e) {
      if (e.code != 'MFA_EMAIL_THROTTLED') {
        if (initial) rethrow;
        if (mounted) setState(() => _error = e.messageHe);
        return;
      }
      _startCountdown(30);
      if (!initial && mounted) setState(() => _error = e.messageHe);
    } finally {
      if (!initial && mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown(int seconds) {
    _resendAt = DateTime.now().add(
      Duration(seconds: seconds < 30 ? 30 : seconds),
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (_secondsLeft == 0) t.cancel();
    });
  }

  int get _secondsLeft {
    final at = _resendAt;
    if (at == null) return 0;
    final s = at.difference(DateTime.now()).inMilliseconds;
    return s <= 0 ? 0 : (s / 1000).ceil();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (_verifying || _locked) return;
    if (_mode != _Mode.recovery && code.length != 6) return;
    if (_mode == _Mode.recovery && code.length < 6) {
      setState(() => _error = 'הקלד את קוד השחזור המלא');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      if (_mode == _Mode.email) {
        final codes = await verifyEmailCode(code, _purpose);
        widget.onVerified?.call();
        if (codes != null) {
          HapticFeedback.mediumImpact();
          if (mounted) setState(() => _recoveryCodes = codes);
          return;
        }
      } else {
        await verifyMfaCode(code);
        widget.onVerified?.call();
      }
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _error = e.code == 'MFA_NOT_PENDING'
            ? 'הקוד פג תוקף — שלח קוד חדש'
            : e.messageHe;
        _locked = e.code == 'MFA_LOCKED';
      });
      if (_mode != _Mode.recovery) _code.clear();
      if (!_locked) _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _switchMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
    _code.clear();
    if (mode == _Mode.email && _resendAt == null) {
      _send();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recoveryCodes != null) {
      return _RecoveryCodesView(codes: _recoveryCodes!);
    }
    final p = context.palette;
    final title = widget.enroll ? AuthHe.mfaEnrollTitle : AuthHe.mfaTitle;
    if (_starting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle(title),
          if (_startError == null)
            const Padding(
              padding: EdgeInsets.all(Space.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Text(
              errorTextHe(_startError!),
              style: AppText.body.copyWith(color: p.danger),
            ),
            const SizedBox(height: Space.l),
            TextButton(onPressed: _start, child: const Text(CommonHe.retry)),
          ],
        ],
      );
    }

    final subtitle = switch (_mode) {
      _Mode.email => AuthHe.mfaSentTo(ltrIsolate(_sentTo ?? 'המייל שלך')),
      _Mode.totp => 'הקלד את הקוד מאפליקציית האימות',
      _Mode.recovery => 'הקלד אחד מקודי השחזור ששמרת',
    };
    final busy = _verifying || _locked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.title.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.m),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(fontSize: 17, color: p.muted),
        ),
        const SizedBox(height: Space.xxl),
        if (_mode == _Mode.recovery)
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _code,
              focusNode: _focus,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _verify(),
              style: AppText.headline,
              decoration: const InputDecoration(hintText: 'xxxx-xxxx'),
            ),
          )
        else
          CodeBoxes(
            controller: _code,
            focusNode: _focus,
            enabled: !busy,
            hasError: _error != null,
            onCompleted: (_) => _verify(),
          ),
        const SizedBox(height: Space.m),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: _verifying
              ? const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              : _error == null
              ? null
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: p.danger),
                  ),
                ),
        ),
        if (_mode == _Mode.recovery) ...[
          const SizedBox(height: Space.m),
          if (!_locked)
            PrimaryButton(
              label: AuthHe.confirm,
              loadingText: _verifying ? AuthHe.confirm : null,
              onPressed: _verify,
            ),
        ],
        const SizedBox(height: Space.m),
        if (_mode == _Mode.email)
          Center(
            child: _secondsLeft > 0
                ? Text(
                    'אפשר לשלוח קוד חדש בעוד ${ltrIsolate(_mmss(_secondsLeft))}',
                    style: AppText.body.copyWith(color: p.muted),
                  )
                : TextButton(
                    onPressed: _sending || _locked ? null : () => _send(),
                    child: const Text(AuthHe.mfaResend),
                  ),
          ),
        if (!widget.enroll) ..._alternatives(),
      ],
    );
  }

  List<Widget> _alternatives() {
    final m = _methods;
    if (m == null) return const [];
    final options = <Widget>[
      if (_mode != _Mode.email && m.useEmail)
        TextButton(
          onPressed: () => _switchMode(_Mode.email),
          child: const Text(AuthHe.mfaUseEmail),
        ),
      if (_mode != _Mode.totp && m.totp)
        TextButton(
          onPressed: () => _switchMode(_Mode.totp),
          child: const Text(AuthHe.mfaUseApp),
        ),
      if (_mode != _Mode.recovery && m.recoveryCodesRemaining > 0)
        TextButton(
          onPressed: () => _switchMode(_Mode.recovery),
          child: const Text(AuthHe.mfaUseRecovery),
        ),
    ];
    return [for (final o in options) Center(child: o)];
  }
}

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Six digit boxes over one invisible TextField (keeps iOS one-time-code
/// autofill, paste and VoiceOver working). Always LTR.
class CodeBoxes extends StatefulWidget {
  const CodeBoxes({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  State<CodeBoxes> createState() => _CodeBoxesState();
}

class _CodeBoxesState extends State<CodeBoxes> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final focused = widget.focusNode.hasFocus;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final diameter = ((constraints.maxWidth - Space.l * 2) / 3).clamp(
                0.0,
                88.0,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: Space.l),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var column = 0; column < 3; column++) ...[
                          if (column > 0) const SizedBox(width: Space.l),
                          _digit(
                            context,
                            row * 3 + column,
                            diameter,
                            text,
                            focused,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              alwaysIncludeSemantics: true,
              child: Semantics(
                label: 'קוד אימות בן 6 ספרות',
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.enabled,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    counterText: '',
                  ),
                  onChanged: (v) {
                    if (v.length == 6) widget.onCompleted(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _digit(
    BuildContext context,
    int index,
    double diameter,
    String text,
    bool focused,
  ) {
    final p = context.palette;
    final active = focused && index == text.length.clamp(0, 5);
    return AnimatedContainer(
      key: ValueKey('mfa-digit-$index'),
      duration: context.motion(150),
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.canvas,
        shape: BoxShape.circle,
        border: Border.all(
          width: active || widget.hasError ? 2 : 1.5,
          color: widget.hasError
              ? p.danger
              : active
              ? p.accent
              : p.line,
        ),
      ),
      child: ExcludeSemantics(
        child: Text(
          index < text.length ? text[index] : '',
          style: AppText.title.copyWith(
            fontSize: 36,
            height: 1.1,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Shown once after enrollment issued recovery codes.
class _RecoveryCodesView extends StatefulWidget {
  const _RecoveryCodesView({required this.codes});

  final List<String> codes;

  @override
  State<_RecoveryCodesView> createState() => _RecoveryCodesViewState();
}

class _RecoveryCodesViewState extends State<_RecoveryCodesView> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle(AuthHe.recoveryTitle, subtitle: AuthHe.recoveryBody),
        Container(
          padding: const EdgeInsets.all(Space.l),
          decoration: BoxDecoration(
            color: p.canvas,
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              spacing: Space.l,
              runSpacing: Space.s,
              alignment: WrapAlignment.center,
              children: [
                for (final c in widget.codes)
                  SelectableText(
                    c,
                    style: AppText.headline.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.l),
        TextButton.icon(
          icon: const Icon(Iconsax.copy),
          label: Text(_copied ? AuthHe.copied : AuthHe.copy),
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: widget.codes.join('\n')),
            );
            if (mounted) setState(() => _copied = true);
          },
        ),
        const SizedBox(height: Space.m),
        PrimaryButton(
          label: AuthHe.savedContinue,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
