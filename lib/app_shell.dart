import 'api/environment.dart';
// The app shell owns root destinations and the floating glass navigation:
// [בית][לקוחות][ניהול][פרופיל] (§5; לקוחות only with Caps.showPeopleTab).
// Invoice creation (＋) sits beside the navigation on Home when the caps allow
// creating documents (Caps.showCreateTab, 1.5); on the other tabs it slides
// out and the capsule keeps its size (owner's navbar, 2026-11-16).

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api/commerce_api.dart';
import 'api/issue_api.dart' show uploadLocalPendingPayment;
import 'screens/billing/billing_screen.dart';
import 'state/caps.dart';
import 'package:flutter/services.dart';

import 'router.dart' show openCompose, peopleChip;
import 'screens/business/business_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/people/people_screen.dart';
import 'screens/profile/profile_settings_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'state/business_context.dart';
import 'ui/widgets/design_controls.dart' show DesignIcon;
import 'util/intent_resolver.dart' show invoiceIntentFor;

// Reference artwork uses a 206 x 72 capsule beside an 80pt invoice orb.
const double _navigationDisplayScale = 1.07;
const double _navigationActionSize = 80;
const double _shellBottomNavigationHeight = 88 * _navigationDisplayScale;
const double _navigationCapsuleWidth = 206;
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
    if (!paidFeaturesEnabled ||
        !mounted ||
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
        // The launch gate already prompted (or is prompting) this business.
        if (status.needsPlan && !PlanPrompts.handled(id)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                ModalRoute.of(context)?.isCurrent == true &&
                !PlanPrompts.handled(id)) {
              PlanPrompts.markShown(id);
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
    businessContext.addListener(_uploadPendingPayment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBilling();
      _uploadPendingPayment();
    });
  }

  /// SA2: a payment an older version kept on this phone goes to the server.
  void _uploadPendingPayment() => unawaited(uploadLocalPendingPayment());

  @override
  void dispose() {
    currentTab.removeListener(_animateTab);
    businessContext.removeListener(_checkBilling);
    businessContext.removeListener(_uploadPendingPayment);
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
      bottomNavigationBar: _ShellBottomNavigation(
        current: tab,
        showPeople: caps.showPeopleTab,
        showCreate: tab == AppTab.home && caps.showCreateTab,
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
      // The body's own MediaQuery: the Scaffold has already taken the
      // keyboard out of it. Copying the shell's (with viewInsets) made every
      // tab's Scaffold subtract the keyboard a second time — P overflowed
      // whenever a keyboard was up (QA 2026-11-15).
      body: Builder(
        builder: (context) {
          final body = MediaQuery.of(context);
          return MediaQuery(
            data: body.copyWith(
              padding: body.padding.copyWith(bottom: bottomContentInset),
            ),
            child: _pagesView(caps),
          );
        },
      ),
    );
  }

  Widget _pagesView(Caps caps) => PageView(
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
  );
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

/// The owner's navigation, reachable from tests.
@visibleForTesting
typedef ShellBottomNavigation = _ShellBottomNavigation;

class _ShellBottomNavigation extends StatefulWidget {
  const _ShellBottomNavigation({
    required this.current,
    this.showPeople = false,
    required this.showCreate,
    required this.onTab,
    required this.onCreate,
  });

  final AppTab current;

  /// לקוחות as a fourth tab (Caps.showPeopleTab): one more item of the same
  /// size; the capsule widens by exactly that item.
  final bool showPeople;
  final bool showCreate;
  final ValueChanged<AppTab> onTab;
  final VoidCallback onCreate;

  @override
  State<_ShellBottomNavigation> createState() => _ShellBottomNavigationState();
}

/// The ＋ slot's open fraction (0 hidden … 1 shown), animated only when
/// [shown] changes; [builder] multiplies its current sizes by it.
class _CreateSlot extends StatelessWidget {
  const _CreateSlot({
    required this.shown,
    required this.duration,
    required this.builder,
  });

  final bool shown;
  final Duration duration;
  final Widget Function(double factor) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: shown ? 1 : 0),
    duration: duration,
    curve: Curves.easeInOutCubic,
    builder: (context, factor, _) => builder(factor),
  );
}

class _ShellBottomNavigationState extends State<_ShellBottomNavigation> {
  bool _pressed = false;
  AppTab? _pressedTab;

