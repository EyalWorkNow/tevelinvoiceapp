import '../../util/labels/customer_crm_he.dart';
import '../../util/labels/common_he.dart';
import 'package:flutter/material.dart';

import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';

class CustomerCrmSyncStatus extends StatelessWidget {
  const CustomerCrmSyncStatus({super.key, required this.store});
  final CustomerCrmStore store;

  Future<void> _resolve(BuildContext context) async {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('המידע עודכן במכשיר אחר'),
        content: Text(
          'יש ${store.pendingCount} שינויים שמורים במכשיר וממתינים לסנכרון.\n\nגרסת השרת תשאיר את נתוני השרת ותוותר על השינויים האלה. גרסת המכשיר תחליף בשרת את תיקי הלקוחות ששינית כאן. נשמר גם עותק מקומי לשחזור.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(CustomerCrmHe.useServerVersion),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(CustomerCrmHe.useDeviceVersion),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      await store.resolveConflict(keepDeviceVersion: choice);
    } on Object catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!store.remoteActive) return const SizedBox.shrink();
    final problem = store.syncError != null;
    final text = store.syncing
        ? 'מסנכרן עם השרת…'
        : store.hasConflict
        ? 'השינויים שלך שמורים. נדרשת בחירת גרסה.'
        : problem
        ? 'אין כרגע סנכרון. ${store.pendingCount} שינויים שמורים במכשיר.'
        : store.pendingCount > 0
        ? '${store.pendingCount} שינויים ממתינים לסנכרון'
        : 'נשמר בשרת';
    return Row(
      children: [
        if (store.syncing)
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            problem ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
            size: 17,
            color: problem ? context.palette.warn : context.palette.muted,
          ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppText.secondary.copyWith(color: context.palette.muted),
          ),
        ),
        if (!store.syncing && store.hasConflict)
          TextButton(
            onPressed: () => _resolve(context),
            child: const Text(CustomerCrmHe.chooseVersion),
          ),
      ],
    );
  }
}
