// "מה יופק" card (SPEC-v2 §6.C step 3): description (tap = edit) · payment
// method (paid kinds only; default = last used) · cheque details · donor ID
// (405) · "פרטים נוספים" (S3). No type name here (F1).

import 'package:flutter/material.dart';

import '../../../ui/ds.dart';
import '../../../util/composer_config.dart';
import '../../../util/labels/labels.dart';
import '../compose_state.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Payment chips (§9.1): the four common ones + "עוד" (DIRECT_DEBIT, OTHER).
const List<String> mainMethods = [
  'CASH',
  'BANK_TRANSFER',
  'CREDIT_CARD',
  'CHECK',
];
const List<String> moreMethods = ['DIRECT_DEBIT', 'OTHER'];

class SummarySection extends StatefulWidget {
  const SummarySection({
    super.key,
    required this.state,
    required this.onMoreDetails,
  });

  final ComposeState state;
  final VoidCallback onMoreDetails;

  @override
  State<SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<SummarySection> {
  late bool _showMoreMethods = moreMethods.contains(widget.state.method);

  ComposeState get s => widget.state;

  Future<void> _editDescription() async {
    final c = TextEditingController(text: s.description);
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(ComposeHe.editDescription),
        content: TextField(
          key: const Key('description-field'),
          controller: c,
          autofocus: true,
          maxLength: 200,
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text(CommonHe.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, c.text),
            child: const Text(CommonHe.save),
          ),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) {
      s
        ..description = text.trim()
        ..descriptionTouched = true
        ..changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = s.config;
    final methods = [...mainMethods, if (_showMoreMethods) ...moreMethods];
    return SummaryCard(
      children: [
        if (!c.receiptOnly)
          SummaryRow(
            key: const Key('compose-description'),
            icon: Iconsax.note_text,
            value: s.mainDescription,
            onTap: _editDescription,
          ),
        if (c.paid)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ChipRow<String>(
                  key: const Key('compose-methods'),
                  padding: EdgeInsets.zero,
                  options: [
                    for (final m in methods)
                      ChipOption(m, paymentMethodLabels[m] ?? m),
                    if (!_showMoreMethods)
                      const ChipOption('_more', ComposeHe.methodMore),
                  ],
                  selected: s.method,
                  onSelected: (m) {
                    if (m == '_more') {
                      setState(() => _showMoreMethods = true);
                      return;
                    }
                    s.method = m;
                    s.changed();
                  },
                ),
                if (s.method == 'CHECK') _checkFields(),
              ],
            ),
          ),
        if (c.counterparty == Counterparty.donor &&
            (s.customer?.taxId ?? '').isEmpty)
          _field(
            const Key('donor-id'),
            ComposeHe.donorId,
            s.donorTaxId,
            (v) => s.donorTaxId = v,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.card,
            vertical: Space.s,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: FilledButton.tonalIcon(
                key: const Key('compose-more-details'),
                onPressed: widget.onMoreDetails,
                icon: const Icon(Iconsax.setting_4, size: 19),
                label: const Text(
                  ComposeHe.moreDetails,
                  textAlign: TextAlign.center,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: AppText.button,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _checkFields() => Column(
    children: [
      _field(
        const Key('check-bank'),
        ComposeHe.checkBank,
        s.bankNumber,
        (v) => s.bankNumber = v,
      ),
      _field(
        const Key('check-branch'),
        ComposeHe.checkBranch,
        s.branchNumber,
        (v) => s.branchNumber = v,
      ),
      _field(
        const Key('check-account'),
        ComposeHe.checkAccount,
        s.accountNumber,
        (v) => s.accountNumber = v,
      ),
      _field(
        const Key('check-number'),
        ComposeHe.checkNumber,
        s.checkNumber,
        (v) => s.checkNumber = v,
      ),
    ],
  );

  Widget _field(
    Key key,
    String label,
    String value,
    void Function(String) set,
  ) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.card,
      vertical: Space.xs,
    ),
    child: TextFormField(
      key: key,
      initialValue: value,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        set(v);
        s.changed();
      },
    ),
  );
}
