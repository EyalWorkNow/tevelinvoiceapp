import 'package:flutter/material.dart';

import '../../ui/ds.dart';
import '../../util/labels/people_he.dart';

/// "לצאת בלי לשמור?" (06·9): true when the user chose to leave.
Future<bool> confirmDiscardChanges(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('discard-confirm'),
        title: const Text(PeopleHe.discardTitle),
        content: const Text(PeopleHe.discardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(PeopleHe.discardStay),
          ),
          TextButton(
            key: const Key('discard-leave'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: context.palette.danger,
            ),
            child: const Text(PeopleHe.discardLeave),
          ),
        ],
      ),
    ) ??
    false;
