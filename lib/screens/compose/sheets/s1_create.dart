// S1 · ＋ יצירה (SPEC-v2 §6 sheets, §4.4). Owner: squad B.
// Only what home does not have: הצעת מחיר · הוצאה · לקוח · עוד סוגים.
// "עוד סוגים" = a flat list of ≤6 kinds allowed to the business type
// (composer_config.moreKinds; 500 with S2's supplier mode) + "סוגים נוספים – המשך במחשב". Every tile is
// behind its capability (hidden, never disabled – F5); the shell hides the ＋
// when no tile is left (caps.showCreateTab).

import 'package:flutter/material.dart';

import '../../../router.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../util/composer_config.dart';
import '../../../util/intent_resolver.dart';
import '../../../util/labels/labels.dart';
import '../../people/sheets/s2_customer.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

class CreateSheet extends StatefulWidget {
  const CreateSheet({super.key});

  @override
  State<CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<CreateSheet> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final bc = businessContext;
    final caps = bc.caps;
    // §4.4 "אריחי ＋": עובד / עובד+מפיק see הצעה·הוצאה·לקוח only – no "עוד".
    final employee = caps.preset == Preset.employee || caps.preset == Preset.employeeIssuer;
    final kinds = employee
        ? const <DocKind>[]
        : moreKinds(bc.businessType, caps,
            section46: (bc.profile?.section46ApprovalNumber ?? '').isNotEmpty, supplierPicker: true);
    final nav = Navigator.of(context);
    void close(void Function(BuildContext root) then) {
      final root = nav.context;
      nav.pop();
      then(root);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetTitle(ComposeHe.s1Title),
      if (caps.can(Cap.docDraft))
        _tile(const Key('s1-quote'), Iconsax.receipt_edit, ComposeHe.tileQuote,
            () => close((c) => openCompose(c, intent: intentQuote))),
      if (caps.can(Cap.expenseCapture))
        _tile(const Key('s1-expense'), Iconsax.receipt_item, ComposeHe.tileExpense,
            () => close(openExpenseCapture)),
      if (caps.can(Cap.docDraft))
        _tile(const Key('s1-customer'), Iconsax.user_add, ComposeHe.tileCustomer,
            () => close((c) => showCustomerSheet(c, startOnNew: true))),
      if (kinds.isNotEmpty && !_more)
        _tile(const Key('s1-more'), Iconsax.more, ComposeHe.tileMore,
            () => setState(() => _more = true)),
      if (_more) ...[
        for (final k in kinds)
          _tile(Key('s1-kind-${configFor(k).code}'), Iconsax.document_text, kindLabels[k]!,
              () => close((c) => openCompose(c, intent: typeIntent(k)))),
        if (caps.can(Cap.settingsBusiness))
          _tile(const Key('s1-desktop'), Iconsax.monitor, ComposeHe.moreOnComputer,
              () => close((c) => openBusinessSection(c, BusinessSection.desktop))),
      ],
    ]);
  }

  Widget _tile(Key key, IconData icon, String label, VoidCallback onTap) => ListTile(
        key: key,
        minTileHeight: Hit.row,
        leading: Icon(icon),
        title: Text(label, style: AppText.body),
        onTap: onTap,
      );
}

/// Opened by the ＋ in the tab bar (lib/app_shell.dart).
Future<void> showCreateSheet(BuildContext context) =>
    showAppSheet<void>(context, builder: (_) => const CreateSheet());
