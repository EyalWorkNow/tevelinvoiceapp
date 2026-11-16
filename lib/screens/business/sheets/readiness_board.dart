// C6 · the accountant's board in S14 (QA 2026-11-16, persona 06 idea 2).
// For a member who is the accountant in several businesses, each row of the
// switch-business sheet shows that business's "מוכן לרו״ח" score, least ready
// first. Built on the existing membership list (session.businesses / BE-24
// search); scores load lazily — only for the rows on screen, a few at a time —
// and the sheet pages the list ([ReadinessBoard.pageSize] rows per page).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../api/models/models.dart' show Business;
import '../../../api/readiness_api.dart';

/// Membership roles that make a business part of the board. READ_ONLY is the
/// P0 accountant preset (READ_ONLY + expense:approve); a plain viewer's row
/// gets no score (the server answers 403 → no badge).
const Set<String> accountantRoles = {
  'ACCOUNTANT',
  'ACCOUNTANT_REP',
  'READ_ONLY',
};
const Set<String> _accountantOnly = {'ACCOUNTANT', 'ACCOUNTANT_REP'};

class ReadinessBoard extends ChangeNotifier {
  ReadinessBoard({
    Future<Readiness?> Function(String businessId)? fetch,
    this.maxInFlight = 3,
  }) : _fetch = fetch ?? fetchReadinessFor;

  final Future<Readiness?> Function(String businessId) _fetch;
  final int maxInFlight;

  static const int pageSize = 20;

  /// Scores survive the sheet (one sheet open = no refetch within 5 minutes).
  static final Map<String, (int?, DateTime)> _cache = {};
  static const Duration _ttl = Duration(minutes: 5);

  /// Test hook.
  @visibleForTesting
  static void resetCache() => _cache.clear();

  final Set<String> _loading = {};
  final List<String> _queue = [];
  bool _disposed = false;

  /// The board applies to a member who is the accountant in 2+ businesses:
  /// [actingAsAccountant] = the open business's caps are an accountant preset.
  static bool appliesTo(
    List<Business> businesses, {
    bool actingAsAccountant = false,
  }) =>
      businesses.where(rowApplies).length > 1 &&
      (actingAsAccountant ||
          businesses.any((b) => _accountantOnly.contains(b.role)));

  static bool rowApplies(Business b) => accountantRoles.contains(b.role);

  /// Known score (null = not loaded / not served).
  int? scoreOf(String businessId) {
    final hit = _cache[businessId];
    if (hit == null || DateTime.now().difference(hit.$2) > _ttl) return null;
    return hit.$1;
  }

  /// True once a fetch for [businessId] finished (a null score = not served).
  bool known(String businessId) {
    final hit = _cache[businessId];
    return hit != null && DateTime.now().difference(hit.$2) <= _ttl;
  }

  bool isLoading(String businessId) =>
      _loading.contains(businessId) || _queue.contains(businessId);

  /// Accountant rows least ready first (unknown scores after, in their
  /// original order); the other rows keep their place at the end.
  List<Business> sort(List<Business> list) {
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    int rank((int, Business) e) {
      if (!rowApplies(e.$2)) return 1 << 20;
      return scoreOf(e.$2.businessId) ?? 1000;
    }

    indexed.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Loads the scores of [visible] accountant rows not known yet.
  void ensure(Iterable<Business> visible) {
    var added = false;
    for (final b in visible) {
      final id = b.businessId;
      if (!rowApplies(b) || known(id) || isLoading(id)) continue;
      _queue.add(id);
      added = true;
    }
    if (added) _pump();
  }

  void _pump() {
    while (_loading.length < maxInFlight && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _loading.add(id);
      unawaited(_load(id));
    }
  }

  Future<void> _load(String id) async {
    int? score;
    try {
      score = (await _fetch(id))?.score;
    } on Object {
      score = null; // offline / no access: the row shows no badge
    }
    _cache[id] = (score, DateTime.now());
    _loading.remove(id);
    if (_disposed) return;
    _pump();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    super.dispose();
  }
}
