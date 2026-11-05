// One review card of E (SPEC-v2 §6.E). Owner: squad D.
//
// Image (tap → zoom) → 4 fields: ספק · סכום · תאריך · קטגוריה; "עוד" →
// מספר מסמך, מע״מ → duplicate banner → ONE primary: "אשר" (expense.approve)
// or "שמור" (otherwise: saved for the owner / accountant) · text "דלג".
// Missing supplier / amount / date are highlighted and required. The screen
// owns ⋯ "דחה" (it knows the current card).
// [editApproved] (BE-44): the same fields for an approved expense; ONE
// primary "שמור" → PATCH /expenses/:id, no "דלג" (the screen owns ⋯ "מחק").


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/expenses_api.dart';
import '../../api/models/models.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/people_he.dart';
import '../../util/money.dart';
import '../people/sheets/s2_customer.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'expense_capture_screen.dart' show captureSupplierHints;

class ExpenseReviewCard extends StatefulWidget {
  const ExpenseReviewCard({
    super.key,
    required this.row,
    required this.categories,
    required this.approver,
    required this.onDone,
    required this.onSkip,
    required this.onUndoDuplicate,
    this.duplicateOf,
    this.reading = false,
    this.editApproved = false,
    this.loadSource = fetchExpenseSource,
  });

  /// Editing an APPROVED expense (BE-44): "שמור" → PATCH /expenses/:id.
  final bool editApproved;

  final ExpenseRow row;
  final List<ExpenseCategory> categories;

  /// Has expense.approve: "אשר"; otherwise "שמור".
  final bool approver;

  /// The card is finished (approved / saved / same-as-duplicate); [message] is the toast.
  final void Function(String? message) onDone;
  final VoidCallback onSkip;
  final Future<void> Function() onUndoDuplicate;

  /// The original of a DUPLICATE (for its date), when it is in the inbox.
  final ExpenseRow? duplicateOf;

  /// OCR is running for this card ("קורא את הקבלה…").
  final bool reading;
  final Future<Uint8List> Function(String id) loadSource;

  @override
  State<ExpenseReviewCard> createState() => _ExpenseReviewCardState();
}

