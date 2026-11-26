import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/screens/tutorial/tutorial_state.dart';

/// Widget tests run in FakeAsync, where an isolate hop (the client's large-body
/// decode, QA 2.5) never completes: decode inline there. test/client_test.dart
/// exercises the real isolate path.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiClient.backgroundDecoder = (bytes) async => jsonDecode(utf8.decode(bytes));
  // 2611 §1: nothing is armed unless a test arms it (in memory, no file IO),
  // and an invitation accepted in one test never opens the tutorial in the next.
  setUp(() => tutorialState.storage = MemoryTutorialStorage());
  await testMain();
}
