// AT-94 (SPEC-v2 §17): recount the §3 capability matrix and check it against
// the §3.8 table.
//
//   dart run tool/count_coverage.dart [docs/SPEC-v2-he.md]
//
// Rule (§3.8): every row of the tables in §3.1–§3.7 is one capability; its
// state is the FIRST character of the "מצב" column (N · L · W · —).
// Exit 0 when the counts and percentages equal §3.8, 1 when they differ.
import 'dart:io';

const states = ['N', 'L', 'W', '—'];

/// Counts per state for the §3.1–§3.7 tables of [spec].
Map<String, int> countMatrix(String spec) {
  final counts = {for (final s in states) s: 0};
  var inMatrix = false;
  for (final line in spec.split('\n')) {
    if (line.startsWith('### 3.')) {
      final n = int.tryParse(line.substring(6, 7)) ?? 0;
      inMatrix = n >= 1 && n <= 7;
      continue;
    }
    if (line.startsWith('## ')) inMatrix = false;
    if (!inMatrix || !line.startsWith('|')) continue;
    final cells = line.split('|');
    if (cells.length < 3) continue;
    final state = cells[2].trim();
    if (state == 'מצב' || state.startsWith('---')) continue;
    final first = state.isEmpty ? '' : String.fromCharCode(state.runes.first);
    if (!counts.containsKey(first)) {
      throw FormatException('unknown state "$state" in row: $line');
    }
    counts[first] = counts[first]! + 1;
  }
  return counts;
}

/// The numbers §3.8 declares: rows per state, 'total', and the percentages
/// (per state, 'N+L', 'N+L+W') as written (one decimal).
({Map<String, int> rows, Map<String, String> pct}) declared(String spec) {
  final start = spec.indexOf('### 3.8');
  if (start < 0) throw const FormatException('§3.8 not found');
  final rows = <String, int>{};
  final pct = <String, String>{};
  for (final line in spec.substring(start).split('\n').skip(1)) {
    if (line.startsWith('#')) break;
    if (!line.startsWith('|')) continue;
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (cells.length < 4) continue;
    final head = cells[1].replaceAll('*', '');
    if (head.startsWith('סה״כ')) {
      rows['total'] = int.parse(cells[2].replaceAll('*', ''));
      for (final m in RegExp(r'(N\+L(?:\+W)?) = \**([\d.]+)%').allMatches(cells[3])) {
        pct[m.group(1)!] = m.group(2)!;
      }
      continue;
    }
    final state = head.isEmpty ? '' : String.fromCharCode(head.runes.first);
    if (!states.contains(state)) continue;
    rows[state] = int.parse(cells[2]);
    pct[state] = cells[3].replaceAll('%', '');
  }
  return (rows: rows, pct: pct);
}

String percent(int part, int total) => (part * 100 / total).toStringAsFixed(1);

/// Differences between the recount and §3.8 (empty = AT-94 passes).
List<String> check(String spec) {
  final c = countMatrix(spec);
  final total = c.values.fold(0, (a, b) => a + b);
  final d = declared(spec);
  final got = <String, String>{
    for (final s in states) 'rows $s': '${c[s]}',
    'rows total': '$total',
    for (final s in states) 'pct $s': percent(c[s]!, total),
    'pct N+L': percent(c['N']! + c['L']!, total),
    'pct N+L+W': percent(c['N']! + c['L']! + c['W']!, total),
  };
  final want = <String, String?>{
    for (final s in states) 'rows $s': d.rows[s]?.toString(),
    'rows total': d.rows['total']?.toString(),
    for (final s in states) 'pct $s': d.pct[s],
    'pct N+L': d.pct['N+L'],
    'pct N+L+W': d.pct['N+L+W'],
  };
  return [
    for (final k in got.keys)
      if (got[k] != want[k]) '$k: counted ${got[k]}, §3.8 says ${want[k]}',
  ];
}

void main(List<String> args) {
  final path = args.isEmpty ? 'docs/SPEC-v2-he.md' : args.first;
  final spec = File(path).readAsStringSync();
  final c = countMatrix(spec);
  final total = c.values.fold(0, (a, b) => a + b);
  for (final s in states) {
    stdout.writeln('$s\t${c[s]}\t${percent(c[s]!, total)}%');
  }
  stdout.writeln('total\t$total\tN+L ${percent(c['N']! + c['L']!, total)}% · '
      'N+L+W ${percent(c['N']! + c['L']! + c['W']!, total)}%');
  final diff = check(spec);
  if (diff.isEmpty) {
    stdout.writeln('AT-94 OK: matches §3.8');
  } else {
    stderr.writeln('AT-94 FAIL:\n  ${diff.join('\n  ')}');
    exitCode = 1;
  }
}
