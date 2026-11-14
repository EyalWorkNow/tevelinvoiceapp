import 'package:flutter/material.dart';

import '../theme.dart';

/// Standard bottom sheet: rounded top, drag handle, safe area, lifts above the
/// keyboard, scrolls when tall. Returns what the sheet pops with.
///
/// [frame] wraps the scroll view (inside the sheet route), e.g. an
/// unsaved-changes guard whose drag blocker must not out-rank the scrolling.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  Widget Function(BuildContext context, Widget child)? frame,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (context) {
      final scroll = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.xl),
        child: builder(context),
      );
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: frame == null ? scroll : frame(context, scroll),
      );
    },
  );
}

/// Bold title line at the top of a sheet.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, this.subtitle});

  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppText.title),
          if (subtitle != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              subtitle!,
              style: AppText.body.copyWith(color: context.palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}
