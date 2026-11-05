// H state (squad A): cache first, then the network (F9 — H never waits).

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../api/client.dart';
import '../../api/inbox_api.dart';
import '../../api/models/models.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../state/session.dart';

class HomeController extends ChangeNotifier {
  HomeController({this.now});

  /// Injectable clock (tests).
  final DateTime Function()? now;

  HomeData? data;
  bool loading = false;

  /// Last load error (shown only when there is nothing to show; otherwise
  /// the offline banner covers a network error).
  ApiException? error;
  String? _business;
  String? _capsKey;
  bool _firstDataFrameLogged = false;
  int _generation = 0;

  bool get offline => (error?.isNetwork ?? false) || businessContext.offline;

  /// Paints the cache, then refreshes. [refreshMe] also re-reads /me
  /// (pull-to-refresh).
  Future<void> load({bool refreshMe = false}) async {
    final business = session.business?.businessId;
    final generation = ++_generation;
    _capsKey = capsKey(businessContext.caps);
    if (business != _business) {
      _business = business;
      data = null;
      error = null;
    }
    if (data == null) {
      final cached = await readCachedHome();
      if (generation != _generation) return;
      if (cached != null) {
        data = filterHome(cached, caps: businessContext.caps, dismissedSetup: await readDismissedSetup());
        _logFirstData();
        notifyListeners();
      }
    }
    loading = true;
    notifyListeners();
    try {
      if (refreshMe) await session.refreshBusiness();
      final fresh = await fetchHome(caps: businessContext.caps, now: now?.call());
      if (generation != _generation) return;
      data = fresh;
      error = null;
      _logFirstData();
    } on ApiException catch (e) {
      if (generation != _generation) return;
      error = e;
    } finally {
      if (generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// AT-97: Timeline event when H first has data.
  void _logFirstData() {
    if (_firstDataFrameLogged || data == null) return;
    _firstDataFrameLogged = true;
    developer.Timeline.instantSync('home_first_data_frame');
  }

  /// The selected business changed (S14) → drop what we show and reload.
  bool businessChanged() => session.business?.businessId != _business;

  /// §4.6 live role change: the caps differ from those [data] was filtered with.
  bool capsChanged() => _capsKey != null && capsKey(businessContext.caps) != _capsKey;

  /// Drops at once what the new caps may not see (amounts, cards) — before the
  /// reload that brings what they may now see.
  void applyCaps() {
    final d = data;
    if (d != null) data = filterHome(d, caps: businessContext.caps);
    notifyListeners();
  }

  /// A load still in flight (e.g. sign-out while home refreshes) must not
  /// notify a disposed controller: bumping the generation makes it a no-op.
  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}

/// Identity of a capability set: preset + granted caps.
String capsKey(Caps caps) =>
    '${caps.preset.name}|${(caps.all.map((c) => c.name).toList()..sort()).join(',')}';
