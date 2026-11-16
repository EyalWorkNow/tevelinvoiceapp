// ייבוא לקוחות: the API helpers (mapping → records, contacts → records, error list,
// idempotent chunk retry) and the flow from the לקוחות tab (file + contacts).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:invoice/api/customer_import_api.dart';
import 'package:invoice/router.dart';
import 'package:invoice/screens/people/import/customer_import_screen.dart';
import 'package:invoice/screens/people/people_screen.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/ui/ds.dart';
import 'package:invoice/util/labels/customer_import_he.dart';

import 'fakes/fake_api.dart';

Map<String, dynamic> parsedTable() => {
  'source': 'GREEN_INVOICE',
  'sourceLabel': 'חשבונית ירוקה (Morning)',
  'encoding': 'xlsx',
  'headerRow': 1,
  'firstRowNumber': 3,
  'headers': ['שם לקוח', 'מספר עוסק', 'נייד', 'כתובת מייל', 'יתרה'],
  'mapping': {'name': 0, 'taxId': 1, 'mobile': 2, 'email': 3, 'unknown': 9},
  'rows': [
    ['כהן שיפוצים', '512345679', '521234567', 'office@cohen.co.il', '0'],
    ['לוי ייעוץ', '34567891', '', '', '-1200'],
    ['שגוי', '123456789', '', '', ''],
  ],
};

Map<String, dynamic> result(
  int row,
  String status, {
  String? name,
  Map<String, dynamic>? duplicate,
  List<Map<String, String>> errors = const [],
}) => {
  'row': row,
  'status': status,
  'duplicate': ?duplicate,
  'errors': errors,
  'warnings': const [],
  if (name != null) 'customer': {'name': name, 'phone': '0521234567'},
};

