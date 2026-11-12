// The customer at the top of the Composer: name + ✎ (SPEC-v2 §6.C step 1).
// Tap → S2 again.

import 'package:flutter/material.dart';

import '../../../api/models/models.dart';
import '../../../ui/ds.dart';
import '../../../util/labels/compose_he.dart';
import '../../../util/phone.dart';

class CustomerChip extends StatelessWidget {
  const CustomerChip({super.key, required this.customer, required this.onTap});

  final Customer? customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = customer?.name;
    return Semantics(
      button: true, label: name ?? ComposeHe.chooseCustomer,
      hint: name == null ? null : ComposeHe.editCustomer, excludeSemantics: true,
      child: TextButton(
        key: const Key('compose-customer'), onPressed: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(name ?? ComposeHe.chooseCustomer, textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: context.palette.ink)),
          if (customer?.phone case final phone? when phone.isNotEmpty)
            Text(formatPhoneHe(phone), textDirection: TextDirection.ltr,
              style: AppText.body.copyWith(color: context.palette.ink)),
        ]),
      ),
    );
  }
}
