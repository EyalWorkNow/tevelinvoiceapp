import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/screens/business/branding_screen.dart';
import 'package:invoice/screens/business/sheets/editor_configs.dart'
    show ibanError;
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
      await tester.tap(find.byKey(const Key('branding-template-elegant')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(
        backend.last('POST', '/settings/branding/preview')!.body['template'],
        'elegant',
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
        containsPair('template', 'elegant'),
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
      (request) => request.body['template'] == 'summary'
          ? stale.future
          : FakeResponse(200, [
              37,
              80,
              68,
              70,
              request.body['template'] == 'elegant' ? 3 : 1,
            ]),
    );
    phone(tester);
    await tester.pumpWidget(
      eApp(const BrandingScreen(), brightness: Brightness.dark),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('branding-template-summary')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.tap(find.byKey(const Key('branding-template-elegant')));
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

  testWidgets(
    'owner Q1: keyboard up keeps the footer note focused and the scroll put; '
    'table-header switch and both notes save',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        eApp(const BrandingScreen(), brightness: Brightness.dark),
      );
      await settle(tester);
      ScrollPosition pos() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('branding-controls')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;

      // The switch toggles in place.
      final tile = find.widgetWithText(SwitchListTile, 'הדגשת כותרת הטבלה');
      await tester.ensureVisible(tile);
      await settle(tester);
      final before = pos().pixels;
      expect(before, greaterThan(0));
      final was = tester.widget<SwitchListTile>(tile).value;
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(tester.widget<SwitchListTile>(tile).value, !was);
      expect(pos().pixels, before);

      // Footer note: the keyboard opens (the body shrinks under 400 pt).
      final footer = find.byKey(const Key('branding-footer-note'));
      await tester.ensureVisible(footer);
      await settle(tester);
      await tester.tap(footer);
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      final field = find.descendant(
        of: footer,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      expect(pos().pixels, greaterThan(0));
      await tester.enterText(footer, 'תודה שבחרתם בנו');
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      expect(
        backend.last('POST', '/settings/branding/preview')!.body['footerNote'],
        'תודה שבחרתם בנו',
      );

      final header = find.byKey(const Key('branding-header-note'));
      await tester.ensureVisible(header);
      await tester.enterText(header, 'א׳–ה׳ 9:00–18:00');
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);

      tester.view.resetViewInsets();
      await settle(tester);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      final put = backend.last('PUT', '/settings/branding')!.body;
      expect(put['footerNote'], 'תודה שבחרתם בנו');
      expect(put['headerNote'], 'א׳–ה׳ 9:00–18:00');
      expect(put['accentTableHeader'], !was);
    },
  );

  testWidgets(
    'r5: colour pair, envelope, ink-save and preview type reach preview + save',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(eApp(const BrandingScreen()));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('color-pair-#0f766e')));
      await tester.tap(find.byKey(const Key('color-pair-#0f766e')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      Map<String, dynamic> bigPreview() => backend
          .calls('POST', '/settings/branding/preview')
          .lastWhere((r) => r.body.containsKey('documentType'))
          .body;
      final preview = bigPreview();
      expect(preview['accentColor'], '#0f766e');
      expect(preview['secondaryColor'], '#f97362');
      expect(preview['documentType'], 'TAX_INVOICE');
      await tester.ensureVisible(
        find.byKey(const Key('branding-envelope-right')),
      );
      await tester.tap(find.byKey(const Key('branding-envelope-right')));
      await tester.ensureVisible(find.byKey(const Key('branding-ink-save')));
      await tester.tap(find.byKey(const Key('branding-ink-save')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      await tester.tap(find.byKey(const Key('branding-preview-type')));
      await settle(tester);
      await tester.tap(find.text('קבלה').last);
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expect(bigPreview()['documentType'], 'RECEIPT');
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      final saved = backend.last('PUT', '/settings/branding')!.body;
      expect(saved['secondaryColor'], '#f97362');
      expect(saved['windowEnvelope'], 'right');
      expect(saved['inkSave'], true);
      expect(saved.containsKey('documentType'), isFalse);
    },
  );

  test('IBAN validation mirrors the server (mod-97)', () {
    expect(ibanError(''), isNull);
    expect(ibanError('IL62 0108 0000 0009 9999 999'), isNull);
    expect(ibanError('IL62 0108 0000 0009 9999 998'), isNotNull);
    expect(ibanError('IL62 0108'), isNotNull);
  });
}
