// Local error log (QA 2026-11-15). TestFlight shows no native crash for a
// Flutter exception, so the app keeps its own: the last [ErrorLog.capacity]
// framework / async errors with a timestamp, the visible route and the first
// [ErrorLog.stackLines] stack lines, in one JSON file on the device. Nothing
// is uploaded; the user sends it from Settings → "שלח יומן תקלות" through the
// share sheet.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ErrorLogEntry {
  const ErrorLogEntry({
    required this.at,
    required this.kind,
    required this.error,
    required this.route,
    required this.stack,
  });

  factory ErrorLogEntry.fromJson(Map<String, dynamic> j) => ErrorLogEntry(
    at:
        DateTime.tryParse('${j['at']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    kind: '${j['kind']}',
    error: '${j['error']}',
    route: j['route'] as String?,
    stack: [for (final l in (j['stack'] as List? ?? const [])) '$l'],
  );

  final DateTime at;
  final String kind;
  final String error;
  final String? route;
  final List<String> stack;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'kind': kind,
    'error': error,
    'route': route,
    'stack': stack,
  };

  String toText() => [
    '${at.toIso8601String()}  [$kind]  ${route ?? '-'}',
    error,
    ...stack.map((l) => '    $l'),
  ].join('\n');
}

class ErrorLog {
  ErrorLog._();
  static final ErrorLog instance = ErrorLog._();

  static const int capacity = 50;
  static const int stackLines = 15;
  static const int maxErrorChars = 2000;

  /// The visible route name; main.dart wires the router's stack.
  String? Function() currentRoute = () => null;

  /// Where the log lives. Tests replace it.
  Future<File> Function() fileProvider = () async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/error_log.json');
  };

  final List<ErrorLogEntry> _entries = [];
  bool _loaded = false;
  Future<void> _io = Future<void>.value();

  List<ErrorLogEntry> get entries => List.unmodifiable(_entries);

  /// Chains onto FlutterError.onError and PlatformDispatcher.onError. The
  /// previous handlers still run (console output in debug / release).
  ///
  /// Only over the default handler: under flutter_test the binding owns
  /// FlutterError.onError (and fails a test that leaves it changed), so the
  /// app's main() inside a test leaves it alone.
  void install() {
    if (FlutterError.onError != FlutterError.presentError) return;
    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record(
        'flutter${details.library == null ? '' : ' · ${details.library}'}',
        details.exceptionAsString(),
        details.stack,
      );
      (previousFlutter ?? FlutterError.presentError)(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record('async', error, stack);
      return previousPlatform?.call(error, stack) ?? false;
    };
    unawaited(load());
  }

  Future<void> load() => _serial(() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await fileProvider();
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString());
      if (list is! List) return;
      final old = [
        for (final e in list)
          if (e is Map<String, dynamic>) ErrorLogEntry.fromJson(e),
      ];
      _entries.insertAll(0, old);
      _trim();
    } on Object {
      // A broken log file is replaced on the next write.
    }
  });

  /// Never throws: it runs inside the error handlers.
  void record(String kind, Object error, StackTrace? stack) {
    try {
      var text = '$error';
      if (text.length > maxErrorChars) {
        text = '${text.substring(0, maxErrorChars)}…';
      }
      String? route;
      try {
        route = currentRoute();
      } on Object {
        route = null;
      }
      _entries.add(
        ErrorLogEntry(
          at: DateTime.now(),
          kind: kind,
          error: text,
          route: route,
          stack: '${stack ?? ''}'
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .take(stackLines)
              .toList(),
        ),
      );
      _trim();
      unawaited(_save());
    } on Object {
      // Logging must never add an error of its own.
    }
  }

  void _trim() {
    if (_entries.length > capacity) {
      _entries.removeRange(0, _entries.length - capacity);
    }
  }

  Future<void> _save() => _serial(() async {
    try {
      final f = await fileProvider();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode([for (final e in _entries) e.toJson()]),
        flush: true,
      );
    } on Object {
      // Disk full / sandbox: the in-memory copy is still shareable.
    }
  });

  Future<void> clear() async {
    _entries.clear();
    await _save();
  }

  /// Plain-text report (newest first).
  String report({String? header}) => [
    ?header,
    'errors: ${_entries.length}',
    '',
    for (final e in _entries.reversed) '${e.toText()}\n',
  ].join('\n');

  Future<void> _serial(Future<void> Function() job) {
    final next = _io.then((_) => job());
    _io = next.catchError((Object _) {});
    return next;
  }
}

/// Shares the log as a .txt file. False when it is empty (nothing shared).
Future<bool> Function({String? header}) shareErrorLog = _shareErrorLog;

Future<bool> _shareErrorLog({String? header}) async {
  final log = ErrorLog.instance;
  await log.load();
  if (log.entries.isEmpty) return false;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/tevel-error-log.txt');
  await file.writeAsString(log.report(header: header), flush: true);
  try {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'text/plain')]),
    );
  } finally {
    if (file.existsSync()) await file.delete();
  }
  return true;
}
