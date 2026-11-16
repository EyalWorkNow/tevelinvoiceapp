// C3 · "הפוך לחשבונית" of a quote (QA 2026-11-16, persona 02): the customer
// pays later (305; פטור: 300) or paid now (320 with the payment step, a
// split too; פטור: a receipt). Owner: squad B.

import 'package:flutter/material.dart';

import '../../../state/business_context.dart';
import '../../../ui/ds.dart';
import '../../../util/composer_config.dart';
import '../../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum QuotePaidChoice { later, paidNow }

/// The kind "שילם עכשיו" issues for this business: 320, or a receipt for an
/// exempt business / nonprofit (no tax invoice there).
DocKind paidNowKind({required bool exempt}) =>
    exempt ? DocKind.receipt : DocKind.taxInvoiceReceipt;

/// The Composer intent of [paidNowKind].
String paidNowIntent({required bool exempt}) =>
    'TYPE:${configFor(paidNowKind(exempt: exempt)).code}';

/// "שילם עכשיו" is offered when the member may issue that kind.
bool canPayNow({required bool exempt}) =>
    businessContext.can(configFor(paidNowKind(exempt: exempt)).cap);

class QuotePaidChoiceSheet extends StatelessWidget {
  const QuotePaidChoiceSheet({super.key, required this.exempt});

  final bool exempt;

  @override
  Widget build(BuildContext context) {
    Widget tile(
      QuotePaidChoice v,
      Key key,
      IconData icon,
      String title,
      String hint,
    ) => ListTile(
      key: key,
      minTileHeight: Hit.row,
      leading: Icon(icon),
      title: Text(title, style: AppText.body),
      subtitle: Text(hint, style: AppText.secondary),
      onTap: () => Navigator.of(context).pop(v),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetTitle(ComposeHe.quoteHowPaid),
        tile(
          QuotePaidChoice.later,
          const Key('quote-choice-later'),
          Iconsax.document_text,
          exempt ? ComposeHe.quoteLaterExempt : ComposeHe.quoteLater,
          ComposeHe.quoteLaterHint,
        ),
        tile(
          QuotePaidChoice.paidNow,
          const Key('quote-choice-paid'),
          Iconsax.money_recive,
          exempt ? ComposeHe.quotePaidNowExempt : ComposeHe.quotePaidNow,
          ComposeHe.quotePaidNowHint,
        ),
      ],
    );
  }
}

/// Null = closed. Without the right to issue the paid kind: [later] at once.
Future<QuotePaidChoice?> askQuotePaid(
  BuildContext context, {
  required bool exempt,
}) async {
  if (!canPayNow(exempt: exempt)) return QuotePaidChoice.later;
  return showAppSheet<QuotePaidChoice>(
    context,
    builder: (_) => QuotePaidChoiceSheet(exempt: exempt),
  );
}
