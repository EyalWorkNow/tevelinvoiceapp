import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/ui/widgets/notch_notice.dart';

/// 0.9: the E2E harness unmounts the app between tests. A host that never
/// showed a notice must unmount cleanly; before the fix its lazy controllers
/// were first created in dispose() and the TickerMode lookup threw there.
void main() {
  testWidgets('a host that never showed a notice unmounts without errors', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => NotchNoticeHost(key: notchNoticeKey, child: child!),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(notchNoticeKey.currentState, isNull);
  });
}
