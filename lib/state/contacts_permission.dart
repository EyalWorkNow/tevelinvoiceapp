import 'package:flutter/widgets.dart';

/// Contacts access is asked only when the user taps "ייבוא מאנשי קשר" in S2
/// (07·U6): the import action asks the OS itself, so nothing is asked when
/// the app opens. Kept as a no-op so existing callers stay valid until they
/// drop the call.
Future<void> requestContactsPermissionOnEntry(BuildContext context) async {}
