import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/widgets/dismiss_keyboard.dart';

void main() {
  late int pressed;

  Widget app() => MaterialApp(
    builder: (context, child) => DismissKeyboardOnTapOutside(child: child!),
    home: Scaffold(
      body: ListView(
        key: const Key('list'),
        children: [
          const TextField(key: Key('a')),
          const TextField(key: Key('b')),
          ElevatedButton(
            key: const Key('btn'),
            onPressed: () => pressed++,
            child: const Text('x'),
          ),
          const SizedBox(key: Key('empty'), height: 1500),
        ],
      ),
    ),
  );

  bool focused(WidgetTester t, String key) => t
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  setUp(() => pressed = 0);

  testWidgets('tap on empty space closes the keyboard', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    expect(focused(t, 'a'), isTrue);
    expect(t.testTextInput.isVisible, isTrue);
    await t.tapAt(
      t.getCenter(find.byKey(const Key('empty'))) - const Offset(0, 500),
    );
    await t.pump();
    expect(focused(t, 'a'), isFalse);
    expect(t.testTextInput.isVisible, isFalse);
  });

  testWidgets('tap on another field moves focus there', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    await t.tap(find.byKey(const Key('b')));
    await t.pump();
    expect(focused(t, 'a'), isFalse);
    expect(focused(t, 'b'), isTrue);
  });

  testWidgets('a button still gets its tap', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    await t.tap(find.byKey(const Key('btn')));
    await t.pump();
    expect(pressed, 1);
  });

  testWidgets('scrolling still scrolls and keeps the keyboard', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    await t.drag(find.byKey(const Key('list')), const Offset(0, -80));
    await t.pump();
    final pos = t
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(pos.pixels, greaterThan(0));
    expect(t.testTextInput.isVisible, isTrue);
  });
}
