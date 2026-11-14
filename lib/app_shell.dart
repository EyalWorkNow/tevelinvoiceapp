// The app shell owns root destinations and the floating glass navigation:
// [בית][לקוחות][ניהול][פרופיל] (§5; לקוחות only with Caps.showPeopleTab).
// Invoice creation (＋) sits beside the navigation on every tab when the caps
// allow creating documents (Caps.showCreateTab, 1.5).

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
import 'ui/widgets/design_controls.dart' show DesignIcon;
import 'util/intent_resolver.dart' show invoiceIntentFor;

const double _navigationDesignScale = 1.4;
const double _navigationScaleReduction = .87;
const double _navigationMaxScale =
    _navigationDesignScale * _navigationScaleReduction;
const double _navigationActionSize = 84;
const double _shellBottomNavigationHeight =
    _navigationActionSize * _navigationMaxScale;

/// Capsule width for [items] tabs (3 tabs = the original 206pt design).
double _navigationCapsuleWidth(int items) =>
    items * _navigationItemSize +
    (items - 1) * _navigationItemGap +
    2 * 4.423 +
    1.7;
const double _navigationCapsuleHeight = 72;
const double _navigationGap = 8;
const double _navigationItemSize = 62.808;
const double _navigationItemGap = 3.538;

/// App destinations. Invoice creation is an action, not a destination.
enum AppTab { home, people, business, profile }