  @override
  Widget build(BuildContext context) {
    final selected = widget.current == AppTab.people && !widget.showPeople
        ? AppTab.business
        : widget.current;
    final capsuleWidth =
        _navigationCapsuleWidth +
        (widget.showPeople ? _navigationItemSize + _navigationItemGap : 0);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final motionDuration = reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 360);
    // Keep the same capsule size on every tab, reserving room for the orb.
    final scale =
        ((screenWidth - 24) /
                (capsuleWidth + _navigationActionSize + _navigationGap))
            .clamp(0.0, _navigationDisplayScale)
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
              // AT-29: when לקוחות comes or goes (a business switch) the bar
              // starts at its new scale instead of resizing in place.
              key: ValueKey(widget.showPeople),
              mainAxisAlignment: MainAxisAlignment.center,
              textDirection: TextDirection.rtl,
              children: [
                // Walkthrough 2026-11-17 #15: only showing / hiding ＋ animates the
                // orb's slot. Its size follows the screen width at once — animating a
                // width change (rotation, split view, a resize) overflowed the row by
                // 6.6px for a few frames. Same sizes and motion as before otherwise.
                _CreateSlot(
                  shown: widget.showCreate,
                  duration: motionDuration,
                  builder: (factor) => ClipRect(
                    child: SizedBox(
                      width: actionSize * factor,
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
                ),
                _CreateSlot(
                  shown: widget.showCreate,
                  duration: motionDuration,
                  builder: (factor) =>
                      SizedBox(width: _navigationGap * scale * factor),
                ),
                SizedBox(
                  width: navWidth,
                  height: _navigationCapsuleHeight * scale,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36 * scale),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 12 * scale,
                        sigmaY: 12 * scale,
                      ),
                      child: DecoratedBox(
                        key: const Key('navigation-capsule'),
                        decoration: BoxDecoration(
                          color: const Color(0xFF39363A).withValues(alpha: .88),
                          borderRadius: BorderRadius.circular(36 * scale),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .28),
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
        onHighlightChanged: (pressed) {
          setState(() => _pressedTab = pressed ? tab : null);
        },
        onTap: () {
          if (selected != tab) widget.onTab(tab);
        },
        child: AnimatedScale(
          scale: _pressedTab == tab ? .93 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
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
                4 * scale,
                4 * scale,
                4 * scale,
                4 * scale,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSlide(
                    offset: selected == tab
                        ? const Offset(0, -.025)
                        : Offset.zero,
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(
                        end: selected == tab
                            ? const Color(0xFF302138)
                            : Colors.white,
                      ),
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      builder: (context, color, child) => ColorFiltered(
                        colorFilter: ColorFilter.mode(color!, BlendMode.srcIn),
                        child: child,
                      ),
                      child: DesignIcon(iconName, size: 30 * scale),
                    ),
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
                      fontSize: 10.5 * scale,
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

  Widget _createButton(double size, double scale) {
    final labelScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    final iconSize = (33 - 14 * (labelScale - 1)).clamp(19.0, 33.0) * scale;
    return AnimatedScale(
      scale: _pressed ? .94 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Semantics(
        button: true,
        label: 'חשבונית',
        excludeSemantics: true,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12 * scale, sigmaY: 12 * scale),
            child: Container(
              key: widget.showCreate
                  ? const Key('home-create-glass')
                  : const Key('home-create-hidden'),
              width: size,
              height: size,
              padding: EdgeInsets.all(3 * scale),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF2EBF3),
                    Color(0xFF736A75),
                    Color(0xFF403741),
                    Color(0xFFB5A0AC),
                  ],
                  stops: [0, .28, .60, 1],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xEB211A24), Color(0xD92B1721)],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                    width: 1.5 * scale,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: widget.showCreate ? const Key('tab-create') : null,
                    customBorder: const CircleBorder(),
                    onTap: widget.showCreate ? widget.onCreate : null,
                    onHighlightChanged: (pressed) {
                      if (_pressed != pressed) {
                        setState(() => _pressed = pressed);
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.2 * scale,
                            ),
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white,
                            size: iconSize * .85,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          'חשבונית',
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'SF Hebrew Rounded',
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.w400,
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
      ),
    );
  }
}
