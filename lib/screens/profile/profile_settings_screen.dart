import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

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

  @override
  Widget build(BuildContext context) {
    final switcher = _switcher(context);
    return AnimatedSwitcher(
      duration: context.motion(280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _showSettings
          ? AccountPage(key: const ValueKey('settings'), header: switcher)
          : EditorPage(
              key: const ValueKey('profile'),
              instance: '13.1',
              title: 'פרופיל',
              header: switcher,
            ),
    );
  }
}
