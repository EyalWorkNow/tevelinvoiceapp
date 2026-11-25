// V4 §8 · a group action, end to end: the params sheet (broadcast / document)
// → the server's preview → a confirm with its numbers ("יישלח ל-12",
// "יוצאו 12 מסמכים, סך ₪X", "3 לא יקבלו") → ONE run under an Idempotency-Key
// (a retry of the same confirm re-sends the SAME key: the server answers with
// the first run, nothing leaves twice) → the result, and when WhatsApp
// messages wait, the tap queue (one wa.me per customer, the owner sends).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/client.dart';
import '../../api/customer_groups_api.dart';
import '../../api/issue_api.dart' show resolveScopeKey;
import '../../state/business_context.dart';
import '../../ui/ds.dart';
import '../../util/composer_config.dart' show isVatExemptBusiness;
import '../../util/labels/common_he.dart';
import '../../util/labels/document_he.dart' show docTypeLabel;
import '../../util/labels/groups_he.dart';
import '../../util/money.dart';
import '../../util/vat.dart';
import '../compose/compose_memory.dart' show fetchVatRate;
import 'group_queue_screen.dart';

/// The lines of a preview, in order (pure; tested).
List<String> previewLines(GroupActionKind kind, GroupPreview p) {
  final lines = <String>[];
  if (kind == GroupActionKind.document) {
    if (p.documents > 0) {
      lines.add(
        GroupsHe.documentsLine(
          p.documents,
          formatMoney(p.totalMinor ?? BigInt.zero, trimZeroAgorot: true),
        ),
      );
      if (p.perDocumentMinor != null) {
        lines.add(
          GroupsHe.perDocument(
            formatMoney(p.perDocumentMinor!, trimZeroAgorot: true),
          ),
        );
      }
    }
  } else if (p.recipients > 0) {
    lines.add(GroupsHe.willSend(p.recipients));
    if (p.email > 0) lines.add(GroupsHe.byEmail(p.email));
    if (p.whatsapp > 0) lines.add(GroupsHe.byWhatsapp(p.whatsapp));
  }
  if (p.notOwing > 0) lines.add(GroupsHe.notOwing(p.notOwing));
  if (p.inactive > 0) lines.add(GroupsHe.skippedInactive(p.inactive));
  if (p.unreachable > 0) {
    final why = [
      if (p.noContact > 0) GroupsHe.noContact(p.noContact),
      if (p.noEmail > 0) GroupsHe.noEmailSkip(p.noEmail),
      if (p.noConsent > 0) GroupsHe.noConsent(p.noConsent),
    ].join(' · ');
    lines.add('${GroupsHe.wontGet(p.unreachable)}: $why');
  }
  return lines;
}

bool previewHasRecipients(GroupActionKind kind, GroupPreview p) =>
    kind == GroupActionKind.document ? p.documents > 0 : p.recipients > 0;

String _title(GroupActionKind kind) => switch (kind) {
  GroupActionKind.paymentRequest => GroupsHe.paymentTitle,
  GroupActionKind.broadcast => GroupsHe.broadcastTitle,
  GroupActionKind.document => GroupsHe.documentTitle,
  GroupActionKind.bookingInvite => GroupsHe.inviteTitle,
  GroupActionKind.statement => GroupsHe.statementTitle,
};

/// The whole flow for [kind]. Returns the run (null = cancelled / failed).
Future<GroupRun?> startGroupAction(
  BuildContext context, {
  required String groupId,
  required String groupName,
  required GroupActionKind kind,
}) async {
  Map<String, Object?>? params = const {};
  if (kind == GroupActionKind.broadcast) {
    params = await showBroadcastSheet(context, groupName: groupName);
  } else if (kind == GroupActionKind.document) {
    params = await showGroupDocumentSheet(context, groupName: groupName);
  }
  if (params == null || !context.mounted) return null;
  final GroupPreview preview;
  try {
    preview = await previewGroupAction(groupId, kind, params);
  } on Object catch (e) {
    if (context.mounted) showErrorSnack(context, e);
    return null;
  }
  if (!context.mounted) return null;
  final ok = await _confirm(context, kind, groupName, preview);
  if (ok != true || !context.mounted) return null;
  // One key per confirm: every retry below re-sends it.
  final key = ApiClient.newIdempotencyKey();
  GroupRun? run;
  while (run == null) {
    try {
      run = await runGroupAction(groupId, kind, params, idempotencyKey: key);
    } on Object catch (e) {
      if (!context.mounted) return null;
      final network = e is ApiException && e.isNetwork;
      if (!network) {
        showErrorSnack(context, e);
        return null;
      }
      final again = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          content: Text(errorText(e)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text(CommonHe.cancel),
            ),
            FilledButton(
              key: const Key('group-run-retry'),
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text(CommonHe.retry),
            ),
          ],
        ),
      );
      if (again != true || !context.mounted) return null;
    }
  }
  if (context.mounted) await showGroupRunResult(context, run);
  return run;
}

