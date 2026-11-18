// 0119 "המסמכים של העסק" (tester 2026-11-18): list, upload (category, title,
// dates, reminder), view, send several to a customer, edit, remove; view-only
// members; the B row and the team-editor grant.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';
import 'package:invoice/api/reports_api.dart' show ExportFile;
import 'package:invoice/api/vault_api.dart';
import 'package:invoice/screens/business/business_screen.dart';
import 'package:invoice/screens/business/vault_screen.dart';
import 'package:invoice/state/caps.dart';
import 'package:invoice/util/labels/labels.dart';

import '../fakes/fake_api.dart';
import 'e_harness.dart';

Map<String, dynamic> _item(
  String id,
  String category,
  String title, {
  String? expiresOn,
  String status = 'NO_EXPIRY',
  int? days,
  String mime = 'application/pdf',
}) => {
  'id': id,
  'category': category,
  'categoryLabel': vaultCategoryLabel(category),
  'title': title,
  'issuedOn': null,
  'expiresOn': expiresOn,
  'remindDaysBefore': 30,
  'expiryStatus': status,
  'daysToExpiry': days,
  'mimeType': mime,
  'byteSize': 1234,
  'filename': 'x.pdf',
};

void main() {
  late FakeBackend backend;
  late List<(List<ExportFile>, String?)> shares;
  late List<Map<String, dynamic>> items;
  late bool canManage;

  setUp(() async {
    backend = await eSetUp();
    shares = [];
    canManage = true;
    items = [
      _item(
        'v1',
        'WITHHOLDING_APPROVAL',
        'אישור ניכוי במקור',
        expiresOn: '2026-12-01',
        status: 'EXPIRING',
        days: 13,
      ),
      _item('v2', 'BOOKKEEPING_APPROVAL', 'אישור ניהול ספרים'),
    ];
    backend
      ..on(
        'GET',
        '/business/vault',
        (_) => FakeResponse(200, {'items': items, 'canManage': canManage}),
      )
      ..on(
        'GET',
        '/business/vault/:id/file',
        (_) => const FakeResponse(200, <int>[37, 80, 68, 70, 45]),
      )
      ..json('POST', '/business/vault/share', {'recorded': 2});
    vaultSharer = (files, {text}) async => shares.add((files, text));
    pickVaultFile = (_) async => VaultFile(
      Uint8List.fromList(utf8.encode('%PDF-1.4 test')),
      'application/pdf',
      'document.pdf',
    );
  });

  testWidgets('lists the documents with their expiry state', (tester) async {
    await pumpAs(tester, backend, Preset.owner, const VaultScreen());
    await settle(tester);
    expect(find.text('אישור ניכוי במקור'), findsWidgets);
    expect(find.text(VaultHe.expiresIn(13)), findsOneWidget);
    expect(find.text(VaultHe.noExpiry), findsOneWidget);
    expect(find.byKey(const Key('vault-bottom')), findsOneWidget);
  });

  testWidgets(
    'upload: source → details (category, title, expiry, reminder) → POST raw file',
    (tester) async {
      backend.on('POST', '/business/vault', (r) {
        items = [
          ...items,
          _item('v3', r.raw.url.queryParameters['category']!, 'x'),
        ];
        return FakeResponse(201, {'item': items.last});
      });
      await pumpAs(tester, backend, Preset.owner, const VaultScreen());
      await settle(tester);
      await tester.tap(find.byKey(const Key('vault-bottom')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('vault-source-pdf')));
      await settle(tester);
      // Category: אישור ניהול ספרים.
      await tester.tap(find.byKey(const Key('vault-category')));
      await settle(tester);
      await tester.tap(find.text('אישור ניהול ספרים').last);
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('vault-title')),
        'ניהול ספרים 2026',
      );
      // Expiry date via the picker (OK on the default date).
      await tester.tap(find.byKey(const Key('vault-expires')));
      await settle(tester);
      await tester.tap(find.text('אישור').last);
      await settle(tester);
      await tester.tap(find.text(VaultHe.remindDays(14)));
      await settle(tester);
      await tester.tap(find.byKey(const Key('vault-save')));
      await settle(tester);
      final post = backend.last('POST', '/business/vault')!;
      final q = post.raw.url.queryParameters;
      expect(q['category'], 'BOOKKEEPING_APPROVAL');
      expect(q['title'], 'ניהול ספרים 2026');
      expect(q['expiresOn'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(q['remindDaysBefore'], '14');
      expect(post.raw.headers['Content-Type'], startsWith('application/pdf'));
      expect(post.raw.headers['X-Filename'], 'document.pdf');
      expect(utf8.decode(post.raw.bodyBytes), '%PDF-1.4 test');
      expect(find.text(VaultHe.uploaded), findsOneWidget);
    },
  );

  testWidgets('a file over 15 MB is refused on the phone', (tester) async {
    pickVaultFile = (_) async =>
        VaultFile(Uint8List(vaultMaxBytes + 1), 'image/jpeg', 'document.jpg');
    await pumpAs(tester, backend, Preset.owner, const VaultScreen());
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-bottom')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-source-camera')));
    await settle(tester);
    expect(find.text(VaultHe.tooLarge), findsOneWidget);
    expect(backend.last('POST', '/business/vault'), isNull);
  });

  testWidgets('send two documents to a customer in one share (and audit it)', (
    tester,
  ) async {
    await pumpAs(tester, backend, Preset.owner, const VaultScreen());
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-select')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-row-v1')));
    await tester.tap(find.byKey(const Key('vault-row-v2')));
    await settle(tester);
    expect(find.text(VaultHe.sendSelected(2)), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-bottom')));
    await settle(tester);
    expect(shares, hasLength(1));
    expect(shares.single.$1.map((f) => f.name), [
      'אישור ניכוי במקור.pdf',
      'אישור ניהול ספרים.pdf',
    ]);
    final audit = backend.last('POST', '/business/vault/share')!;
    expect(audit.body['ids'], ['v1', 'v2']);
  });

  testWidgets('edit and remove from the row actions', (tester) async {
    backend
      ..on(
        'PATCH',
        '/business/vault/:id',
        (r) => FakeResponse(200, {'item': items.first}),
      )
      ..on('DELETE', '/business/vault/:id', (_) {
        items = [items.last];
        return const FakeResponse(204);
      });
    await pumpAs(tester, backend, Preset.owner, const VaultScreen());
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-row-v1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-action-edit')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-save')));
    await settle(tester);
    final patch = backend.last('PATCH', '/business/vault/:id')!;
    expect(patch.params['id'], 'v1');
    expect(patch.body['expiresOn'], '2026-12-01');

    await tester.tap(find.byKey(const Key('vault-row-v1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('vault-action-delete')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-danger')));
    await settle(tester);
    expect(backend.last('DELETE', '/business/vault/:id')!.params['id'], 'v1');
    expect(find.byKey(const Key('vault-row-v1')), findsNothing);
  });

  testWidgets('view-only member: view + send, no add / edit / delete', (
    tester,
  ) async {
    canManage = false;
    await pumpAs(tester, backend, Preset.employee, const VaultScreen());
    await settle(tester);
    expect(find.byKey(const Key('vault-bottom')), findsNothing);
    expect(find.text(VaultHe.viewOnly), findsOneWidget);
    await tester.tap(find.byKey(const Key('vault-row-v2')));
    await settle(tester);
    expect(find.byKey(const Key('vault-action-view')), findsOneWidget);
    expect(find.byKey(const Key('vault-action-share')), findsOneWidget);
    expect(find.byKey(const Key('vault-action-edit')), findsNothing);
    expect(find.byKey(const Key('vault-action-delete')), findsNothing);
  });

  testWidgets('empty vault invites the first upload', (tester) async {
    items = [];
    await pumpAs(tester, backend, Preset.owner, const VaultScreen());
    await settle(tester);
    expect(find.text(VaultHe.empty), findsOneWidget);
    expect(find.text(VaultHe.add), findsOneWidget);
  });

  group('permissions', () {
    Caps caps(String role, List<String> perms) =>
        Caps.fromMe(Me(userId: 'u', role: role, permissions: perms));

    test('business_documents:read → the B row; without it, none', () {
      final owner = caps('OWNER', [
        'document:read',
        'business:configure',
        'business_documents:read',
      ]);
      expect(owner.can(Cap.vaultView), isTrue);
      expect(
        allBusinessRows(owner, memberCount: 1).map((r) => r.key),
        contains('vault'),
      );
      final employee = caps('EMPLOYEE', ['document:read']);
      expect(employee.can(Cap.vaultView), isFalse);
      expect(
        allBusinessRows(employee, memberCount: 1).map((r) => r.key),
        isNot(contains('vault')),
      );
    });

    test('the grant is a toggle, not a "custom" permission set', () {
      expect(hasCustomGrants('EMPLOYEE', const [vaultGrant]), isFalse);
      expect(vaultGrantable(Preset.employee), isTrue);
      expect(vaultGrantable(Preset.partner), isFalse);
    });
  });
}
