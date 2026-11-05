import 'package:flutter/material.dart';
import '../../api/client.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../../state/caps.dart';
import '../../ui/app_page_route.dart';
import 'cardcom_merchant_screen.dart';
import '../../ui/ds.dart';
import '../billing/billing_screen.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});
  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  Map<String, dynamic>? _status;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final j = await ApiClient.instance.get('/integrations/status');
      if (mounted) {
        setState(() {
          _status = j;
          _error = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  bool _connected(String key) => (_status?[key] as Map?)?['configured'] == true;
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
                  child: Text('חיבורים ושליחה', style: AppText.displayTitle),
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
                  Text(
                    'כל מה שצריך כדי להפיק, לחתום ולשלוח.\nמצב החיבורים מתעדכן מהשרת.',
                    style: AppText.body.copyWith(
                      color: context.palette.muted,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    ErrorView(error: _error!, onRetry: _load)
                  else if (_status == null)
                    const SkeletonList(rows: 5)
                  else
                    ContentReveal(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _card(
                            'תשלומי הלקוחות שלך',
                            'מסוף קארדקום של העסק',
                            Icons.storefront_outlined,
                            _connected('businessCardcom'),
                            'המסוף נפרד ממנוי תבל. תשלומי הלקוחות נסלקים בעסק שלך.',
                            businessContext.can(Cap.owner)
                                ? () async {
                                    await Navigator.of(context).push(
                                      AppPageRoute<void>(
                                        builder: (_) =>
                                            const CardcomMerchantScreen(),
                                      ),
                                    );
                                    await _load();
                                  }
                                : null,
                          ),
                          _card(
                            'תשלום על המסלול',
                            'קארדקום',
                            Icons.credit_card_rounded,
                            _connected('cardcom'),
                            'מסוף הסליקה של תבל מופעל לאחר פתיחת חשבון ספק.',
                            () => showBillingPlans(context),
                          ),
                          _card(
                            'חשבוניות במייל',
                            'שליחה מהשרת',
                            Icons.mail_outline_rounded,
                            _connected('email'),
                            (_status!['email'] as Map?)?['mode'] == 'file'
                                ? 'סביבת פיתוח: הודעות נשמרות כקבצים מקומיים.'
                                : 'נדרש חיבור ספק מייל פעיל.',
                            null,
                          ),
                          _card(
                            'WhatsApp עסקי',
                            'משלוח אוטומטי ללקוח',
                            Icons.chat_bubble_outline_rounded,
                            _connected('whatsapp'),
                            'נדרשים חשבון WhatsApp Business ותבנית הודעה מאושרת.',
                            null,
                          ),
                          _card(
                            'חתימה דיגיטלית',
                            'חתימה על המקור השמור',
                            Icons.draw_outlined,
                            _connected('signing'),
                            'התעודה שייכת לעסק. חתימה מתבצעת לאחר הפעלה והרשאה.',
                            () => openBusinessSection(
                              context,
                              BusinessSection.shaam,
                            ),
                          ),
                          _card(
                            'חשבוניות ישראל',
                            'מספרי הקצאה ורשות המסים',
                            Icons.account_balance_outlined,
                            (_status!['israelInvoices']
                                    as Map?)?['connected'] ==
                                true,
                            'החיבור דורש הרשאה אישית של העסק ברשות המסים.',
                            () => openBusinessSection(
                              context,
                              BusinessSection.shaam,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'מצב משלוח ותשלום מוצג לפי אישור השרת והספק. ניתן לפתוח את אפשרויות השליחה מתוך כל מסמך.',
                            style: AppText.secondary.copyWith(
                              color: context.palette.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _card(
    String title,
    String subtitle,
    IconData icon,
    bool connected,
    String detail,
    VoidCallback? onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: connected ? DesignTokens.green : DesignTokens.lavender,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.headline),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppText.secondary.copyWith(
                        color: context.palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                connected ? Icons.check_circle_rounded : Icons.pending_outlined,
                color: connected ? DesignTokens.green : context.palette.muted,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            connected ? 'מחובר' : 'ממתין לחיבור',
            style: AppText.body.copyWith(
              color: connected ? DesignTokens.green : context.palette.warn,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: AppText.secondary.copyWith(
              color: context.palette.muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
