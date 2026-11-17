// Help-assistant corpus tooling (0120). The corpus is docs/help/kb.he.json —
// Hebrew, versioned, checked in; the server answers only from it.
//
//   dart run tool/help_kb.dart check                 # coverage + schema (also a test)
//   dart run tool/help_kb.dart stub                  # append placeholder entries for
//                                                    # uncovered routes/sections/extras
//   dart run tool/help_kb.dart sync <invoice-repo>   # write the server copy
//                                                    # apps/api/src/help/kb.generated.ts
//
// After a feature lands (new route in lib/router.dart, new business section,
// new help extra in lib/screens/help/help_links.dart): run `check`, then
// `stub`, write the real answers for the stubs, bump "version", `sync`.
// Pure Dart (no Flutter imports): the sources are parsed as text.

import 'dart:convert';
import 'dart:io';

const kbPath = 'docs/help/kb.he.json';
const placeholderPrefix = '[טיוטה — יעודכן אחרי האינטגרציה]';

/// routeTable keys of lib/router.dart.
List<String> routerPatterns(String routerSource) {
  final start = routerSource.indexOf('const Map<String, ScreenId> routeTable');
  if (start < 0) throw StateError('routeTable not found in lib/router.dart');
  final end = routerSource.indexOf('};', start);
  return RegExp(r"^\s*'(/[^']*)'\s*:", multiLine: true)
      .allMatches(routerSource.substring(start, end))
      .map((m) => m.group(1)!)
      .toList();
}

/// BusinessSection values → `/business/<name>`.
List<String> businessSections(String routerSource) {
  final start = routerSource.indexOf('enum BusinessSection');
  if (start < 0) throw StateError('BusinessSection not found');
  final body = routerSource.substring(
    routerSource.indexOf('{', start) + 1,
    routerSource.indexOf('}', start),
  );
  final noComments = body.replaceAll(RegExp(r'//[^\n]*'), '');
  return RegExp(
    r'\b([a-z][A-Za-z0-9]*)\b',
  ).allMatches(noComments).map((m) => '/business/${m.group(1)}').toList();
}

/// helpExtraLocations of lib/screens/help/help_links.dart.
List<String> helpExtras(String linksSource) {
  final start = linksSource.indexOf('helpExtraLocations');
  final end = linksSource.indexOf('};', start);
  return RegExp(r"'(/[^']*)'")
      .allMatches(linksSource.substring(start, end))
      .map((m) => m.group(1)!)
      .toList();
}

/// Everything the corpus must cover.
List<String> requiredCovers(String routerSource, String linksSource) => [
  ...routerPatterns(routerSource),
  ...businessSections(routerSource),
  ...helpExtras(linksSource),
];

