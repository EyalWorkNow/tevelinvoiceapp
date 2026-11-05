import 'package:flutter/cupertino.dart';

import 'theme.dart';

/// Each route paints its own background so transitions never expose the shell.
/// Cupertino supplies coordinated forward/back motion and interactive back swipes.
class AppPageRoute<T> extends CupertinoPageRoute<T> {
  AppPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(builder: (context) => AppBackground(child: builder(context)));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
