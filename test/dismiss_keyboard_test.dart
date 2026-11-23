import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/theme.dart';
import 'package:invoice/ui/widgets/dismiss_keyboard.dart';

void main() {
  late int pressed;
  late int cardTaps;
  late int suffixTaps;

  Widget app() => MaterialApp(
    theme: buildTheme(Brightness.dark),
    builder: (context, child) => DismissKeyboardOnTapOutside(child: child!),
    home: Scaffold(
      body: ListView(
        key: const Key('list'),
        children: [
          const TextField(key: Key('a')),
          const TextField(key: Key('b')),
          TextField(
            key: const Key('num'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                key: const Key('suffix'),
                onPressed: () => suffixTaps++,
                icon: const Icon(Icons.clear),
              ),
            ),
          ),
          // A tappable card: its InkWell used to win the tap and the
          // keyboard stayed up (2026-11-19).
          Card(
            child: InkWell(
              key: const Key('card'),
              onTap: () => cardTaps++,
              child: const SizedBox(height: 80, width: double.infinity),
            ),
          ),
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

  setUp(() {
    pressed = 0;
    cardTaps = 0;
    suffixTaps = 0;
  });

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

  testWidgets('tap on a tappable card closes the keyboard and still taps', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    await t.tap(find.byKey(const Key('card')));
    await t.pump();
    expect(cardTaps, 1);
    expect(focused(t, 'a'), isFalse);
    expect(t.testTextInput.isVisible, isFalse);
  });

  testWidgets('a button outside closes the keyboard and gets its tap', (
    t,
  ) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    await t.pump();
    await t.tap(find.byKey(const Key('btn')));
    await t.pump();
    expect(pressed, 1);
    expect(focused(t, 'a'), isFalse);
  });

  testWidgets('the field\'s own suffix button keeps the keyboard', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('num')));
    await t.pump();
    await t.tap(find.byKey(const Key('suffix')));
    await t.pump();
    expect(suffixTaps, 1);
    expect(focused(t, 'num'), isTrue);
  });

  testWidgets('a number pad gets a "סיום" bar that closes it', (t) async {
    await t.pumpWidget(app());
    await t.tap(find.byKey(const Key('a')));
    t.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    expect(find.byKey(const Key('keyboard-done')), findsNothing);
    await t.tap(find.byKey(const Key('num')));
    await t.pump();
    expect(find.byKey(const Key('keyboard-done')), findsOneWidget);
    await t.tap(find.byKey(const Key('keyboard-done')));
    await t.pump();
    expect(focused(t, 'num'), isFalse);
    expect(find.byKey(const Key('keyboard-done')), findsNothing);
  });
}
