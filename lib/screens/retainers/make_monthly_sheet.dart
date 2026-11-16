// "הפוך לחשבונית חודשית" from D's ⋯ menu (QA 2026-11-16 C4). Creates a
// template (customer + lines + day of month); the server then prepares a
// DRAFT each month on that day. Nothing is issued or sent without a person.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/models/models.dart' show DocumentDetail;
import '../../state/caps.dart';
import '../../ui/ds.dart';
import '../../util/labels/retainer_he.dart';
import '../document/dialogs.dart' show toast;
import 'retainers_api.dart';

const Set<String> _monthlyTypes = {'TAX_INVOICE', 'TRANSACTION_INVOICE'};
const Set<String> _issued = {'FINALIZED', 'SIGNED', 'ARCHIVED', 'SENT'};

/// D shows the item for an issued 305 / 300 with a customer, to who may
/// draft and see amounts.
bool mayMakeMonthly(DocumentDetail doc, Caps caps) =>
    _monthlyTypes.contains(doc.documentType) &&
    _issued.contains(doc.status) &&
    doc.voidedAt == null &&
    doc.customerId != null &&
    !doc.amountHidden &&
    caps.can(Cap.docDraft) &&
    caps.can(Cap.moneyView);

/// The day defaults to the document's issue day (persona 03: "בתחילת החודש").
Future<void> showMakeMonthlySheet(
  BuildContext context,
  DocumentDetail doc,
) async {
  final issueDay = int.tryParse((doc.issueDate ?? '').split('-').last);
  final day = await showAppSheet<int>(
    context,
    builder: (_) => _MakeMonthly(initialDay: issueDay ?? 1),
  );
  if (day == null || !context.mounted) return;
  try {
    final r = await createRetainerTemplate(
      sourceDocumentId: doc.id,
      dayOfMonth: day,
    );
    if (context.mounted) {
      toast(context, r.created ? RetainerHe.created : RetainerHe.alreadyExists);
    }
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
  }
}

class _MakeMonthly extends StatefulWidget {
  const _MakeMonthly({required this.initialDay});

  final int initialDay;

  @override
  State<_MakeMonthly> createState() => _MakeMonthlyState();
}

class _MakeMonthlyState extends State<_MakeMonthly> {
  late int _day = widget.initialDay.clamp(1, 31);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SheetTitle(
        RetainerHe.makeMonthlyTitle,
        subtitle: RetainerHe.makeMonthlySubtitle,
      ),
      InputDecorator(
        decoration: const InputDecoration(labelText: RetainerHe.dayOfMonth),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const Key('monthly-day'),
            value: _day,
            isExpanded: true,
            items: [
              for (var d = 1; d <= 31; d++)
                DropdownMenuItem(value: d, child: Text(RetainerHe.dayLabel(d))),
            ],
            onChanged: (v) => setState(() => _day = v ?? _day),
          ),
        ),
      ),
      const SizedBox(height: Space.l),
      PrimaryButton(
        key: const Key('monthly-create'),
        label: RetainerHe.create,
        onPressed: () => Navigator.pop(context, _day),
      ),
    ],
  );
}
