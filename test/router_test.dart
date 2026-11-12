import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/activity/activity_screen.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/compose/compose_screen.dart';
import 'package:invoice/screens/document/document_screen.dart';
import 'package:invoice/screens/expense/expenses_screen.dart';
import 'package:invoice/screens/people/person_screen.dart';
import 'package:invoice/screens/reports/reports_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/state/session.dart';

import 'fakes/fake_api.dart';

void main() {
  test(
    'signed-out and restoring sessions cannot open protected routes',
    () async {
      final previous = session.status;
      addTearDown(() => session.status = previous);
      for (final status in [SessionStatus.signedOut, SessionStatus.unknown]) {
        session.status = status;
        for (final path in [
          '/home',
          '/people',
          '/business',
          '/setup',
          '/business/account',
          '/doc/1',
        ]) {
          expect(await go(path), isFalse, reason: '$status: $path');
        }
      }
    },
  );
  test('AT-93: the route list is exactly §5 and maps onto the 10 screens', () {
    expect(routeTable.keys.toList(), [
      '/gate',
      '/setup',
      '/home',
      '/activity',
      '/compose',
      '/doc/:id',
      '/quote/:id',
      '/people',
      '/person/:id',
      '/expenses',
      '/expenses/overview',
      '/reports',
      '/reports/:kind',
      '/business',
      '/business/:section',
    ]);
    expect(routeTable.values.toSet(), ScreenId.values.toSet());
    expect(ScreenId.values, hasLength(10));
  });

  test('AT-93: 8 sheets, each file exists', () {
    expect(sheetRegistry.keys.toList(), [
      'S1',
      'S2',
      'S3',
      'S5',
      'S6',
      'S8',
      'S13',
      'S14',
    ]);
    for (final path in sheetRegistry.values) {
      expect(File('lib/$path').existsSync(), isTrue, reason: path);
    }
  });

  test('parse: paths, params, query, tevel:// links', () {
    final d = AppRoute.parse('/doc/abc')!;
    expect(d.pattern, '/doc/:id');
    expect(d.params, {'id': 'abc'});
    final c = AppRoute.parse('/compose?intent=PAID&customerId=c1')!;
    expect(c.pattern, '/compose');
    expect(c.query, {'intent': 'PAID', 'customerId': 'c1'});
    expect(AppRoute.parse('tevel://doc/abc')!.params, {'id': 'abc'});
    expect(AppRoute.parse('tevel:///doc/abc')!.params, {'id': 'abc'});
    expect(
      AppRoute.parse('tevel://compose?intent=REQUEST')!.query['intent'],
      'REQUEST',
    );
    expect(AppRoute.parse('tevel://home')!.pattern, '/home');
    expect(AppRoute.parse('tevel://business/team')!.params, {
      'section': 'team',
    });
    expect(AppRoute.parse('tevel://reports/vat?period=2026-09')!.params, {
      'kind': 'vat',
    });
    expect(AppRoute.parse('/nope'), isNull);
    expect(AppRoute.parse('/doc'), isNull);
    expect(AppRoute.parse('https://evil.example/doc/1'), isNull);
  });

  test(
    'parse: ids are tokens only — crafted tevel:// links never reach an API path',
    () {
      expect(
        AppRoute.parse('tevel://doc/..%2F..%2Fbusiness%2Fmembers%3Fx%3D'),
        isNull,
      );
      expect(AppRoute.parse('tevel://quote/a%2Fb'), isNull);
      expect(AppRoute.parse('tevel://person/..'), isNull);
      expect(
        AppRoute.parse('tevel://compose?intent=PAID&customerId=..%2Fx'),
        isNull,
      );
      expect(AppRoute.parse('tevel://compose?fromDocId=a%3Fb'), isNull);
      expect(AppRoute.parse('tevel://compose?draftId=x%23y'), isNull);
      expect(
        AppRoute.parse(
          'tevel://doc/0b6f1c1e-7d4b-4a8e-9c1f-2f3a4b5c6d7e',
        )!.params['id'],
        '0b6f1c1e-7d4b-4a8e-9c1f-2f3a4b5c6d7e',
      );
    },
  );

  test('location() drops empty query values', () {
    expect(
      location('/compose', {
        'intent': 'PAID',
        'customerId': null,
        'draftId': '',
      }),
      '/compose?intent=PAID',
    );
    expect(location('/home'), '/home');
  });

  test('screenFor builds the owning squad screen with its arguments', () {
    expect(
      screenFor(AppRoute.parse('/activity?chip=unpaid')!),
      isA<ActivityScreen>(),
    );
    final c =
        screenFor(AppRoute.parse('/compose?intent=QUOTE&fromQuoteId=q1')!)
            as ComposeScreen;
    expect((c.intent, c.fromQuoteId), ('QUOTE', 'q1'));
    final q = screenFor(AppRoute.parse('/quote/q9')!) as DocumentScreen;
    expect((q.id, q.isQuote), ('q9', true));
    final p =
        screenFor(AppRoute.parse('/person/s1?kind=supplier')!) as PersonScreen;
    expect(p.isSupplier, isTrue);
    expect(
      (screenFor(AppRoute.parse('/expenses?id=e1')!) as ExpensesScreen)
          .expenseId,
      'e1',
    );
    expect(
      (screenFor(AppRoute.parse('/reports/vat')!) as ReportsScreen).kind,
      'vat',
    );
    expect(
      (screenFor(AppRoute.parse('/business/team')!) as BusinessScreen).section,
      'team',
    );
    expect(screenFor(AppRoute.parse('/home')!), isNull);
  });

  test('route guard follows caps (§4.5: no screen without its capability)', () {
    Caps caps(Preset p) => Caps.fromMe(Me.fromJson(meJson(p)));
    final employee = caps(Preset.employee);
    final viewer = caps(Preset.viewer);
    final rep = caps(Preset.accountantRep);
    expect(
      AppRoute.parse('/compose?intent=PAID')!.allowedFor(employee),
      isTrue,
    );
    expect(AppRoute.parse('/compose?intent=PAID')!.allowedFor(viewer), isFalse);
    expect(AppRoute.parse('/reports')!.allowedFor(employee), isFalse);
    expect(AppRoute.parse('/reports')!.allowedFor(rep), isTrue);
    expect(AppRoute.parse('/expenses')!.allowedFor(viewer), isFalse);
    expect(AppRoute.parse('/expenses')!.allowedFor(employee), isTrue);
    expect(AppRoute.parse('/business/team')!.allowedFor(employee), isFalse);
    expect(AppRoute.parse('/business/account')!.allowedFor(viewer), isTrue);
    expect(AppRoute.parse('/business/whatever')!.allowedFor(viewer), isTrue);
    expect(AppRoute.parse('/doc/1')!.allowedFor(Caps.none), isFalse);
  });

  test('Info.plist registers the tevel:// scheme and Flutter deep linking', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<string>$deepLinkScheme</string>'));
    expect(plist, contains('CFBundleURLSchemes'));
    expect(plist, contains('FlutterDeepLinkingEnabled'));
  });
}