class _ExpenseReviewCardState extends State<ExpenseReviewCard> {
  late ExpenseDraft _draft = ExpenseDraft.fromRow(widget.row);
  late final _amount = TextEditingController(
      text: widget.row.totalMinor == null ? '' : agorotToKeypadText(widget.row.totalMinor!));
  late final _vat = TextEditingController(
      text: widget.row.vatMinor == null ? '' : agorotToKeypadText(widget.row.vatMinor!));
  late final _docNumber = TextEditingController(text: widget.row.documentNumber ?? '');
  late final Future<Uint8List> _source = widget.loadSource(widget.row.id);
  bool _more = false;
  bool _attempted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final hint = captureSupplierHints[widget.row.id];
    if (hint != null && (_draft.supplierName ?? '').isEmpty) {
      _draft = _draft.copyWith(supplierId: hint.id, supplierName: hint.name, supplierTaxId: hint.taxId);
    }
    if (_draft.categoryId == null && !widget.editApproved) _prefillCategory();
  }

  @override
  void didUpdateWidget(ExpenseReviewCard old) {
    super.didUpdateWidget(old);
    // OCR finished while the card was open: take what it read into empty fields.
    final r = widget.row;
    if (identical(r, old.row)) return;
    setState(() {
      _draft = ExpenseDraft(
        supplierId: _draft.supplierId ?? r.supplierId,
        supplierName: (_draft.supplierName ?? '').isEmpty ? r.supplierName : _draft.supplierName,
        supplierTaxId: _draft.supplierTaxId ?? r.supplierTaxId,
        documentNumber: _draft.documentNumber ?? r.documentNumber,
        documentDate: _draft.documentDate ?? r.expenseDate,
        totalMinor: _draft.totalMinor ?? r.totalMinor,
        vatMinor: _draft.vatMinor ?? r.vatMinor,
        categoryId: _draft.categoryId ?? r.categoryId,
        allocationNumber: r.allocationNumber,
        currency: r.currency,
      );
      if (_amount.text.isEmpty && r.totalMinor != null) _amount.text = agorotToKeypadText(r.totalMinor!);
      if (_vat.text.isEmpty && r.vatMinor != null) _vat.text = agorotToKeypadText(r.vatMinor!);
      if (_docNumber.text.isEmpty && r.documentNumber != null) _docNumber.text = r.documentNumber!;
    });
  }

  Future<void> _prefillCategory() async {
    final id = await lastExpenseCategory(_draft.supplierName);
    if (id == null || !mounted || _draft.categoryId != null) return;
    if (widget.categories.any((c) => c.id == id)) setState(() => _draft = _draft.copyWith(categoryId: id));
  }

  @override
  void dispose() {
    _amount.dispose();
    _vat.dispose();
    _docNumber.dispose();
    super.dispose();
  }

  ExpenseDraft get _current {
    final total = parseAmount(_amount.text);
    final vatText = _vat.text.trim();
    final vat = vatText.isEmpty ? null : parseAmount(vatText);
    final number = _docNumber.text.trim();
    return ExpenseDraft(
      supplierId: _draft.supplierId,
      supplierName: _draft.supplierName,
      supplierTaxId: _draft.supplierTaxId,
      documentNumber: number.isEmpty ? null : number,
      documentDate: _draft.documentDate,
      totalMinor: total == null || total == BigInt.zero ? null : total,
      vatMinor: vat,
      categoryId: _draft.categoryId,
      allocationNumber: _draft.allocationNumber,
      currency: _draft.currency,
    );
  }

  bool get _approves => widget.approver && !widget.editApproved;

  static const Map<String, String> _fieldWords = {
    'supplier': ExpenseHe.supplier,
    'amount': ExpenseHe.amount,
    'date': ExpenseHe.date,
  };

  Future<void> _submit() async {
    if (_busy) return;
    final draft = _current;
    final missing = draft.missing();
    final vat = draft.vatMinor;
    final vatBad = vat != null && draft.totalMinor != null && vat > draft.totalMinor!;
    if (missing.isNotEmpty || vatBad) {
      HapticFeedback.heavyImpact();
      setState(() {
        _attempted = true;
        if (vatBad) _more = true;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(ExpenseHe.missing(
                [for (final m in missing) _fieldWords[m]!, if (vatBad) ExpenseHe.vat].join(', ')))));
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.editApproved) {
        await updateExpense(widget.row.id, draft);
      } else if (widget.approver) {
        await saveAndApproveExpense(widget.row.id, draft);
      } else {
        await saveExpenseDraft(widget.row.id, draft);
      }
      if (draft.categoryId != null) await rememberExpenseCategory(draft.supplierName, draft.categoryId!);
      HapticFeedback.mediumImpact();
      widget.onDone(widget.editApproved
          ? ExpenseHe.updated
          : widget.approver
              ? ExpenseHe.approved
              : ExpenseHe.saved);
    } on Object catch (e) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  Future<void> _chooseSupplier() async {
    final s = await showSupplierSheet(context);
    if (s == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(supplierId: s.id, supplierName: s.name, supplierTaxId: s.taxId));
    if (_draft.categoryId == null) _prefillCategory();
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_draft.documentDate ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(now.year - 7),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => _draft = _draft.copyWith(
        documentDate: '${picked.year}-${two(picked.month)}-${two(picked.day)}'));
  }

  void _zoom(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
            PositionedDirectional(
              top: Space.xl,
              start: Space.s,
              child: IconButton(
                tooltip: CommonHe.close,
                icon: const Icon(Iconsax.close_circle),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final processing = row.isProcessing || widget.reading;
    final error = row.status == 'ERROR';
    final duplicate = row.isDuplicate;
    final showForm = !processing && !error && !duplicate;
    // Each card is its own "screen" for the one-primary rule: during the
    // swap to the next card both are briefly in the tree.
    return PrimaryScope(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.page, Space.s, Space.page, Space.l),
            children: [
              _image(context),
              const SizedBox(height: Space.l),
              if (processing) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(row.status == 'SCANNING' ? ExpenseHe.scanning : ExpenseHe.reading,
                      textAlign: TextAlign.center, style: AppText.headline),
                ),
                const SkeletonList(rows: 4),
              ],
              if (error)
                AppCard(
                  color: context.palette.tint(context.palette.danger),
                  child: Text(ExpenseHe.errorCard, style: AppText.body),
                ),
              if (duplicate) _duplicateBanner(context),
              if (showForm) ..._fields(context),
            ],
          ),
        ),
        if (showForm)
          BottomActionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PrimaryButton(
                  key: const Key('expense-primary'),
                  label: _approves ? ExpenseHe.approve : ExpenseHe.save,
                  loadingText: _busy ? (_approves ? ExpenseHe.approving : PeopleHe.saving) : null,
                  offline: businessContext.offline,
                  onPressed: _submit,
                ),
                if (!widget.editApproved)
                  TextButton(
                    key: const Key('expense-skip'),
                    onPressed: _busy ? null : widget.onSkip,
                    child: const Text(ExpenseHe.skip),
                  ),
              ],
            ),
          )
        else
          SafeArea(
            top: false,
            child: TextButton(
                key: const Key('expense-skip'), onPressed: widget.onSkip, child: const Text(ExpenseHe.skip)),
          ),
      ],
    ));
  }

  Widget _image(BuildContext context) {
    final p = context.palette;
    if (widget.row.isPdf) {
      return Semantics(
        label: ExpenseHe.pdf,
        child: AppCard(child: Icon(Iconsax.document_text, size: 56, color: p.muted)),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _source,
      builder: (context, snap) {
        final bytes = snap.data;
        return Semantics(
          image: true,
          button: bytes != null,
          label: ExpenseHe.image,
          child: GestureDetector(
            onTap: bytes == null ? null : () => _zoom(bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Container(
                height: 180,
                color: p.surface,
                alignment: Alignment.center,
                child: bytes == null
                    ? Icon(Iconsax.receipt_item, size: 48, color: p.muted)
                    : Image.memory(bytes, fit: BoxFit.contain, width: double.infinity, gaplessPlayback: true),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _duplicateBanner(BuildContext context) {
    final p = context.palette;
    final date = widget.duplicateOf?.expenseDate;
    return AppCard(
      key: const Key('expense-duplicate'),
      color: p.tint(p.warn),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(date == null ? ExpenseHe.duplicateUnknown : ExpenseHe.duplicateOf(formatDateHe(date)),
              style: AppText.body),
          const SizedBox(height: Space.s),
          Row(
            children: [
              TextButton(
                key: const Key('expense-dup-yes'),
                onPressed: () => widget.onDone(null),
                child: const Text(ExpenseHe.duplicateYes),
              ),
              TextButton(
                key: const Key('expense-dup-no'),
                onPressed: widget.onUndoDuplicate,
                child: const Text(ExpenseHe.duplicateNo),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _fields(BuildContext context) {
    final p = context.palette;
    final d = _draft;
    String? need(bool missing) => _attempted && missing ? ExpenseHe.required : null;
    final cats = widget.categories;
    return [
      _FieldRow(
        key: const Key('expense-supplier'),
        label: ExpenseHe.supplier,
        value: (d.supplierName ?? '').isEmpty ? ExpenseHe.chooseSupplier : d.supplierName!,
        error: need((d.supplierName ?? '').trim().isEmpty),
        onTap: _chooseSupplier,
      ),
      const SizedBox(height: Space.m),
      TextField(
        key: const Key('expense-amount'),
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        style: AppText.amountRow,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: ExpenseHe.amount,
          prefixText: '₪ ',
          errorText: need(_current.totalMinor == null),
        ),
      ),
      const SizedBox(height: Space.m),
      _FieldRow(
        key: const Key('expense-date'),
        label: ExpenseHe.date,
        value: d.documentDate == null ? ExpenseHe.chooseDate : formatDateHe(d.documentDate),
        error: need(d.documentDate == null),
        onTap: _chooseDate,
      ),
      if (cats.isNotEmpty) ...[
        const SizedBox(height: Space.l),
        Text(ExpenseHe.category, style: AppText.secondary.copyWith(color: p.muted)),
        const SizedBox(height: Space.s),
        ChipRow<String>(
          padding: EdgeInsets.zero,
          options: [for (final c in cats) ChipOption(c.id, c.name)],
          selected: d.categoryId,
          onSelected: (id) => setState(() => _draft = _draft.copyWith(categoryId: id)),
        ),
      ],
      const SizedBox(height: Space.s),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          key: const Key('expense-more'),
          onPressed: () => setState(() => _more = !_more),
          child: Text(ExpenseHe.more),
        ),
      ),
      if (_more) ...[
        TextField(
          key: const Key('expense-docnumber'),
          controller: _docNumber,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: ExpenseHe.docNumber),
        ),
        const SizedBox(height: Space.m),
        TextField(
          key: const Key('expense-vat'),
          controller: _vat,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(labelText: ExpenseHe.vat, prefixText: '₪ '),
        ),
      ],
    ];
  }
}

/// A tappable value row with a label (supplier / date): looks like a field.
class _FieldRow extends StatelessWidget {
  const _FieldRow({super.key, required this.label, required this.value, required this.onTap, this.error});

  final String label;
  final String value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value${error == null ? '' : ', $error'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: error,
            suffixIcon: const Icon(Iconsax.arrow_left_2),
          ),
          child: Text(value, style: AppText.body),
        ),
      ),
    );
  }
}
