// Feature 1 · "הלקוחות שלי": one thin row at the top of the accountant home
// (R embedded): "12 לקוחות · 3 דורשים טיפול". A tap opens S14 (the clients
// list). Loading → the count only; an error / an old server → the count
// without "דורשים טיפול"; all clear → "· הכול מסודר".

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../state/accountant_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/labels.dart';
import '../business/sheets/s14_switch.dart';

class ClientsSummaryRow extends StatefulWidget {
  const ClientsSummaryRow({super.key});

  @override
  State<ClientsSummaryRow> createState() => _ClientsSummaryRowState();
}

class _ClientsSummaryRowState extends State<ClientsSummaryRow> {
  @override
  void initState() {
    super.initState();
    unawaited(accountantStore.load());
  }

  Future<void> _open() async {
    await showSwitchBusinessSheet(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: accountantStore,
    builder: (context, _) {
      final p = context.palette;
      final store = accountantStore;
      final o = store.supported == true ? store.overview : null;
      final count = o?.clients.length ?? store.sessionClientCount;
      final attention = (o == null || store.error != null)
          ? null
          : o.needingAttention;
      final text = clientsSummaryText(count, attention);
      return Semantics(
        button: true,
        label: '${AccountantHe.myClients}, $text',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('clients-summary-row'),
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Row(
              children: [
                Icon(Iconsax.briefcase, size: 18, color: p.muted),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    text,
                    key: const Key('clients-summary-text'),
                    style: AppText.secondary.copyWith(
                      color: (attention ?? 0) > 0 ? p.ink : p.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Iconsax.arrow_left_2, size: 16, color: p.muted),
              ],
            ),
          ),
        ),
      );
    },
  );
}
