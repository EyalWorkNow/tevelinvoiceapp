import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invoice/screens/business/branding_screen.dart';
import 'package:invoice/screens/business/template_gallery.dart';
import 'package:invoice/screens/document/document_parts.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

final _png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 6)));

void main() {
  late FakeBackend backend;
  final originalPreview = pdfPreviewBuilder;
  final originalRasterizer = templateThumbnailRasterizer;
  setUp(() async {
    backend = await eSetUp();
    clearTemplateThumbnails();
    pdfPreviewBuilder = (bytes) => const SizedBox.expand();
    templateThumbnailRasterizer = (_) async => _png;
    backend.on(
      'POST',
      '/settings/branding/preview',
      (_) => const FakeResponse(200, [37, 80, 68, 70, 1]),
    );
  });
  tearDown(() {
    pdfPreviewBuilder = originalPreview;
    templateThumbnailRasterizer = originalRasterizer;
  });

  List<String> thumbRequests() => [
    for (final r in backend.calls('POST', '/settings/branding/preview'))
      r.body['template'] as String,
  ];

  void expectCard(WidgetTester tester, String id, {required bool selected}) =>
      expect(
        tester.getSemantics(find.byKey(Key('branding-template-$id'))),
        containsSemantics(
          label:
              'תבנית ${invoiceTemplates[id]!.$1}. ${invoiceTemplates[id]!.$2}',
          isButton: true,
          isSelected: selected,
          hasTapAction: true,
        ),
      );

  for (final brightness in Brightness.values) {
    testWidgets('gallery shows every design with thumbnails ($brightness)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      phone(tester);
      await tester.pumpWidget(
        eApp(const BrandingScreen(), brightness: brightness),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(invoiceTemplates.length, greaterThanOrEqualTo(6));
      // Every design got exactly one thumbnail render (+ the big preview).
      expect(
        thumbRequests().toSet(),
        containsAll(invoiceTemplates.keys.toList()),
      );
      final gallery = find.byKey(const Key('branding-template-gallery'));
      for (final id in invoiceTemplates.keys) {
        await tester.scrollUntilVisible(
          find.byKey(Key('branding-template-thumb-$id')),
          120,
          scrollable: find.descendant(
            of: gallery,
            matching: find.byType(Scrollable),
          ),
        );
        expectCard(tester, id, selected: id == 'modern');
      }
      handle.dispose();
    });
  }

  testWidgets(
    'cards run right-to-left and tapping selects + re-renders preview',
    (tester) async {
      final handle = tester.ensureSemantics();
      phone(tester);
      await tester.pumpWidget(eApp(const BrandingScreen()));
      await settle(tester);
      // RTL: the first design sits to the right of the second.
      expect(
        tester.getCenter(find.byKey(const Key('branding-template-classic'))).dx,
        greaterThan(
          tester
              .getCenter(find.byKey(const Key('branding-template-modern')))
              .dx,
        ),
      );
      expect(
        find.byKey(const Key('branding-template-check-modern')),
        findsOneWidget,
      );
      final before = thumbRequests().length;
      await tester.tap(find.byKey(const Key('branding-template-classic')));
      await tester.pump(const Duration(milliseconds: 450));
      await settle(tester);
      expectCard(tester, 'classic', selected: true);
      expectCard(tester, 'modern', selected: false);
      expect(
        find.byKey(const Key('branding-template-check-classic')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('branding-template-check-modern')),
        findsNothing,
      );
      // Only the big preview re-rendered — thumbnails come from the cache.
      expect(thumbRequests().sublist(before), ['classic']);
      await tester.tap(find.byKey(const Key('editor-save')));
      await settle(tester);
      expect(
        backend.last('PUT', '/settings/branding')!.body,
        containsPair('template', 'classic'),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'thumbnails are cached across visits and refresh on a new colour',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(eApp(const BrandingScreen()));
      await settle(tester);
      final first = thumbRequests().length;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(eApp(const BrandingScreen()));
      await settle(tester);
      expect(thumbRequests().length, first + 1, reason: 'big preview only');
      await tester.ensureVisible(find.byKey(const Key('color-#0b6e4f')));
      await tester.tap(find.byKey(const Key('color-#0b6e4f')));
      await tester.pump(const Duration(milliseconds: 800));
      await settle(tester);
      final recolour = backend
          .calls('POST', '/settings/branding/preview')
          .skip(first + 1)
          .where((r) => r.body['accentColor'] == '#0b6e4f')
          .map((r) => r.body['template'])
          .toSet();
      expect(recolour, containsAll(invoiceTemplates.keys.toList()));
    },
  );

  testWidgets('a design an older server rejects (422) is hidden', (
    tester,
  ) async {
    backend.on(
      'POST',
      '/settings/branding/preview',
      (r) => r.body['template'] == 'stripe'
          ? FakeResponse.error(422, 'VALIDATION')
          : const FakeResponse(200, [37, 80, 68, 70, 1]),
    );
    phone(tester);
    await tester.pumpWidget(eApp(const BrandingScreen()));
    await settle(tester);
    expect(find.byKey(const Key('branding-template-stripe')), findsNothing);
    expect(find.byKey(const Key('branding-template-classic')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed thumbnail shows a placeholder, never an error', (
    tester,
  ) async {
    templateThumbnailRasterizer = (_) async => throw StateError('no pdfium');
    phone(tester);
    await tester.pumpWidget(eApp(const BrandingScreen()));
    await settle(tester);
    expect(
      find.byKey(const Key('branding-template-thumb-classic')),
      findsNothing,
    );
    expect(find.byKey(const Key('branding-template-classic')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
