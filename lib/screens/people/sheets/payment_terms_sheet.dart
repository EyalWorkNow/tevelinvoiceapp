// "תנאי תשלום" (0110): a customer's terms + preferred payment method, or the
// business default (customerId == null; business:configure). Presets מיידי /
// שוטף / שוטף+30/45/60/90, or "מותאם": N days from the end of the month
// (שוטף+N) or from the document date. The sheet shows the due date a
// document issued today would get (Israel date), so "שוטף+30" is concrete.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../api/collection_reminders_api.dart' show customerCadences;
import '../../../api/customer_timeline_api.dart';
import '../../../api/customers_api.dart' show saveCustomerReminderCadence;
import '../../../util/labels/collection_he.dart';
import '../../../ui/ds.dart';
import '../../../util/labels/common_he.dart' show formatDateHe;
import '../../../util/labels/payment_he.dart';
import '../../../util/labels/timeline_he.dart';
import '../../../util/payment_terms.dart';
import '../../../util/still_here.dart';

/// Returns the saved value, or null when dismissed.
/// 2611 §2: with [cadence] (a customer, owner/partner) the sheet is "תנאי
/// תשלום ותזכורות" and also sets the customer's reminder cadence
/// (BUSINESS | WEEKLY | BIWEEKLY | MONTHLY | NONE).
Future<PaymentTermsValue?> showPaymentTermsSheet(
  BuildContext context, {
  String? customerId,
  required PaymentTermsValue initial,
  String? cadence,
}) => showAppSheet<PaymentTermsValue>(
  context,
  builder: (_) => PaymentTermsSheet(
    customerId: customerId,
    initial: initial,
    cadence: cadence,
  ),
);

/// The methods a customer may prefer (server PREFERRED_PAYMENT_METHODS).
const List<String> preferredPaymentChoices = [
  'CASH',
  'BANK_TRANSFER',
  'CREDIT_CARD',
  'BIT',
  'PAYBOX',
  'CHECK',
  'DIRECT_DEBIT',
  'OTHER',
];

class PaymentTermsSheet extends StatefulWidget {
  const PaymentTermsSheet({
    super.key,
    this.customerId,
    required this.initial,
    this.cadence,
  });

  /// null = the business default.
  final String? customerId;
  final PaymentTermsValue initial;

  /// The customer's reminder cadence; null = the section is not shown.
  final String? cadence;

  @override
  State<PaymentTermsSheet> createState() => _PaymentTermsSheetState();
}

const String _none = '';
const String _custom = 'CUSTOM';

class _PaymentTermsSheetState extends State<PaymentTermsSheet> {
  late String _choice = switch (widget.initial.code) {
    null => _none,
    final c when isCustomTerms(c) => _custom,
    final c => c,
  };
  late bool _fromEom = widget.initial.code != customNetTerms;
  late final TextEditingController _days = TextEditingController(
    text: isCustomTerms(widget.initial.code)
        ? '${widget.initial.days ?? ''}'
        : '',
  );
  late String _method = widget.initial.method ?? _none;
  late String? _cadence = widget.cadence;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  /// The chosen code + days; null code = no terms. Throws on bad days.
  ({String? code, int? days}) get _value {
    if (_choice == _none) return (code: null, days: null);
    if (_choice != _custom) return (code: _choice, days: null);
    final n = int.tryParse(_days.text.trim());
    final min = _fromEom ? 0 : 1;
    if (n == null || n < min || n > 365) {
      throw const FormatException(TimelineHe.daysInvalid);
    }
    return (code: _fromEom ? customEomTerms : customNetTerms, days: n);
  }

  String? get _example {
    try {
      final v = _value;
      if (v.code == null) return null;
      return TimelineHe.dueExample(
        formatDateHe(dueDateTodayFor(v.code, days: v.days)),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    final ({String? code, int? days}) v;
    try {
      v = _value;
    } on FormatException catch (e) {
      return setState(() => _error = e.message);
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    HapticFeedback.selectionClick();
    final value = PaymentTermsValue(
      code: v.code,
      days: v.days,
      method: _method == _none ? null : _method,
    );
    try {
      final id = widget.customerId;
      final saved = id == null
          ? await saveBusinessPaymentTerms(value)
          : await saveCustomerPaymentTerms(id, value).then((_) => value);
      final cadence = _cadence;
      if (id != null && cadence != null && cadence != widget.cadence) {
        await saveCustomerReminderCadence(id, cadence);
      }
      if (mounted && stillHere(context)) Navigator.of(context).pop(saved);
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
    final business = widget.customerId == null;
    final example = _example;
    return Column(
      key: const Key('terms-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          business
              ? TimelineHe.businessTermsTitle
              : widget.cadence != null
              ? CollectionHe.termsAndReminders
              : TimelineHe.terms,
          subtitle: business
              ? TimelineHe.businessTermsSubtitle
              : TimelineHe.termsSheetSubtitle,
        ),
        Text(
          TimelineHe.terms,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.s),
        ChipRow<String>(
          key: const Key('terms-chips'),
          padding: EdgeInsets.zero,
          options: [
            const ChipOption(_none, TimelineHe.termsNoTerms),
            for (final c in presetPaymentTerms)
              ChipOption(c, paymentTermsLabel(c)!),
            const ChipOption(_custom, TimelineHe.termsCustom),
          ],
          selected: _choice,
          onSelected: (v) => setState(() {
            _choice = v;
            _error = null;
          }),
        ),
        if (_choice == _custom) ...[
          const SizedBox(height: Space.m),
          TextField(
            key: const Key('terms-days'),
            controller: _days,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: TimelineHe.termsCustomDays,
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: Space.s),
          ChipRow<bool>(
            key: const Key('terms-base'),
            padding: EdgeInsets.zero,
            options: const [
              ChipOption(true, TimelineHe.termsFromEom),
              ChipOption(false, TimelineHe.termsFromIssue),
            ],
            selected: _fromEom,
            onSelected: (v) => setState(() => _fromEom = v),
          ),
        ],
        if (example != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              example,
              key: const Key('terms-example'),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
        const SizedBox(height: Space.l),
        Text(
          TimelineHe.preferredMethod,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.s),
        ChipRow<String>(
          key: const Key('terms-method'),
          padding: EdgeInsets.zero,
          options: [
            const ChipOption(_none, TimelineHe.preferredNone),
            for (final m in preferredPaymentChoices)
              ChipOption(m, paymentMethodLabel(m)),
          ],
          selected: _method,
          onSelected: (v) => setState(() => _method = v),
        ),
        if (_cadence != null) ...[
          const SizedBox(height: Space.l),
          Text(
            CollectionHe.customerCadenceTitle,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.s),
          ChipRow<String>(
            key: const Key('terms-cadence'),
            padding: EdgeInsets.zero,
            options: [
              for (final c in customerCadences)
                ChipOption(c, CollectionHe.cadenceLabel(c)),
            ],
            selected: _cadence,
            onSelected: (v) => setState(() => _cadence = v),
          ),
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              CollectionHe.cadenceHint(_cadence!),
              key: const Key('terms-cadence-hint'),
              style: AppText.secondary.copyWith(color: p.muted),
            ),
          ),
        ],
        const SizedBox(height: Space.l),
        PrimaryButton(
          key: const Key('terms-save'),
          label: TimelineHe.termsSave,
          loadingText: _saving ? TimelineHe.termsSave : null,
          onPressed: _save,
        ),
      ],
    );
  }
}