String errorText(Object e) =>
    e is ApiException ? e.messageHe : GroupsHe.genericError;

Future<bool?> _confirm(
  BuildContext context,
  GroupActionKind kind,
  String groupName,
  GroupPreview preview,
) {
  final has = previewHasRecipients(kind, preview);
  final lines = previewLines(kind, preview);
  return showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      key: const Key('group-confirm'),
      title: Text(_title(kind)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(groupName, style: AppText.secondary),
          const SizedBox(height: Space.s),
          if (!has) const Text(GroupsHe.nobody),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(l, style: AppText.body),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('group-confirm-cancel'),
          onPressed: () => Navigator.of(d).pop(false),
          child: Text(has ? CommonHe.cancel : GroupsHe.done),
        ),
        if (has)
          FilledButton(
            key: const Key('group-confirm-ok'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(
              kind == GroupActionKind.document
                  ? GroupsHe.confirmIssue
                  : GroupsHe.confirmSend,
            ),
          ),
      ],
    ),
  );
}

/// The result lines of a run (pure; tested).
List<String> runResultLines(GroupRun run) => [
  if (run.documents > 0) GroupsHe.issued(run.documents),
  if (run.email > 0) GroupsHe.sentEmail(run.email),
  if (run.queue.isNotEmpty) GroupsHe.waiting(run.queue.length),
  if (run.skipped > 0) GroupsHe.skipped(run.skipped),
  if (run.failed > 0) GroupsHe.failed(run.failed),
];

Future<void> showGroupRunResult(BuildContext context, GroupRun run) async {
  final queue = run.queue;
  final open = await showAppSheet<bool>(
    context,
    builder: (sheet) => Column(
      key: const Key('group-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(GroupsHe.resultTitle),
        for (final l in runResultLines(run))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Text(l, style: AppText.body),
          ),
        const SizedBox(height: Space.l),
        if (queue.isNotEmpty)
          FilledButton.icon(
            key: const Key('group-result-queue'),
            onPressed: () => Navigator.of(sheet).pop(true),
            icon: const Icon(Iconsax.message),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            label: const Text(GroupsHe.openQueue),
          )
        else
          FilledButton(
            key: const Key('group-result-done'),
            onPressed: () => Navigator.of(sheet).pop(false),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
            ),
            child: const Text(GroupsHe.done),
          ),
      ],
    ),
  );
  if (open == true && context.mounted) {
    await openGroupQueue(context, run);
  }
}

// ---- broadcast ---------------------------------------------------------------

Future<Map<String, Object?>?> showBroadcastSheet(
  BuildContext context, {
  required String groupName,
}) => showAppSheet<Map<String, Object?>>(
  context,
  builder: (_) => BroadcastSheet(groupName: groupName),
);

class BroadcastSheet extends StatefulWidget {
  const BroadcastSheet({super.key, required this.groupName});
  final String groupName;

  @override
  State<BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<BroadcastSheet> {
  final _text = TextEditingController();
  final _subject = TextEditingController();
  String _purpose = 'SERVICE';
  String _channel = 'WHATSAPP';
  String? _error;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _subject.dispose();
    super.dispose();
  }

  void _insertName() {
    final t = _text;
    final sel = t.selection;
    final at = sel.isValid ? sel.start : t.text.length;
    final end = sel.isValid ? sel.end : t.text.length;
    t.value = TextEditingValue(
      text: t.text.replaceRange(at, end, '{שם}'),
      selection: TextSelection.collapsed(offset: at + 4),
    );
  }

