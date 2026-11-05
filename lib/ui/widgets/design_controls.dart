import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../theme.dart';

/// Original vector exports, rasterized at 1x and 3x without redrawing paths.
/// Preserve each export's aspect ratio inside its original icon slot.
class DesignIcon extends StatelessWidget {
  const DesignIcon(this.name, {super.key, this.size = 28});
  final String name;
  final double size;

  static const _dimensions = <String, Size>{
    'request': Size(24.9401, 24.9355),
    'expense': Size(24.94, 24.94),
    'income': Size(24.94, 24.9401),
    'documents': Size(24.9517, 24.9401),
    'search': Size(22, 22),
    'profile': Size(20.8175, 29.3013),
    'manage': Size(29.5625, 29.5625),
    'home': Size(29.5625, 29.5249),
    'more': Size(19.5, 5.5),
    'person-yellow': Size(13.5407, 19.1598),
    'person-green': Size(13.5407, 19.1598),
    'existing-customer': Size(21.0633, 29.8042),
    'new-customer': Size(29.24, 28.4067),
    'walk-in': Size(25.0943, 25.0936),
    'back': Size(28, 28),
  };

  @override
  Widget build(BuildContext context) {
    final dimensions = _dimensions[name] ?? Size(size, size);
    final maxDim = dimensions.width > dimensions.height
        ? dimensions.width
        : dimensions.height;
    final scale = maxDim > 0 ? (size / maxDim).clamp(0.0, 1.0) : 1.0;
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Image.asset(
          'assets/design/$name.png',
          width: dimensions.width * scale,
          height: dimensions.height * scale,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// The 56pt pastel action circle, with its label outside the circle.
class ActionOrb extends StatelessWidget {
  const ActionOrb({
    super.key,
    required this.label,
    this.semanticsLabel,
    required this.icon,
    required this.color,
    required this.onPressed,
  });
  final String label;
  final String? semanticsLabel;
  final Widget icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    label: semanticsLabel ?? label,
    excludeSemantics: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onPressed == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onPressed!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Center(child: icon),
            ),
            const SizedBox(height: 13),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: context.palette.ink),
            ),
          ],
        ),
      ),
    ),
  );
}

class DesignBackButton extends StatelessWidget {
  const DesignBackButton({super.key, this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 57.303,
    child: IconButton(
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
      style: IconButton.styleFrom(backgroundColor: DesignTokens.control),
      icon: Icon(Icons.arrow_back_rounded, color: context.palette.ink),
    ),
  );
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    if (context.isDark) {
      const colors = [
        DesignTokens.yellow,
        DesignTokens.green,
        DesignTokens.coral,
        Color(0xFF2F80ED),
      ];
      final color = colors[name.hashCode.abs() % colors.length];
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: Center(
          child: Icon(
            Iconsax.user,
            size: 18,
            color: color == const Color(0xFF2F80ED)
                ? Colors.white
                : Colors.black87,
          ),
        ),
      );
    }
    final green = name.runes.fold<int>(0, (a, b) => a + b).isOdd;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: green ? DesignTokens.green : DesignTokens.yellow,
      ),
      child: DesignIcon(green ? 'person-green' : 'person-yellow', size: 22),
    );
  }
}
