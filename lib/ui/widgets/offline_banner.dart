import 'package:flutter/material.dart';

import '../../util/labels/common_he.dart';
import '../theme.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Thin banner shown while working from cache without a server connection
/// (spec V2 §6: "אין חיבור – מציג נתונים אחרונים").
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.visible, this.onRetry});

  final bool visible;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedSize(
      duration: context.motion(200),
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Material(
                color: p.tint(p.warn),
                child: InkWell(
                  onTap: onRetry,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: Space.s),
                    child: Row(
                      children: [
                        Icon(Iconsax.cloud_cross, size: 18, color: p.warn),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Text(
                            CommonHe.offlineBanner,
                            style: AppText.secondary.copyWith(color: p.warn),
                          ),
                        ),
                        if (onRetry != null)
                          Text(
                            CommonHe.retry,
                            style: AppText.secondary.copyWith(
                              color: p.warn,
                              fontWeight: FontWeight.w700,
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
}