  void _next() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = GroupsHe.textRequired);
      return;
    }
    Navigator.of(context).pop(<String, Object?>{
      'text': text,
      'purpose': _purpose,
      'channel': _channel,
      if (_channel == 'EMAIL' && _subject.text.trim().isNotEmpty)
        'subject': _subject.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sample = _text.text.trim();
    return Column(
      key: const Key('group-broadcast'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(GroupsHe.broadcastTitle, subtitle: widget.groupName),
        Text(GroupsHe.purpose, style: AppText.body.copyWith(color: p.muted)),
        const SizedBox(height: Space.s),
        ChipRow<String>(
          options: const [
            ChipOption('SERVICE', GroupsHe.purposeService),
            ChipOption('MARKETING', GroupsHe.purposeMarketing),
          ],
          selected: _purpose,
          onSelected: (v) => setState(() => _purpose = v),
        ),
        if (_purpose == 'MARKETING') ...[
          const SizedBox(height: Space.s),
          Text(
            GroupsHe.marketingNote,
            key: const Key('group-marketing-note'),
            style: AppText.secondary.copyWith(color: p.muted),
          ),
        ],
        const SizedBox(height: Space.m),
        Text(GroupsHe.channel, style: AppText.body.copyWith(color: p.muted)),
        const SizedBox(height: Space.s),
        ChipRow<String>(
          options: const [
            ChipOption('WHATSAPP', GroupsHe.channelWhatsapp),
            ChipOption('EMAIL', GroupsHe.channelEmail),
          ],
          selected: _channel,
          onSelected: (v) => setState(() => _channel = v),
        ),
        const SizedBox(height: Space.m),
        if (_channel == 'EMAIL') ...[
          TextField(
            key: const Key('group-broadcast-subject'),
            controller: _subject,
            maxLength: 120,
            decoration: const InputDecoration(labelText: GroupsHe.subject),
          ),
          const SizedBox(height: Space.s),
        ],
        TextField(
          key: const Key('group-broadcast-text'),
          controller: _text,
          minLines: 3,
          maxLines: 8,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: GroupsHe.broadcastText,
            hintText: GroupsHe.broadcastHint,
            helperText: GroupsHe.nameHelp,
            errorText: _error,
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('group-broadcast-name'),
            onPressed: _insertName,
            icon: const Icon(Iconsax.user_add, size: 18),
            label: const Text(GroupsHe.nameHintChip),
          ),
        ),
        if (sample.contains('{שם}')) ...[
          const SizedBox(height: Space.s),
          Text(
            GroupsHe.previewFor,
            style: AppText.secondary.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.xs),
          Text(
            personalizeBroadcast(sample, 'דנה כהן'),
            key: const Key('group-broadcast-sample'),
            style: AppText.body,
          ),
        ],
        const SizedBox(height: Space.l),
        FilledButton(
          key: const Key('group-broadcast-next'),
          onPressed: _next,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: const Text(GroupsHe.next),
        ),
      ],
    );
  }
}

// ---- document for everyone ---------------------------------------------------

/// Tests replace these (the VAT rate and the numbering scope).
Future<int> Function() groupVatRate = fetchVatRate;
Future<String> Function() groupScopeKey = resolveScopeKey;

/// The one line every member's document carries ([grossMinor] = what each
/// customer pays, VAT included), shaped like compose_state.requestLines.
Map<String, Object?> groupDocumentLine({
  required String description,
  required BigInt grossMinor,
  required int rate,
}) {
  final quantity = BigInt.from(1000000);
  final g = rate > 0
      ? grossLine(
          quantityMicros: quantity,
          grossUnitMinor: grossMinor,
          basisPoints: rate,
          agreed: true,
        )
      : null;
  return {
    'description': description,
    'quantityMicros': quantity.toString(),
    'unitPriceMinor': (g?.unitPriceMinor ?? grossMinor).toString(),
    'discountMinor': '0',
    'taxRateBasisPoints': rate,
    if (g?.agreedTotalMinor != null)
      'agreedTotalMinor': g!.agreedTotalMinor.toString(),
  };
}

