// Deep-link chips of the help assistant: a help-corpus location → the screen.
// Locations are §5 routes (lib/router.dart routeTable, opened with go()) or
// one of the help extras below (screens reached through typed helpers, not
// routes). The KB coverage test (test/help/kb_coverage_test.dart) checks the
// corpus uses only these.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_shell.dart' show AppTab;
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../billing/billing_screen.dart' show showBillingPlans;
import '../signature/signature_screen.dart' show openSignatureScreen;

/// Locations that are not §5 routes but have a typed opener.
const Set<String> helpExtraLocations = {
  '/sign-requests',
  '/customers/import',
  '/expenses/capture',
  '/profile',
  '/signature',
  '/billing',
  '/help',
  // FIXA (2026-11-18): the bell's "עדכונים" and the Home search.
  '/notifications',
  '/search',
};

/// True when [location] can be opened from a chip in this build.
bool isHelpLocation(String location) {
  final path = Uri.tryParse(location)?.path ?? '';
  if (helpExtraLocations.contains(path)) return true;
  final route = AppRoute.parse(location);
  return route != null && !route.pattern.contains(':id');
}

/// Opens [location]; false when this build does not know it (a placeholder
/// entry for a screen that is not released yet) or the caps refuse it.
Future<bool> openHelpLocation(BuildContext context, String location) async {
  final path = Uri.tryParse(location)?.path ?? '';
  switch (path) {
    case '/help':
      return true; // already here
    case '/sign-requests':
      unawaited(openSignRequests(context));
      return true;
    case '/customers/import':
      unawaited(openCustomerImport(context));
      return true;
    case '/expenses/capture':
      unawaited(openExpenseCapture(context));
      return true;
    case '/signature':
      unawaited(openSignatureScreen(context));
      return true;
    case '/billing':
      unawaited(showBillingPlans(context));
      return true;
    case '/notifications':
      unawaited(openNotifications(context));
      return true;
    case '/search':
      // The Home search field is for members who see documents (R).
      if (!businessContext.caps.can(Cap.docView)) return false;
      unawaited(openGlobalSearch(context));
      return true;
    case '/profile':
      selectTab(AppTab.profile);
      Navigator.of(context).popUntil((r) => r.isFirst);
      return true;
  }
  if (!isHelpLocation(location)) return false;
  return go(location, context: context);
}
