import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cache.dart';

const _contactsChannel = MethodChannel('tevel/contacts_permission');
bool _requestInFlight = false;

/// Ask once after sign-in, with context about why the app needs Contacts.
/// The app still imports only a contact the user explicitly selects.
Future<void> requestContactsPermissionOnEntry(BuildContext context) async {
  if (_requestInFlight || !context.mounted) return;
  _requestInFlight = true;
  try {
    const key = 'contacts_permission_prompted';
    final alreadyPrompted = await AppCache.read(key);
    if (alreadyPrompted == true || !context.mounted) return;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.contacts_outlined),
        title: const Text('חיבור לאנשי הקשר'),
        content: const Text(
          'אפשר להשתמש באנשי הקשר כדי לבחור לקוח במהירות. אנשי הקשר לא יועתקו לחשבון; רק פרטים שתבחר/י לייבא ייכנסו ללקוח.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('לא עכשיו'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('המשך'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    await AppCache.write(key, true);
    if (accepted != true) return;

    final granted = await _contactsChannel.invokeMethod<bool>('requestAccess');
    if (!context.mounted || granted == true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('אפשר לאפשר גישה לאנשי קשר בהגדרות המכשיר.'),
      ),
    );
  } on PlatformException {
    // Manual customer entry remains available if the OS permission flow fails.
  } on MissingPluginException {
    // Non-iOS builds do not register the native contacts bridge.
  } on Object {
    // Permission is optional; keep the app usable if local prompt state fails.
  } finally {
    _requestInFlight = false;
  }
}
