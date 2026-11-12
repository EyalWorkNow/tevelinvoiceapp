import 'package:flutter/widgets.dart';

import '../theme.dart';

/// Bottom padding for a scrollable inside an AppShell tab (1.6).
///
/// AppShell reports the floating navigation (+ the home indicator) as
/// `MediaQuery.padding.bottom`; this adds the breathing room so the last row
/// of every tab list scrolls clear of the bar. Outside the shell it is the
/// plain safe-area inset + the same gap.
double shellListBottom(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + Space.xl;
