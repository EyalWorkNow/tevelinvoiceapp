// R7 · one quiet line under the amount: the document will get an allocation
// number (or the business must connect to the Tax Authority first). Nothing
// below the threshold. The decision is allocationRequired() (pure, tested).

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../api/issue_api.dart' show todayIso;
import '../../../state/business_context.dart';
import '../../../ui/ds.dart';
import '../../../util/allocation_meter.dart';
import '../compose_state.dart';

/// The hint for the Composer's current state.
AllocationHint composeAllocationHint(
  ComposeState s, {
  String? shaamStatus,
  String? issueDate,
}) {
  final type = s.config.serverType;
  if (type == null || !s.showVat) return AllocationHint.none;
  final totals = s.totals;
  return allocationHint(
    required: allocationRequired(
      documentType: type,
      customerVatDealerStatus: s.customer?.vatDealerStatus,
      amountBeforeVatMinor: totals.subtotalMinor,
      vatMinor: totals.taxMinor,
      issueDate: issueDate ?? todayIso(),
    ),
    shaamStatus: shaamStatus,
  );
}

class AllocationHintLine extends StatelessWidget {
  const AllocationHintLine({
    super.key,
    required this.state,
    required this.onConnect,
  });

  final ComposeState state;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final hint = composeAllocationHint(
      state,
      shaamStatus: businessContext.me?.shaam?.status,
    );
    final p = context.palette;
    return switch (hint) {
      AllocationHint.none => const SizedBox.shrink(),
      AllocationHint.willAllocate => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Row(
          key: const Key('compose-allocation-hint'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.verify, size: 16, color: p.muted),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                AllocationHe.willAllocate,
                style: AppText.secondary.copyWith(color: p.muted),
              ),
            ),
          ],
        ),
      ),
      AllocationHint.needsConnection => Padding(
        padding: const EdgeInsets.only(top: Space.xs),
        child: Row(
          key: const Key('compose-allocation-connect'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Iconsax.danger, size: 16, color: p.danger),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                AllocationHe.needsConnection,
                style: AppText.secondary.copyWith(color: p.danger),
              ),
            ),
            TextButton(
              key: const Key('compose-allocation-connect-link'),
              onPressed: onConnect,
              child: const Text(AllocationHe.connect),
            ),
          ],
        ),
      ),
    };
  }
}
