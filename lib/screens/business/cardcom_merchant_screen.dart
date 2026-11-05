import 'package:flutter/material.dart';
import '../../api/commerce_api.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';

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
            child: const Text('חזרה'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ניתוק'),
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
                              label: 'שומרים פרטי מסוף',
                              onPressed: _save,
                              loadingText: _busy ? 'שומרים…' : null,
                            ),
                            if (_account!['configured'] == true)
                              TextButton(
                                onPressed: _busy ? null : _disconnect,
                                child: const Text('ניתוק המסוף'),
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
                                  child: const Text('בדיקה מול קארדקום'),
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
