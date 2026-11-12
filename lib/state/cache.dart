import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny read-through JSON file cache (spec §7.4): show instantly, refresh in
/// the background.
///
/// Name entries per business, e.g. `AppCache.write('dashboard_$businessId', json)`.
///
/// Three places on disk:
/// - read-only data → Library/Caches (not in iCloud/iTunes backups; iOS may
///   purge it, which only costs a refetch);
/// - pending operations ([isPending]: idempotency state of an issue / payment /
///   credit in progress) → Application Support/pending, which iOS never purges.
///   AppDelegate.swift marks this and user-entered local records excluded from backup;
/// - user-entered local records → Application Support/user_data, which iOS does
///   not purge. Composer drafts ([isUserEntered]) live there too.
///
/// Entries are kept per signed-in user ([userScope]): on a shared device one
/// member never sees what was cached while another member was signed in.
abstract final class AppCache {
  static Directory? _dir;
  static Directory? _pendingDir;
  static Directory? _userDataDir;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationCacheDirectory()).path}/cache');

  /// Overridable in tests (pending entries then go to `<dir>/pending`).
  static Future<Directory> Function() directoryProvider = _defaultDirectory;

  /// Entries that must survive an expiry sign-out and must not be purged:
  /// losing them could issue a duplicate numbered document.
  static bool isPending(String name) =>
      name.startsWith('pending_') || name.startsWith('nd_pending_issue_');

  /// The signed-in user (set by the session). Null before sign-in.
  static String? userScope;

  /// Read before the user is known (offline cold start).
  static const Set<String> _unscoped = {'account'};

  /// Typed by the user and not on the server yet: never in Library/Caches.
  static bool isUserEntered(String name) =>
      name.startsWith('nd_local_draft_') || name.startsWith('team_grants_');

  static String _safe(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static String _scoped(String name) {
    final user = userScope;
    if (user == null || _unscoped.contains(name)) return name;
    return 'u_${user}__$name';
  }

  static Future<Directory> _cacheDir() async =>
      _dir ??= await directoryProvider();

  static Future<Directory> _pendingDirectory() async =>
      _pendingDir ??= directoryProvider == _defaultDirectory
      ? Directory('${(await getApplicationSupportDirectory()).path}/pending')
      : Directory('${(await _cacheDir()).path}/pending');

  static Future<Directory> _userDataDirectory() async =>
      _userDataDir ??= directoryProvider == _defaultDirectory
      ? Directory('${(await getApplicationSupportDirectory()).path}/user_data')
      : Directory('${(await _cacheDir()).path}/user_data');

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
    if (isPending(name)) {
      final dir = await _pendingDirectory();
      if (!dir.existsSync()) await dir.create(recursive: true);
      return File('${dir.path}/${_safe(name)}.json');
    }
    final dir = isUserEntered(name)
        ? await _userDataDirectory()
        : await _cacheDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/${_safe(_scoped(name))}.json');
  }

  /// Where a user-entered entry lived before it moved (unscoped, in Caches).
  static Future<File> _legacyFile(String name) async =>
      File('${(await _cacheDir()).path}/${_safe(name)}.json');

  /// Cached JSON or null (missing / unreadable).
  static Future<Object?> read(String name) async {
    try {
      final file = await _file(name);
      if (file.existsSync()) return jsonDecode(await file.readAsString());
      if (!isUserEntered(name)) return null;
      // Silent one-time move of a draft saved by an older version.
      final legacy = await _legacyFile(name);
      if (legacy.path == file.path || !legacy.existsSync()) return null;
      final value = jsonDecode(await legacy.readAsString());
      await write(name, value);
      await legacy.delete();
      return value;
    } on Object {
      return null;
    }
  }

  static Future<void> write(String name, Object? json) async {
    final file = await _file(name);
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }

  /// Durable device-local JSON for user-entered records. Unlike the cache,
  /// this survives OS cache eviction and is cleared on explicit sign-out or
  /// account deletion, but preserved when a session expires.
  static Future<Object?> readUserData(
    String name, {
    bool strict = false,
  }) async {
    try {
      final dir = await _userDataDirectory();
      final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final file = File('${dir.path}/$safe.json');
      if (!file.existsSync()) return null;
      return jsonDecode(await file.readAsString());
    } on Object {
      if (strict) rethrow;
      return null;
    }
  }

  static Future<void> writeUserData(String name, Object? json) async {
    final dir = await _userDataDirectory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final file = File('${dir.path}/$safe.json');
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(file.path);
  }

  static Future<void> remove(String name) async {
    final file = await _file(name);
    if (file.existsSync()) await file.delete();
    if (isUserEntered(name)) {
      final legacy = await _legacyFile(name);
      if (legacy.existsSync()) await legacy.delete();
    }
  }

  /// True when an issue / payment / credit is still in progress on this device.
  static Future<bool> hasPending() async {
    try {
      final dir = await _pendingDirectory();
      if (dir.existsSync() &&
          dir.listSync().any((f) => f.path.endsWith('.json'))) {
        return true;
      }
      final userData = await _userDataDirectory();
      if (!userData.existsSync()) return false;
      for (final file in userData.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (!name.startsWith('customer_crm_') ||
            !name.endsWith('.json') ||
            name.contains('_conflict_backup')) {
          continue;
        }
        final value = jsonDecode(await file.readAsString());
        if (value is Map &&
            value['pending'] is List &&
            (value['pending'] as List).isNotEmpty) {
          return true;
        }
      }
      return false;
    } on Object {
      // An unreadable queue must not silently bypass the sign-out confirmation.
      return true;
    }
  }

  /// Wipes the cache. Pending operations and user-entered local records are
  /// wiped only on explicit sign-out / account deletion, never on token expiry.
  static Future<void> clearAll({bool keepPending = false}) async {
    final dir = await _cacheDir();
    final pending = await _pendingDirectory();
    final marker = await _installMarker();
    final userData = await _userDataDirectory();
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        if (e.path == pending.path ||
            e.path == marker.path ||
            e.path == userData.path) {
          continue;
        }
        await e.delete(recursive: true);
      }
    }
    // Files only: the directory keeps its exclude-from-backup flag.
    if (!keepPending && pending.existsSync()) {
      for (final e in pending.listSync()) {
        await e.delete(recursive: true);
      }
    }
    if (!keepPending && userData.existsSync()) {
      for (final e in userData.listSync()) {
        await e.delete(recursive: true);
      }
    }
  }
}
