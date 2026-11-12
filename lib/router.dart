// The ONE navigation map (SPEC-v2 §5). Owner: INT.
//
// Plain Navigator + named locations — no router library. Screens open other
// screens only through the helpers below (or [go] with a location string), so
// the route list lives here and AT-93 can compare it with the spec.
// Sheets are opened by their own show*() functions in the owning squad's
// folder (listed in [sheetRegistry]).
//
// Deep links: tevel://<path> (Info.plist CFBundleURLTypes) carries the same
// locations, e.g. tevel://doc/123, tevel://compose?intent=PAID. A link that
// arrives before sign-in is kept and opened once the app reaches home.

import 'dart:async';

import 'package:flutter/material.dart';

import 'ui/widgets/notch_notice.dart';
import 'app_shell.dart';
import 'ui/app_page_route.dart';
import 'screens/activity/activity_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/business/business_screen.dart';
import 'screens/business/delete_account_screen.dart';
import 'screens/compose/compose_screen.dart';
import 'screens/document/document_screen.dart';
import 'screens/expense/expense_capture_screen.dart';
import 'screens/expense/expenses_screen.dart';
import 'screens/expense/expense_overview_screen.dart';
import 'screens/people/person_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'state/business_context.dart';
import 'state/caps.dart';
import 'state/session.dart';
import 'util/labels/common_he.dart';

/// Root navigator (MaterialApp.navigatorKey) for resets without a context.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Root messenger (MaterialApp.scaffoldMessengerKey) for app-wide toasts.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Custom URL scheme registered in ios/Runner/Info.plist.
const String deepLinkScheme = 'tevel';

// ---- route table (§5, AT-93) ------------------------------------------------

/// The 10 screens of §5.
enum ScreenId { a, h, l, c, d, p, p2, e, r, b }

/// §5 routes → screen. Exactly the spec list; AT-93 (test/router_test.dart)
/// compares it and checks the 10 screens.
const Map<String, ScreenId> routeTable = {
  '/gate': ScreenId.a,
  '/setup': ScreenId.a,
  '/home': ScreenId.h,
  '/activity': ScreenId.l,
  '/compose': ScreenId.c,
  '/doc/:id': ScreenId.d,
  '/quote/:id': ScreenId.d,
  '/people': ScreenId.p,
  '/person/:id': ScreenId.p2,
  '/expenses': ScreenId.e,
  '/expenses/overview': ScreenId.e,
  '/reports': ScreenId.r,
  '/reports/:kind': ScreenId.r,
  '/business': ScreenId.b,
  '/business/:section': ScreenId.b,
};

/// The 8 sheets of §5 → file that owns the show*() function (AT-93).
const Map<String, String> sheetRegistry = {
  'S1': 'screens/compose/sheets/s1_create.dart',
  'S2': 'screens/people/sheets/s2_customer.dart',
  'S3': 'screens/compose/sheets/s3_more.dart',
  'S5': 'screens/document/sheets/s5_payment.dart',
  'S6': 'screens/document/sheets/s6_share.dart',
  'S8': 'screens/document/sheets/s8_cancel.dart',
  'S13': 'screens/business/sheets/s13_editor.dart',
  'S14': 'screens/business/sheets/s14_switch.dart',
};

/// /business/:section slugs (B sub-pages, §6.B / §13). Squad E may ask INT to
/// append; unknown slugs open the business list.
enum BusinessSection {
  notifications,
  integrations,
  team,
  profile,
  branding,
  approvals,
  shaam,
  account,
  desktop,
  numbering,
}

/// Capability a business sub-page needs (§4.4). `account` and `desktop` are for everyone.
Cap? sectionCap(BusinessSection s) => switch (s) {
  BusinessSection.team => Cap.teamManage,
  BusinessSection.integrations => Cap.settingsBusiness,
  BusinessSection.profile => Cap.settingsBusiness,
  BusinessSection.branding => Cap.settingsDesign,
  BusinessSection.approvals => Cap.settingsBusiness,
  BusinessSection.shaam => null,
  BusinessSection.account || BusinessSection.notifications => null,
  BusinessSection.desktop => null,
  BusinessSection.numbering => Cap.settingsNumbering,
};

