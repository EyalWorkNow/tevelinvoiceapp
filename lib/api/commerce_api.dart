import 'client.dart';
import 'documents_api.dart' show notifyDocumentsChanged;
import 'models/json.dart';

class BillingPlan {
  const BillingPlan({
    required this.code,
    required this.name,
    required this.monthlyMinor,
    this.appleProductId = '',
    this.limit,
  });
  factory BillingPlan.fromJson(Map<String, dynamic> j) => BillingPlan(
    code: j['code'] as String,
    name: j['name'] as String,
    monthlyMinor: (j['monthlyMinor'] as num).toInt(),
    appleProductId: j['appleProductId'] as String? ?? '',
    limit: (j['invoiceLimit'] as num?)?.toInt(),
  );
  final String code;
  final String name;
  final int monthlyMinor;
  final String appleProductId;
  final int? limit;
}

class BillingCatalog {
  const BillingCatalog(
    this.plans, {
    required this.available,
    required this.recurring,
    this.appleIapAvailable = false,
  });
  final List<BillingPlan> plans;
  final bool available;
  final bool recurring;
  final bool appleIapAvailable;
}

class SubscriptionStatus {
  SubscriptionStatus.fromJson(Map<String, dynamic> j)
    : active = j['active'] == true,
      needsPlan = j['needsPlan'] == true,
      used = (j['usedInvoices'] as num?)?.toInt() ?? 0,
      planCode = (j['subscription'] as Map?)?['plan_code'] as String?,
      end = (j['subscription'] as Map?)?['period_end'] as String?,
      cancelAtPeriodEnd =
          (j['subscription'] as Map?)?['cancel_at_period_end'] == true,
      billingProvider =
          (j['subscription'] as Map?)?['billing_provider'] as String? ??
          'CARDCOM';
  final bool active, needsPlan;
  final bool cancelAtPeriodEnd;
  final String billingProvider;
  final int used;
  final String? planCode, end;
}

