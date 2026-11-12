import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/api/documents_api.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/theme.dart';

DocumentSummary doc(
  String id,
  String type,
  String status, {
  String total = '100000',
  String? balance,
  String? name,
  String? number,
  String? date,
}) => DocumentSummary.fromJson({
  'id': id,
  'documentType': type,
  'status': status,
  'documentNumber': number,
  'customerName': name,
  'issueDate': date,
  'currency': 'ILS',
  'totalMinor': total,
  'balanceMinor': balance ?? total,
});

Map<String, dynamic> docJson(
  String id,
  String type,
  String status,
  String number,
  String name,
  String total,
  String balance,
) => {
  'id': id,
  'documentType': type,
  'status': status,
  'documentNumber': number,
  'customerId': 'c-$name',
  'customerName': name,
  'issueDate': '2026-10-30',
  'currency': 'ILS',
  'totalMinor': total,
  'balanceMinor': balance,
};

Widget app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  locale: const Locale('he', 'IL'),
  supportedLocales: const [Locale('he', 'IL')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: buildTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: child,
);

void main() {
  final api = ApiClient.instance;
  late List<http.Request> sent;

  void route(Map<String, Object> Function(http.Request r) handler) {
    api.httpClient = MockClient((request) async {
      sent.add(request);
      final res = handler(request);
      final status = res['status'] as int;
      final body = res['body'];
      if (body is List<int>) {
        return http.Response.bytes(
          body,
          status,
          headers: {'content-type': 'application/pdf'},
        );
      }
      return http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('home_test');
    AppCache.directoryProvider = () async => dir;
  });

  setUp(() {
    sent = [];
    api.clearCredentials();
    api.deviceToken = 'inv_test';
    api.businessId = 'b1';
    session.account = const MobileAccount(
      userId: 'u1',
      email: 'a@b.co',
      displayName: 'אורי בעלים',
      businesses: [
        Business(businessId: 'b1', legalName: 'סטודיו תבל', role: 'OWNER'),
      ],
    );
    session.business = session.account!.businesses.first;
    session.me = Me.fromJson({
      'userId': 'u1',
      'role': 'OWNER',
      'canFinalize': true,
      'canConfigure': true,
      'onboarding': {'completed': true},
    });
    session.profile = null;
    session.offline = false;
  });

  group('pure helpers', () {
    test('balance is only meaningful on issued invoices', () {
      expect(
        withMeaningfulBalance(
          doc('1', 'TAX_INVOICE', 'ARCHIVED', balance: '5'),
        ).balanceMinor,
        BigInt.from(5),
      );
      expect(
        withMeaningfulBalance(doc('2', 'RECEIPT', 'ARCHIVED')).balanceMinor,
        isNull,
      );
      expect(
        withMeaningfulBalance(doc('3', 'TAX_INVOICE', 'DRAFT')).balanceMinor,
        isNull,
      );
      expect(
        withMeaningfulBalance(
          doc('4', 'CREDIT_DOCUMENT', 'ARCHIVED'),
        ).balanceMinor,
        isNull,
      );
    });

    test('unpaid keeps invoice types with a positive balance', () {
      final list = unpaidInvoices([
        doc('1', 'TAX_INVOICE', 'SENT'),
        doc('2', 'RECEIPT', 'ARCHIVED'), // server quirk: balance == total
        doc('3', 'TAX_INVOICE_RECEIPT', 'ARCHIVED', balance: '0'),
        doc('4', 'TRANSACTION_INVOICE', 'ARCHIVED'),
      ]);
      expect(list.map((d) => d.id), ['1', '4']);
    });

    test(
      'month income: accrual for VAT businesses, receipts for exempt ones',
      () {
        final month = [
          doc('1', 'TAX_INVOICE', 'ARCHIVED', total: '118000'),
          doc(
            '2',
            'RECEIPT',
            'ARCHIVED',
            total: '118000',
          ), // payment of #1 — not counted twice
          doc('3', 'TAX_INVOICE_RECEIPT', 'SENT', total: '50000'),
          doc('4', 'CREDIT_DOCUMENT', 'ARCHIVED', total: '10000'),
          doc('5', 'TAX_INVOICE', 'DRAFT', total: '99999'),
          doc('6', 'TAX_INVOICE', 'PENDING_APPROVAL', total: '99999'),
        ];
        expect(monthIncome(month, vatExempt: false), (BigInt.from(158000), 3));
        final patur = [
          doc('1', 'TRANSACTION_INVOICE', 'ARCHIVED', total: '50000'),
          doc('2', 'RECEIPT', 'ARCHIVED', total: '50000'),
          doc('3', 'RECEIPT', 'FINALIZED', total: '20000'),
        ];
        expect(monthIncome(patur, vatExempt: true), (BigInt.from(70000), 2));
      },
    );

    test('filters + search by customer name or number prefix', () {
      final all = [
        doc('1', 'TAX_INVOICE', 'SENT', name: 'דנה כהן', number: '1042'),
        doc('2', 'RECEIPT', 'ARCHIVED', name: 'יוסי לוי', number: '7'),
        doc(
          '3',
          'TAX_INVOICE_RECEIPT',
          'ARCHIVED',
          balance: '0',
          name: 'דנה כהן',
          number: '1043',
        ),
        doc('4', 'CREDIT_DOCUMENT', 'ARCHIVED', name: 'יוסי לוי', number: '8'),
      ];
      List<String> ids(DocFilter f, [String q = '']) =>
          filterDocuments(all, all, f, q).map((d) => d.id).toList();
      expect(ids(DocFilter.all), ['1', '2', '3', '4']);
      expect(ids(DocFilter.unpaid), ['1']);
      expect(ids(DocFilter.invoices), ['1', '3', '4']);
      expect(ids(DocFilter.receipts), ['2', '3']);
      expect(ids(DocFilter.all, 'דנה'), ['1', '3']);
      expect(ids(DocFilter.all, '104'), ['1', '3']);
      expect(ids(DocFilter.receipts, ' יוסי '), ['2']);
      expect(ids(DocFilter.all, 'אין כזה'), isEmpty);
    });

    test('quantity and month start formatting', () {
      expect(formatQuantity(BigInt.from(1000000)), '1');
      expect(formatQuantity(BigInt.from(2500000)), '2.5');
      expect(formatQuantity(BigInt.from(1250)), '0.00125');
      expect(monthStartIso(DateTime(2026, 3, 17)), '2026-03-01');
    });
  });

  group('documents api', () {
    test('missing original → POST /artifact once, then the PDF', () async {
      var artifactCalls = 0;
      var pdfCalls = 0;
      route((r) {
        if (r.url.path == '/documents/d1/pdf') {
          pdfCalls++;
          return artifactCalls == 0
              ? {
                  'status': 404,
                  'body': {'error': 'ARTIFACT_REQUIRED'},
                }
              : {'status': 200, 'body': utf8.encode('%PDF-1.7')};
        }
        if (r.url.path == '/documents/d1/artifact') {
          artifactCalls++;
          return {
            'status': 201,
            'body': {'artifactId': 'a'},
          };
        }
        return {
          'status': 500,
          'body': {'error': 'INTERNAL'},
        };
      });
      final before = documentsVersion.value;
      final bytes = await fetchDocumentPdf('d1');
      expect(utf8.decode(bytes), '%PDF-1.7');
      expect((artifactCalls, pdfCalls), (1, 2));
      expect(documentsVersion.value, before + 1);
      expect(sent[1].method, 'POST');
      expect(sent[1].headers['X-Business-Id'], 'b1');
    });

    test('no artifact retry when not allowed or for other errors', () async {
      route(
        (r) => {
          'status': 404,
          'body': {'error': 'ARTIFACT_REQUIRED'},
        },
      );
      await expectLater(
        fetchDocumentPdf('d1', createIfMissing: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'ARTIFACT_REQUIRED',
          ),
        ),
      );
      route(
        (r) => {
          'status': 404,
          'body': {'error': 'DOCUMENT_NOT_FOUND'},
        },
      );
      await expectLater(fetchDocumentPdf('d1'), throwsA(isA<ApiException>()));
      expect(sent.where((r) => r.url.path.endsWith('/artifact')), isEmpty);
    });

    test('list query sends only the filters given', () async {
      route(
        (r) => {
          'status': 200,
          'body': {'total': 0, 'documents': []},
        },
      );
      await fetchDocuments(unpaid: true, issuedFrom: '2026-10-01');
      expect(sent.single.url.queryParameters, {
        'unpaid': '1',
        'issuedFrom': '2026-10-01',
      });
    });
  });
}
