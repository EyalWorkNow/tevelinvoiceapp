import 'package:flutter/widgets.dart';

/// Late-navigation guard (owner sweep 2026-11-16): true while [context]'s
/// screen is still mounted and on top. A request that ends after the user
/// left — or while the back transition is still running, when the widget is
/// still mounted — must not open a share sheet or WhatsApp, push a route or
/// start an upload.
bool stillHere(BuildContext context) =>
    context.mounted && ModalRoute.of(context)?.isCurrent == true;
