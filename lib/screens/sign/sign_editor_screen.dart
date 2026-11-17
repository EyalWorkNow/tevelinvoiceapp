// Field placement over the rendered pages of a DRAFT sign request: pick a
// field type, tap the page to add it there; drag to move, the corner handle
// resizes, a tap on a selected field opens its settings (label, help text,
// required, delete). Geometry is SignField's normalized page coordinates.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/sign_requests_api.dart';
import '../../router.dart';
import '../../ui/ds.dart';
import '../../ui/widgets/notch_notice.dart';
import '../../util/labels/sign_he.dart';
import 'sign_common.dart';

IconData signKindIcon(SignFieldKind k) => switch (k) {
  SignFieldKind.signature => Iconsax.edit_2,
  SignFieldKind.text => Iconsax.text,
  SignFieldKind.date => Iconsax.calendar_1,
  SignFieldKind.checkbox => Iconsax.tick_square,
  SignFieldKind.initials => Iconsax.text_block,
};

class SignEditorScreen extends StatefulWidget {
  const SignEditorScreen({super.key, required this.request});
  final SignRequest request;

  @override
  State<SignEditorScreen> createState() => _SignEditorScreenState();
}

class _SignEditorScreenState extends State<SignEditorScreen> {
  late List<SignField> _fields = [...widget.request.fields];
  SignFieldKind _kind = SignFieldKind.signature;
  int? _selected;
  bool _dirty = false;
  bool _saving = false;
  final Map<int, Uint8List> _pages = {};

  SignRequest get _r => widget.request;
  int get _pageCount => _r.pageCount > 0 ? _r.pageCount : _r.pages.length;

  void _add(int page, Offset local, Size size) {
    if (_fields.length >= maxSignFields) {
      signToast(context, SignHe.tooManyFields, motion: NoticeMotion.error);
      return;
    }
    if (_selected != null) {
      setState(() => _selected = null); // first tap only deselects
      return;
    }
    final f = SignField.placeAt(
      _kind,
      page,
      local.dx / size.width,
      local.dy / size.height,
      aspect: _r.page(page).aspect,
    );
    setState(() {
      _fields.add(f);
      _selected = _fields.length - 1;
      _dirty = true;
    });
  }

  void _update(int i, SignField f) => setState(() {
    _fields[i] = f;
    _dirty = true;
  });

