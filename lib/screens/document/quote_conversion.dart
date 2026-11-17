// C3 "הפוך לחשבונית" of an accepted quote — ONE path for the quote screen (D)
// and the home "לטיפול" card (walkthrough 2026-11-17 #3: the card sent no
// quote id and opened an empty Composer at ₪0).
//
// * "ישלם אחר כך": POST /quotes/:id/convert → the 305 (פטור: 300) draft,
//   opened prefilled in the Composer.
// * "שילם עכשיו": the Composer (320 / receipt) prefilled from the quote; the
//   quote converts when "הפק" is pressed.

import 'package:flutter/widgets.dart';

import '../../api/actions_api.dart' show quoteToInvoice;
import '../../api/models/models.dart';
import '../../router.dart';
import '../../state/business_context.dart';
import '../compose/compose_memory.dart' show fetchVatRate;
import '../compose/sheets/quote_paid_choice.dart';

/// Asks pay-later / paid-now for [quote] and opens the Composer.
/// [guard] wraps the server conversion (D: busy state + error banner);
/// errors propagate without one. [vatRate]: the business VAT (test seam).
Future<void> convertAcceptedQuote(
  BuildContext context,
  Quote quote, {
  Future<void> Function(Future<void> Function() work)? guard,
  Future<int> Function() vatRate = fetchVatRate,
}) async {
  final exempt = businessContext.isVatExempt;
  final choice = await askQuotePaid(context, exempt: exempt);
  if (choice == null || !context.mounted) return;
  if (choice == QuotePaidChoice.paidNow) {
    await openCompose(
      context,
      intent: paidNowIntent(exempt: exempt),
      fromQuoteId: quote.id,
    );
    return;
  }
  String? draftId;
  Future<void> convert() async {
    draftId = await quoteToInvoice(
      quote,
      vatExempt: exempt,
      vatRateBasisPoints: exempt ? 0 : await vatRate(),
    );
  }

  await (guard == null ? convert() : guard(convert));
  if (draftId == null || !context.mounted) return;
  await openCompose(
    context,
    intent: exempt ? 'TYPE:300' : 'TYPE:305',
    draftId: draftId,
    fromQuoteId: quote.id,
  );
}
