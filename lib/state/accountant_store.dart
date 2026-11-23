// The accountant's overview (GET /mobile/accountant/clients): one call for all
// client businesses, their task counts, readiness, pending access requests and
// the office name. Loaded on each open of the home row / clients list (no
// background refresh, spec feature 3 "עדכון").

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/accountant_api.dart';
import '../api/models/models.dart' show Business;
import 'session.dart';

/// Membership roles of an accountant (READ_ONLY = the P0 preset with
/// expense:approve; a plain viewer's row simply gets no counts).
const Set<String> accountantMembershipRoles = {
  'ACCOUNTANT',
  'ACCOUNTANT_REP',
  'READ_ONLY',
};

bool isAccountantMembership(Business b) =>
    accountantMembershipRoles.contains(b.role);

/// Roles that are an accountant without looking at grants.
const Set<String> _strictAccountantRoles = {'ACCOUNTANT', 'ACCOUNTANT_REP'};

class AccountantStore extends ChangeNotifier {
  AccountantStore() {
    // Another member may sign in next: nothing of this one's survives.
    session.addListener(() {
      if (session.status == SessionStatus.signedOut && overview != null) {
        reset();
      }
    });
  }

  AccountantOverview? overview;
  bool loading = false;
  Object? error;

  /// null = not probed yet; false = the server has no accountant endpoints.
  bool? supported;

  Future<void>? _inFlight;

  /// The user is an accountant (profile flag or an accountant membership).
  bool get isAccountant =>
      overview?.isAccountant == true ||
      session.businesses.any((b) => _strictAccountantRoles.contains(b.role));

  /// Count of accountant memberships known from the session (the loading /
  /// error state of the home row).
  int get sessionClientCount =>
      session.businesses.where(isAccountantMembership).length;

  Future<void> load() => _inFlight ??= _load().whenComplete(() {
    _inFlight = null;
  });

  Future<void> _load() async {
    loading = true;
    error = null;
    // May start from a widget's initState (mid-build): tell listeners after.
    scheduleMicrotask(notifyListeners);
    try {
      final o = await fetchAccountantClients();
      supported = o != null;
      overview = o;
    } on Object catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// After PUT /mobile/accountant/profile.
  void markAccountant(String officeName) {
    final o = overview;
    overview = AccountantOverview(
      isAccountant: true,
      officeName: officeName,
      clients: o?.clients ?? const [],
      requests: o?.requests ?? const [],
    );
    supported = true;
    notifyListeners();
  }

  @visibleForTesting
  void reset() {
    overview = null;
    loading = false;
    error = null;
    supported = null;
    _inFlight = null;
  }
}

final AccountantStore accountantStore = AccountantStore();

/// Set when a client row was tapped: the accountant home (R) scrolls to its
/// "לטיפול" section once loaded, then clears it.
final ValueNotifier<bool> accountantFocusTodo = ValueNotifier<bool>(false);