Future<Map<String, Object?>?> showGroupDocumentSheet(
  BuildContext context, {
  required String groupName,
}) => showAppSheet<Map<String, Object?>>(
  context,
  builder: (_) => GroupDocumentSheet(groupName: groupName),
);

class GroupDocumentSheet extends StatefulWidget {
  const GroupDocumentSheet({super.key, required this.groupName});
  final String groupName;

  @override
  State<GroupDocumentSheet> createState() => _GroupDocumentSheetState();
}

class _GroupDocumentSheetState extends State<GroupDocumentSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _type = 'TRANSACTION_INVOICE';
  DateTime? _due;
  bool _send = true;
  bool _busy = false;
  String? _descError;
  String? _amountError;

  bool get _exempt => isVatExemptBusiness(businessContext.businessType);

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _due ?? now.add(const Duration(days: 30)),
    );
    if (d != null && mounted) setState(() => _due = d);
  }

  Future<void> _next() async {
    final description = _description.text.trim();
    final gross = parseAmount(_amount.text) ?? BigInt.zero;
    setState(() {
      _descError = description.isEmpty ? GroupsHe.descriptionRequired : null;
      _amountError = gross <= BigInt.zero ? GroupsHe.amountRequired : null;
    });
    if (_descError != null || _amountError != null) return;
    setState(() => _busy = true);
    try {
      final rate = _exempt ? 0 : await groupVatRate();
      final scopeKey = await groupScopeKey();
      if (!mounted) return;
      String two(int n) => n.toString().padLeft(2, '0');
      final due = _due;
      Navigator.of(context).pop(<String, Object?>{
        'documentType': _type,
        'line': groupDocumentLine(
          description: description,
          grossMinor: gross,
          rate: rate,
        ),
        if (due != null)
          'dueDate': '${due.year}-${two(due.month)}-${two(due.day)}',
        'send': _send,
        'scopeKey': scopeKey,
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final due = _due;
    return Column(
      key: const Key('group-document'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(GroupsHe.documentTitle, subtitle: widget.groupName),
        Text(
          GroupsHe.documentBody,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.m),
        if (!_exempt) ...[
          Text(
            GroupsHe.documentType,
            style: AppText.body.copyWith(color: p.muted),
          ),
          const SizedBox(height: Space.s),
          ChipRow<String>(
            options: [
              ChipOption(
                'TRANSACTION_INVOICE',
                docTypeLabel('TRANSACTION_INVOICE'),
              ),
              ChipOption('TAX_INVOICE', docTypeLabel('TAX_INVOICE')),
            ],
            selected: _type,
            onSelected: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: Space.m),
        ],
        TextField(
          key: const Key('group-document-description'),
          controller: _description,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: GroupsHe.description,
            hintText: GroupsHe.descriptionHint,
            errorText: _descError,
          ),
        ),
        TextField(
          key: const Key('group-document-amount'),
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: _exempt ? GroupsHe.amountNoVat : GroupsHe.amount,
            prefixText: '₪ ',
            errorText: _amountError,
          ),
        ),
        const SizedBox(height: Space.s),
        ListTile(
          key: const Key('group-document-due'),
          contentPadding: EdgeInsets.zero,
          title: const Text(GroupsHe.dueDate),
          trailing: Text(
            due == null
                ? GroupsHe.noDueDate
                : formatDateHe(
                    '${due.year}-${due.month.toString().padLeft(2, '0')}-'
                    '${due.day.toString().padLeft(2, '0')}',
                  ),
            style: AppText.body,
          ),
          onTap: _pickDue,
        ),
        SwitchListTile.adaptive(
          key: const Key('group-document-send'),
          contentPadding: EdgeInsets.zero,
          value: _send,
          onChanged: (v) => setState(() => _send = v),
          title: const Text(GroupsHe.sendToCustomers),
        ),
        const SizedBox(height: Space.l),
        FilledButton(
          key: const Key('group-document-next'),
          onPressed: _busy ? null : _next,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: const Text(GroupsHe.next),
        ),
      ],
    );
  }
}
