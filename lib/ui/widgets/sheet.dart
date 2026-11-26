import 'package:flutter/material.dart';

import '../theme.dart';

/// Standard bottom sheet: rounded top, drag handle, safe area, lifts above the
/// keyboard, scrolls when tall. Returns what the sheet pops with.
///
/// [frame] wraps the scroll view (inside the sheet route), e.g. an
/// unsaved-changes guard whose drag blocker must not out-rank the scrolling.
/// [scroll] false: the builder scrolls by itself (a sheet with a pinned
/// [PinnedSheetFooter] action).
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
  Widget Function(BuildContext context, Widget child)? frame,
  bool scroll = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    builder: (context) {
      final body = scroll
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                0,
                Space.page,
                Space.xl,
              ),
              child: builder(context),
            )
          : builder(context);
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: frame == null ? body : frame(context, body),
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

/// A sheet body whose [content] scrolls while [action] (the primary button)
/// stays pinned at the bottom, above the home indicator. Open it with
/// `showAppSheet(..., scroll: false)`.
class PinnedSheetFooter extends StatelessWidget {
  const PinnedSheetFooter({
    super.key,
    required this.content,
    required this.action,
  });

  final Widget content;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.page,
              0,
              Space.page,
              Space.m,
            ),
            child: content,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: context.palette.line)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              Space.page,
              Space.m,
              Space.page,
              keyboard || bottom < Space.l ? Space.l : bottom,
            ),
            child: action,
          ),
        ),
      ],
    );
  }
}
