import '../../util/labels/common_he.dart';
import '../../util/labels/business_he.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/commerce_api.dart';
import '../../api/client.dart';
import '../../state/business_context.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../../util/allowed_urls.dart';

const _planColors = [
  DesignTokens.green,
  DesignTokens.lavender,
  DesignTokens.yellow,
];

Future<void> showBillingPlans(BuildContext context) async {
  final navigator = Navigator.of(context);
  final plan = await showModalBottomSheet<BillingPlan>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 420),
      reverseDuration: Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
    builder: (_) => const PlansSheet(),
  );
  if (plan != null && context.mounted) {
    await navigator.push(
      AppPageRoute<void>(builder: (_) => BillingCheckoutScreen(plan: plan)),
    );
  }
}

class PlansSheet extends StatefulWidget {
  const PlansSheet({
    super.key,
    this.requiredForAccess = false,
    this.onSubscribed,
    this.onExit,
  });

  final bool requiredForAccess;
  final VoidCallback? onSubscribed;
  final VoidCallback? onExit;

  @override
  State<PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends State<PlansSheet> with WidgetsBindingObserver {
  BillingCatalog? _catalog;
  SubscriptionStatus? _subscription;
  final Map<String, ProductDetails> _products = {};
  bool _cancelling = false;
  final _pages = PageController(initialPage: 1, viewportFraction: .84);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  Object? _error;
  String? _selected;
  bool _returnedAfterSubscription = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _subscription?.billingProvider == 'APPLE') {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    try {
      final c = await fetchBillingPlans();
      final subscription = await fetchSubscription();
      if (Platform.isIOS && c.appleIapAvailable) {
        final store = InAppPurchase.instance;
        if (await store.isAvailable()) {
          final response = await store.queryProductDetails(
            c.plans
                .map((plan) => plan.appleProductId)
                .where((id) => id.isNotEmpty)
                .toSet(),
          );
          _products
            ..clear()
            ..addEntries(
              response.productDetails.map(
                (product) => MapEntry(product.id, product),
              ),
            );
        }
      }
      if (mounted) {
        setState(() {
          _catalog = c;
          _subscription = subscription;
          _selected = c.plans.length > 1 ? c.plans[1].code : c.plans.first.code;
          _error = null;
        });
        if (widget.requiredForAccess &&
            subscription.active &&
            !_returnedAfterSubscription) {
          _returnedAfterSubscription = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onSubscribed?.call();
          });
        }
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cancel() async {
    if (_subscription?.billingProvider == 'APPLE') {
      final opened = await launchUrl(
        Uri.parse('https://apps.apple.com/account/subscriptions'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        setState(() => _error = 'לא ניתן לפתוח את ניהול המינויים של Apple.');
      }
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('לבטל את חידוש המסלול?'),
        content: const Text(
          'המסלול נשאר פעיל עד סוף התקופה ששולמה. לאחר מכן לא יתבצע חידוש.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(BusinessHe.keepSubscription),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(BusinessHe.cancelRenewalAction),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await cancelSubscription();
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _continueWithPlan(BillingPlan plan) async {
    if (!widget.requiredForAccess) {
      Navigator.pop(context, plan);
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute<void>(builder: (_) => BillingCheckoutScreen(plan: plan)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.requiredForAccess,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.requiredForAccess) widget.onExit?.call();
    },
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('מקום לגדול', style: AppText.displayTitle),
                ),
                if (!widget.requiredForAccess || widget.onExit != null)
                  IconButton(
                    tooltip: CommonHe.close,
                    onPressed: widget.requiredForAccess
                        ? widget.onExit
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
            ),
            Text(
              'מסלול קטן. שקט גדול.\nבוחרים מה שמתאים לעסק שלך.',
              style: AppText.body.copyWith(
                color: context.palette.muted,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              ErrorView(error: _error!, onRetry: _load)
            else if (_catalog == null)
              const SkeletonList(rows: 3)
            else ...[
              if (_subscription?.active == true) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('המסלול שלך פעיל', style: AppText.headline),
                      const SizedBox(height: 8),
                      Text(
                        '${_subscription!.used} מסמכי הכנסה הופקו החודש',
                        style: AppText.body,
                      ),
                      if (_subscription!.cancelAtPeriodEnd)
                        const Text(
                          'החידוש בוטל. המסלול פעיל עד סוף התקופה ששולמה.',
                          style: AppText.secondary,
                        )
                      else
                        TextButton(
                          onPressed: _cancelling ? null : _cancel,
                          child: Text(
                            _subscription!.billingProvider == 'APPLE'
                                ? BusinessHe.manageAppleSubscription
                                : BusinessHe.cancelPlanRenewal,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              SizedBox(
                height:
                    500 *
                    MediaQuery.textScalerOf(context).scale(1).clamp(1, 2.0),
                child: PageView.builder(
                  key: const Key('plans-carousel'),
                  controller: _pages,
                  itemCount: _catalog!.plans.length,
                  onPageChanged: (index) =>
                      setState(() => _selected = _catalog!.plans[index].code),
                  itemBuilder: (context, index) => AnimatedBuilder(
                    animation: _pages,
                    builder: (context, _) {
                      final page =
                          _pages.hasClients &&
                              _pages.position.hasContentDimensions
                          ? _pages.page ?? 1
                          : 1.0;
                      final distance = (page - index).clamp(-1.0, 1.0);
                      final reduced = MediaQuery.disableAnimationsOf(context);
                      return Transform.rotate(
                        angle: reduced ? 0 : distance * .055,
                        child: Transform.scale(
                          scale: reduced ? 1 : 1 - distance.abs() * .07,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                            child: _PlanCard(
                              plan: _catalog!.plans[index],
                              localizedPrice:
                                  _products[_catalog!
                                          .plans[index]
                                          .appleProductId]
                                      ?.price,
                              color: _planColors[index % 3],
                              selected:
                                  _selected == _catalog!.plans[index].code,
                              onTap: () => _pages.animateToPage(
                                index,
                                duration: context.motion(300),
                                curve: Curves.easeOutCubic,
                              ),
                              onContinue: () =>
                                  _continueWithPlan(_catalog!.plans[index]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _catalog!.plans.length; i++)
                    Semantics(
                      selected: _selected == _catalog!.plans[i].code,
                      button: true,
                      label: 'בחירת מסלול ${_catalog!.plans[i].name}',
                      child: InkWell(
                        key: Key('plan-dot-${_catalog!.plans[i].code}'),
                        onTap: () => _pages.animateToPage(
                          i,
                          duration: context.motion(300),
                          curve: Curves.easeOutCubic,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 14,
                          ),
                          child: AnimatedContainer(
                            duration: context.motion(220),
                            height: 8,
                            width: _selected == _catalog!.plans[i].code
                                ? 28
                                : 8,
                            decoration: BoxDecoration(
                              color: _selected == _catalog!.plans[i].code
                                  ? _planColors[i % 3]
                                  : context.palette.line,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'המחירים כוללים מע״מ • מכסה חודשית של מסמכי הכנסה',
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(
                  color: context.palette.muted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              const Text('טוב לדעת', style: AppText.title),
              const SizedBox(height: 8),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('מה נספר במכסה החודשית?'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'כל מסמכי ההכנסה שהופקו, כולל חשבוניות וקבלות. טיוטות אינן נספרות.',
                    ),
                  ),
                ],
              ),
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('אפשר לבטל את החידוש?'),
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text(
                      'כן. ניתן לבטל את החידוש בניהול המסלול. התקופה ששולמה נשארת פעילה עד סיומה.',
                    ),
                  ),
                ],
              ),
            ],
            if (widget.requiredForAccess && widget.onExit != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('required-plan-later'),
                onPressed: widget.onExit,
                icon: const Icon(Icons.close_rounded),
                label: const Text('אולי אחר כך'),
              ),
              const SizedBox(height: 6),
              Text(
                'אפשר לבחור מסלול בהמשך. בחירת המסלול תופיע שוב בכניסה הבאה.',
                textAlign: TextAlign.center,
                style: AppText.secondary.copyWith(color: context.palette.muted),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class RequiredSubscriptionScreen extends StatelessWidget {
  const RequiredSubscriptionScreen({
    super.key,
    required this.onSubscribed,
    required this.onExit,
  });

  final VoidCallback onSubscribed;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: PlansSheet(
        requiredForAccess: true,
        onSubscribed: onSubscribed,
        onExit: onExit,
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    this.localizedPrice,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.onContinue,
  });
  final BillingPlan plan;
  final String? localizedPrice;
  final Color color;
  final bool selected;
  final VoidCallback onTap, onContinue;
  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF302139);
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.name}, ${plan.monthlyMinor ~/ 100} שקלים לחודש',
      child: Material(
        key: Key('plan-${plan.code}'),
        color: color,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          plan.limit == null
                              ? Icons.all_inclusive_rounded
                              : plan.limit == 21
                              ? Icons.auto_awesome_outlined
                              : Icons.workspace_premium_outlined,
                          size: 42,
                          color: ink,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          plan.name,
                          textAlign: TextAlign.center,
                          style: AppText.title.copyWith(color: ink),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              localizedPrice ?? '₪${plan.monthlyMinor ~/ 100}',
                              textDirection: TextDirection.ltr,
                              style: AppText.displayTitle.copyWith(
                                fontSize: 42,
                                color: ink,
                              ),
                            ),
                            Text(
                              ' / לחודש',
                              style: AppText.body.copyWith(color: ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        for (final text in [
                          plan.limit == null
                              ? 'מסמכי הכנסה ללא הגבלה'
                              : 'עד ${plan.limit} מסמכי הכנסה בחודש',
                          'המסמך נשלח ללקוח במייל או בקוד QR',
                          'מעקב מסודר אחרי הכנסות והוצאות',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 20,
                                      color: ink,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        text,
                                        textAlign: TextAlign.center,
                                        style: AppText.body.copyWith(
                                          color: ink,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  key: selected ? const Key('plans-continue') : null,
                  onPressed: onContinue,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: ink,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      BusinessHe.selectPlanAndPay,
                      textAlign: TextAlign.center,
                      style: AppText.button,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BillingCheckoutScreen extends StatefulWidget {
  const BillingCheckoutScreen({super.key, required this.plan});
  final BillingPlan plan;
  @override
  State<BillingCheckoutScreen> createState() => _BillingCheckoutScreenState();
}

class _BillingCheckoutScreenState extends State<BillingCheckoutScreen>
    with WidgetsBindingObserver {
  bool _accepted = false, _busy = false, _paid = false, _storeAvailable = false;
  final bool _isIOS = Platform.isIOS;
  String? _error;
  String? _checkoutId;
  String _paymentMethod = 'CARD';
  ProductDetails? _product;
  BillingCatalog? _catalog;
  bool _checking = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isIOS) {
      _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
        _handlePurchases,
        onError: (Object error) {
          if (mounted) {
            setState(
              () => _error = 'התקשורת עם App Store נכשלה. אפשר לנסות שוב.',
            );
          }
        },
      );
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final catalog = await fetchBillingPlans();
      var available = false;
      ProductDetails? product;
      if (_isIOS && catalog.appleIapAvailable) {
        final store = InAppPurchase.instance;
        available = await store.isAvailable();
        if (available && widget.plan.appleProductId.isNotEmpty) {
          final response = await store.queryProductDetails({
            widget.plan.appleProductId,
          });
          product = response.productDetails
              .where((item) => item.id == widget.plan.appleProductId)
              .firstOrNull;
        }
      }
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _storeAvailable = available;
          _product = product;
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'לא ניתן לטעון את פרטי התשלום. נסה שוב.');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_isIOS) {
        unawaited(_refreshSubscription());
      } else if (_checkoutId != null) {
        unawaited(_verifyCardcom());
      }
    }
  }

  Future<void> _verifyCardcom() async {
    final id = _checkoutId;
    if (id == null || _checking || _paid) return;
    setState(() => _checking = true);
    try {
      final paid = await verifyBillingCheckout(id);
      if (mounted) setState(() => _paid = paid);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == 'PAYMENT_NOT_COMPLETE'
              ? 'ממתינים לאישור התשלום. אפשר לבדוק שוב בעוד רגע.'
              : error.messageHe,
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _refreshSubscription() async {
    try {
      final subscription = await fetchSubscription();
      if (mounted && subscription.active) setState(() => _paid = true);
    } on Object {
      // The purchase stream remains the source for the current checkout result.
    }
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _busy = true);
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _busy = false);
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error =
                purchase.error?.message ?? 'הרכישה לא הושלמה. אפשר לנסות שוב.';
          });
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      try {
        final signedTransaction =
            purchase.verificationData.serverVerificationData;
        if (signedTransaction.isEmpty) {
          throw const FormatException('חסרים נתוני עסקה חתומים מ־Apple');
        }
        final status = await verifyAppleSubscription(signedTransaction);
        if (mounted) {
          setState(() {
            _paid = status == 'ACTIVE';
            _busy = false;
            _error = _paid
                ? null
                : 'המינוי לא פעיל כרגע. אפשר לשחזר רכישות או לנסות שוב.';
          });
        }
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = error is ApiException
                ? error.messageHe
                : 'לא ניתן לאמת את הרכישה מול Apple. נסה שוב.';
          });
        }
      }
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await InAppPurchase.instance.restorePurchases();
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'לא ניתן לשחזר רכישות כרגע. בדוק את חשבון Apple ונסה שוב.';
        });
      }
    }
  }

  Future<void> _openLegal(String url) async {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      setState(() => _error = 'לא ניתן לפתוח את הקישור כרגע.');
    }
  }

  Future<void> _pay() async {
    if (_busy) return;
    if (!_accepted) {
      setState(() => _error = 'יש לאשר את פרטי המסלול לפני התשלום');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isIOS) {
        final product = _product;
        if (!_storeAvailable || product == null) {
          throw const FormatException(
            'מסלול התשלום אינו זמין כרגע. יש להשלים את הגדרת המינוי ב־App Store Connect.',
          );
        }
        final appAccountToken = await fetchAppleAccountToken();
        final submitted = await InAppPurchase.instance.buyNonConsumable(
          purchaseParam: PurchaseParam(
            productDetails: product,
            applicationUserName: appAccountToken,
          ),
        );
        if (!submitted && mounted) {
          setState(() {
            _busy = false;
            _error = 'App Store לא התחיל את הרכישה. אפשר לנסות שוב.';
          });
        }
      } else {
        final checkout = await createBillingCheckout(
          widget.plan.code,
          paymentMethod: _paymentMethod,
        );
        if (!mounted) return;
        _checkoutId = checkout.id;
        final opened = await openPaymentPage(checkout.url);
        if (!opened && mounted) {
          setState(() => _error = 'דף התשלום לא נפתח. ניתן לנסות שוב.');
        }
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.messageHe;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is FormatException
              ? error.message.toString()
              : 'לא ניתן להתחיל את הרכישה כרגע. נסה שוב.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('בדרך לשקט שלך', style: AppText.title),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: ContentReveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: context.motion(240),
                        child: Container(
                          key: ValueKey(_product?.id ?? widget.plan.code),
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              colors: [
                                DesignTokens.lavender,
                                Color(0xFFE9DEFA),
                              ],
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _isIOS
                                          ? 'מינוי דרך App Store'
                                          : 'תשלום מאובטח',
                                      style: AppText.title.copyWith(
                                        color: const Color(0xFF302139),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    _paid
                                        ? Icons.check_circle_outline
                                        : Icons.contactless_outlined,
                                    color: const Color(0xFF302139),
                                    size: 30,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 30),
                              Text(
                                _product?.price ??
                                    '₪${widget.plan.monthlyMinor ~/ 100}',
                                textDirection: TextDirection.ltr,
                                style: AppText.displayTitle.copyWith(
                                  color: const Color(0xFF302139),
                                  fontSize: 38,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${widget.plan.name} · חודש',
                                style: AppText.body.copyWith(
                                  color: const Color(0xFF302139),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        _paid ? 'העסק שלך מוכן להמשיך' : 'המסלול שבחרת',
                        textAlign: TextAlign.center,
                        style: AppText.displayTitle.copyWith(fontSize: 30),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        businessContext.displayName,
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: p.muted),
                      ),
                      const SizedBox(height: 24),
                      if (!_paid) ...[
                        if (_isIOS)
                          Text(
                            'התשלום מאובטח ומתבצע בחלון של App Store. המינוי מתחדש מדי חודש דרך חשבון Apple שלך; אפשר לנהל או לבטל אותו בהגדרות Apple בכל עת.',
                            style: AppText.secondary.copyWith(
                              color: p.muted,
                              height: 1.5,
                            ),
                          )
                        else ...[
                          const Text('איך נוח לך לשלם?', style: AppText.title),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final method in ['CARD', 'BIT'])
                                ChoiceChip(
                                  key: Key('payment-$method'),
                                  selected: _paymentMethod == method,
                                  avatar: Icon(
                                    method == 'CARD'
                                        ? Icons.credit_card_rounded
                                        : Icons.phone_iphone_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    method == 'CARD' ? 'כרטיס' : 'bit',
                                  ),
                                  onSelected: _busy || _checkoutId != null
                                      ? null
                                      : (_) => setState(
                                          () => _paymentMethod = method,
                                        ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _paymentMethod == 'BIT'
                                ? 'תשלום bit זמין אם הוא מופעל במסוף העסק.'
                                : 'התשלום מתבצע בדף המאובטח של Cardcom לפי האפשרויות במסוף.',
                            style: AppText.secondary.copyWith(
                              color: p.muted,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 28),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.plan.name,
                                    style: AppText.title,
                                  ),
                                ),
                                Text(
                                  _product?.price ??
                                      '₪${widget.plan.monthlyMinor ~/ 100}',
                                  textDirection: TextDirection.ltr,
                                  style: AppText.title.copyWith(fontSize: 38),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              widget.plan.limit == null
                                  ? 'מסמכי הכנסה ללא הגבלה'
                                  : 'עד ${widget.plan.limit} מסמכי הכנסה בכל חודש',
                              style: AppText.body,
                            ),
                            const SizedBox(height: 18),
                            Divider(color: p.line),
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                Expanded(child: Text('תקופת המסלול')),
                                Flexible(
                                  child: Text('חודש', textAlign: TextAlign.end),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                Expanded(child: Text('מע״מ')),
                                Flexible(
                                  child: Text(
                                    'כלול במחיר',
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isIOS
                                  ? 'מינוי חודשי מתחדש אוטומטית. מחיר החידוש מוצג לפני אישור הרכישה וניתן לבטל את המינוי בכל עת בניהול המינויים של Apple.'
                                  : _catalog?.recurring == true &&
                                        _paymentMethod == 'CARD'
                                  ? 'חיוב חודשי מתחדש. ניתן לבטל את החידוש.'
                                  : 'תשלום עבור חודש אחד. חידוש יתבצע מתוך האפליקציה.',
                              style: AppText.secondary.copyWith(
                                color: p.muted,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_isIOS)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: () => _openLegal(
                                'https://www.tevel.space/legal/tevel-invoice',
                              ),
                              child: const Text(BusinessHe.termsAction),
                            ),
                            TextButton(
                              onPressed: () => _openLegal(
                                'https://www.tevel.space/legal/privacy',
                              ),
                              child: const Text(BusinessHe.privacyAction),
                            ),
                          ],
                        ),
                      if (!_paid && _isIOS)
                        TextButton.icon(
                          onPressed: _busy ? null : _restore,
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text(BusinessHe.restorePurchasesAction),
                        )
                      else if (!_paid && _checkoutId != null)
                        TextButton.icon(
                          onPressed: _checking ? null : _verifyCardcom,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(
                            _checking
                                ? BusinessHe.checkingPayment
                                : BusinessHe.checkPaymentApproval,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            BottomActionArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .4,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_paid)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _accepted,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                        setState(() => _accepted = v ?? false),
                              title: const Text(
                                'אני מאשר/ת את המסלול ואת המחיר המוצגים',
                                style: AppText.body,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          if ((_isIOS &&
                                  (!_storeAvailable || _product == null)) ||
                              (!_isIOS && _catalog?.available == false))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                _isIOS
                                    ? 'רכישה דרך App Store אינה זמינה כרגע. יש להשלים ולהפעיל את מוצרי המינוי ב־App Store Connect.'
                                    : 'התשלום ייפתח לאחר השלמת חיבור הסליקה לעסק.',
                                style: AppText.body.copyWith(color: p.warn),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: AppText.body.copyWith(color: p.danger),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PrimaryButton(
                    key: const Key('checkout-pay'),
                    label: _paid
                        ? BusinessHe.backToBusiness
                        : _isIOS
                        ? BusinessHe.monthlySubscriptionPrice(
                            _product?.price ??
                                '₪${widget.plan.monthlyMinor ~/ 100}',
                          )
                        : BusinessHe.securePaymentPrice(
                            widget.plan.monthlyMinor,
                          ),
                    icon: _paid
                        ? Icons.check_rounded
                        : Icons.lock_outline_rounded,
                    loadingText: _busy
                        ? _isIOS
                              ? BusinessHe.waitingForAppStore
                              : BusinessHe.preparingCheckout
                        : null,
                    onPressed: _paid ? () => Navigator.pop(context) : _pay,
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
