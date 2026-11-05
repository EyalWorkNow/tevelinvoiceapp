import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny read-through JSON file cache (spec §7.4): show instantly, refresh in
/// the background.
///
/// Name entries per business, e.g. `AppCache.write('dashboard_$businessId', json)`.
///
/// Two places on disk:
/// - read-only data → Library/Caches (not in iCloud/iTunes backups; iOS may
///   purge it, which only costs a refetch);
/// - pending operations ([isPending]: idempotency state of an issue / payment /
///   credit in progress) → Application Support/pending, which iOS never purges.
///   AppDelegate.swift marks that directory excluded from backup.
abstract final class AppCache {
  static Directory? _dir;
  static Directory? _pendingDir;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/cache');

  /// Overridable in tests (pending entries then go to `<dir>/pending`).
  static Future<Directory> Function() directoryProvider = _defaultDirectory;

  /// Entries that must survive an expiry sign-out and must not be purged:
  /// losing them could issue a duplicate numbered document.
  static bool isPending(String name) =>
      name.startsWith('pending_') || name.startsWith('nd_pending_issue_');

  static Future<Directory> _cacheDir() async => _dir ??= await directoryProvider();

  static Future<Directory> _pendingDirectory() async => _pendingDir ??=
      directoryProvider == _defaultDirectory
          ? Directory('${(await getApplicationSupportDirectory()).path}/pending')
          : Directory('${(await _cacheDir()).path}/pending');

  /// Marker next to the pending directory (never wiped by [clearAll]). It is
  /// gone after an uninstall, while the Keychain is not.
  static Future<File> _installMarker() async =>
      File('${(await _pendingDirectory()).parent.path}/.installed');

  /// True on the first launch after install (and records that it ran).
  static Future<bool> isFirstLaunch() async {
    try {
      final marker = await _installMarker();
      if (marker.existsSync()) return false;
      await marker.parent.create(recursive: true);
      await marker.writeAsString('1', flush: true);
      return true;
    } on Object {
      return false;
    }
  }

  static Future<File> _file(String name) async {
    final dir = isPending(name) ? await _pendingDirectory() : await _cacheDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return File('${dir.path}/$safe.json');
  }

  /// Cached JSON or null (missing / unreadable).
  static Future<Object?> read(String name) async {
    try {
      final file = await _file(name);
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString());
    } on Object {
      return null;
    }
  }

  static Future<void> write(String name, Object? json) async {
    final file = await _file(name);
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }

  static Future<void> remove(String name) async {
    final file = await _file(name);
    if (file.existsSync()) await file.delete();
  }

  /// True when an issue / payment / credit is still in progress on this device.
  static Future<bool> hasPending() async {
    try {
      final dir = await _pendingDirectory();
      return dir.existsSync() && dir.listSync().any((f) => f.path.endsWith('.json'));
    } on Object {
      return false;
    }
  }

  /// Wipes the cache. Pending operations are wiped only when [keepPending]
  /// is false (explicit sign-out / account deletion), never on token expiry.
  static Future<void> clearAll({bool keepPending = false}) async {
    final dir = await _cacheDir();
    final pending = await _pendingDirectory();
    final marker = await _installMarker();
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e.path == pending.path || e.path == marker.path) continue;
        await e.delete(recursive: true);
      }
    }
    // Files only: the directory keeps its exclude-from-backup flag.
    if (!keepPending && pending.existsSync()) {
      for (final e in pending.listSync()) {
        await e.delete(recursive: true);
      }
    }
  }
}