void main() {
  group('helpers', () {
    test('ImportTable maps rows to records with file row numbers', () {
      final t = ImportTable.fromJson(parsedTable());
      expect(t.mapping, {'name': 0, 'taxId': 1, 'mobile': 2, 'email': 3});
      expect(t.hasHeader, isTrue);
      expect(t.sample(3), 'office@cohen.co.il');
      expect(t.records(), [
        {
          'row': 3,
          'name': 'כהן שיפוצים',
          'taxId': '512345679',
          'mobile': '521234567',
          'email': 'office@cohen.co.il',
        },
        {'row': 4, 'name': 'לוי ייעוץ', 'taxId': '34567891'},
        {'row': 5, 'name': 'שגוי', 'taxId': '123456789'},
      ]);
    });

    test(
      'a contact becomes a record: mobile first, company name with contact person',
      () {
        final c = DeviceContact.fromMap({
          'id': 'x',
          'name': 'דני כהן',
          'organization': 'כהן שיפוצים',
          'phones': ['03-5551234', '+972 52-123-4567'],
          'emails': ['dani@cohen.co.il'],
          'street': 'הרצל 12',
          'city': 'תל אביב',
          'postalCode': '',
        });
        expect(c.toRecord(1), {
          'row': 1,
          'name': 'דני כהן',
          'mobile': '+972 52-123-4567',
          'phone': '03-5551234',
          'email': 'dani@cohen.co.il',
          'street': 'הרצל 12',
          'city': 'תל אביב',
          'contactPerson': 'דני כהן',
        });
        final company = DeviceContact.fromMap({
          'id': 'y',
          'name': '',
          'organization': 'חברה',
        });
        expect(company.displayName, 'חברה');
      },
    );

    test('error list is a UTF-8 CSV with BOM and one line per issue', () {
      final bytes = errorsCsv(
        [
          ImportRowResult.fromJson(
            result(
              5,
              'ERROR',
              errors: [
                {
                  'field': 'taxId',
                  'message': 'מספר ח.פ. / ת.ז. לא תקין (123456789)',
                },
              ],
            ),
          ),
          ImportRowResult.fromJson(result(3, 'CREATED', name: 'x')),
        ],
        ImportHe.errorsCsvHeader,
        (f) => f == 'taxId' ? 'ח.פ.' : f,
        (row) => 'שגוי',
      );
      expect(bytes.sublist(0, 3), [0xef, 0xbb, 0xbf]);
      expect(
        utf8.decode(bytes.sublist(3)),
        '${ImportHe.errorsCsvHeader}\r\n5,שגוי,ח.פ.,מספר ח.פ. / ת.ז. לא תקין (123456789)\r\n',
      );
    });

    test('import ids are v4 UUIDs', () {
      expect(
        newImportId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test(
      'a chunk lost to the network is retried with the identical body',
      () async {
        final backend = FakeBackend()..install();
        var calls = 0;
        final bodies = <String>[];
        backend.on('POST', '/customers/import', (r) {
          calls++;
          bodies.add(r.raw.body);
          if (calls == 1) throw http.ClientException('connection reset');
          return FakeResponse(200, {
            'results': [result(3, 'CREATED', name: 'a')],
            'replayed': false,
          });
        });
        var retried = 0;
        final out = await commitImportChunk(
          importId: newImportId(),
          chunkIndex: 0,
          source: 'FILE',
          onDuplicate: 'SKIP',
          records: [
            {'row': 3, 'name': 'a'},
          ],
          onRetry: () => retried++,
        );
        expect(out.single.status, 'CREATED');
        expect(calls, 2);
        expect(retried, 1);
        expect(bodies[0], bodies[1]);
      },
    );
  });

  group('flow', () {
    late FakeBackend backend;
    late Directory tmp;
    Uint8List? shared;

    setUpAll(() async {
      tmp = await Directory.systemTemp.createTemp('import_test');
      AppCache.directoryProvider = () async => tmp;
    });

    setUp(() async {
      resetSession();
      await AppCache.clearAll();
      backend = FakeBackend()..install();
      shared = null;
      shareImportFile = (bytes, name, mime) async => shared = bytes;
      pickImportFile = () async => PickedImportFile(
        'customers.xlsx',
        Uint8List.fromList([0x50, 0x4b, 3, 4]),
      );
    });

    Future<void> flush(WidgetTester tester, [int rounds = 10]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
        await flush(tester, 3);
      }
      await tester.ensureVisible(f);
      await tester.tap(f);
      await flush(tester);
    }

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Preset preset = Preset.owner,
    }) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => signInAs(backend, preset));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: messengerKey,
          locale: const Locale('he', 'IL'),
          supportedLocales: const [Locale('he', 'IL')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildTheme(Brightness.light),
          home: home,
        ),
      );
      await flush(tester);
    }

    testWidgets('owner: empty לקוחות offers "ייבא לקוחות"; employee does not', (
      tester,
    ) async {
      installPeopleFakes(backend);
      await pump(tester, const PeopleScreen());
      expect(find.text(ImportHe.emptyImportAction), findsOneWidget);
      expect(find.byKey(const Key('people-more')), findsOneWidget);

      await pump(tester, const PeopleScreen(), preset: Preset.employee);
      expect(find.text(ImportHe.emptyImportAction), findsNothing);
      expect(find.byKey(const Key('people-more')), findsNothing);
    });

    testWidgets(
      'file: mapping → review (dup policy, fix a row) → import → summary + error list',
      (tester) async {
        installPeopleFakes(backend);
        backend.json('POST', '/customers/import/parse', parsedTable());
        backend.on('POST', '/customers/import/preview', (r) {
          final records = (r.body['records'] as List).cast<Map>();
          return FakeResponse(200, {
            'results': [
              for (final rec in records)
                switch (rec['row']) {
                  3 => result(
                    3,
                    'DUPLICATE',
                    name: 'כהן שיפוצים',
                    duplicate: {
                      'customerId': 'c9',
                      'name': 'כהן',
                      'by': 'TAX_ID',
                    },
                  ),
                  4 => result(4, 'NEW', name: 'לוי ייעוץ'),
                  _ when rec['taxId'] == '123456789' => result(
                    5,
                    'ERROR',
                    errors: [
                      {'field': 'taxId', 'message': 'מספר ח.פ. / ת.ז. לא תקין'},
                    ],
                  ),
                  _ => result(5, 'NEW', name: '${rec['name']}'),
                },
            ],
          });
        });
        backend.on('POST', '/customers/import', (r) {
          expect(r.body['onDuplicate'], 'MERGE');
          final records = (r.body['records'] as List).cast<Map>();
          return FakeResponse(200, {
            'results': [
              for (final rec in records)
                rec['row'] == 3
                    ? result(3, 'UPDATED', name: 'כהן שיפוצים')
                    : result(
                        rec['row'] as int,
                        'CREATED',
                        name: '${rec['name']}',
                      ),
            ],
          });
        });

        await pump(tester, const CustomerImportScreen());
        await tap(tester, find.byKey(const Key('import-source-file')));
        expect(find.byKey(const Key('import-mapping')), findsOneWidget);
        expect(find.textContaining('חשבונית ירוקה'), findsWidgets);
        await tester.dragUntilVisible(
          find.byKey(const Key('import-preview-table')),
          find.byKey(const Key('import-mapping')),
          const Offset(0, -300),
        );
        expect(find.byKey(const Key('import-preview-table')), findsOneWidget);

        await tap(tester, find.byKey(const Key('import-check')));
        expect(find.text(ImportHe.newCount(1)), findsOneWidget);
        expect(find.text(ImportHe.dupCount(1)), findsOneWidget);
        expect(find.text(ImportHe.errCount(1)), findsOneWidget);

        await tap(tester, find.text(ImportHe.dupCount(1)));
        expect(
          find.text(ImportHe.existing('כהן', ImportHe.byTaxId)),
          findsOneWidget,
        );
        await tap(tester, find.text(ImportHe.policyMerge).first);
        expect(find.text(ImportHe.policyMergeHelp), findsOneWidget);
        expect(find.text(ImportHe.importN(2)), findsOneWidget);

        // Fix the invalid row: it becomes valid and is imported too.
        await tap(tester, find.text(ImportHe.errCount(1)));
        await tap(tester, find.byKey(const Key('import-row-5')));
        await tester.enterText(find.byKey(const Key('import-fix-taxId')), '');
        await tap(tester, find.byKey(const Key('import-fix-save')));
        expect(find.text(ImportHe.errCount(0)), findsOneWidget);
        expect(find.text(ImportHe.importN(3)), findsOneWidget);

        await tap(tester, find.byKey(const Key('import-start')));
        expect(find.byKey(const Key('import-summary')), findsOneWidget);
        expect(find.text(ImportHe.added(2)), findsOneWidget);
        expect(find.text(ImportHe.updated(1)), findsOneWidget);
        expect(find.text(ImportHe.errors(0)), findsOneWidget);
        final call = backend.last('POST', '/customers/import')!;
        expect(call.body['chunkIndex'], 0);
        expect(call.body['importId'], isA<String>());
      },
    );

    testWidgets('a summary with errors shares the error list', (tester) async {
      installPeopleFakes(backend);
      backend.json('POST', '/customers/import/parse', parsedTable());
      backend.on(
        'POST',
        '/customers/import/preview',
        (r) => FakeResponse(200, {
          'results': [
            result(3, 'NEW', name: 'כהן שיפוצים'),
            result(4, 'NEW', name: 'לוי ייעוץ'),
            result(
              5,
              'ERROR',
              errors: [
                {'field': 'taxId', 'message': 'מספר ח.פ. / ת.ז. לא תקין'},
              ],
            ),
          ],
        }),
      );
      backend.on(
        'POST',
        '/customers/import',
        (r) => FakeResponse(200, {
          'results': [
            result(3, 'CREATED', name: 'a'),
            result(4, 'CREATED', name: 'b'),
          ],
        }),
      );
      await pump(tester, const CustomerImportScreen());
      await tap(tester, find.byKey(const Key('import-source-file')));
      await tap(tester, find.byKey(const Key('import-check')));
      await tap(tester, find.byKey(const Key('import-start')));
      expect(find.text(ImportHe.errors(1)), findsOneWidget);
      await tap(tester, find.byKey(const Key('import-share-errors')));
      expect(utf8.decode(shared!.sublist(3)), contains('5,שגוי,'));
    });

    testWidgets('a file the server refuses shows its Hebrew message', (
      tester,
    ) async {
      installPeopleFakes(backend);
      backend.on(
        'POST',
        '/customers/import/parse',
        (_) => FakeResponse.error(
          422,
          'IMPORT_FILE_UNSUPPORTED',
          'קובץ Excel ישן (xls)',
        ),
      );
      await pump(tester, const CustomerImportScreen());
      await tap(tester, find.byKey(const Key('import-source-file')));
      expect(find.text('קובץ Excel ישן (xls)'), findsOneWidget);
    });

    testWidgets(
      'contacts: multi-select with search and "כבר לקוח", then import',
      (tester) async {
        installPeopleFakes(
          backend,
          customers: [customerJson('c1', 'דנה', phone: '0501234567')],
        );
        loadDeviceContacts = () async => [
          DeviceContact(id: 'a', name: 'דנה', phones: ['+972 50-123-4567']),
          DeviceContact(id: 'b', name: 'אבי', phones: ['052-7654321']),
          DeviceContact(id: 'c', name: 'רונית', emails: ['r@x.co.il']),
          DeviceContact(id: 'd', name: ''),
        ];
        backend.on('POST', '/customers/import/preview', (r) {
          final records = (r.body['records'] as List).cast<Map>();
          return FakeResponse(200, {
            'results': [
              for (final rec in records)
                result(rec['row'] as int, 'NEW', name: '${rec['name']}'),
            ],
          });
        });
        backend.on('POST', '/customers/import', (r) {
          expect(r.body['source'], 'CONTACTS');
          final records = (r.body['records'] as List).cast<Map>();
          expect(records.map((x) => x['name']), ['אבי', 'רונית']);
          return FakeResponse(200, {
            'results': [
              for (final rec in records)
                result(rec['row'] as int, 'CREATED', name: '${rec['name']}'),
            ],
          });
        });
        await pump(tester, const CustomerImportScreen());
        await tap(tester, find.byKey(const Key('import-source-contacts')));
        expect(
          find.byKey(const Key('import-contact-d')),
          findsNothing,
        ); // no name
        expect(find.byKey(const Key('import-known-a')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('import-contacts-search')),
          'א',
        );
        await flush(tester);
        await tap(tester, find.byKey(const Key('import-contacts-all')));
        expect(find.text(ImportHe.selectedCount(1)), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('import-contacts-search')),
          '',
        );
        await flush(tester);
        await tap(tester, find.byKey(const Key('import-contact-c')));
        await tap(tester, find.byKey(const Key('import-contacts-continue')));
        await tap(tester, find.byKey(const Key('import-start')));
        expect(find.text(ImportHe.added(2)), findsOneWidget);
      },
    );

    testWidgets('contacts permission denied explains how to allow it', (
      tester,
    ) async {
      installPeopleFakes(backend);
      loadDeviceContacts = () async => null;
      await pump(tester, const CustomerImportScreen());
      await tap(tester, find.byKey(const Key('import-source-contacts')));
      expect(find.byKey(const Key('import-contacts-denied')), findsOneWidget);
    });
  });
}
