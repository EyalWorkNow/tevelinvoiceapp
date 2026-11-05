// The tab shell (SPEC-v2 §5). Owner: INT.
//
//   עסק   ·   [ ＋ ]   ·   לקוחות   ·   בית        (RTL: בית on the right)
//
// The ＋ lives inside the tab bar and opens the default invoice Composer. It
// disappears when the user cannot draft a document. The "בית"
// tab shows R for the accountant presets, H for everyone else (§4.4).

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api/commerce_api.dart';
import 'screens/billing/billing_screen.dart';
import 'state/caps.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import 'router.dart' show openCompose, peopleChip;
import 'screens/business/business_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/people/people_screen.dart';
import 'screens/profile/profile_settings_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'state/business_context.dart';
import 'ui/theme.dart';
import 'ui/widgets/design_controls.dart' show DesignIcon;
import 'util/labels/common_he.dart';
import 'util/intent_resolver.dart' show invoiceIntentFor;

/// App destinations. ＋ is an action, not a tab.
enum AppTab { home, people, business, profile }

/// The visible tab. Written by router.dart (selectTab / go / reset).
final ValueNotifier<AppTab> currentTab = ValueNotifier(AppTab.home);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// True while an AppShell is in the tree (router decides tab switch vs reset).
  static bool get mounted => _mountedCount > 0;
  static int _mountedCount = 0;

  /// Height of the tab bar (screens add it + 24 to their bottom padding, §6.H).
  static const double barHeight = 88;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  String? _billingBusiness;
  bool _checkingBilling = false;
  void _checkBilling() {
    final id = businessContext.business?.businessId;
    if (!mounted ||
        id == null ||
        id == _billingBusiness ||
        _checkingBilling ||
        !businessContext.can(Cap.owner)) {
      return;
    }
    _checkingBilling = true;
    unawaited(() async {
      try {
        final status = await fetchSubscription();
        if (!mounted || id != businessContext.business?.businessId) return;
        _billingBusiness = id;
        if (status.needsPlan) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              unawaited(showBillingPlans(context));
            }
          });
          WidgetsBinding.instance.scheduleFrame();
        }
      } on Object {
        // The explicit plan page exposes retry/error state; keep the shell usable offline.
      } finally {
        _checkingBilling = false;
      }
    }());
  }

  void _animateTab() {
    final next = currentTab.value;
    if (next != _lastTab) {
      _previousTab = _lastTab;
      _lastTab = next;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
  }

  AppTab _lastTab = AppTab.home;
  AppTab _previousTab = AppTab.home;

  @override
  void initState() {
    super.initState();
    AppShell._mountedCount++;
    currentTab.addListener(_animateTab);
    businessContext.addListener(_checkBilling);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBilling());
  }

  @override
  void dispose() {
    currentTab.removeListener(_animateTab);
    businessContext.removeListener(_checkBilling);
    _transition.dispose();
    AppShell._mountedCount--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([currentTab, businessContext, peopleChip]),
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final caps = businessContext.caps;
    final tab = currentTab.value;
    return Scaffold(
      extendBody: true,
      body: FadeTransition(
        opacity: _transition.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: SlideTransition(
          position: _transition.drive(
            Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: IndexedStack(
            index: tab.index,
            children: [
              caps.homeIsReports
                  ? const ReportsScreen(embedded: true)
                  : const HomeScreen(),
              PeopleScreen(
                chip: peopleChip.value,
                onBack: () => currentTab.value = _previousTab,
              ),
              const BusinessScreen(),
              const ProfileSettingsScreen(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: TabBarWithCreate(
        current: tab,
        showCreate:
            tab == AppTab.home && !caps.homeIsReports && caps.showCreateTab,
        onTab: (t) {
          HapticFeedback.selectionClick();
          currentTab.value = t;
        },
        onCreate: () {
          HapticFeedback.mediumImpact();
          unawaited(
            openCompose(
              context,
              intent: invoiceIntentFor(businessContext.businessType),
            ),
          );
        },
      ),
    );
  }
}

/// Three frosted-glass destinations; invoice creation is a separate home action.
class TabBarWithCreate extends StatelessWidget {
  const TabBarWithCreate({
    super.key,
    required this.current,
    required this.showCreate,
    required this.onTab,
    required this.onCreate,
  });

  final AppTab current;
  final bool showCreate;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 364;
    final navigationWidth = (screenWidth * .58)
        .clamp(compact ? 184.0 : 196.0, 252.0)
        .toDouble();
    return SizedBox(
      width: double.infinity,
      height: 88 + MediaQuery.viewPaddingOf(context).bottom,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.symmetric(horizontal: showCreate ? 0 : 12),
        child: AnimatedAlign(
          alignment: showCreate ? Alignment.centerRight : Alignment.center,
          duration: context.motion(380),
          curve: Curves.easeInOutCubic,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AnimatedSize(
              duration: context.motion(380),
              curve: Curves.easeInOutCubic,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: TextDirection.rtl,
                children: [
                  AnimatedSwitcher(
                    duration: context.motion(380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: showCreate
                        ? KeyedSubtree(
                            key: const ValueKey('home-create-visible'),
                            child: _createButton(context),
                          )
                        : const SizedBox(
                            key: ValueKey('home-create-hidden'),
                            width: 0,
                            height: 0,
                          ),
                  ),
                  AnimatedContainer(
                    duration: context.motion(380),
                    curve: Curves.easeInOutCubic,
                    width: showCreate ? 10 : 0,
                  ),
                  SizedBox(
                    width: navigationWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: .29),
                                (context.isDark
                                        ? const Color(0xFF514951)
                                        : p.surface)
                                    .withValues(alpha: .82),
                                Colors.white.withValues(alpha: .2),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(40),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .48),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .28),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: .09),
                                blurRadius: 1,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Row(
                              children: [
                                _item(
                                  context,
                                  AppTab.home,
                                  CommonHe.tabHome,
                                  'home',
                                ),
                                _item(
                                  context,
                                  AppTab.business,
                                  'ניהול',
                                  'manage',
                                ),
                                _item(
                                  context,
                                  AppTab.profile,
                                  'פרופיל',
                                  'profile',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    AppTab tab,
    String label,
    String iconName,
  ) => Expanded(
    child: Center(
      child: _button(
        context,
        key: Key('tab-${tab.name}'),
        label: label,
        iconName: iconName,
        active:
            tab == current ||
            (tab == AppTab.business && current == AppTab.people),
        onTap: () {
          if (tab != current) onTab(tab);
        },
      ),
    ),
  );

  Widget _button(
    BuildContext context, {
    required Key key,
    required String label,
    required String iconName,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 364;
    final diameter = compact ? 54.0 : 72.0;
    final p = context.palette;
    final color = active
        ? const Color(0xFF382844)
        : context.isDark
        ? Colors.white
        : p.ink;
    return Semantics(
      selected: active,
      button: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        width: diameter,
        height: diameter,
        duration: context.motion(300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFD9BDF0)
              : const Color(0xFF302832).withValues(alpha: .96),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: active ? .22 : .13),
            width: 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: .24),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: key,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ColorFiltered(
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                      child: DesignIcon(iconName, size: compact ? 27 : 36),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      label,
                      textScaler: TextScaler.noScaling,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: MediaQuery.textScalerOf(context)
                            .scale(compact ? 11.5 : 13)
                            .clamp(11.5, 15.0)
                            .toDouble(),
                        fontWeight: FontWeight.w600,
                        color: color,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _createButton(BuildContext context) {
    final diameter = MediaQuery.sizeOf(context).width < 364 ? 80.0 : 86.0;
    return SizedBox(
      key: const Key('home-create-glass'),
      width: diameter,
      height: diameter,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: const Color(0xFF442532).withValues(alpha: .96),
            child: InkWell(
              key: const Key('tab-create'),
              onTap: onCreate,
              customBorder: const CircleBorder(),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF5A3749), const Color(0xFF321B27)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .78),
                    width: 2.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: .34),
                      blurRadius: 22,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Iconsax.add_circle,
                          color: Colors.white,
                          size: 47,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'חשבונית\nחדשה',
                        textScaler: TextScaler.noScaling,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: MediaQuery.textScalerOf(
                            context,
                          ).scale(12).clamp(12.0, 15.0).toDouble(),
                          height: 1.05,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
