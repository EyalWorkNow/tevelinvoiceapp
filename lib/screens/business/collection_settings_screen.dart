// "תזכורות גבייה אוטומטיות" — the ladder (server 0111): the master switch,
// the steps (on/off, days before / on / after the due date, the owner's
// wording), the maximum per document, the channels and the one daily
// summary. Every change saves at once (a partial PUT); a failure reverts.
// Owner / partner only (settings.business).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/collection_reminders_api.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/business_he.dart';
import '../../util/labels/collection_he.dart';
import 'business_template.dart';

/// Loads the settings (tests replace it).
Future<CollectionSettings?> Function() loadCollectionSettings =
    fetchCollectionSettings;

Future<void> openCollectionSettings(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CollectionSettingsScreen()),
    );

class CollectionSettingsScreen extends StatefulWidget {
  const CollectionSettingsScreen({super.key});

  @override
  State<CollectionSettingsScreen> createState() =>
      _CollectionSettingsScreenState();
}

class _CollectionSettingsScreenState extends State<CollectionSettingsScreen> {
  CollectionSettings? _s;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final s = await loadCollectionSettings();
      if (mounted) setState(() => _s = s);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Saves one change; the screen shows the server's answer.
  Future<void> _save(Future<CollectionSettings> Function() call) async {
    setState(() => _saving = true);
    try {
      final s = await call();
      if (mounted) setState(() => _s = s);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setEnabled(bool on) async {
    if (on) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text(BusinessHe.remindersConfirmTitle),
          content: const Text(BusinessHe.remindersConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              key: const Key('collection-confirm'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text(BusinessHe.remindersConfirmAction),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await _save(() => saveCollectionSettings(enabled: on));
  }

  Future<void> _editStep(int index) async {
    final s = _s!;
    final edited = await showAppSheet<LadderStep>(
      context,
      builder: (_) => _StepEditor(
        step: s.steps[index],
        defaultFor: s.defaultFor,
        taken: {
          for (var i = 0; i < s.steps.length; i++)
            if (i != index) s.steps[i].offsetDays,
        },
      ),
    );
    if (edited == null || !mounted) return;
    final steps = [...s.steps]..[index] = edited;
    await _save(() => saveCollectionSettings(steps: steps));
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final p = context.palette;
    final locked = _saving || session.offline;
    return BusinessPage(
      title: CollectionHe.settingsTitle,
      children: [
        if (s == null)
          _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : const SkeletonList()
        else ...[
          BusinessRow(
            key: const Key('collection-master'),
            label: CollectionHe.master,
            value: CollectionHe.masterHint,
            icon: Iconsax.notification_bing,
            trailing: Switch.adaptive(
              key: const Key('collection-master-switch'),
              value: s.enabled,
              onChanged: locked ? null : (v) => unawaited(_setEnabled(v)),
            ),
          ),
          const RowGroupGap(),
          _SectionTitle(CollectionHe.whenTitle),
          for (var i = 0; i < s.steps.length; i++)
            BusinessRow(
              key: Key('collection-step-$i'),
              label: CollectionHe.stepLabel(s.steps[i].offsetDays),
              value: s.steps[i].template == null
                  ? CollectionHe.stepDefaultText
                  : CollectionHe.stepCustomText,
              icon: s.steps[i].offsetDays < 0
                  ? Iconsax.calendar_1
                  : s.steps[i].offsetDays == 0
                  ? Iconsax.calendar_tick
                  : Iconsax.calendar_remove,
              onTap: locked ? null : () => unawaited(_editStep(i)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('collection-step-edit-$i'),
                    tooltip: CollectionHe.editStep,
                    onPressed: locked ? null : () => unawaited(_editStep(i)),
                    icon: Icon(Iconsax.edit_2, color: p.muted),
                  ),
                  Switch.adaptive(
                    key: Key('collection-step-switch-$i'),
                    value: s.steps[i].enabled,
                    onChanged: locked
                        ? null
                        : (v) {
                            final steps = [...s.steps]
                              ..[i] = s.steps[i].copyWith(enabled: v);
                            unawaited(
                              _save(() => saveCollectionSettings(steps: steps)),
                            );
                          },
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.m),
          _SectionTitle(CollectionHe.maxTitle),
          SegmentedButton<int>(
            key: const Key('collection-max'),
            showSelectedIcon: false,
            segments: [
              for (var n = 1; n <= 5; n++)
                ButtonSegment(value: n, label: Text('$n')),
            ],
            selected: {s.maxPerDocument.clamp(1, 5)},
            onSelectionChanged: locked
                ? null
                : (v) => unawaited(
                    _save(
                      () => saveCollectionSettings(maxPerDocument: v.first),
                    ),
                  ),
          ),
          const SizedBox(height: Space.m),
          const RowGroupGap(),
          _SectionTitle(CollectionHe.channelsTitle),
          BusinessRow(
            key: const Key('collection-email'),
            label: CollectionHe.email,
            value: CollectionHe.emailHint,
            icon: Iconsax.sms,
            trailing: Switch.adaptive(
              key: const Key('collection-email-switch'),
              value: s.email,
              onChanged: locked
                  ? null
                  : (v) => unawaited(
                      _save(() => saveCollectionSettings(email: v)),
                    ),
            ),
          ),
          BusinessRow(
            key: const Key('collection-whatsapp'),
            label: CollectionHe.whatsapp,
            value: CollectionHe.whatsappHint,
            icon: Iconsax.message,
            trailing: Switch.adaptive(
              key: const Key('collection-whatsapp-switch'),
              value: s.whatsapp,
              onChanged: locked
                  ? null
                  : (v) => unawaited(
                      _save(() => saveCollectionSettings(whatsapp: v)),
                    ),
            ),
          ),
          BusinessRow(
            key: const Key('collection-summary'),
            label: CollectionHe.summary,
            value: CollectionHe.summaryHint,
            icon: Iconsax.notification,
            trailing: Switch.adaptive(
              key: const Key('collection-summary-switch'),
              value: s.dailySummary,
              onChanged: locked
                  ? null
                  : (v) => unawaited(
                      _save(() => saveCollectionSettings(dailySummary: v)),
                    ),
            ),
          ),
          const RowGroupGap(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Iconsax.moon, size: 18, color: p.muted),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(
                    CollectionHe.quietHours,
                    key: const Key('collection-quiet'),
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s, bottom: Space.xs),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppText.secondary.copyWith(
          color: context.palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// One step: before / on / after + days, and the wording with placeholders.
class _StepEditor extends StatefulWidget {
  const _StepEditor({
    required this.step,
    required this.defaultFor,
    required this.taken,
  });

  final LadderStep step;
  final String Function(int offsetDays) defaultFor;

  /// Offsets other steps use (two steps cannot share a day).
  final Set<int> taken;

  @override
  State<_StepEditor> createState() => _StepEditorState();
}

enum _When { before, onDay, after }

class _StepEditorState extends State<_StepEditor> {
  late _When _when;
  late int _days;
  late final TextEditingController _text;
  late bool _custom;

  @override
  void initState() {
    super.initState();
    final o = widget.step.offsetDays;
    _when = o < 0
        ? _When.before
        : o == 0
        ? _When.onDay
        : _When.after;
    _days = o == 0 ? 3 : o.abs();
    _custom = widget.step.template != null;
    _text = TextEditingController(
      text: widget.step.template ?? widget.defaultFor(o),
    );
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _offset => switch (_when) {
    _When.before => -_days,
    _When.onDay => 0,
    _When.after => _days,
  };

  void _insert(String placeholder) {
    final sel = _text.selection;
    final value = _text.text;
    final at = sel.isValid ? sel.start : value.length;
    final end = sel.isValid ? sel.end : value.length;
    _text.value = TextEditingValue(
      text: value.replaceRange(at, end, placeholder),
      selection: TextSelection.collapsed(offset: at + placeholder.length),
    );
    setState(() => _custom = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final clash = widget.taken.contains(_offset);
    final max = _when == _When.before ? 30 : 90;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          CollectionHe.editStep,
          subtitle: CollectionHe.stepLabel(_offset),
        ),
        SegmentedButton<_When>(
          key: const Key('step-when'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _When.before,
              label: Text(CollectionHe.before),
            ),
            ButtonSegment(value: _When.onDay, label: Text(CollectionHe.onDay)),
            ButtonSegment(value: _When.after, label: Text(CollectionHe.after)),
          ],
          selected: {_when},
          onSelectionChanged: (v) => setState(() {
            _when = v.first;
            _days = _days.clamp(1, _when == _When.before ? 30 : 90);
            if (!_custom) _text.text = widget.defaultFor(_offset);
          }),
        ),
        if (_when != _When.onDay) ...[
          const SizedBox(height: Space.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                key: const Key('step-days-minus'),
                onPressed: _days > 1 ? () => setState(() => _days--) : null,
                icon: const Icon(Iconsax.minus),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                child: Text(
                  '$_days ${CollectionHe.days}',
                  key: const Key('step-days'),
                  style: AppText.headline,
                ),
              ),
              IconButton.outlined(
                key: const Key('step-days-plus'),
                onPressed: _days < max ? () => setState(() => _days++) : null,
                icon: const Icon(Iconsax.add),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.l),
        Text(CollectionHe.textTitle, style: AppText.headline),
        const SizedBox(height: Space.xs),
        Text(
          CollectionHe.textHint,
          style: AppText.secondary.copyWith(color: p.muted),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.xs,
          runSpacing: Space.xs,
          children: [
            for (final ph in reminderPlaceholders)
              ActionChip(
                key: Key('step-ph-$ph'),
                label: Text(CollectionHe.placeholderNames[ph] ?? ph),
                onPressed: () => _insert(ph),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        TextField(
          key: const Key('step-text'),
          controller: _text,
          minLines: 5,
          maxLines: 10,
          maxLength: 1000,
          textDirection: TextDirection.rtl,
          onChanged: (_) => _custom = true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        TextButton(
          key: const Key('step-reset'),
          onPressed: () => setState(() {
            _custom = false;
            _text.text = widget.defaultFor(_offset);
          }),
          child: const Text(CollectionHe.resetText),
        ),
        if (clash)
          Text(
            CollectionHe.stepClash,
            key: const Key('step-clash'),
            style: AppText.secondary.copyWith(color: p.danger),
          ),
        const SizedBox(height: Space.s),
        PrimaryButton(
          key: const Key('step-save'),
          label: CollectionHe.saveStep,
          onPressed: () {
            if (clash) return;
            final text = _text.text.trim();
            final isDefault =
                !_custom || text.isEmpty || text == widget.defaultFor(_offset);
            Navigator.of(context).pop(
              widget.step.copyWith(
                offsetDays: _offset,
                template: isDefault ? null : text,
                clearTemplate: isDefault,
              ),
            );
          },
        ),
      ],
    );
  }
}
