// Walkthrough 2026-11-17 #10a: the plan is a HARD gate at the moment of
// issuing. The server refuses to number any document without an active plan
// (402 SUBSCRIPTION_REQUIRED) or above the month's quota (402
// INVOICE_QUOTA_EXCEEDED); every issue path (Composer, receipts, credit,
// quote conversion, retainers, approvals) gets that answer. Here the answer
// opens the plans sheet on top of whatever is on screen — a modal sheet,
// never a stack reset (TestFlight build 8 crashed when a background gate did
// pushAndRemoveUntil mid-action). The refused screen keeps its own inline
// error and the draft.
//
// Without a plan the app stays usable: sign in, read, export, billing,
// account deletion. Only the owner buys (owner-only checkout); others read
// the inline error ("…בעל העסק…").

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/client.dart';
import '../../router.dart' show navigatorKey;
import '../../state/business_context.dart';
import '../../state/caps.dart';
import 'billing_screen.dart' show showBillingPlans;

abstract final class PlanGate {
  static StreamSubscription<ApiEvent>? _sub;
  static bool _open = false;

  /// Plans sheet opener (tests replace it).
  static Future<void> Function(BuildContext context) showPlans =
      showBillingPlans;

  /// Once, from main() (idempotent).
  static void install() {
    unawaited(_sub?.cancel());
    _sub = ApiClient.instance.events
        .where((e) => e == ApiEvent.planRequired)
        .listen((_) => unawaited(_open ? Future<void>.value() : _show()));
  }

  static Future<void> _show() async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (!businessContext.can(Cap.owner)) return;
    _open = true;
    try {
      await showPlans(context);
    } finally {
      _open = false;
    }
  }

  @visibleForTesting
  static bool get isOpen => _open;

  /// Tests: a sheet left open by an earlier test.
  @visibleForTesting
  static void reset() => _open = false;
}
