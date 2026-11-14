import 'dart:async';
import 'dart:convert';

import 'package:invoice/api/client.dart';

/// Widget tests run in FakeAsync, where an isolate hop (the client's large-body
/// decode, QA 2.5) never completes: decode inline there. test/client_test.dart
/// exercises the real isolate path.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiClient.backgroundDecoder = (bytes) async => jsonDecode(utf8.decode(bytes));
  await testMain();
}
