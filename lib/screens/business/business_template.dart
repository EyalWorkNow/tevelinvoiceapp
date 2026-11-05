// The one B template (SPEC-v2 §6.B): a titled page of rows (+ an optional
// single action at the bottom). The business list, צוות, החשבון שלי and
// רשות המסים וחתימה are all instances of it. Owner: squad E.

import 'package:flutter/material.dart';

import '../../state/session.dart';
import '../../ui/ds.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class BusinessPage extends StatelessWidget {
  const BusinessPage({
    super.key,
    required this.title,
    required this.children,
    this.bottom,
    this.showAppBar = true,
    this.header,
    this.onRefresh,
  });

  final String title;
  final List<Widget> children;

  /// Usually a `BottomActionArea(PrimaryButton)`; at most one (F2).
  final Widget? bottom;
  final bool showAppBar;

  /// Under the large title (e.g. the business name on the tab).
  final Widget? header;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: EdgeInsets.fromLTRB(
        Space.page,
        showAppBar ? Space.s : Space.xl,
        Space.page,
        showAppBar ? Space.xl : 110,
      ),
      children: [
        if (!showAppBar) Semantics(header: true, child: Text(title, style: AppText.displayTitle)),
        ?header,
        const SizedBox(height: Space.s),
        ...children,
      ],
    );
    return Scaffold(
      appBar: (showAppBar && !context.isDark) ? AppBar(title: Text(title)) : null,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            if (showAppBar && context.isDark)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.page, Space.m, Space.page, Space.s),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppText.displayTitle,
                      ),
                    ),
                    const DesignBackButton(),
                  ],
                ),
              ),
            OfflineBanner(visible: session.offline),
            Expanded(
              child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottom,
    );
  }
}

/// One row: icon · label (· value) · chevron. ≥ 64pt. Destructive = red, no chevron.
class BusinessRow extends StatelessWidget {
  const BusinessRow({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.onTap,
    this.trailing,
    this.destructive = false,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = destructive ? p.danger : p.ink;
    return Semantics(
      button: onTap != null,
      label: value == null ? label : '$label, $value',
      excludeSemantics: trailing == null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.button),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Hit.row),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: destructive ? p.danger : p.muted),
                  const SizedBox(width: Space.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppText.body.copyWith(color: color)),
                      if (value != null) Text(value!, style: AppText.secondary.copyWith(color: p.muted)),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (onTap != null && !destructive)
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Iconsax.arrow_left_2
                        : Iconsax.arrow_right_3,
                    color: p.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin divider between row groups.
class RowGroupGap extends StatelessWidget {
  const RowGroupGap({super.key});

  @override
  Widget build(BuildContext context) => Divider(height: Space.xl, color: context.palette.line);
}
