// וואטסאפ עסקי — "תבנית חדשה": the owner writes the text ({שם} = the
// customer's first name, inserted by the "הוסף שם לקוח" chip), sees it live
// in a bubble with the fixed footer and opt-out button, and sends it to Meta
// for approval. Also the template details sheet (preview + delete).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/whatsapp_business_api.dart';
import '../../ui/ds.dart';
import '../../util/labels/common_he.dart';
import '../../util/labels/whatsapp_business_he.dart';
import 'wa_widgets.dart';

const waTemplateMaxLength = 900;

/// Returns the created template (null = cancelled).
Future<WaTemplate?> showWaTemplateSheet(BuildContext context) =>
    showAppSheet<WaTemplate>(context, builder: (_) => const WaTemplateSheet());

class WaTemplateSheet extends StatefulWidget {
  const WaTemplateSheet({super.key});

  @override
  State<WaTemplateSheet> createState() => _WaTemplateSheetState();
}

class _WaTemplateSheetState extends State<WaTemplateSheet> {
  final _text = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _insertName() {
    final t = _text;
    final sel = t.selection;
    final at = sel.isValid ? sel.start : t.text.length;
    final end = sel.isValid ? sel.end : t.text.length;
    t.value = TextEditingValue(
      text: t.text.replaceRange(at, end, waNameToken),
      selection: TextSelection.collapsed(offset: at + waNameToken.length),
    );
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = WaHe.textRequired);
      return;
    }
    if (text.length > waTemplateMaxLength) {
      setState(() => _error = WaHe.textTooLong);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final t = await createWaTemplate(text);
      if (mounted) Navigator.of(context).pop(t);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      key: const Key('wa-template-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetTitle(WaHe.newTemplate),
        TextField(
          key: const Key('wa-template-text'),
          controller: _text,
          minLines: 3,
          maxLines: 8,
          maxLength: waTemplateMaxLength,
          decoration: InputDecoration(
            labelText: WaHe.templateText,
            hintText: WaHe.templateHint,
            helperText: WaHe.nameHelp,
            errorText: _error,
          ),
        ),
        const SizedBox(height: Space.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionChip(
            key: const Key('wa-template-name'),
            avatar: Icon(Iconsax.user_add, size: 18, color: p.ink),
            label: const Text(WaHe.insertName),
            onPressed: _insertName,
          ),
        ),
        const SizedBox(height: Space.l),
        Text(
          WaHe.previewTitle,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.s),
        WaBubble(bodyText: _text.text, placeholder: WaHe.templateHint),
        const SizedBox(height: Space.l),
        Text(
          WaHe.approvalNote,
          key: const Key('wa-template-note'),
          style: AppText.secondary.copyWith(color: p.muted, height: 1.5),
        ),
        const SizedBox(height: Space.l),
        FilledButton(
          key: const Key('wa-template-submit'),
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
          ),
          child: const Text(WaHe.submit),
        ),
      ],
    );
  }
}

/// The template's details; true when it was deleted.
Future<bool> showWaTemplateDetails(BuildContext context, WaTemplate t) async =>
    await showAppSheet<bool>(
      context,
      builder: (sheet) => _TemplateDetails(template: t),
    ) ==
    true;

class _TemplateDetails extends StatefulWidget {
  const _TemplateDetails({required this.template});
  final WaTemplate template;

  @override
  State<_TemplateDetails> createState() => _TemplateDetailsState();
}

class _TemplateDetailsState extends State<_TemplateDetails> {
  bool _busy = false;

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text(WaHe.deleteTemplateTitle),
        content: const Text(WaHe.deleteTemplateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text(CommonHe.cancel),
          ),
          FilledButton(
            key: const Key('wa-template-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: d.palette.danger,
              foregroundColor: d.palette.onDanger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text(WaHe.deleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await deleteWaTemplate(widget.template.id);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    final p = context.palette;
    return Column(
      key: const Key('wa-template-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: SheetTitle(WaHe.templates)),
            WaPill(WaHe.templateStatus(t.status), waTemplateTone(t.status)),
          ],
        ),
        WaBubble(bodyText: t.bodyText),
        if (t.rejectedReason != null) ...[
          const SizedBox(height: Space.m),
          Text(
            WaHe.rejected(t.rejectedReason!),
            style: AppText.body.copyWith(color: p.danger),
          ),
        ],
        const SizedBox(height: Space.xl),
        TextButton.icon(
          key: const Key('wa-template-delete'),
          onPressed: _busy ? null : () => unawaited(_delete()),
          style: TextButton.styleFrom(foregroundColor: p.danger),
          icon: const Icon(Iconsax.trash),
          label: const Text(WaHe.deleteTemplate),
        ),
      ],
    );
  }
}
