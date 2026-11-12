// The selected business as the UI sees it (SPEC-v2 §4.2, §4.6, §4.7). Owner: INT.
//
// Wraps the session: capabilities ([caps]), business type, display name, and
// the refresh rules of §4.6:
// * GET /me on open (session.restore), on business switch (session),
//   on foreground after > 60 s ([onResumed]), and on every capability 403
//   ([ApiEvent.forbidden] from client.dart);
// * a 403 → [permissionsChanged] fires (the shell shows "ההרשאות שלך עודכנו"
//   and the router leaves a screen that is no longer allowed);
// * capabilities older than 24 h are not used (session.freshMe).

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/models/models.dart';
import 'caps.dart';
import 'session.dart';

class BusinessContext extends ChangeNotifier {
  BusinessContext({
    SessionController? sessionController,
    ApiClient? client,
    DateTime Function()? clock,
  }) : _session = sessionController ?? session,
       _client = client ?? ApiClient.instance,
       _clock = clock ?? DateTime.now {
    _session.addListener(_onSession);
    // Root zone: this app-wide singleton outlives whichever zone first touched
    // it (matters in widget tests, where each test runs in its own fake zone).
    _sub = Zone.root.run(
      () => _client.events.listen((e) {
        if (e == ApiEvent.forbidden) unawaited(handleForbidden());
      }),
    );
  }

  final SessionController _session;
  final ApiClient _client;
  final DateTime Function() _clock;
  late final StreamSubscription<ApiEvent> _sub;

  /// Minimum gap between /me refreshes on foreground (§4.6).
  static const Duration resumeRefreshAfter = Duration(seconds: 60);

  Caps? _caps;
  Me? _capsFrom;
  bool _refreshing = false;

  final StreamController<void> _permissionsChanged =
      StreamController<void>.broadcast();

  /// Fires after a capability 403 refreshed /me (toast + route guard).
  Stream<void> get permissionsChanged => _permissionsChanged.stream;

  /// Current capabilities; [Caps.none] without a fresh /me.
  Caps get caps {
    final me = _session.freshMe;
    if (me == null) return Caps.none;
    if (!identical(me, _capsFrom)) {
      _capsFrom = me;
      _caps = Caps.fromMe(me);
    }
    return _caps!;
  }

  bool can(Cap cap) => caps.can(cap);

  Me? get me => _session.freshMe;
  BusinessProfile? get profile => _session.profile;
  Business? get business => _session.business;

  /// OSEK_PATUR | OSEK_MURSHE | COMPANY | PARTNERSHIP | NONPROFIT.
  /// /me (BE-02) first, else /business/profile, else OSEK_MURSHE.
  String get businessType =>
      _session.me?.businessType ??
      _session.profile?.businessType ??
      'OSEK_MURSHE';

  /// §4.7: no VAT component at all (עוסק פטור / עמותה).
  bool get isVatExempt =>
      businessType == 'OSEK_PATUR' || businessType == 'NONPROFIT';

  /// Header name: trading name, else legal name, else the membership name.
  String get displayName =>
      _session.profile?.displayName ?? _session.business?.legalName ?? '';

  /// The header opens S14 only with more than one business (§6.H).
  bool get hasManyBusinesses => _session.businesses.length > 1;

  bool get offline => _session.offline;

  /// App back in the foreground: refresh /me if the last fetch is > 60 s old.
  Future<void> onResumed() async {
    final at = _session.meFetchedAt;
    if (_session.business == null ||
        _session.status != SessionStatus.signedIn) {
      return;
    }
    if (at != null && _clock().difference(at) < resumeRefreshAfter) return;
    await _refresh();
  }

  /// A capability 403 (§4.6): refresh /me, then tell the shell.
  Future<void> handleForbidden() async {
    if (_session.business == null) return;
    await _refresh();
    _permissionsChanged.add(null);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _session.refreshBusiness();
    } on ApiException {
      // Offline / expired: the session handles it; caps stay as they were.
    } finally {
      _refreshing = false;
    }
  }

  void _onSession() => notifyListeners();

  @override
  void dispose() {
    _session.removeListener(_onSession);
    unawaited(_sub.cancel());
    unawaited(_permissionsChanged.close());
    super.dispose();
  }
}

/// The app-wide business context.
final BusinessContext businessContext = BusinessContext();
