// Spec lints (SPEC-v2 §17): AT-91 (StatusPill takes only the §15.5 enums),
// AT-92 (no Hebrew literal in a button outside lib/util/labels/) and AT-94
// (tool/count_coverage.dart reproduces the §3.8 numbers).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/labels/status_he.dart';
import 'package:invoice/util/status_map.dart';

import '../tool/count_coverage.dart' as coverage;

final hebrew = RegExp(r'[֐-׿]');

/// Dart sources under lib/ (relative paths, '/'-separated).
List<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Source with comments removed (string contents kept).
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    if (quote != null) {
      out.write(c);
      if (c == r'\' && i + 1 < src.length) {
        out.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (src.startsWith(quote, i)) {
        out.write(quote.substring(1));
        i += quote.length;
        quote = null;
        continue;
      }
      i++;
      continue;
    }
    if (src.startsWith('//', i)) {
      final end = src.indexOf('\n', i);
      i = end < 0 ? src.length : end;
      continue;
    }
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      i = end < 0 ? src.length : end + 2;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = src.startsWith(c * 3, i) ? c * 3 : c;
      out.write(quote);
      i += quote.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// The argument list of the call starting at [open] ('(' index), or null.
String? argsAt(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return src.substring(open, i + 1);
  }
  return null;
}

/// String literals in [code] that contain Hebrew.
Iterable<String> hebrewLiterals(String code) => RegExp(
  r"'([^'\\\n]|\\.)*'|"
  r'"([^"\\\n]|\\.)*"',
).allMatches(code).map((m) => m.group(0)!).where(hebrew.hasMatch);

const buttons = [
  'PrimaryButton',
  'BigButton',
  'IntentButton',
  'TextButton',
  'TextButton.icon',
  'ElevatedButton',
  'ElevatedButton.icon',
  'FilledButton',
  'FilledButton.icon',
  'FilledButton.tonal',
  'OutlinedButton',
  'OutlinedButton.icon',
  'CupertinoButton',
  'IconButton',
  'MoreMenuItem',
  'SnackBarAction',
  'PopupMenuItem',
];

void main() {
  group('AT-91: StatusPill accepts only the §15.5 enums', () {
    test('invoice-family list statuses = F10 five + "הופק"', () {
      expect(DocStatus.values.map((s) => docStatusLabels[s]).toList(), [
        'טיוטה',
        'ממתין לאישור',
        'ממתין לתשלום',
        'באיחור',
        'שולם',
        'בוטל',
        'הופק',
      ]);
      for (final s in DocStatus.values) {
        expect(docStatusTones[s], isNotNull, reason: '$s has a tone');
      }
    });

    test('quote list statuses = F10 five', () {
      expect(QuoteListStatus.values.map((s) => quoteStatusLabels[s]).toList(), [
        'טיוטה',
        'אצל הלקוח',
        'אושרה',
        'הפכה לחשבונית',
        'לא רלוונטית',
      ]);
      for (final s in QuoteListStatus.values) {
        expect(quoteStatusTones[s], isNotNull, reason: '$s has a tone');
      }
    });

    test(
      'StatusPill has only the .doc(DocStatus) / .quote(QuoteListStatus) constructors',
      () {
        final src = stripComments(
          File('lib/ui/widgets/status_pill.dart').readAsStringSync(),
        );
        final ctors = RegExp(
          r'const StatusPill(\.\w+)?\(([^)]*)\)',
        ).allMatches(src).toList();
        expect(ctors.map((m) => m.group(1)).toSet(), {'.doc', '.quote'});
        expect(ctors.map((m) => m.group(2)!.trim().split(' ').first).toSet(), {
          'DocStatus',
          'QuoteListStatus',
        });
      },
    );

    test('every StatusPill in lib/ is built through .doc / .quote', () {
      final bad = <String>[];
      for (final f in libFiles()) {
        final src = stripComments(f.readAsStringSync());
        for (final m in RegExp(r'\bStatusPill(\.\w+)?\(').allMatches(src)) {
          final named = m.group(1);
          if (named != '.doc' &&
              named != '.quote' &&
              !f.path.endsWith('status_pill.dart')) {
            bad.add('${f.path}: ${src.substring(m.start, m.end + 20)}');
          }
        }
      }
      expect(bad, isEmpty);
    });
  });

  test(
    'AT-92: no Hebrew string literal in a button outside lib/util/labels/',
    () {
      final callStart = RegExp(
        '(?<![\\w.])(${buttons.map(RegExp.escape).join('|')})\\s*\\(',
      );
      final bad = <String>[];
      for (final f in libFiles()) {
        final path = f.path.replaceAll(r'\', '/');
        if (path.startsWith('lib/util/labels/')) continue;
        final src = stripComments(f.readAsStringSync());
        for (final m in callStart.allMatches(src)) {
          final args = argsAt(src, m.end - 1);
          if (args == null) continue;
          for (final lit in hebrewLiterals(args)) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            bad.add('$path:$line ${m.group(1)} $lit');
          }
        }
      }
      expect(
        bad,
        isEmpty,
        reason: 'move these words to lib/util/labels/*:\n${bad.join('\n')}',
      );
    },
  );

  test('AT-92 lint catches a literal (self-check)', () {
    const sample = "x = TextButton(onPressed: f, child: const Text('שמור'));";
    final args = argsAt(sample, sample.indexOf('('));
    expect(hebrewLiterals(args!), ["'שמור'"]);
    expect(
      hebrewLiterals(
        stripComments("TextButton(child: Text(L.save)) // 'שמור'"),
      ),
      isEmpty,
    );
  });

  test(
    'AT-94: tool/count_coverage.dart on SPEC-v2 §3 returns the §3.8 numbers',
    () {
      final spec = File('docs/SPEC-v2-he.md').readAsStringSync();
      expect(coverage.check(spec), isEmpty);
      // A changed row is caught.
      final drifted = spec.replaceFirst(
        '| חשבונית מס 305 | N |',
        '| חשבונית מס 305 | W |',
      );
      expect(coverage.check(drifted), isNotEmpty);
    },
  );
}