/// The visible tab. Written by router.dart (selectTab / go / reset).
final ValueNotifier<AppTab> currentTab = ValueNotifier(AppTab.home);

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  /// True while an AppShell is in the tree (router decides tab switch vs reset).
  static bool get mounted => _mountedCount > 0;
  static int _mountedCount = 0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
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
      if (_pages.hasClients) _pages.jumpToPage(next.index);
      return;
    }
    if (!_pages.hasClients) return;
    unawaited(
      _pages.animateToPage(
        next.index,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeInOutCubic,
      ),
    );
  }

  AppTab _lastTab = currentTab.value;
  AppTab _previousTab = currentTab.value;
  late final PageController _pages = PageController(
    initialPage: currentTab.value.index,
  );

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
    _pages.dispose();
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
    final media = MediaQuery.of(context);
    final bottomContentInset = media.viewInsets.bottom > 0
        ? media.padding.bottom
        : _shellBottomNavigationHeight + media.viewPadding.bottom;
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: ShellBottomNavigation(
        current: tab,
        showPeople: caps.showPeopleTab,
        showCreate: caps.showCreateTab,
        onTab: (next) {
          HapticFeedback.selectionClick();
          currentTab.value = next;
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
      body: MediaQuery(
        data: media.copyWith(
          padding: media.padding.copyWith(bottom: bottomContentInset),
        ),
        child: PageView(
          key: const Key('app-shell-pages'),
          controller: _pages,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _KeepAliveTab(
              child: caps.homeIsReports
                  ? const ReportsScreen(embedded: true)
                  : HomeScreen(
                      onOpenProfile: () => currentTab.value = AppTab.profile,
                    ),
            ),
            _KeepAliveTab(
              child: PeopleScreen(
                chip: peopleChip.value,
                // A root tab of its own; without it P is not reachable.
                onBack: caps.showPeopleTab
                    ? null
                    : () => currentTab.value = _previousTab,
              ),
            ),
            const _KeepAliveTab(child: BusinessScreen()),
            const _KeepAliveTab(child: ProfileSettingsScreen()),
          ],
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin<_KeepAliveTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

@visibleForTesting
class ShellBottomNavigation extends StatefulWidget {
  const ShellBottomNavigation({
    super.key,
    required this.current,
    required this.showPeople,
    required this.showCreate,
    required this.onTab,
    required this.onCreate,
  });

  final AppTab current;
  final bool showPeople;
  final bool showCreate;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onCreate;

  @override
  State<ShellBottomNavigation> createState() => _ShellBottomNavigationState();
}

class _ShellBottomNavigationState extends State<ShellBottomNavigation> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.current == AppTab.people && !widget.showPeople
        ? AppTab.business
        : widget.current;
    final capsuleWidth = _navigationCapsuleWidth(widget.showPeople ? 4 : 3);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motionDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 360);
    final scale =
        (((screenWidth - 24) /
                        (capsuleWidth + _navigationActionSize + _navigationGap))
                    .clamp(.7, _navigationDesignScale) *
                _navigationScaleReduction)
            .clamp(.7, _navigationMaxScale)
            .toDouble();
    final navWidth = capsuleWidth * scale;
    final actionSize = _navigationActionSize * scale;
    const barHeight = _shellBottomNavigationHeight;

    return SizedBox(
      height: barHeight + MediaQuery.viewPaddingOf(context).bottom,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 2, 12, 2),
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              textDirection: TextDirection.rtl,
              children: [
                ClipRect(
                  child: AnimatedContainer(
                    duration: motionDuration,
                    curve: Curves.easeInOutCubic,
                    width: widget.showCreate ? actionSize : 0,
                    height: actionSize,
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.centerRight,
                        minWidth: actionSize,
                        maxWidth: actionSize,
                        minHeight: actionSize,
                        maxHeight: actionSize,
                        child: AnimatedSlide(
                          duration: motionDuration,
                          curve: Curves.easeInOutCubic,
                          offset: widget.showCreate
                              ? Offset.zero
                              : const Offset(1.15, 0),
                          child: AnimatedOpacity(
                            duration: motionDuration,
                            curve: Curves.easeOutCubic,
                            opacity: widget.showCreate ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !widget.showCreate,
                              child: ExcludeSemantics(
                                excluding: !widget.showCreate,
                                child: _createButton(actionSize, scale),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: motionDuration,
                  curve: Curves.easeInOutCubic,
                  width: widget.showCreate ? _navigationGap * scale : 0,
                ),
                AnimatedContainer(
                  duration: motionDuration,
                  curve: Curves.easeInOutCubic,
                  width: navWidth,
                  height: _navigationCapsuleHeight * scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34.5 * scale),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 2 * scale,
                        sigmaY: 2 * scale,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(39, 27, 40, .68),
                          borderRadius: BorderRadius.circular(34.5 * scale),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .22),
                            width: scale,
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            4.423 * scale,
                            2.654 * scale,
                            4.423 * scale,
                            3.538 * scale,
                          ),
                          // AT-29: when the לקוחות tab comes or goes (caps
                          // change on a business switch) the capsule animates
                          // its width while the Row already has the new item
                          // count; the tabs keep their size and the capsule
                          // clips them for those 360ms instead of overflowing.
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: double.infinity,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              textDirection: TextDirection.rtl,
                              children: [
                                _item(
                                  context,
                                  AppTab.home,
                                  'בית',
                                  'home',
                                  selected,
                                  motionDuration,
                                  scale,
                                ),
                                if (widget.showPeople) ...[
                                  SizedBox(width: _navigationItemGap * scale),
                                  _item(
                                    context,
                                    AppTab.people,
                                    'לקוחות',
                                    'existing-customer',
                                    selected,
                                    motionDuration,
                                    scale,
                                  ),
                                ],
                                SizedBox(width: _navigationItemGap * scale),
                                _item(
                                  context,
                                  AppTab.business,
                                  'ניהול',
                                  'manage',
                                  selected,
                                  motionDuration,
                                  scale,
                                ),
                                SizedBox(width: _navigationItemGap * scale),
                                _item(
                                  context,
                                  AppTab.profile,
                                  'פרופיל',
                                  'profile',
                                  selected,
                                  motionDuration,
                                  scale,
                                ),
                              ],
                            ),
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
    );
  }

  Widget _item(
    BuildContext context,
    AppTab tab,
    String label,
    String iconName,
    AppTab selected,
    Duration duration,
    double scale,
  ) => SizedBox(
    width: _navigationItemSize * scale,
    height: _navigationItemSize * scale,
    child: Semantics(
      button: true,
      selected: selected == tab,
      label: label,
      child: InkWell(
        key: Key('tab-${tab.name}'),
        borderRadius: BorderRadius.circular(31.404 * scale),
        onTap: () {
          if (selected != tab) widget.onTab(tab);
        },
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          width: _navigationItemSize * scale,
          height: _navigationItemSize * scale,
          decoration: BoxDecoration(
            color: selected == tab
                ? const Color(0xFFD6BDF1)
                : const Color(0xFF322A35),
            borderRadius: BorderRadius.circular(31.404 * scale),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              8 * scale,
              8 * scale,
              8 * scale,
              4 * scale,
            ),
            // scaleDown: four tabs on a narrow phone shrink the bar's scale;
            // the label and icon then fit instead of overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      selected == tab ? const Color(0xFF302138) : Colors.white,
                      BlendMode.srcIn,
                    ),
                    child: DesignIcon(iconName, size: 33 * scale),
                  ),
                  SizedBox(height: 3 * scale),
                  Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected == tab
                          ? const Color(0xFF302138)
                          : Colors.white,
                      fontFamily: 'SF Hebrew Rounded',
                      fontSize: 12.5 * scale,
                      fontWeight: FontWeight.w400,
                      height: 1,
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

  Widget _createButton(double size, double scale) => AnimatedScale(
    scale: _pressed ? .96 : 1,
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    child: ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10 * scale, sigmaY: 10 * scale),
        child: Container(
          key: widget.showCreate
              ? const Key('home-create-glass')
              : const Key('home-create-hidden'),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(66, 34, 49, .24),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: .25),
              width: 4 * scale,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(4 * scale),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                key: widget.showCreate ? const Key('tab-create') : null,
                customBorder: const CircleBorder(),
                onTap: widget.showCreate ? widget.onCreate : null,
                onHighlightChanged: (pressed) {
                  if (mounted && _pressed != pressed) {
                    setState(() => _pressed = pressed);
                  }
                },
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4 * scale),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.add_circle,
                          color: Colors.white,
                          size: 45.5 * scale,
                        ),
                        SizedBox(height: 2 * scale),
                        Text(
                          'חשבונית',
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'SF Hebrew Rounded',
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w400,
                            height: 1,
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
      ),
    ),
  );
}
