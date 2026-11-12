import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../util/labels/common_he.dart';
import '../theme.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// The one main action of a screen or sheet (spec V2 F2, §15.2).
///
/// * Full width, ≥56pt, lime. Put it in [BottomActionArea].
/// * [onPressed] is required: the button is never greyed out. The only
///   disabled state is [offline] ("אין חיבור", spec F5 exception).
///   No action → do not build the button at all.
/// * [loadingText] (e.g. "מפיק…") shows a spinner + that step and blocks taps.
/// * Debug builds assert there is at most one per screen/sheet (nearest
///   [PrimaryScope], else [Scaffold], else route). Keep it out of an
///   AnimatedSwitcher so two never overlap during a cross-fade.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loadingText,
    this.offline = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Non-null = loading with this step text.
  final String? loadingText;
  final bool offline;

  /// Red (S8 "הפק זיכוי" / "בטל מסמך").
  final bool destructive;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

final Expando<int> _primaryCount = Expando('PrimaryButton count');

class _PrimaryButtonState extends State<PrimaryButton> {
  Object? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kDebugMode) _register();
  }

  void _register() {
    final Object? scope =
        PrimaryScope._of(context) ??
        Scaffold.maybeOf(context) ??
        ModalRoute.of(context);
    if (identical(scope, _scope)) return;
    _unregister();
    if (scope == null) return;
    final count = (_primaryCount[scope] ?? 0) + 1;
    _primaryCount[scope] = count;
    _scope = scope;
    if (count > 1) {
      // Reported, not thrown: throwing mid-build corrupts the element tree.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: AssertionError(
            'Spec F2: at most one PrimaryButton per screen or sheet.',
          ),
          library: 'design system',
          context: ErrorDescription(
            'while registering PrimaryButton "${widget.label}"',
          ),
        ),
      );
    }
  }

  void _unregister() {
    final scope = _scope;
    if (scope == null) return;
    _primaryCount[scope] = (_primaryCount[scope] ?? 1) - 1;
    _scope = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final loading = widget.loadingText != null;
    final enabled = !widget.offline && !loading;
    final (Color bg, Color fg) = widget.offline
        ? (p.line, p.ink)
        : widget.destructive
        ? (p.danger, p.onDanger)
        : (p.accent, p.accentInk);
    final label = widget.offline
        ? CommonHe.offlineButton
        : (widget.loadingText ?? widget.label);
    return Semantics(
      button: true,
      enabled: enabled,
      liveRegion: loading,
      label: label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: Hit.primary,
          minWidth: double.infinity,
        ),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.button),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    widget.onPressed();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.l,
                vertical: Space.m,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading) ...[
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: Space.m),
                  ] else if (widget.offline) ...[
                    Icon(Iconsax.cloud_cross, size: 22, color: fg),
                    const SizedBox(width: Space.s),
                  ] else if (widget.icon != null) ...[
                    Icon(widget.icon, size: 22, color: fg),
                    const SizedBox(width: Space.s),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: AppText.button.copyWith(color: fg),
                    ),
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

/// Explicit "one screen" boundary for the PrimaryButton count (gallery,
/// tests, a tab body that shares its Scaffold with siblings).
class PrimaryScope extends StatefulWidget {
  const PrimaryScope({super.key, required this.child});

  final Widget child;

  static Object? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PrimaryScopeMarker>()?.token;

  @override
  State<PrimaryScope> createState() => _PrimaryScopeState();
}

class _PrimaryScopeState extends State<PrimaryScope> {
  final Object _token = Object();

  @override
  Widget build(BuildContext context) =>
      _PrimaryScopeMarker(token: _token, child: widget.child);
}

class _PrimaryScopeMarker extends InheritedWidget {
  const _PrimaryScopeMarker({required this.token, required super.child});

  final Object token;

  @override
  bool updateShouldNotify(_PrimaryScopeMarker oldWidget) =>
      token != oldWidget.token;
}

/// Bottom area for the primary button: safe area + 16, optional one-line
/// [note] above it (e.g. "מסמך מ-₪X כולל מע״מ דורש אישור").
class BottomActionArea extends StatelessWidget {
  const BottomActionArea({super.key, required this.child, this.note});

  final Widget child;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: Space.l),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, Space.s, Space.page, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) ...[
              Text(
                note!,
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
              const SizedBox(height: Space.s),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
