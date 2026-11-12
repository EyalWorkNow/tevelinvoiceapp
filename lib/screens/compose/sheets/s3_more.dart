// S3 · פרטים נוספים (SPEC-v2 §6 sheets). Owner: squad B.
// Lines (quantity, price; catalog autocomplete + "לשמור כפריט?", BE-15) ·
// total discount · VAT (רגיל / ללא / לפי שורה) · note (BE-07) · due date
// (BE-07, from the customer's terms) · document type (allowed list) ·
// "הלקוח ביקש מספר הקצאה" · quote validity → "סיום".
// Exempt business: no VAT and no allocation rows. Quote: no type row.
// Not here: language (P3).

import 'package:flutter/material.dart';

import '../../../ui/widgets/notch_notice.dart';
import '../../../api/client.dart' show ApiException;
import '../../../api/items_api.dart';
import '../../../api/models/models.dart';
import '../../../state/business_context.dart';
import '../../../state/caps.dart';
import '../../../ui/ds.dart';
import '../../../util/composer_config.dart';
import '../../../util/labels/labels.dart';
import '../../../util/money.dart';
import '../../../util/vat.dart';
import '../compose_state.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// S3 VAT chips.
enum _VatMode { regular, none, perLine }

class MoreDetailsSheet extends StatefulWidget {
  const MoreDetailsSheet({
    super.key,
    required this.state,
    this.kinds = const [],
  });

  final ComposeState state;

  /// Types the user may switch to (empty = no type row).
  final List<DocKind> kinds;

  @override
  State<MoreDetailsSheet> createState() => _MoreDetailsSheetState();
}

class _MoreDetailsSheetState extends State<MoreDetailsSheet> {
  ComposeState get s => widget.state;

  /// The catalog (GET /items, cached by squad D's items_api). Empty on error.
  List<Item> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    List<Item> items;
    try {
      items = await fetchItems();
    } on Object {
      items = const [];
    }
    if (mounted) {
      setState(() => _items = items.where((i) => i.isActive).toList());
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    s.changed();
  }

  _VatMode get _vatMode => s.vatNone
      ? _VatMode.none
      : s.vatPerLine
      ? _VatMode.perLine
      : _VatMode.regular;

