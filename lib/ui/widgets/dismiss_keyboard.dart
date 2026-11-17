// Owner feedback 2026-11-16 (Q1): a tap anywhere outside a text field closes
// the keyboard, on every screen, sheet and dialog (they all live under
// MaterialApp.builder). The tap recognizer joins the gesture arena last: a
// button, a chip, the compose keypad or another text field under the finger
// wins the tap, and a drag (scrolling) wins over a tap — so only a tap on
// "nothing" reaches [_dismiss].

import 'package:flutter/widgets.dart';

class DismissKeyboardOnTapOutside extends StatelessWidget {
  const DismissKeyboardOnTapOutside({super.key, required this.child});

  final Widget child;

  static void _dismiss() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null) return;
    // Only a text field: other focus (a selected chip, a keyboard shortcut
    // scope) stays where it is.
    if (context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null) {
      focus!.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: _dismiss,
    excludeFromSemantics: true,
    child: child,
  );
}
