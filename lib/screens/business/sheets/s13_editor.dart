// S13 · עורך גנרי (SPEC-v2 §6 sheets, §12, §13). Owner: squad E.
//
// A form built from an [EditorConfig]: fields → validation → one "שמור"
// (PrimaryButton) → onSave. The same [EditorForm] body is used inside the
// sheet and as a B sub-page (/business/profile, …), so every settings
// instance is one template. Instances by id: see editor_configs.dart.

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../../ui/widgets/notch_notice.dart';
import '../../../state/session.dart';
import '../../../ui/ds.dart';
import '../../../util/labels/labels.dart';
import 'editor_configs.dart';
import 'editor_fields.dart';

export 'editor_fields.dart';

/// One form.
class EditorConfig {
  const EditorConfig({
    required this.title,
    this.subtitle,
    required this.fields,
    this.saveLabel = CommonHe.save,
    this.onSave,
    this.more = const [],
    this.savedMessage = BusinessHe.saved,
  });

  final String title;
  final String? subtitle;
  final List<EditorField> fields;
  final String saveLabel;

  /// Null = read-only form (no PrimaryButton, AT-90 "read screen").
  /// Throw [ApiException] to show the server's Hebrew message.
  final Future<void> Function(EditorValues values)? onSave;

  /// "⋯" items (destructive last, MoreMenu orders them).
  final List<MoreMenuItem> more;

  /// Snack after a successful save ('' = none).
  final String savedMessage;
}

/// Opens S13. [instance]: '13.1' | '13.2' | '13.6' | '13.9' | '13.3' (loaded by
/// [editorLoaderFor]), or any id with an explicit [config] ('member', 'invite',
/// person details). Returns true when saved.
Future<bool> showEditorSheet(
  BuildContext context, {
  required String instance,
  EditorConfig? config,
}) async {
  if (config == null && editorLoaderFor(instance) == null) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => EditorSheet(instance: instance, config: config),
  );
  return saved ?? false;
}

/// "לצאת בלי לשמור?" (06·U8). True = leave and drop the changes.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(BusinessHe.discardTitle),
      content: const Text(BusinessHe.discardBody),
      actions: [
        TextButton(
          key: const Key('discard-keep'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(BusinessHe.keepEditing),
        ),
        TextButton(
          key: const Key('discard-confirm'),
          style: TextButton.styleFrom(foregroundColor: context.palette.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(BusinessHe.discardAction),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Guards a route against losing [dirty] input: back / barrier tap ask first,
/// and while dirty a drag on the content does not close a sheet. Does nothing
/// on a route that cannot pop (a root tab).
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.dirty,
    required this.child,
  });

  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!(ModalRoute.of(context)?.canPop ?? false)) return child;
    return PopScope<Object?>(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await confirmDiscardChanges(context)) navigator.pop();
      },
      // The sheet's own drag-to-close bypasses PopScope; an inner vertical
      // drag recogniser wins the arena and keeps the sheet open.
      // Always the same tree (toggling it would remount the form).
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: dirty ? (_) {} : null,
        child: child,
      ),
    );
  }
}

class EditorSheet extends StatelessWidget {
  const EditorSheet({super.key, required this.instance, this.config});

  /// Which form: '13.1' business details, 'member', 'invite', '13.9', …
  final String instance;
  final EditorConfig? config;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: config != null
        ? EditorForm(config: config!, popOnSave: true)
        : EditorLoader(instance: instance, popOnSave: true),
  );
}

/// Loads an instance's config (current values from the server), then shows
/// the form. Loading = skeleton, error = message + "נסה שוב".
class EditorLoader extends StatefulWidget {
  const EditorLoader({
    super.key,
    required this.instance,
    this.popOnSave = false,
  });

  final String instance;
  final bool popOnSave;

  @override
  State<EditorLoader> createState() => _EditorLoaderState();
}

class _EditorLoaderState extends State<EditorLoader> {
  late Future<EditorConfig> _future = _load();