  @override
  Widget build(BuildContext context) {
    final c = s.config;
    final allocationRow =
        s.showVat &&
        (c.kind == DocKind.taxInvoice || c.kind == DocKind.taxInvoiceReceipt);
    return PrimaryScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle(ComposeHe.s3Title),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.box_1, color: context.palette.info, size: 20),
              const SizedBox(width: Space.s),
              Text(
                ComposeHe.lines,
                style: AppText.headline,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          // Keyed by the row object, not its index: removing row 1 must not
          // leave row 2's fields showing row 1's values (H1).
          for (var i = 0; i < s.extraLines.length; i++)
            KeyedSubtree(key: ObjectKey(s.extraLines[i]), child: _line(i)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('s3-add-line'),
              onPressed: () => _set(() => s.extraLines.add(ComposeLine())),
              child: const Text(ComposeHe.addLine),
            ),
          ),
          _text(
            const Key('s3-discount'),
            ComposeHe.discount,
            s.discountText,
            (v) => s.discountText = v,
            error: s.discountValid ? null : ComposeHe.discountTooBig,
          ),
          if (s.showVat) ...[
            const SizedBox(height: Space.l),
            Text(ComposeHe.vat, style: AppText.headline),
            const SizedBox(height: Space.s),
            ChipRow<_VatMode>(
              key: const Key('s3-vat'),
              padding: EdgeInsets.zero,
              options: const [
                ChipOption(_VatMode.regular, ComposeHe.vatRegular),
                ChipOption(_VatMode.none, ComposeHe.vatNone),
                ChipOption(_VatMode.perLine, ComposeHe.vatPerLine),
              ],
              selected: _vatMode,
              onSelected: (v) => _set(() {
                s
                  ..vatNone = v == _VatMode.none
                  ..vatPerLine = v == _VatMode.perLine;
              }),
            ),
          ],
          if (s.hasNotes) ...[
            const SizedBox(height: Space.l),
            TextFormField(
              key: const Key('s3-notes'),
              initialValue: s.notes,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: ComposeHe.notes,
                helperText: ComposeHe.notesHint,
              ),
              onChanged: (v) {
                s.notes = v;
                s.changed();
              },
            ),
          ],
          if (s.hasDueDate)
            ListTile(
              key: const Key('s3-due-date'),
              contentPadding: EdgeInsets.zero,
              title: const Text(ComposeHe.dueDate),
              trailing: Text(formatDateHe(s.dueDate)),
              onTap: () => _pickDate(s.dueDate, (d) => s.pickedDueDate = d),
            ),
          if (widget.kinds.length > 1) ...[
            const SizedBox(height: Space.l),
            Text(ComposeHe.docType, style: AppText.headline),
            const SizedBox(height: Space.s),
            ChipRow<DocKind>(
              key: const Key('s3-type'),
              padding: EdgeInsets.zero,
              options: [
                for (final k in widget.kinds) ChipOption(k, kindLabels[k]!),
              ],
              selected: s.kind,
              onSelected: (k) => _set(() => s.setKind(k)),
            ),
          ],
          if (allocationRow)
            SwitchListTile(
              key: const Key('s3-allocation'),
              contentPadding: EdgeInsets.zero,
              title: const Text(ComposeHe.customerAskedAllocation),
              value: s.requestAllocation,
              onChanged: (v) => _set(() => s.requestAllocation = v),
            ),
          if (c.validUntil)
            ListTile(
              key: const Key('s3-valid-until'),
              contentPadding: EdgeInsets.zero,
              title: const Text(ComposeHe.validUntil),
              trailing: Text(formatDateHe(s.validUntil)),
              onTap: () => _pickDate(s.validUntil, (d) => s.validUntil = d),
            ),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: CommonHe.done,
            offline: businessContext.offline,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(String current, void Function(String iso) set) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = DateTime.tryParse(current) ?? today;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 366)),
      initialDate: initial.isBefore(today) ? today : initial,
    );
    if (picked == null) return;
    _set(
      () => set(
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      ),
    );
  }

  /// Catalog price (net) as typed in this Composer (gross when amounts
  /// include VAT).
  String _typedPrice(Item item, ComposeLine l) {
    final net = item.defaultUnitPriceMinor;
    if (net == null || net <= BigInt.zero) return l.priceText;
    final rate = s.lineRate(l);
    final shown = s.inclusive && rate > 0
        ? calculateLine(
            quantityMicros: oneQuantity,
            unitPriceMinor: net,
            discountMinor: null,
            taxRateBasisPoints: rate,
          ).totalMinor
        : net;
    return agorotToKeypadText(shown);
  }

  bool _canSaveItem(ComposeLine l) =>
      l.isValid &&
      l.itemId == null &&
      businessContext.can(Cap.itemManage) &&
      !_items.any((i) => i.name.trim() == l.description.trim());

  /// One POST /items at a time: a second tap while it runs would create the
  /// catalog item twice.
  bool _savingItem = false;

  Future<void> _saveItem(ComposeLine l) async {
    if (_savingItem) return;
    _savingItem = true;
    final net = s.lineNetPrice(l);
    try {
      final item = await createItem(name: l.description, priceMinor: net);
      if (!mounted) return;
      _set(() {
        l.itemId = item.id;
        _items = [..._items, item];
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showNotchNotice(SnackBar(content: Text(e.messageHe)), motion: NoticeMotion.error);
      }
    } finally {
      _savingItem = false;
    }
  }

  Widget _line(int i) {
    final l = s.extraLines[i];
    return Column(
      key: Key('s3-line-$i'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(flex: 3, child: _description(i, l)),
            const SizedBox(width: Space.s),
            Expanded(
              child: _text(
                Key('s3-line-$i-quantity-${l.itemId}'),
                ComposeHe.lineQuantity,
                l.quantityText,
                (v) => l.quantityText = v,
                fieldKey: Key('s3-line-$i-quantity'),
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              flex: 2,
              child: _text(
                Key('s3-line-$i-price-${l.itemId}'),
                ComposeHe.linePrice,
                l.priceText,
                (v) => l.priceText = v,
                fieldKey: Key('s3-line-$i-price'),
              ),
            ),
            IconButton(
              tooltip: ComposeHe.removeLine,
              icon: const Icon(Iconsax.close_circle),
              onPressed: () => _set(() => s.extraLines.removeAt(i)),
            ),
          ],
        ),
        Wrap(
          spacing: Space.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (s.vatPerLine && s.showVat)
              FilterChip(
                key: Key('s3-line-$i-vat-none'),
                label: const Text(ComposeHe.lineVatNone),
                selected: l.vatNone,
                onSelected: (v) => _set(() => l.vatNone = v),
              ),
            if (_canSaveItem(l))
              TextButton(
                key: Key('s3-line-$i-save-item'),
                onPressed: () => _saveItem(l),
                child: const Text(ComposeHe.saveAsItem),
              )
            else if (l.itemId != null && l.isValid)
              Text(
                ComposeHe.savedAsItem,
                key: Key('s3-line-$i-item'),
                style: AppText.secondary,
              ),
          ],
        ),
      ],
    );
  }

  /// Description with the catalog autocomplete: choosing an item fills the
  /// description, its price and `itemId`.
  Widget _description(int i, ComposeLine l) => Autocomplete<Item>(
    key: Key('s3-line-$i-autocomplete'),
    initialValue: TextEditingValue(text: l.description),
    displayStringForOption: (item) => item.name,
    optionsBuilder: (value) {
      final q = value.text.trim();
      if (q.isEmpty) return const Iterable<Item>.empty();
      return _items.where((item) => item.name.contains(q)).take(6);
    },
    onSelected: (item) => _set(() {
      l
        ..description = item.name
        ..itemId = item.id
        ..priceText = _typedPrice(item, l);
    }),
    fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
        TextFormField(
          key: Key('s3-line-$i-description'),
          controller: controller,
          focusNode: focusNode,
          decoration: const InputDecoration(
            labelText: ComposeHe.lineDescription,
          ),
          onFieldSubmitted: (_) => onSubmit(),
          onChanged: (v) {
            l
              ..description = v
              ..itemId = null; // typed over the item: a free line again
            setState(() {});
            s.changed();
          },
        ),
  );

  /// [key] changes when an item fills the line, so the field shows the new
  /// value; [fieldKey] is the stable key tests use.
  Widget _text(
    Key key,
    String label,
    String value,
    void Function(String) set, {
    Key? fieldKey,
    String? error,
  }) {
    final field = TextFormField(
      key: fieldKey ?? key,
      initialValue: value,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, errorText: error),
      onChanged: (v) {
        set(v);
        setState(() {});
        s.changed();
      },
    );
    return fieldKey == null ? field : KeyedSubtree(key: key, child: field);
  }
}

/// Opens S3 over the Composer. Changes apply to [state] live.
Future<void> showMoreDetailsSheet(
  BuildContext context, {
  required ComposeState state,
  List<DocKind> kinds = const [],
}) => showAppSheet<void>(
  context,
  builder: (_) => MoreDetailsSheet(state: state, kinds: kinds),
);
