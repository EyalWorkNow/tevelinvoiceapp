// C1 · "רשום חוב": X owes me ₪Y for Z, with NO document (ספר חובות).
// An internal note on the server (debt_entries, 0101): never a tax document,
// never revenue or VAT. The sheet says so in its subtitle.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart';
import '../../api/debts_api.dart';
import '../../api/models/models.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/debts_he.dart';
import '../../util/money.dart';
import '../people/sheets/s2_customer.dart';

/// S2 for "מי חייב" (tests replace it).
Future<Customer?> Function(BuildContext context) pickDebtCustomer = (c) =>
    showCustomerSheet(c, openExistingCard: false);

/// Opens the sheet. [customer]: fixed (from the customer card); [edit]: an
/// open entry to change. Returns the saved entry, or null.
Future<DebtEntry?> showDebtEntrySheet(
  BuildContext context, {
  Customer? customer,
  DebtEntry? edit,
  String? customerName,
}) => showAppSheet<DebtEntry>(
  context,
  builder: (_) => DebtEntrySheet(
    customer: customer,
    edit: edit,
    customerName: customerName,
  ),
);

class DebtEntrySheet extends StatefulWidget {
  const DebtEntrySheet({
    super.key,
    this.customer,
    this.edit,
    this.customerName,
  });

  final Customer? customer;
  final DebtEntry? edit;
  final String? customerName;

  @override
  State<DebtEntrySheet> createState() => _DebtEntrySheetState();
}

class _DebtEntrySheetState extends State<DebtEntrySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.edit == null
        ? ''
        : agorotToKeypadText(widget.edit!.amountMinor),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.edit?.note ?? '',
  );
  late Customer? _customer = widget.customer;
  late String _date = widget.edit?.debtDate ?? isoDay(DateTime.now());
  String? _error;
  bool _saving = false;

  /// One key per sheet: a retried save never writes the entry twice.
  final String _key = ApiClient.newIdempotencyKey();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _customerLabel =>
      _customer?.name ?? widget.customerName ?? DebtsHe.pickCustomer;

  Future<void> _pickCustomer() async {
    if (widget.edit != null || widget.customer != null) return;
    final c = await pickDebtCustomer(context);
    if (c != null && mounted) setState(() => _customer = c);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = isoDay(picked));
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text) ?? BigInt.zero;
    final note = _note.text.trim();
    final error = widget.edit == null && _customer == null
        ? DebtsHe.missingCustomer
        : amount <= BigInt.zero
        ? DebtsHe.missingAmount
        : note.isEmpty
        ? DebtsHe.missingNote
        : null;
    if (error != null) return setState(() => _error = error);
    setState(() {
      _error = null;
      _saving = true;
    });
    HapticFeedback.selectionClick();
    try {
      final edit = widget.edit;
      final saved = edit == null
          ? await createDebtEntry(
              customerId: _customer!.id,
              amountMinor: amount,
              note: note,
              debtDate: _date,
              idempotencyKey: _key,
            )
          : await updateDebtEntry(
              edit.id,
              amountMinor: amount,
              note: note,
              debtDate: _date,
            );
      if (mounted) Navigator.of(context).pop(saved);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnack(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fixed = widget.edit != null || widget.customer != null;
    return Column(
      key: const Key('debt-entry-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          widget.edit == null ? DebtsHe.addTitle : DebtsHe.editTitle,
          subtitle: DebtsHe.addSubtitle,
        ),
        ListTile(
          key: const Key('debt-entry-customer'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Iconsax.user),
          title: Text(DebtsHe.customer, style: AppText.secondary),
          subtitle: Text(_customerLabel, style: AppText.body),
          trailing: fixed ? null : const Icon(Iconsax.arrow_left_2, size: 18),
          onTap: fixed ? null : _pickCustomer,
        ),
        TextField(
          key: const Key('debt-entry-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            labelText: DebtsHe.amount,
            prefixText: '₪ ',
          ),
        ),
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('debt-entry-note'),
          controller: _note,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: DebtsHe.note,
            hintText: DebtsHe.noteHint,
          ),
        ),
        ListTile(
          key: const Key('debt-entry-date'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Iconsax.calendar_1),
          title: Text(DebtsHe.date, style: AppText.secondary),
          subtitle: Text(formatDateHe(_date), style: AppText.body),
          onTap: _pickDate,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text(
              _error!,
              key: const Key('debt-entry-error'),
              style: AppText.secondary.copyWith(color: p.danger),
            ),
          ),
        const SizedBox(height: Space.s),
        PrimaryButton(
          key: const Key('debt-entry-save'),
          label: DebtsHe.save,
          loadingText: _saving ? DebtsHe.save : null,
          onPressed: _save,
        ),
      ],
    );
  }
}