/// Query keys that carry an entity id into an API path.
const Set<String> idQueryKeys = {
  'businessId',
  'id',
  'customerId',
  'fromDocId',
  'fromQuoteId',
  'draftId',
};

final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Route ids (UUIDs on the server, short tokens in fakes): letters, digits,
/// '-' and '_' only — never '/', '.', '?', '%' or '#'.
bool isSafeId(String v) => _safeId.hasMatch(v);

/// A parsed location: one §5 pattern + its path parameters + query.
class AppRoute {
  const AppRoute(this.pattern, {this.params = const {}, this.query = const {}});

  final String pattern;
  final Map<String, String> params;
  final Map<String, String> query;

  ScreenId get screen => routeTable[pattern]!;

  /// Parses '/doc/1', 'tevel://doc/1', 'tevel:///doc/1?x=y'. Null when the
  /// location is not one of the §5 routes.
  static AppRoute? parse(String location) {
    var uri = Uri.tryParse(location.trim());
    if (uri == null) return null;
    if (uri.scheme == deepLinkScheme) {
      // tevel://doc/1 → host "doc", path "/1".
      final path = [
        if (uri.host.isNotEmpty) uri.host,
        ...uri.pathSegments,
      ].join('/');
      uri = Uri(
        path: '/$path',
        queryParameters: uri.queryParameters.isEmpty
            ? null
            : uri.queryParameters,
      );
    } else if (uri.hasScheme) {
      return null; // https links are universal links (BE-00 §5), not routes yet.
    }
    // Ids from a link go into API paths ('/documents/$id'), so a crafted
    // tevel://doc/..%2F..%2Fx must not resolve elsewhere: ids are tokens only.
    for (final k in idQueryKeys) {
      final v = uri.queryParameters[k];
      if (v != null && !isSafeId(v)) return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (final pattern in routeTable.keys) {
      final parts = pattern.substring(1).split('/');
      if (parts.length != segments.length) continue;
      final params = <String, String>{};
      var ok = true;
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].startsWith(':')) {
          if (!isSafeId(segments[i])) return null;
          params[parts[i].substring(1)] = segments[i];
        } else if (parts[i] != segments[i]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return AppRoute(pattern, params: params, query: uri.queryParameters);
      }
    }
    return null;
  }

  /// Capability the route needs; null = any signed-in member.
  Cap? get requiredCap => switch (pattern) {
    '/compose' => Cap.docDraft,
    '/activity' || '/doc/:id' || '/quote/:id' => Cap.docView,
    '/reports' || '/reports/:kind' => Cap.reportView,
    '/expenses/overview' => Cap.expenseApprove,
    '/business/:section' =>
      _sectionOf(params['section']) == null
          ? null
          : sectionCap(_sectionOf(params['section'])!),
    _ => null,
  };

  /// /expenses needs capture OR approve; everything else one [requiredCap].
  bool allowedFor(Caps caps) {
    if (pattern == '/expenses') {
      return caps.can(Cap.expenseCapture) || caps.can(Cap.expenseApprove);
    }
    final cap = requiredCap;
    return cap == null || caps.can(cap);
  }

  @override
  String toString() => 'AppRoute($pattern, $params, $query)';
}

BusinessSection? _sectionOf(String? slug) {
  for (final s in BusinessSection.values) {
    if (s.name == slug) return s;
  }
  return null;
}

/// Location string for a pattern + params + query (null values dropped).
String location(String path, [Map<String, String?> query = const {}]) {
  final q = {
    for (final e in query.entries)
      if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
  };
  return Uri(path: path, queryParameters: q.isEmpty ? null : q).toString();
}

// ---- opening a location ----------------------------------------------------

