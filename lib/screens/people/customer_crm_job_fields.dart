import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../state/customer_crm_job_budget.dart';
import '../../state/customer_crm_store.dart';
import '../../ui/ds.dart';
import '../../util/labels/customer_crm_he.dart';
import '../../util/money.dart';

const crmRepeatLabels = {
  0: CustomerCrmHe.repeatNone,
  7: CustomerCrmHe.repeatWeek,
  14: CustomerCrmHe.repeatTwoWeeks,
  30: CustomerCrmHe.repeatMonth,
  90: CustomerCrmHe.repeatQuarter,
};

/// Controllers live for the complete editor route, including its exit transition.
class CustomerCrmJobDraft {
  CustomerCrmJobDraft(CustomerCrmJob? original, {required bool repeat})
    : _originalItems = repeat ? const [] : original?.checklist ?? const [],
      price = TextEditingController(text: _amount(original?.budget.priceMinor)),
      cost = TextEditingController(
        text: repeat ? '' : _amount(original?.budget.costMinor),
      ),
      minutes = TextEditingController(
        text: repeat ? '' : original?.budget.workMinutes?.toString() ?? '',
      ),
      paid = TextEditingController(
        text: repeat ? '' : _amount(original?.budget.paidMinor),
      ),
      tasks = TextEditingController(
        text: original?.checklist.map((item) => item.text).join('\n') ?? '',
      ),
      paymentDueAt = repeat ? null : original?.budget.paymentDueAt,
      repeatEveryDays = original?.repeatEveryDays ?? 0;

  final TextEditingController price, cost, minutes, paid, tasks;
  final List<CustomerCrmChecklistItem> _originalItems;
  DateTime? paymentDueAt;
  int repeatEveryDays;

  static String _amount(int? value) => value == null
      ? ''
      : value == 0
      ? '0'
      : agorotToKeypadText(BigInt.from(value));
  static int? _minor(String value) =>
      value.trim().isEmpty ? null : parseAmount(value)?.toInt();
  CustomerCrmJobBudget get budget => CustomerCrmJobBudget(
    priceMinor: _minor(price.text),
    costMinor: _minor(cost.text),
    workMinutes: int.tryParse(minutes.text.trim()),
    paidMinor: _minor(paid.text) ?? 0,
    paymentDueAt: paymentDueAt,
  );

  List<CustomerCrmChecklistItem> get checklist {
    final unused = _originalItems.toList();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return [
      for (final (index, text) in taskLines.indexed)
        () {
          final match = unused.indexWhere((item) => item.text == text);
          if (match >= 0) return unused.removeAt(match);
          return CustomerCrmChecklistItem(id: '$stamp-$index', text: text);
        }(),
    ];
  }

  List<String> get taskLines => tasks.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void dispose() {
    for (final controller in [price, cost, minutes, paid, tasks]) {
      controller.dispose();
    }
  }
}

class CustomerCrmJobFields extends StatefulWidget {
  const CustomerCrmJobFields({
    super.key,
    required this.draft,
    required this.showMoney,
  });
  final CustomerCrmJobDraft draft;
  final bool showMoney;
  @override
  State<CustomerCrmJobFields> createState() => _CustomerCrmJobFieldsState();
}

class _CustomerCrmJobFieldsState extends State<CustomerCrmJobFields> {
  CustomerCrmJobDraft get draft => widget.draft;

  String? _validateAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final amount = parseAmount(value);
    return amount == null || amount > BigInt.from(99999999999)
        ? CustomerCrmHe.invalidAmount
        : null;
  }

  Future<void> _choosePaymentDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: draft.paymentDueAt ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (mounted && date != null) setState(() => draft.paymentDueAt = date);
  }

  Widget _moneyField(
    String key,
    String label,
    TextEditingController controller, {
    bool received = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: Space.m),
    child: TextFormField(
      key: Key(key),
      controller: controller,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: null,
        helperMaxLines: 2,
      ),
      validator: (value) {
        final error = _validateAmount(value);
        if (error != null || !received) return error;
        final paid = parseAmount(value ?? '') ?? BigInt.zero;
        final price = parseAmount(draft.price.text) ?? BigInt.zero;
        return paid > price ? CustomerCrmHe.invalidPaid : null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: Space.m),
      DropdownButtonFormField<int>(
        key: const Key('crm-repeat-days'),
        initialValue: draft.repeatEveryDays,
        isExpanded: true,
        decoration: const InputDecoration(labelText: CustomerCrmHe.repeat),
        items: [
          for (final value in crmRepeatLabels.entries)
            DropdownMenuItem(value: value.key, child: Text(value.value)),
        ],
        onChanged: (value) =>
            setState(() => draft.repeatEveryDays = value ?? 0),
      ),
      const SizedBox(height: Space.s),
      const Text(CustomerCrmHe.repeatHint, style: AppText.secondary),
      const SizedBox(height: Space.m),
      TextFormField(
        key: const Key('crm-work-checklist'),
        controller: draft.tasks,
        minLines: 2,
        maxLines: 6,
        maxLength: 2419,
        decoration: const InputDecoration(
          labelText: CustomerCrmHe.checklist,
          hintText: CustomerCrmHe.checklistHint,
          counterText: '',
          alignLabelWithHint: true,
        ),
        validator: (_) =>
            draft.taskLines.length > 20 ||
                draft.taskLines.any((line) => line.length > 120)
            ? CustomerCrmHe.invalidChecklist
            : null,
      ),
      if (widget.showMoney) ...[
        const SizedBox(height: Space.m),
        const Text(CustomerCrmHe.finances, style: AppText.headline),
        const SizedBox(height: Space.s),
        const Text(
          'מעקב ידני. מחיר ועלות על אותו בסיס מע״מ.',
          style: AppText.secondary,
        ),
        _moneyField('crm-work-price', CustomerCrmHe.price, draft.price),
        _moneyField('crm-work-cost', CustomerCrmHe.cost, draft.cost),
        const SizedBox(height: Space.m),
        TextFormField(
          key: const Key('crm-work-minutes'),
          controller: draft.minutes,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: CustomerCrmHe.minutes,
            helperText: null,
            helperMaxLines: 2,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final minutes = int.tryParse(value.trim());
            return minutes == null || minutes <= 0 || minutes > 60000
                ? CustomerCrmHe.invalidMinutes
                : null;
          },
        ),
        _moneyField(
          'crm-work-paid',
          CustomerCrmHe.paid,
          draft.paid,
          received: true,
        ),
        const SizedBox(height: Space.s),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('crm-payment-date'),
              onPressed: _choosePaymentDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(
                draft.paymentDueAt == null
                    ? CustomerCrmHe.paymentDate
                    : '${CustomerCrmHe.paymentDate}: ${DateFormat('dd.MM.yy').format(draft.paymentDueAt!)}',
              ),
            ),
            if (draft.paymentDueAt != null)
              IconButton(
                tooltip: CustomerCrmHe.clearPaymentDate,
                onPressed: () => setState(() => draft.paymentDueAt = null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ],
    ],
  );
}
