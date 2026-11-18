// 0120 help corpus (docs/help/kb.he.json): the assistant answers only from
// it, so it must not silently rot. Fails when a §5 route, a business section
// or a help extra has no entry, when a chip route cannot be opened, or when
// the schema drifts. Fix with `dart run tool/help_kb.dart stub` + answers.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/help/help_links.dart';

import '../../tool/help_kb.dart' as kb;

void main() {
  final corpus = kb.readKb();
  final router = kb.readRouter();
  final links = kb.readLinks();
  final entries = (corpus['entries'] as List).cast<Map<String, dynamic>>();

  test('every route, business section and help extra has a KB entry', () {
    expect(kb.check(corpus, router, links), isEmpty);
  });

  test('the parsed lists match the app (routeTable, sections, extras)', () {
    expect(kb.routerPatterns(router).toSet(), routeTable.keys.toSet());
    expect(kb.businessSections(router).toSet(), {
      for (final s in BusinessSection.values) '/business/${s.name}',
    });
    expect(kb.helpExtras(links).toSet(), helpExtraLocations);
  });

  test('every chip route opens in this build', () {
    for (final e in entries) {
      final route = e['route'] as String?;
      if (route == null) continue;
      expect(isHelpLocation(route), isTrue, reason: '${e['id']}: $route');
    }
  });

  test('a new route without an entry is caught (self-check)', () {
    final drifted = router.replaceFirst(
      "  '/home': ScreenId.h,",
      "  '/home': ScreenId.h,\n  '/brand-new': ScreenId.h,",
    );
    expect(
      kb.check(corpus, drifted, links),
      contains('no KB entry covers /brand-new'),
    );
    final copy = jsonDecode(jsonEncode(corpus)) as Map<String, dynamic>;
    (copy['entries'] as List).add({
      'id': 'bad',
      'title': 'x',
      'path': '',
      'route': '/doc/:id',
      'covers': [],
      'keywords': ['x'],
      'answer': 'x',
      'audience': 'all',
      'status': 'live',
    });
    expect(
      kb.check(copy, router, links),
      contains('bad: route /doc/:id is not an app location'),
    );
  });

  test('core paths the owner named are in the corpus', () {
    String pathOf(String id) =>
        entries.firstWhere((e) => e['id'] == id)['path'] as String;
    expect(pathOf('payment-request'), contains('ניהול → בקשת תשלום'));
    expect(pathOf('sign-requests'), contains('מסמך לחתימה'));
    expect(pathOf('my-signature'), contains('החתימה שלי'));
    expect(pathOf('help-assistant'), contains('עזרה'));
  });

  test('the server module carries every entry', () {
    final ts = kb.serverModule(corpus);
    expect(ts, startsWith('// GENERATED'));
    for (final e in entries) {
      expect(ts, contains('"id": "${e['id']}"'));
    }
  });
}
