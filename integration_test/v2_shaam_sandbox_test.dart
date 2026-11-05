// ITA SANDBOX end to end: the real app, issuing through the UI against the
// LOCAL sandbox API (:3021, SHAAM_ENABLED=1, SHAAM_ENV=sandbox) whose business
// is connected to the Israel Tax Authority sandbox. Nothing is mocked on the
// server side; the allocation number comes from the ITA sandbox.
//
//   ~/flutter/bin/flutter test integration_test/v2_shaam_sandbox_test.dart -d <udid> \
//     --dart-define=API_BASE=http://127.0.0.1:3021 \
//     --dart-define=SBX_TOKEN="$(cat ~/invoiceproject-storage/local-sandbox-token)"
//
// SBX_BUSINESS defaults to the sandbox demo business (tax id 199999996) and
// SBX_CUSTOMER to its AUTHORIZED_DEALER customer (199999988).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invoice/screens/document/document_screen.dart';

import 'qa_compose_helpers.dart';

const String sbxToken = String.fromEnvironment('SBX_TOKEN');
const String sbxBusiness =
    String.fromEnvironment('SBX_BUSINESS', defaultValue: 'c083ef07-a85d-4a67-858a-85f8871a7d15');
const String sbxCustomerPrefix = String.fromEnvironment('SBX_CUSTOMER', defaultValue: '0e69eda3');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SBX-1 "בקש תשלום" ₪7,080 to an authorized dealer → ITA sandbox allocation number on D',
      (tester) async {
    expect(sbxToken, isNotEmpty, reason: 'pass --dart-define=SBX_TOKEN=…');
    final owner = DevUser('sandbox-owner', sbxBusiness, sbxToken);

    final status = await tester.runAsync(() => owner.must('GET', '/shaam/status'));
    expect(status!['status'], 'CONNECTED', reason: 'business must be connected to the ITA sandbox');
    final customers = (await tester.runAsync(() => owner.must('GET', '/customers')))!['customers'] as List;
    final customer = customers.cast<Map<String, dynamic>>()
        .firstWhere((c) => (c['id'] as String).startsWith(sbxCustomerPrefix));
    final cid = customer['id'] as String;
    expect(customer['vat_dealer_status'], 'AUTHORIZED_DEALER');

    await signInApp(tester, owner);
    await tester.runAsync(() => rememberRecentForTest(cid));
    final t = TapCounter(tester);

    await t.tap(find.byKey(const Key('intent-request')));
    final circle = find.byKey(Key('s2-recent-$cid'));
    await pumpUntil(tester, circle, timeout: const Duration(seconds: 15), reason: 'S2 recent circle');
    await t.tap(circle, why: 'S2 circle');
    await typeAmount(tester, '7080'); // 6,000 + 18% VAT > threshold
    await t.tap(find.byKey(const Key('compose-primary')));

    await pumpUntil(tester, find.byType(DocumentScreen),
        timeout: const Duration(seconds: 90), reason: 'D after issuing');
    // Allocation is requested by the issue flow; poll the server until ITA answers.
    Map<String, dynamic>? doc;
    final end = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(end)) {
      await pumpFor(tester, const Duration(seconds: 2));
      final docs = await tester.runAsync(() => docsOf(owner, cid));
      final newest = docs!.first;
      doc = await tester.runAsync(() => docDetail(owner, newest['id'] as String));
      if (doc!['allocation_number'] != null || doc['status'] != 'WAITING_FOR_ALLOCATION') break;
    }
    debugPrint('SBX-1 document ${doc!['document_number']} status ${doc['status']} '
        'allocation ${doc['allocation_number']} taps ${t.taps}');
    expect(doc['allocation_number'], isNotNull, reason: 'ITA sandbox must return an allocation number');
    expect(RegExp(r'^\d{9}$').hasMatch('${doc['allocation_number']}'), isTrue);
    expect(BigInt.parse('${doc['total_minor']}'), BigInt.from(708000));
    expect(t.taps, lessThanOrEqualTo(3), reason: '§7: request payment = 3 taps');

    await pumpFor(tester, const Duration(seconds: 3)); // D refreshes to the approved state
    expect(find.textContaining('${doc['allocation_number']}'), findsWidgets,
        reason: 'D shows the allocation number');
  });
}