  Future<EditorConfig> _load() => editorLoaderFor(widget.instance)!();

  @override
  Widget build(BuildContext context) => FutureBuilder<EditorConfig>(
    future: _future,
    builder: (context, snap) {
      if (snap.hasError) {
        return SizedBox(
          height: 320,
          child: ErrorView(
            error: snap.error!,
            onRetry: () => setState(() => _future = _load()),
          ),
        );
      }
      if (!snap.hasData)
        return const SizedBox(height: 320, child: SkeletonList(rows: 4));
      return EditorForm(
        config: snap.data!,
        popOnSave: widget.popOnSave,
        shrinkWrap: widget.popOnSave,
      );
    },
  );
}

/// The form body. [popOnSave]: pop the route with `true` after saving (sheet).
class EditorForm extends StatefulWidget {
  const EditorForm({
    super.key,
    required this.config,
    this.popOnSave = false,
    this.shrinkWrap = true,
  });

  final EditorConfig config;
  final bool popOnSave;

  /// Sheet = shrink-wrapped column; page = fills the screen.
  final bool shrinkWrap;

  @override
  State<EditorForm> createState() => _EditorFormState();
}

class _EditorFormState extends State<EditorForm> {
  late final EditorValues _values = EditorValues({
    for (final f in widget.config.fields) f.key: f.initial,
  });
  bool _validate = false;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  List<EditorField> get _visible => [
    for (final f in widget.config.fields)
      if (f.visibleWhen?.call(_values) ?? true) f,
  ];

  Future<void> _save() async {
    final onSave = widget.config.onSave;
    if (onSave == null || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validate = true;
      _error = null;
    });
    if (_visible.any((f) => f.errorFor(_values) != null)) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    try {
      await onSave(_values);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _dirty = false);
      final msg = widget.config.savedMessage;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (widget.popOnSave) Navigator.of(context).pop(true);
      if (msg.isNotEmpty)
        messenger?.showNotchNotice(SnackBar(content: Text(msg)));
    } on Object catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = errorTextHe(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changed(String key, Object? value) => setState(() {
    _values[key] = value;
    _dirty = true;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final p = context.palette;
    final fields = <Widget>[];
    String? lastSection;
    for (final f in _visible) {
      if (f.section != null && f.section != lastSection) {
        fields.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Space.m, 0, Space.s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(f.section!, style: AppText.headline),
                ),
                Divider(color: p.line, height: Space.l),
              ],
            ),
          ),
        );
      }
      if (f.section != null) lastSection = f.section;
      fields.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: EditorFieldView(
            key: ValueKey('field-${f.key}'),
            field: f,
            values: _values,
            errorText: _validate ? f.errorFor(_values) : null,
            onChanged: (v) => _changed(f.key, v),
          ),
        ),
      );
    }
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(cfg.title, style: AppText.title),
                ),
                if (cfg.subtitle != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    cfg.subtitle!,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
                ],
              ],
            ),
          ),
          if (cfg.more.isNotEmpty) MoreMenu(items: cfg.more),
        ],
      ),
    );
    final error = _error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: AppText.body.copyWith(color: p.danger),
              ),
            ),
          );
    final action = cfg.onSave == null
        ? null
        : BottomActionArea(
            child: PrimaryButton(
              key: const Key('editor-save'),
              label: cfg.saveLabel,
              loadingText: _saving ? cfg.saveLabel : null,
              offline: session.offline,
              onPressed: _save,
            ),
          );
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [...fields, ?error],
      ),
    );
    if (widget.shrinkWrap) {
      return UnsavedChangesGuard(
        dirty: _dirty,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, body],
                ),
              ),
            ),
            ?action,
          ],
        ),
      );
    }
    return UnsavedChangesGuard(
      dirty: _dirty,
      child: Column(
        children: [
          Expanded(child: ListView(children: [header, body])),
          ?action,
        ],
      ),
    );
  }
}
