// Owner feedback 2026-11-16 (Q1): a tap anywhere outside a text field closes
// the keyboard, on every screen, sheet and dialog (they all live under
// MaterialApp.builder).
//
// 2026-11-19: the keyboard still "got stuck" very often. The first version
// was a tap recognizer that joined the gesture arena last, so any tappable
// thing under the finger (a card, a row, a chip, a sheet's background) won
// the tap and the keyboard stayed. Now a raw pointer [Listener] sees every
// tap, outside the arena: a tap (not a drag: scrolling keeps the keyboard)
// whose down position is not inside a text field's tap region
// ([TextFieldTapRegion]: the field, its suffix icons, the selection handles
// and toolbar) closes it. The tapped button still gets its tap.
//
// iOS number / phone pads have no return key: while one is up, a "סיום" bar
// sits on top of it, and the app below sees the keyboard as that much taller
// (viewInsets), so screens and sheets keep the focused field above both.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../util/labels/common_he.dart';
import '../theme.dart';

class DismissKeyboardOnTapOutside extends StatefulWidget {
  const DismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  /// Height of the "סיום" bar over a number / phone pad.
  static const double doneBarHeight = 44;

  @override
  State<DismissKeyboardOnTapOutside> createState() =>
      _DismissKeyboardOnTapOutsideState();
}

class _DismissKeyboardOnTapOutsideState
    extends State<DismissKeyboardOnTapOutside> {
  int? _pointer;
  Offset _down = Offset.zero;
  bool _inField = false;
  bool _numberPad = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  /// The focused text field, if the focus is one.
  static EditableText? _focusedField() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return null;
    final widget = context.widget;
    if (widget is EditableText) return widget;
    return context.findAncestorWidgetOfExactType<EditableText>();
  }

  static void _dismiss() {
    // Only a text field: other focus (a selected chip, a keyboard shortcut
    // scope) stays where it is.
    if (_focusedField() != null) FocusManager.instance.primaryFocus?.unfocus();
  }

  void _focusChanged() {
    final type = _focusedField()?.keyboardType;
    final pad =
        type != null &&
        (type.index == TextInputType.number.index ||
            type.index == TextInputType.phone.index);
    if (pad != _numberPad && mounted) setState(() => _numberPad = pad);
  }

  static bool _inTextField(PointerDownEvent event) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, event.position, event.viewId);
    return result.path.any(
      (entry) =>
          entry.target is RenderTapRegion &&
          (entry.target as RenderTapRegion).groupId == EditableText,
    );
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null) {
      _pointer = null; // a second finger: not a tap
      return;
    }
    _pointer = event.pointer;
    _down = event.position;
    _inField = _inTextField(event);
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer == _pointer &&
        (event.position - _down).distance > kTouchSlop) {
      _pointer = null; // a drag / scroll keeps the keyboard
    }
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    if (!_inField) _dismiss();
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final bar = _numberPad && keyboard > 0;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: Stack(
        children: [
          MediaQuery(
            data: bar
                ? media.copyWith(
                    viewInsets: media.viewInsets.copyWith(
                      bottom:
                          keyboard + DismissKeyboardOnTapOutside.doneBarHeight,
                    ),
                  )
                : media,
            child: widget.child,
          ),
          if (bar)
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboard,
              child: const _DoneBar(onDone: _dismiss),
            ),
        ],
      ),
    );
  }
}

/// "סיום" over an iOS number / phone pad (they have no return key).
class _DoneBar extends StatelessWidget {
  const _DoneBar({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Material(
    color: context.palette.surface,
    child: SizedBox(
      height: DismissKeyboardOnTapOutside.doneBarHeight,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          key: const Key('keyboard-done'),
          onPressed: onDone,
          child: const Text(CommonHe.done),
        ),
      ),
    ),
  );
}