/// Builds the pushed screen for [route]; null for tab / reset routes.
Widget? screenFor(AppRoute route) {
  final p = route.params;
  final q = route.query;
  return switch (route.pattern) {
    '/activity' => ActivityScreen(chip: q['chip']),
    '/compose' => ComposeScreen(
      intent: q['intent'] ?? 'REQUEST',
      customerId: q['customerId'],
      fromDocId: q['fromDocId'],
      fromQuoteId: q['fromQuoteId'],
      draftId: q['draftId'],
    ),
    '/doc/:id' => DocumentScreen(id: p['id']!),
    '/quote/:id' => DocumentScreen(id: p['id']!, isQuote: true),
    '/person/:id' => PersonScreen(
      id: p['id']!,
      isSupplier: q['kind'] == 'supplier',
    ),
    '/expenses' => ExpensesScreen(expenseId: q['id']),
    '/expenses/overview' => const ExpenseOverviewScreen(),
    '/reports' => ReportsScreen(period: q['period']),
    '/reports/:kind' => ReportsScreen(kind: p['kind'], period: q['period']),
    '/business/:section' => BusinessScreen(section: p['section']),
    _ => null,
  };
}

/// Opens [locationString] (a §5 path or a tevel:// link). Tab routes switch
/// the tab of the running shell; /gate and /setup reset the stack. Returns
/// false when the location is unknown or not allowed for the current caps.
Future<bool> go(String locationString, {BuildContext? context}) async {
  final route = AppRoute.parse(locationString);
  if (route == null) return false;
  if (route.pattern == '/gate') {
    resetToLogin();
    return true;
  }
  if (session.status != SessionStatus.signedIn) return false;
  if (route.pattern == '/setup') {
    resetToSetup();
    return true;
  }
  var switchedBusiness = false;
  final targetBusiness = route.query['businessId'];
  if (targetBusiness != null && targetBusiness != session.business?.businessId) {
    if (session.status != SessionStatus.signedIn) return false;
    final matches = session.account?.businesses.where((business) => business.businessId == targetBusiness);
    if (matches == null || matches.isEmpty) return false;
    await session.selectBusiness(matches.first);
    resetToHome();
    await WidgetsBinding.instance.endOfFrame;
    switchedBusiness = true;
  }
  if (!route.allowedFor(businessContext.caps)) return false;
  switch (route.pattern) {
    case '/home':
      _toTab(AppTab.home);
      return true;
    case '/people':
      peopleChip.value = route.query['chip'];
      _toTab(AppTab.people);
      return true;
    case '/business':
      _toTab(AppTab.business);
      return true;
  }
  final screen = screenFor(route)!;
  final nav = context != null && context.mounted && !switchedBusiness
      ? Navigator.of(context)
      : navigatorKey.currentState;
  if (nav == null) return false;
  unawaited(
    nav.push(
      _page(screen, locationString, fullscreen: route.pattern == '/compose'),
    ),
  );
  return true;
}

PageRoute<T> _page<T>(Widget screen, String name, {bool fullscreen = false}) =>
    AppPageRoute<T>(
      builder: (_) => screen,
      settings: RouteSettings(name: name),
      fullscreenDialog: fullscreen,
    );

Future<T?> _push<T>(
  BuildContext context,
  Widget screen,
  String name, {
  bool fullscreen = false,
}) {
  return _pushPage(context, _page<T>(screen, name, fullscreen: fullscreen));
}

Future<T?> _pushPage<T>(
  BuildContext context,
  PageRoute<T> page, {
  bool replace = false,
}) {
  final origin = ModalRoute.of(context);
  // Ignore repeated taps from a page covered by another active route.
  // A popped route may still hand off to another screen before disposal.
  if (origin != null && origin.isActive && !origin.isCurrent) {
    return Future.value();
  }
  return replace
      ? Navigator.of(context).pushReplacement(page)
      : Navigator.of(context).push(page);
}

void _resetTo(Widget screen, String name) => navigatorKey.currentState
    ?.pushAndRemoveUntil(_page<void>(screen, name), (_) => false);

