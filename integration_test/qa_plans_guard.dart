// The dev business on :3031 has no subscription, so every sign-in meets the
// required-plans screen (auth_flow) and then the plans sheet (AppShell). The
// E2E suites are not about the in-app purchase: close both the way a user
// taps X, so the journeys under test start from home as before.
// Debug builds also push the customer-payment demo (clearing, out of scope)
// after "בקש תשלום" before D opens: close it too.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/router.dart' show navigatorKey;
import 'package:invoice/screens/billing/billing_screen.dart';

Timer? _guard;
final _closed = Expando<bool>();

/// Call once in a suite's main(), after the binding is initialised.
void dismissPlansDuringTests() {
  _guard ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (WidgetsBinding.instance.rootElement == null) return; // before the first pumpWidget/runApp
    for (final el in find.byType(PlansSheet).evaluate().toList()) {
      if (!el.mounted || _closed[el] == true) continue;
      final sheet = el.widget as PlansSheet;
      if (sheet.requiredForAccess) {
        _closed[el] = true;
        sheet.onExit?.call();
      } else if (ModalRoute.of(el)?.isCurrent ?? false) {
        _closed[el] = true;
        Navigator.of(el).pop();
      }
    }
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.popUntil((r) => r.settings.name != '/demo/customer-payment');
    }
  });
}