Future<BillingCatalog> fetchBillingPlans() async {
  final j = await ApiClient.instance.get('/billing/plans');
  return BillingCatalog(
    [
      for (final p in j['plans'] as List)
        BillingPlan.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    available: j['checkoutAvailable'] == true,
    recurring: j['renewal'] == 'AUTOMATIC',
    appleIapAvailable: j['appleIapAvailable'] == true,
  );
}

Future<SubscriptionStatus> fetchSubscription() async =>
    SubscriptionStatus.fromJson(
      await ApiClient.instance.get('/billing/subscription'),
    );
Future<({String id, Uri url})> createBillingCheckout(
  String plan, {
  String paymentMethod = 'CARD',
}) async {
  final j = await ApiClient.instance.post('/billing/checkout', {
    'planCode': plan,
    'accepted': true,
    if (paymentMethod != 'CARD') 'paymentMethod': paymentMethod,
  });
  final url = Uri.parse(j['url'] as String);
  if (url.scheme != 'https' ||
      url.host != 'secure.cardcom.solutions' ||
      (url.hasPort && url.port != 443) ||
      url.userInfo.isNotEmpty) {
    throw const FormatException('Unexpected payment URL');
  }
  return (id: j['id'] as String, url: url);
}

Future<bool> verifyBillingCheckout(String id) async =>
    (await ApiClient.instance.post(
      '/billing/checkouts/$id/verify',
    ))['status'] ==
    'PAID';
Future<void> cancelSubscription() =>
    ApiClient.instance.post('/billing/subscription/cancel');

Future<String> fetchAppleAccountToken() async {
  final j = await ApiClient.instance.get('/billing/apple/account');
  final token = j['appAccountToken'];
  if (token is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(token)) {
    throw const FormatException('Invalid App Store account token');
  }
  return token;
}

Future<String> verifyAppleSubscription(String signedTransaction) async =>
    (await ApiClient.instance.post('/billing/apple/transactions/verify', {
          'signedTransaction': signedTransaction,
        }))['status'] ==
        'ACTIVE'
    ? 'ACTIVE'
    : 'INACTIVE';

class ExpenseOverview {
  ExpenseOverview.fromJson(Map<String, dynamic> j)
    : month = j['month'] as String,
      total = jBigOrNull(j['totalMinor']) ?? BigInt.zero,
      recognized = jBigOrNull(j['recognizedMinor']) ?? BigInt.zero,
      vat = jBigOrNull(j['recoverableVatMinor']) ?? BigInt.zero,
      unclassified = jBigOrNull(j['unclassifiedMinor']) ?? BigInt.zero,
      count = (j['count'] as num?)?.toInt() ?? 0,
      categories = [
        for (final c in j['categories'] as List? ?? [])
          Map<String, dynamic>.from(c as Map),
      ],
      trend = [
        for (final c in j['trend'] as List? ?? [])
          Map<String, dynamic>.from(c as Map),
      ],
      expenses = [
        for (final c in j['expenses'] as List? ?? [])
          Map<String, dynamic>.from(c as Map),
      ],
      note = j['recognitionNote'] as String? ?? '';
  final String month, note;
  final BigInt total, recognized, vat, unclassified;
  final int count;
  final List<Map<String, dynamic>> categories, trend, expenses;
}

Future<ExpenseOverview> fetchExpenseOverview(String month) async =>
    ExpenseOverview.fromJson(
      await ApiClient.instance.get(
        '/expenses/overview',
        query: {'month': month},
      ),
    );
Future<void> saveExpenseRecognition(
  String id, {
  required String classification,
  required int? expensePercent,
  required int? vatPercent,
  String note = '',
  String? categoryId,
}) => ApiClient.instance.patch('/expenses/$id/recognition', {
  'classification': classification,
  'expensePercent': expensePercent,
  'vatPercent': vatPercent,
  'note': note,
  'categoryId': ?categoryId,
});

class DispatchResult {
  DispatchResult.fromJson(Map<String, dynamic> j)
    : status = j['status'] as String,
      channel = j['channel'] as String,
      transport = j['transport'] as String?,
      paymentLinkError = j['paymentLinkError'] as String?;
  final String status, channel;
  final String? transport, paymentLinkError;
  bool get needsRecipient => status == 'MANUAL_REQUIRED';
  bool get delivered => status == 'SENT' && transport != 'file';
  String get message => needsRecipient
      ? 'המסמך מוכן לקבלה בסריקה, בטלפון או במייל'
      : delivered
      ? paymentLinkError == null
            ? 'המסמך נשלח ללקוח'
            : 'המסמך נשלח. קישור התשלום דורש בדיקה.'
      : transport == 'file'
      ? 'המסמך נשמר למשלוח בדיקה מקומי'
      : status == 'UNKNOWN'
      ? 'מצב המשלוח בבדיקה'
      : 'המסמך ממתין למשלוח';
}

Future<DispatchResult> dispatchDocument(
  String id, {
  String channel = 'AUTO',
}) async => DispatchResult.fromJson(
  await ApiClient.instance.post('/documents/$id/dispatch', {
    'channel': channel,
  }),
);

Future<Map<String, dynamic>> fetchBusinessCardcom() =>
    ApiClient.instance.get('/settings/cardcom');
Future<void> saveBusinessCardcom(String terminal, String apiName) =>
    ApiClient.instance.put('/settings/cardcom', {
      'terminalNumber': terminal,
      'apiName': apiName,
      'acceptedOwnership': true,
    });
Future<void> disconnectBusinessCardcom() =>
    ApiClient.instance.post('/settings/cardcom/disconnect');
Future<List<Map<String, dynamic>>> fetchCustomerCheckouts() async {
  final j = await ApiClient.instance.get('/payments/cardcom-checkouts');
  return [
    for (final row in j['checkouts'] as List? ?? [])
      Map<String, dynamic>.from(row as Map),
  ];
}

Future<Map<String, dynamic>> verifyCustomerCheckout(String id) async {
  final result = await ApiClient.instance.post(
    '/payments/cardcom-checkouts/$id/verify',
  );
  notifyDocumentsChanged();
  return result;
}

Future<String> createCustomerPaymentLink(String documentId) async {
  final j = await ApiClient.instance.post(
    '/documents/$documentId/payment-link',
  );
  final uri = Uri.parse(j['url'] as String);
  if (uri.scheme != 'https' ||
      uri.host != 'secure.cardcom.solutions' ||
      (uri.hasPort && uri.port != 443) ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Unexpected payment URL');
  }
  return uri.toString();
}