/// Selects a tab; if the shell is not the visible root, resets to it first.
void _toTab(AppTab tab) {
  currentTab.value = tab;
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  if (_shellMounted) {
    nav.popUntil((r) => r.isFirst);
  } else {
    resetToHome(tab: tab);
  }
}

bool get _shellMounted => AppShell.mounted;

// ---- stack resets ------------------------------------------------------------

/// Main app (tabs). [tab] picks the initial tab. Opens a pending deep link.
void resetToHome({AppTab tab = AppTab.home}) {
  currentTab.value = tab;
  _resetTo(const AppShell(), '/home');
  final pending = _pendingDeepLink;
  _pendingDeepLink = null;
  if (pending != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(go(pending)));
  }
}

/// A (sign-in). [expired] shows "פג תוקף ההתחברות".
void resetToLogin({bool expired = false}) =>
    _resetTo(LoginScreen(sessionExpired: expired), '/gate');

/// A (business setup) as the whole stack.
void resetToSetup() => _resetTo(const OnboardingScreen(), '/setup');

/// Switch the visible tab of the running AppShell.
void selectTab(AppTab tab) => currentTab.value = tab;

/// Initial chip for the people tab (/people?chip=); P reads and clears it.
final ValueNotifier<String?> peopleChip = ValueNotifier<String?>(null);

// ---- typed helpers (one per route) ------------------------------------------

/// L. [chip]: all | unpaid | drafts | quotes | inbox.
Future<void> openActivity(BuildContext context, {String? chip}) => _push(
  context,
  ActivityScreen(chip: chip),
  location('/activity', {'chip': chip}),
);

/// C. [intent]: PAID | REQUEST | QUOTE | TYPE:<code>.
Future<void> openCompose(
  BuildContext context, {
  required String intent,
  String? customerId,
  String? fromDocId,
  String? fromQuoteId,
  String? draftId,
}) => _push(
  context,
  ComposeScreen(
    intent: intent,
    customerId: customerId,
    fromDocId: fromDocId,
    fromQuoteId: fromQuoteId,
    draftId: draftId,
  ),
  location('/compose', {
    'intent': intent,
    'customerId': customerId,
    'fromDocId': fromDocId,
    'fromQuoteId': fromQuoteId,
    'draftId': draftId,
  }),
  fullscreen: true,
);

/// D (document). [replace] swaps the current route (Composer → D after issue).
/// [banner] / [openShare] / [justIssued] are D's after-issue options (§6.C).
Future<void> openDocument(
  BuildContext context,
  String id, {
  bool replace = false,
  String? banner,
  bool openShare = false,
  bool justIssued = false,
}) {
  final page = _page<void>(
    DocumentScreen(
      id: id,
      banner: banner,
      openShare: openShare,
      justIssued: justIssued,
    ),
    '/doc/$id',
  );
  return _pushPage(context, page, replace: replace);
}

/// D (quote).
Future<void> openQuote(
  BuildContext context,
  String id, {
  bool replace = false,
}) {
  final page = _page<void>(DocumentScreen(id: id, isQuote: true), '/quote/$id');
  return _pushPage(context, page, replace: replace);
}

/// P (tab). [chip]: all | debtors | suppliers.
void openPeople({String? chip}) {
  peopleChip.value = chip;
  _toTab(AppTab.people);
}

/// P2.
Future<void> openPerson(
  BuildContext context,
  String id, {
  bool supplier = false,
}) => _push(
  context,
  PersonScreen(id: id, isSupplier: supplier),
  location('/person/$id', {'kind': supplier ? 'supplier' : null}),
);

/// E (review / list). [expenseId] opens on one expense. [replace] swaps the
/// current route (capture → review card).
Future<void> openExpenses(
  BuildContext context, {
  String? expenseId,
  bool replace = false,
}) {
  final page = _page<void>(
    ExpensesScreen(expenseId: expenseId),
    location('/expenses', {'id': expenseId}),
  );
  return _pushPage(context, page, replace: replace);
}

