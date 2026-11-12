import '../../util/labels/people_he.dart';
import '../../util/labels/business_he.dart';
import '../../util/labels/payment_he.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../api/commerce_api.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';

class CardcomMerchantScreen extends StatefulWidget {
  const CardcomMerchantScreen({super.key});
  @override
  State<CardcomMerchantScreen> createState() => _CardcomMerchantScreenState();
}

class _CardcomMerchantScreenState extends State<CardcomMerchantScreen> {
  final _terminal = TextEditingController(), _apiName = TextEditingController();
  Map<String, dynamic>? _account;
  List<Map<String, dynamic>> _checkouts = [];
  bool _busy = false, _accepted = false;
  Object? _error;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _terminal.dispose();
    _apiName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final account = await fetchBusinessCardcom();
      final checkouts = await fetchCustomerCheckouts();
      if (mounted) {
        setState(() {
          _account = account;
          _checkouts = checkouts;
          _error = null;
          _terminal.text =
              (account['account'] as Map?)?['terminalNumber']?.toString() ?? '';
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    if (!_accepted ||
        !RegExp(r'^[1-9]\d{0,8}$').hasMatch(_terminal.text.trim()) ||
        _apiName.text.trim().isEmpty) {
      setState(
        () => _message = 'יש להזין מספר מסוף ושם API ולאשר שהמסוף שייך לעסק.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await saveBusinessCardcom(_terminal.text.trim(), _apiName.text.trim());
      if (!mounted) return;
      _apiName.clear();
      await _load();
      if (mounted) {
        setState(
          () =>
              _message = 'פרטי המסוף נשמרו. האימות יתבצע מול קארדקום בעת עסקה.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ניתוק המסוף מהעסק'),
        content: const Text(
          'לא ייווצרו קישורים חדשים. קישורים שכבר נשלחו עשויים להישאר פעילים בקארדקום, ויש לבטל אותם מול הספק.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AuthHe.back),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(BusinessHe.disconnectAction),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await disconnectBusinessCardcom();
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String id) async {
    setState(() => _busy = true);
    try {
      final result = await verifyCustomerCheckout(id);
      await _load();
      if (mounted) {
        setState(
          () => _message = result['status'] == 'PAID'
              ? result['receiptError'] == null
                    ? 'התשלום אומת ונרשם לעסק.'
                    : 'התשלום נרשם. הקבלה ממתינה להשלמה מתוך המסמכים.'
              : 'התשלום ממתין לבדיקה. ניתן לראות אותו ביומן התשלומים.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text('הסליקה של העסק', style: AppText.displayTitle),
                ),
                DesignBackButton(),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: DesignTokens.lavender,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.credit_card_rounded,
                      size: 32,
                      color: Color(0xFF302139),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(businessContext.displayName, style: AppText.title),
                  const SizedBox(height: 10),
                  Text(
                    'מסוף קארדקום נפרד לעסק שלך. תשלומי הלקוחות נסלקים במסוף הזה, בנפרד מהתשלום על המנוי לתבל.',
                    style: AppText.body.copyWith(
                      color: context.palette.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (kDebugMode)
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Iconsax.card, color: context.palette.info),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'תצוגה מקדימה של תשלום לקוח',
                                  style: AppText.headline,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'כך הלקוח יבחר איך לשלם. אפשרויות ההדגמה זמינות גם כשמסוף קארדקום עדיין לא מחובר.',
                            style: AppText.secondary.copyWith(
                              color: context.palette.muted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const Key('customer-payment-preview'),
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const CustomerPaymentPreviewScreen(),
                              ),
                            ),
                            icon: const Icon(Iconsax.eye),
                            label: const Text(BusinessHe.openingPreview),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (_error != null) ErrorView(error: _error!, onRetry: _load),
                  if (_account == null && _error == null)
                    const SkeletonList(rows: 3),
                  if (_account != null) ...[
                    ContentReveal(
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _account!['configured'] == true
                                      ? Icons.check_circle_outline
                                      : Icons.link_outlined,
                                  color: DesignTokens.lavender,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _account!['configured'] == true
                                        ? 'פרטי מסוף הוגדרו'
                                        : 'ממתינים למסוף שלך',
                                    style: AppText.headline,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'הפרטים מתקבלים מקארדקום לאחר פתיחת חשבון. שמירתם כאן אינה אישור של הספק לזהות העסק.',
                              style: AppText.secondary,
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              key: const Key('merchant-terminal'),
                              controller: _terminal,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'מספר המסוף של העסק',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('merchant-api-name'),
                              controller: _apiName,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              textDirection: TextDirection.ltr,
                              decoration: const InputDecoration(
                                labelText: 'שם ממשק API',
                                helperText:
                                    'מוצפן בשרת. הערך השמור אינו מוצג בחזרה.',
                              ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _accepted,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                        setState(() => _accepted = v ?? false),
                              title: const Text(
                                'אני מאשר/ת שהמסוף שייך לעסק הזה',
                                style: AppText.body,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            PrimaryButton(
                              key: const Key('merchant-save'),
                              label: BusinessHe.savingTerminal,
                              onPressed: _save,
                              loadingText: _busy
                                  ? ExpenseHe.savingInProgress
                                  : null,
                            ),
                            if (_account!['configured'] == true)
                              TextButton(
                                onPressed: _busy ? null : _disconnect,
                                child: const Text(
                                  BusinessHe.disconnectTerminal,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_message!, style: AppText.body),
                      ),
                    const SizedBox(height: 24),
                    const Text('תשלומים מקארדקום', style: AppText.title),
                    const SizedBox(height: 12),
                    if (_checkouts.isEmpty)
                      const AppCard(
                        child: Text(
                          'קישורי תשלום נוצרים מתוך מסמך פתוח לתשלום. כאן יופיעו התוצאות מהספק.',
                          style: AppText.body,
                        ),
                      ),
                    for (final row in _checkouts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                row['status'] == 'PAID'
                                    ? 'התשלום התקבל'
                                    : row['status'] == 'REVIEW'
                                    ? 'התשלום דורש בדיקה'
                                    : row['status'] == 'FAILED'
                                    ? 'יצירת הקישור נכשלה'
                                    : 'ממתינים לאישור תשלום',
                                style: AppText.headline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '₪${((num.tryParse(row['amount_minor'].toString()) ?? 0) / 100).toStringAsFixed(2)}',
                                textDirection: TextDirection.ltr,
                                style: AppText.title,
                              ),
                              if (row['receipt_error'] != null)
                                const Text(
                                  'יש להשלים בדיקת שיוך או קבלה. התשלום המאומת נשמר.',
                                  style: AppText.secondary,
                                ),
                              if (![
                                'CREATING',
                                'FAILED',
                              ].contains(row['status']))
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _verify(row['id'] as String),
                                  child: const Text(BusinessHe.checkCardcom),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

enum _DemoPaymentMethod { card, bit, applePay, googlePay, payBox }

/// Customer facing checkout preview for the proxy/demo account.
/// It deliberately never submits or stores payment credentials.
class CustomerPaymentPreviewScreen extends StatefulWidget {
  const CustomerPaymentPreviewScreen({
    super.key,
    this.businessName,
    this.invoiceLabel,
    this.amountMinor,
  });

  final String? businessName;
  final String? invoiceLabel;
  final BigInt? amountMinor;

  @override
  State<CustomerPaymentPreviewScreen> createState() =>
      _CustomerPaymentPreviewScreenState();
}

class _CustomerPaymentPreviewScreenState
    extends State<CustomerPaymentPreviewScreen> {
  _DemoPaymentMethod _method = _DemoPaymentMethod.card;

  void _showPaymentSoon() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentNotchNotice()
      ..showNotchNotice(
        const SnackBar(content: Text('בקרוב — הסליקה תהיה זמינה כאן')),
        motion: NoticeMotion.payment,
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final amountMinor = widget.amountMinor ?? BigInt.from(118000);
    final amount = (amountMinor.toDouble() / 100).toStringAsFixed(2);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.m,
                Space.page,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('תשלום מאובטח', style: AppText.displayTitle),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.xl,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(Space.l),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(Radii.card),
                      border: Border.all(color: p.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'תשלום עבור',
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          widget.businessName ?? businessContext.displayName,
                          style: AppText.headline,
                        ),
                        const SizedBox(height: Space.m),
                        Text(
                          widget.invoiceLabel ?? 'חשבונית לדוגמה · 1048',
                          style: AppText.secondary.copyWith(color: p.muted),
                        ),
                        const SizedBox(height: Space.s),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text('₪$amount', style: AppText.displayTitle),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.section),
                  Text(
                    'איך נוח לך לשלם?',
                    style: AppText.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.m),
                  Column(
                    key: const Key('payment-method-grid'),
                    children: [
                      for (final method in _DemoPaymentMethod.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: _PaymentMethodTile(
                            method: method,
                            selected: _method == method,
                            onTap: () => setState(() => _method = method),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.m),
                  AppCard(
                    child: Row(
                      children: [
                        Icon(Iconsax.info_circle, color: p.info),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Text(
                            'אפשרויות התשלום ייפתחו בקרוב. כרגע לא מזינים פרטי אשראי ולא מתבצע חיוב.',
                            style: AppText.body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Container(
                    padding: const EdgeInsets.all(Space.m),
                    decoration: BoxDecoration(
                      color: p.tint(p.warn),
                      borderRadius: BorderRadius.circular(Radii.button),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Iconsax.info_circle, size: 20, color: p.warn),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text(
                            'הודעת הדגמה בלבד — פרטי תשלום אינם נאספים או נשמרים.',
                            style: AppText.secondary.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  SizedBox(
                    height: Hit.primary,
                    child: FilledButton.icon(
                      key: const Key('secure-payment-continue'),
                      onPressed: _showPaymentSoon,
                      icon: const Icon(Iconsax.info_circle),
                      label: Text(PaymentHe.comingSoon, style: AppText.button),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.accentInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.button),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });
  final _DemoPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 78,
      child: Material(
        color: selected ? p.tint(p.info) : p.surface,
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.button),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.button),
              border: Border.all(
                color: selected ? p.info : p.line,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 82,
                  child: Center(child: _PaymentBrand(method: method)),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _paymentMethodLabel(method),
                        style: AppText.headline,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _paymentMethodSubtitle(method),
                        style: AppText.secondary.copyWith(
                          color: p.muted,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.s),
                Icon(
                  selected ? Iconsax.tick_circle : Icons.radio_button_unchecked,
                  color: selected ? p.info : p.muted,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentBrand extends StatelessWidget {
  const _PaymentBrand({required this.method});
  final _DemoPaymentMethod method;

  @override
  Widget build(BuildContext context) {
    final mark = switch (method) {
      _DemoPaymentMethod.card => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.card, color: context.palette.ink, size: 20),
          const SizedBox(width: 7),
          Text('כרטיס אשראי', style: AppText.headline.copyWith(fontSize: 14)),
        ],
      ),
      _DemoPaymentMethod.bit => const Image(
        image: AssetImage('assets/brand/bit-app-icon.png'),
        width: 40,
        height: 40,
        fit: BoxFit.contain,
      ),
      _DemoPaymentMethod.applePay => const Image(
        image: AssetImage('assets/brand/apple-pay-mark.png'),
        width: 76,
        height: 48,
        fit: BoxFit.contain,
      ),
      _DemoPaymentMethod.googlePay => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'G',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4285F4),
            ),
          ),
          SizedBox(width: 5),
          Text(
            'Pay',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
      _DemoPaymentMethod.payBox => const Image(
        image: AssetImage('assets/brand/paybox-app-icon.png'),
        width: 40,
        height: 40,
        fit: BoxFit.contain,
      ),
    };
    if (method == _DemoPaymentMethod.applePay ||
        method == _DemoPaymentMethod.bit ||
        method == _DemoPaymentMethod.payBox) {
      return mark;
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 72, minHeight: 38),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: method == _DemoPaymentMethod.card
            ? context.palette.tint(context.palette.info)
            : Colors.white,
        borderRadius: BorderRadius.circular(11),
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: mark),
    );
  }
}

String _paymentMethodLabel(_DemoPaymentMethod method) => switch (method) {
  _DemoPaymentMethod.card => 'כרטיס אשראי',
  _DemoPaymentMethod.bit => 'תשלום ב־bit',
  _DemoPaymentMethod.applePay => 'Apple Pay',
  _DemoPaymentMethod.googlePay => 'Google Pay',
  _DemoPaymentMethod.payBox => 'PayBox',
};

String _paymentMethodSubtitle(_DemoPaymentMethod method) => switch (method) {
  _DemoPaymentMethod.card => 'Visa, Mastercard וכרטיסים נוספים',
  _DemoPaymentMethod.bit => 'אישור באפליקציית bit',
  _DemoPaymentMethod.applePay => 'תשלום מהיר במכשירי Apple',
  _DemoPaymentMethod.googlePay => 'תשלום מהיר דרך Google Pay',
  _DemoPaymentMethod.payBox => 'אישור באפליקציית PayBox',
};
