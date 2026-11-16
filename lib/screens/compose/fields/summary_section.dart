// "מה יופק" card (SPEC-v2 §6.C step 3): description (tap = edit) · payment
// method (paid kinds only; default = last used) · cheque details · donor ID
// (405) · "פרטים נוספים" (S3). No type name here (F1).
// C3 "פיצול תשלום" (opt-in): 2–10 lines of method + amount, "נותר: ₪X".

import 'package:flutter/material.dart';

import '../../../ui/ds.dart';
import '../../../util/composer_config.dart';
import '../../../util/labels/labels.dart';
import '../../../api/issue_api.dart' show todayIso;
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
    this.allowSplit = true,
  });

  final ComposeState state;
  final VoidCallback onMoreDetails;

  /// "פיצול תשלום" is offered (not to a cashier: one payment per issue, B1).
  final bool allowSplit;

  @override
  State<SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends State<SummarySection> {
  late bool _showMoreMethods = moreMethods.contains(widget.state.method);
  final _checkKey = GlobalKey();

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
        if (c.paid && s.split) _splitSection(),
        if (c.paid && !s.split)
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
                    if (m == 'CHECK') _revealCheckFields();
                  },
                ),
                if (s.method == 'CHECK') _checkFields(),
                if (widget.allowSplit)
                  TextButton.icon(
                    key: const Key('compose-split'),
                    onPressed: s.totalMinor > BigInt.zero ? s.startSplit : null,
                    icon: const Icon(Iconsax.money_send, size: 18),
                    label: const Text(ComposeHe.splitPayment),
                  ),
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

  Widget _splitSection() {
    final left = s.splitRemainingMinor;
    final p = context.palette;
    final lastIsCheck = s.splits.isNotEmpty && s.splits.last.method == 'CHECK';
    return Padding(
      key: const Key('compose-splits'),
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < s.splits.length; i++)
            KeyedSubtree(key: ObjectKey(s.splits[i]), child: _splitLine(i)),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: const Key('split-add'),
                onPressed: s.splits.length < maxSplitLines
                    ? s.addSplitLine
                    : null,
                child: Text(
                  lastIsCheck ? PaymentHe.addCheck : PaymentHe.addPayment,
                ),
              ),
              TextButton(
                key: const Key('split-off'),
                onPressed: s.endSplit,
                child: const Text(ComposeHe.splitOff),
              ),
            ],
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              left == BigInt.zero
                  ? ComposeHe.splitFull
                  : left > BigInt.zero
                  ? ComposeHe.splitRemaining(left)
                  : ComposeHe.splitOver(-left),
              key: const Key('split-remaining'),
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: left == BigInt.zero ? p.ink : p.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitLine(int i) {
    final l = s.splits[i];
    final methods = [...mainMethods, ...moreMethods];
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.card,
        vertical: Space.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChipRow<String>(
            key: Key('split-methods-$i'),
            padding: EdgeInsets.zero,
            options: [
              for (final m in methods)
                ChipOption(m, paymentMethodLabels[m] ?? m),
            ],
            selected: l.method,
            onSelected: (m) {
              l.method = m;
              s.changed();
            },
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: Key('split-amount-$i'),
                  initialValue: l.amountText,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    labelText: ComposeHe.splitAmount,
                    prefixText: '₪ ',
                  ),
                  onChanged: (v) {
                    l.amountText = v;
                    s.changed();
                  },
                ),
              ),
              IconButton(
                key: Key('split-remove-$i'),
                tooltip: ComposeHe.splitRemove,
                onPressed: () => s.removeSplitLine(i),
                icon: const Icon(Iconsax.trash, size: 20),
              ),
            ],
          ),
          if (l.method == 'CHECK') ...[
            for (final (key, label, value, set) in [
              (
                'bank',
                ComposeHe.checkBank,
                l.bankNumber,
                (String v) => l.bankNumber = v,
              ),
              (
                'branch',
                ComposeHe.checkBranch,
                l.branchNumber,
                (String v) => l.branchNumber = v,
              ),
              (
                'account',
                ComposeHe.checkAccount,
                l.accountNumber,
                (String v) => l.accountNumber = v,
              ),
              (
                'number',
                ComposeHe.checkNumber,
                l.checkNumber,
                (String v) => l.checkNumber = v,
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: TextFormField(
                  key: Key('split-check-$key-$i'),
                  initialValue: value,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: label),
                  onChanged: (v) {
                    set(v);
                    s.changed();
                  },
                ),
              ),
            TextButton.icon(
              key: Key('split-check-date-$i'),
              onPressed: () => _pickCheckDate(l),
              icon: const Icon(Iconsax.calendar_1, size: 18),
              label: Text('${ComposeHe.checkDate}: ${formatDateHe(l.date)}'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickCheckDate(SplitLine l) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(l.date) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2), // a post-dated cheque (§9.1)
    );
    if (picked == null) return;
    l.date = todayIso(picked);
    s.changed();
  }

  /// owner/040: the four cheque fields opened under the keypad. The
  /// Composer puts the keypad away; this scrolls them into view.
  void _revealCheckFields() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _checkKey.currentContext;
      if (c == null || !c.mounted) return;
      Scrollable.ensureVisible(
        c,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Widget _checkFields() => Column(
    key: _checkKey,
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