/// Expense capture (camera / gallery / PDF) — not a counted screen (§5).
Future<void> openExpenseCapture(BuildContext context) => _push(
  context,
  const ExpenseCaptureScreen(),
  '/expenses/capture',
  fullscreen: true,
);

/// R.
Future<void> openReports(BuildContext context, {String? period}) => _push(
  context,
  ReportsScreen(period: period),
  location('/reports', {'period': period}),
);

/// R2.
Future<void> openReport(BuildContext context, String kind, {String? period}) =>
    _push(
      context,
      ReportsScreen(kind: kind, period: period),
      location('/reports/$kind', {'period': period}),
    );

/// B (tab).
void openBusiness() => _toTab(AppTab.business);

/// B sub-page.
Future<void> openBusinessSection(
  BuildContext context,
  BusinessSection section,
) => _push(
  context,
  BusinessScreen(section: section.name),
  '/business/${section.name}',
);

/// Account deletion (Apple 5.1.1(v)) — not a counted screen (§5).
Future<void> openDeleteAccount(BuildContext context) =>
    _push(context, const DeleteAccountScreen(), '/business/account/delete');

/// A (setup) pushed from B → פרטי העסק (identity not locked yet).
Future<void> openSetup(BuildContext context) =>
    _push(context, const OnboardingScreen(), '/setup');

// ---- deep links + capability guard -----------------------------------------

String? _pendingDeepLink;

/// Receives tevel:// links (Flutter iOS deep linking sends the full URL) and
/// enforces the route guard after a capability refresh (§4.6).
class AppRouter with WidgetsBindingObserver {
  AppRouter._();
  static final AppRouter instance = AppRouter._();

  StreamSubscription<void>? _caps;

  /// Call once from main() before runApp.
  void install() {
    WidgetsBinding.instance.removeObserver(this); // install() is idempotent
    WidgetsBinding.instance.addObserver(this);
    unawaited(_caps?.cancel());
    _caps = businessContext.permissionsChanged.listen(
      (_) => onPermissionsChanged(),
    );
    // Cold start through a link: the engine's initial route.
    final initial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (initial != '/' && AppRoute.parse(initial) != null) {
      _pendingDeepLink = initial;
    }
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final link = routeInformation.uri.toString();
    if (AppRoute.parse(link) == null) return false;
    await openDeepLink(link);
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(businessContext.onResumed());
    }
  }

  /// Opens now when signed in and the shell is up; otherwise after sign-in.
  Future<void> openDeepLink(String link) async {
    if (session.status == SessionStatus.signedIn && _shellMounted) {
      await go(link);
    } else {
      _pendingDeepLink = link;
    }
  }

  /// §4.6: toast, then leave the screen if the new caps no longer allow
  /// any route on the stack.
  void onPermissionsChanged() {
    final caps = businessContext.caps;
    final forbidden = observer.stack.any((name) {
      final parsed = AppRoute.parse(name);
      return parsed != null && !parsed.allowedFor(caps);
    });
    if (forbidden) resetToHome();
    // After the reset, so the toast lands on the visible Scaffold.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => messengerKey.currentState?.showNotchNotice(
        const SnackBar(
          content: Text(CommonHe.permissionsUpdated),
          behavior: SnackBarBehavior.fixed,
        ),
      ),
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Register in MaterialApp.navigatorObservers: tracks the named stack.
  final RouteStackObserver observer = RouteStackObserver();
}

/// Keeps the names of the routes on the root navigator (bottom → top).
class RouteStackObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  List<String> get stack => [
    for (final r in _routes)
      if (r.isActive && r.settings.name != null) r.settings.name!,
  ];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) return;
    if (i < 0) {
      _routes.add(newRoute);
    } else {
      _routes[i] = newRoute;
    }
  }
}

Future<void> openExpenseOverview(BuildContext context) =>
    _push(context, const ExpenseOverviewScreen(), '/expenses/overview');