/// True when [route] is a chip target the app can open: a help extra or a
/// concrete (id-free) form of a routeTable pattern.
bool routeAllowed(String route, List<String> patterns, List<String> extras) {
  final uri = Uri.tryParse(route);
  if (uri == null) return false;
  if (extras.contains(uri.path)) return true;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (final pattern in patterns) {
    final parts = pattern.substring(1).split('/');
    if (parts.length != segments.length || pattern == '/') continue;
    var ok = true;
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] == ':id') {
        ok = false; // no entity ids in a help chip
        break;
      }
      if (!parts[i].startsWith(':') && parts[i] != segments[i]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

/// Problems with [kb] (empty = fine).
List<String> check(
  Map<String, dynamic> kb,
  String routerSource,
  String linksSource,
) {
  final problems = <String>[];
  final patterns = routerPatterns(routerSource);
  final extras = helpExtras(linksSource);
  if (kb['version'] is! String || (kb['version'] as String).isEmpty) {
    problems.add('version missing');
  }
  final entries = (kb['entries'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final ids = <String>{};
  final covered = <String>{};
  for (final e in entries) {
    final id = e['id'];
    if (id is! String || !RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id)) {
      problems.add('bad id: $id');
      continue;
    }
    if (!ids.add(id)) problems.add('duplicate id: $id');
    for (final key in ['title', 'path', 'answer', 'audience']) {
      if (e[key] is! String) problems.add('$id: $key must be a string');
    }
    if ((e['title'] as String? ?? '').isEmpty) problems.add('$id: empty title');
    if ((e['answer'] as String? ?? '').isEmpty) {
      problems.add('$id: empty answer');
    }
    if (e['keywords'] is! List || (e['keywords'] as List).isEmpty) {
      problems.add('$id: keywords missing');
    }
    final status = e['status'];
    if (status != 'live' && status != 'placeholder') {
      problems.add('$id: status must be live|placeholder');
    }
    if (status == 'placeholder' &&
        !(e['answer'] as String? ?? '').startsWith(placeholderPrefix)) {
      problems.add('$id: placeholder answer must start with the draft prefix');
    }
    final route = e['route'];
    if (route != null &&
        (route is! String || !routeAllowed(route, patterns, extras))) {
      problems.add('$id: route $route is not an app location');
    }
    for (final c in (e['covers'] as List? ?? const [])) {
      covered.add(c as String);
    }
  }
  for (final need in requiredCovers(routerSource, linksSource)) {
    if (!covered.contains(need)) problems.add('no KB entry covers $need');
  }
  return problems;
}

/// The server copy: a TypeScript module the API compiles in.
String serverModule(Map<String, dynamic> kb) {
  final json = const JsonEncoder.withIndent('  ').convert({
    'version': kb['version'],
    'generatedFrom': kb['generatedFrom'] ?? '',
    'entries': [
      for (final e in (kb['entries'] as List).cast<Map<String, dynamic>>())
        {
          'id': e['id'],
          'title': e['title'],
          'path': e['path'],
          'route': e['route'],
          'covers': e['covers'] ?? const [],
          'keywords': e['keywords'] ?? const [],
          'answer': e['answer'],
          'audience': e['audience'] ?? 'all',
          'status': e['status'],
        },
    ],
  });
  return '// GENERATED by tevelinvoiceapp tool/help_kb.dart sync — do not edit.\n'
      '// Source: docs/help/kb.he.json in the app repo (version ${kb['version']}).\n'
      "import type { HelpKb } from './kb';\n\n"
      'export const HELP_KB: HelpKb = $json;\n';
}

Map<String, dynamic> readKb() =>
    jsonDecode(File(kbPath).readAsStringSync()) as Map<String, dynamic>;

String readRouter() => File('lib/router.dart').readAsStringSync();
String readLinks() =>
    File('lib/screens/help/help_links.dart').readAsStringSync();

void main(List<String> args) {
  final command = args.isEmpty ? 'check' : args.first;
  final kb = readKb();
  switch (command) {
    case 'check':
      final problems = check(kb, readRouter(), readLinks());
      if (problems.isEmpty) {
        stdout.writeln(
          'help KB ${kb['version']}: ${(kb['entries'] as List).length} '
          'entries, coverage OK',
        );
        return;
      }
      stderr.writeln(problems.join('\n'));
      exitCode = 1;
    case 'stub':
      final entries = (kb['entries'] as List).cast<Map<String, dynamic>>();
      final covered = {
        for (final e in entries) ...(e['covers'] as List).cast<String>(),
      };
      var added = 0;
      for (final need in requiredCovers(readRouter(), readLinks())) {
        if (covered.contains(need)) continue;
        final id = 'todo${need.replaceAll(RegExp(r'[^a-z0-9]+'), '-')}'
            .replaceAll(RegExp(r'-+$'), '');
        entries.add({
          'id': id,
          'title': need,
          'path': '',
          'route': null,
          'covers': [need],
          'keywords': [need],
          'answer': '$placeholderPrefix $need',
          'audience': 'all',
          'status': 'placeholder',
        });
        added++;
      }
      File(kbPath).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(kb)}\n',
      );
      stdout.writeln('added $added placeholder entries — write their answers');
    case 'sync':
      if (args.length < 2) {
        stderr.writeln('usage: dart run tool/help_kb.dart sync <invoice-repo>');
        exitCode = 64;
        return;
      }
      final problems = check(kb, readRouter(), readLinks());
      if (problems.isNotEmpty) {
        stderr.writeln('fix the KB first:\n${problems.join('\n')}');
        exitCode = 1;
        return;
      }
      final out = File('${args[1]}/apps/api/src/help/kb.generated.ts');
      out.writeAsStringSync(serverModule(kb));
      stdout.writeln('wrote ${out.path} (version ${kb['version']})');
    default:
      stderr.writeln('commands: check | stub | sync <invoice-repo>');
      exitCode = 64;
  }
}
