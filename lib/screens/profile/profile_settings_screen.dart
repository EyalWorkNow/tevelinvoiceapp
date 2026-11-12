import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../billing/billing_screen.dart';
import '../../ui/theme.dart';
import '../business/account_page.dart';
import '../business/business_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _showSettings = false;

  Widget _switcher(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('profile-settings-switcher'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          _option(
            context,
            label: 'פרופיל',
            icon: Icons.person_outline_rounded,
            selected: !_showSettings,
            onTap: () => setState(() => _showSettings = false),
          ),
          _option(
            context,
            label: 'הגדרות',
            icon: Iconsax.setting_2,
            selected: _showSettings,
            onTap: () => setState(() => _showSettings = true),
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final p = context.palette;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: AnimatedContainer(
          duration: context.motion(240),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? DesignTokens.lavender : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? const Color(0xFF382844) : p.muted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: AppText.button.copyWith(
                      color: selected ? const Color(0xFF382844) : p.ink,
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

  Widget _header(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _switcher(context),
      const SizedBox(height: 10),
      _planButton(context),
    ],
  );

  Widget _planButton(BuildContext context) {
    final p = context.palette;
    void openPlans() => unawaited(showBillingPlans(context));
    return Semantics(
      button: true,
      container: true,
      label: 'המסלול והמנוי',
      hint: 'צפייה במסלול ועדכון פרטי תשלום',
      onTap: openPlans,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('profile-plan-cta'),
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(18),
          onTap: openPlans,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  DesignTokens.lavender.withValues(alpha: .22),
                  p.surface.withValues(alpha: .48),
                ],
              ),
              border: Border.all(
                color: DesignTokens.lavender.withValues(alpha: .4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: DesignTokens.lavender,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Iconsax.crown,
                    size: 19,
                    color: Color(0xFF382844),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'המסלול והמנוי',
                        style: AppText.button.copyWith(color: p.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'צפייה במסלול ועדכון פרטי תשלום',
                        style: AppText.secondary.copyWith(color: p.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Iconsax.arrow_left_2, size: 18, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final header = _header(context);
    return AnimatedSwitcher(
      duration: context.motion(280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showSettings
          ? AccountPage(key: const ValueKey('settings'), header: header)
          : EditorPage(
              key: const ValueKey('profile'),
              instance: '13.1',
              title: 'פרופיל',
              header: header,
              showTitle: false,
            ),
    );
  }
}
