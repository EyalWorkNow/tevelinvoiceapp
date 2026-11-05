import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/branding_screen.dart';
import 'package:invoice/screens/document/document_parts.dart';
import 'business/e_harness.dart';
import 'fakes/fake_api.dart';

void main() {
  late FakeBackend backend;
  final originalPreview = pdfPreviewBuilder;
  setUp(() async {
    backend = await eSetUp();
    pdfPreviewBuilder = (bytes) => Center(
      child: Text('PDF ${bytes.last}', key: const Key('branding-pdf')),
    );
    backend.on(
      'POST',
      '/settings/branding/preview',
      (_) => const FakeResponse(200, [37, 80, 68, 70, 1]),
    );
  });
  tearDown(() => pdfPreviewBuilder = originalPreview);
  testWidgets(
    'unsaved template and colour update the PDF, and save preserves existing notes',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(const BrandingScreen(), brightness: Brightness.dark),
      );
      await settle(tester);
      expect(find.text('PDF 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('branding-template-minimal')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(
        backend.last('POST', '/settings/branding/preview')!.body['template'],
        'minimal',
      );
      expect(backend.calls('PUT', '/settings/branding'), isEmpty);
      await tester.ensureVisible(find.byKey(const Key('color-#0b6e4f')));
      await tester.tap(find.byKey(const Key('color-#0b6e4f')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(
        backend.last('POST', '/settings/branding/preview')!.body['accentColor'],
        '#0b6e4f',
      );
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(
        backend.last('PUT', '/settings/branding')!.body,
        containsPair('template', 'minimal'),
      );
      expect(
        backend.last('PUT', '/settings/branding')!.body,
        containsPair('headerNote', 'כותרת'),
      );
      expect(find.text('עיצוב המסמכים נשמר'), findsOneWidget);
    },
  );
  testWidgets('late PDF response cannot replace a newer selected design', (
    tester,
  ) async {
    final stale = Completer<FakeResponse>();
    backend.on(
      'POST',
      '/settings/branding/preview',
      (request) => request.body['template'] == 'classic'
          ? stale.future
          : FakeResponse(200, [
              37,
              80,
              68,
              70,
              request.body['template'] == 'minimal' ? 3 : 1,
            ]),
    );
    phone(tester);
    await tester.pumpWidget(
      eApp(const BrandingScreen(), brightness: Brightness.dark),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('branding-template-classic')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.tap(find.byKey(const Key('branding-template-minimal')));
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester);
    expect(find.text('PDF 3'), findsOneWidget);
    stale.complete(const FakeResponse(200, [37, 80, 68, 70, 2]));
    await settle(tester);
    expect(find.text('PDF 3'), findsOneWidget);
    expect(find.text('PDF 2'), findsNothing);
  });
  for (final width in [320.0, 402.0]) {
    testWidgets('branding fits $width pt at 200 percent text', (tester) async {
      tester.view.physicalSize = Size(width * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        eApp(const BrandingScreen(), brightness: Brightness.dark),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('branding-footer-note')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed preview is retryable without discarding the draft', (
    tester,
  ) async {
    backend.error(
      'POST',
      '/settings/branding/preview',
      503,
      'SERVICE_UNAVAILABLE',
    );
    phone(tester);
    await tester.pumpWidget(
      eApp(const BrandingScreen(), brightness: Brightness.dark),
    );
    await settle(tester);
    expect(find.text('התצוגה לא נטענה. נסה שוב'), findsOneWidget);
    backend.on(
      'POST',
      '/settings/branding/preview',
      (_) => const FakeResponse(200, [37, 80, 68, 70, 4]),
    );
    await tester.tap(find.text('התצוגה לא נטענה. נסה שוב'));
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester);
    expect(find.text('PDF 4'), findsOneWidget);
  });
}
