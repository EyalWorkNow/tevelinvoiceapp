import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/expense/expense_capture_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/people_he.dart';

import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

void main() {
  testWidgets(
    'PDF picker returning during back transition never starts an expense upload',
    (tester) async {
      late FakeBackend backend;
      await tester.runAsync(() async {
        backend = await eSetUp();
        installIssueFakes(backend);
        await signInAs(backend, Preset.owner);
      });
      final picked = Completer<Uint8List?>();
      phone(tester);
      await tester.pumpWidget(
        eApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpenseCaptureScreen(
                      autoOpenCamera: false,
                      pickPdf: () => picked.future,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text(ExpenseHe.pickPdf));
      await tester.pump();
      navigatorKey.currentState!.pop();
      picked.complete(Uint8List.fromList('%PDF-1.4 test'.codeUnits));
      await settle(tester);
      expect(find.text('open'), findsOneWidget);
      expect(
        backend.requests.where((request) => request.method != 'GET'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