  Future<void> _settings(int i) async {
    final f = _fields[i];
    final label = TextEditingController(text: f.label ?? '');
    final help = TextEditingController(text: f.placeholder ?? '');
    var required = f.required;
    final result = await showAppSheet<String>(
      context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetTitle(SignHe.fieldSheetTitle, subtitle: SignHe.kind(f.kind)),
            TextField(
              key: const Key('sign-field-label'),
              controller: label,
              maxLength: maxFieldLabel,
              decoration: const InputDecoration(labelText: SignHe.fieldLabel),
            ),
            if (f.kind == SignFieldKind.text)
              TextField(
                key: const Key('sign-field-placeholder'),
                controller: help,
                maxLength: maxFieldLabel,
                decoration: const InputDecoration(
                  labelText: SignHe.fieldPlaceholder,
                ),
              ),
            SwitchListTile(
              key: const Key('sign-field-required'),
              contentPadding: EdgeInsets.zero,
              title: const Text(SignHe.fieldRequired),
              value: required,
              onChanged: (v) => setSheet(() => required = v),
            ),
            const SizedBox(height: Space.s),
            FilledButton(
              key: const Key('sign-field-done'),
              onPressed: () => Navigator.of(context).pop('done'),
              child: const Text(SignHe.fieldDone),
            ),
            TextButton.icon(
              key: const Key('sign-field-delete'),
              onPressed: () => Navigator.of(context).pop('delete'),
              icon: Icon(Iconsax.trash, color: context.palette.danger),
              label: Text(
                SignHe.fieldDelete,
                style: TextStyle(color: context.palette.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'delete') {
      setState(() {
        _fields.removeAt(i);
        _selected = null;
        _dirty = true;
      });
    } else if (result == 'done') {
      _update(
        i,
        f.copyWith(
          required: required,
          label: label.text,
          placeholder: help.text,
          clearLabel: label.text.trim().isEmpty,
          clearPlaceholder: help.text.trim().isEmpty,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_fields.isEmpty) {
      signToast(context, SignHe.noFields, motion: NoticeMotion.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await updateSignRequest(_r.id, fields: _fields);
      if (!mounted) return;
      setState(() {
        _fields = [...saved.fields];
        _dirty = false;
      });
      await openSignSend(context, saved, replace: true);
    } catch (e) {
      if (mounted) {
        signToast(
          context,
          signErrorText(e, SignHe.uploadFailed),
          motion: NoticeMotion.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text(SignHe.leaveTitle),
          content: const Text(SignHe.leaveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text(SignHe.stay),
            ),
            TextButton(
              key: const Key('sign-leave'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text(SignHe.leave),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SignHeader(SignHe.editorTitle),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.page),
                child: Row(
                  children: [
                    for (final k in SignFieldKind.values)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: Space.s),
                        child: ChoiceChip(
                          key: Key('sign-kind-${k.name}'),
                          avatar: Icon(signKindIcon(k), size: 18),
                          label: Text(SignHe.kind(k)),
                          selected: _kind == k,
                          onSelected: (_) => setState(() {
                            _kind = k;
                            _selected = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.s,
                ),
                child: Text(
                  SignHe.editorHint,
                  style: AppText.secondary.copyWith(color: p.muted),
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: p.canvas,
                  child: ListView.builder(
                    key: const Key('sign-pages'),
                    padding: const EdgeInsets.all(Space.page),
                    itemCount: _pageCount,
                    itemBuilder: (context, page) => Padding(
                      padding: const EdgeInsets.only(bottom: Space.l),
                      child: Column(
                        children: [
                          _pageView(page),
                          const SizedBox(height: Space.xs),
                          Text(
                            SignHe.pageOf(page, _pageCount),
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.m,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: Hit.primary,
                  child: FilledButton.icon(
                    key: const Key('sign-editor-save'),
                    onPressed: _saving ? null : () => unawaited(_save()),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Iconsax.send_2),
                    label: Text('${SignHe.editorSave} (${_fields.length})'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageView(int page) {
    final aspect = _r.page(page).aspect;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxWidth * aspect);
        return SizedBox(
          key: Key('sign-page-$page'),
          width: size.width,
          height: size.height,
          // Physical left/top: page coordinates never mirror under RTL.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: SignPageImage(
                      requestId: _r.id,
                      index: page,
                      aspect: aspect,
                      cache: _pages,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(
                    key: Key('sign-page-tap-$page'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _add(page, d.localPosition, size),
                  ),
                ),
                for (var i = 0; i < _fields.length; i++)
                  if (_fields[i].pageIndex == page) _fieldBox(i, size),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fieldBox(int i, Size size) {
    final f = _fields[i];
    final p = context.palette;
    final selected = _selected == i;
    final color =
        f.kind == SignFieldKind.signature || f.kind == SignFieldKind.initials
        ? p.info
        : p.ok;
    return Positioned(
      key: Key('sign-field-$i'),
      left: f.x * size.width,
      top: f.y * size.height,
      width: f.width * size.width,
      height: f.height * size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => selected
                  ? unawaited(_settings(i))
                  : setState(() => _selected = i),
              onPanStart: (_) => setState(() => _selected = i),
              onPanUpdate: (d) => _update(
                i,
                _fields[i].moved(
                  d.delta.dx / size.width,
                  d.delta.dy / size.height,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color, width: selected ? 2 : 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: f.kind == SignFieldKind.checkbox
                        ? Icon(Iconsax.tick_square, color: color, size: 16)
                        : Text(
                            '${(f.label ?? '').isNotEmpty ? f.label! : SignHe.kind(f.kind)}${f.required ? ' *' : ''}',
                            textDirection: TextDirection.rtl,
                            style: AppText.secondary.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned(
              right: -14,
              bottom: -14,
              child: GestureDetector(
                key: Key('sign-resize-$i'),
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => _update(
                  i,
                  _fields[i].resized(
                    d.delta.dx / size.width,
                    d.delta.dy / size.height,
                  ),
                ),
                child: SizedBox.square(
                  dimension: 28,
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.surface, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
