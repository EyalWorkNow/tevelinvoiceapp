// Field model + views for S13 (squad E). One widget per [FieldKind].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/ds.dart';
import '../../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum FieldKind {
  text,
  email,
  phone,
  number,
  money,
  url,
  multiline,
  toggle,
  choice,
  colors,
  logo,
  info,
}

/// Mutable values of one form, by field key.
class EditorValues {
  EditorValues(this._map);

  final Map<String, Object?> _map;

  Object? operator [](String key) => _map[key];
  void operator []=(String key, Object? value) => _map[key] = value;

  String str(String key) => (_map[key] as String?)?.trim() ?? '';
  bool flag(String key) => _map[key] == true;
  BigInt money(String key) =>
      _map[key] is BigInt ? _map[key] as BigInt : BigInt.zero;

  /// Trimmed text, or null when empty (PUT bodies clear optional fields).
  String? orNull(String key) => str(key).isEmpty ? null : str(key);
}

/// One option of a [FieldKind.choice] (radio row with a "what it means" line).
class EditorOption {
  const EditorOption(this.value, this.label, {this.hint, this.icon});

  final String value;
  final String label;
  final String? hint;
  final IconData? icon;
}

class EditorField {
  const EditorField({
    required this.key,
    required this.label,
    this.section,
    this.kind = FieldKind.text,
    this.initial,
    this.hint,
    this.required = false,
    this.readOnly = false,
    this.autofocus = false,
    this.validator,
    this.options = const [],
    this.collapsedAfter,
    this.visibleWhen,
    this.pickLogo,
  });

  final String key;
  final String label;

  /// Optional visual group for long forms; it does not affect saved data.
  final String? section;
  final FieldKind kind;
  final Object? initial;

  /// Helper line under the field / switch.
  final String? hint;
  final bool required;
  final bool readOnly;
  final bool autofocus;

  /// Hebrew error or null.
  final String? Function(Object? value)? validator;
  final List<EditorOption> options;

  /// [FieldKind.choice]: show only the first N options until "עוד ▾".
  final int? collapsedAfter;
  final bool Function(EditorValues values)? visibleWhen;

  /// [FieldKind.logo]: returns new image bytes (null = cancelled).
  final Future<Uint8List?> Function()? pickLogo;

  String? errorFor(EditorValues values) {
    final v = values[key];
    if (required && (v == null || (v is String && v.trim().isEmpty))) {
      return 'שדה חובה';
    }
    return validator?.call(v);
  }
}

class EditorFieldView extends StatefulWidget {
  const EditorFieldView({
    super.key,
    required this.field,
    required this.values,
    required this.onChanged,
    this.errorText,
  });

  final EditorField field;
  final EditorValues values;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  @override
  State<EditorFieldView> createState() => _EditorFieldViewState();
}

class _EditorFieldViewState extends State<EditorFieldView> {
  late final TextEditingController _text = TextEditingController(
    text: _initialText(),
  );
  bool _expanded = false;

  String _initialText() {
    final v = widget.values[widget.field.key];
    if (v is BigInt) {
      return v == BigInt.zero ? '' : (v ~/ BigInt.from(100)).toString();
    }
    return v?.toString() ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final p = context.palette;
    switch (f.kind) {
      case FieldKind.toggle:
        return MergeSemantics(
          child: SwitchListTile.adaptive(
            key: Key('switch-${f.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(f.label, style: AppText.body),
            subtitle: f.hint == null
                ? null
                : Text(
                    f.hint!,
                    style: AppText.secondary.copyWith(color: p.muted),
                  ),
            value: widget.values.flag(f.key),
            onChanged: f.readOnly ? null : (v) => widget.onChanged(v),
          ),
        );
      case FieldKind.info:
        return Text(f.label, style: AppText.secondary.copyWith(color: p.muted));
      case FieldKind.choice:
        return _choice(context);
      case FieldKind.colors:
        return _colors(context);
      case FieldKind.logo:
        return _logo(context);
      default:
        return _textField(context);
    }
  }

  Widget _textField(BuildContext context) {
    final f = widget.field;
    final ltr = const {
      FieldKind.email,
      FieldKind.phone,
      FieldKind.number,
      FieldKind.url,
      FieldKind.money,
    }.contains(f.kind);
    return TextField(
      key: Key('text-${f.key}'),
      controller: _text,
      autofocus: f.autofocus,
      readOnly: f.readOnly,
      enabled: !f.readOnly,
      minLines: f.kind == FieldKind.multiline ? 2 : 1,
      maxLines: f.kind == FieldKind.multiline ? 4 : 1,
      textDirection: ltr ? TextDirection.ltr : null,
      autocorrect: !ltr,
      keyboardType: switch (f.kind) {
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        FieldKind.number || FieldKind.money => TextInputType.number,
        FieldKind.url => TextInputType.url,
        FieldKind.multiline => TextInputType.multiline,
        _ => TextInputType.text,
      },
      inputFormatters: f.kind == FieldKind.number || f.kind == FieldKind.money
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: (v) => widget.onChanged(
        f.kind == FieldKind.money
            ? BigInt.from(int.tryParse(v) ?? 0) * BigInt.from(100)
            : v,
      ),
      decoration: InputDecoration(
        labelText: f.label,
        helperText: f.hint,
        helperMaxLines: 3,
        errorText: widget.errorText,
        prefixText: f.kind == FieldKind.money ? '₪ ' : null,
      ),
    );
  }

  Widget _choice(BuildContext context) {
    final f = widget.field;
    final p = context.palette;
    final selected = widget.values[f.key] as String?;
    final cut = f.collapsedAfter;
    final collapsed =
        cut != null &&
        !_expanded &&
        f.options.indexWhere((o) => o.value == selected) < cut;
    final shown = collapsed ? f.options.take(cut).toList() : f.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Text(f.label, style: AppText.headline),
          ),
        for (final o in shown)
          Semantics(
            inMutuallyExclusiveGroup: true,
            checked: o.value == selected,
            button: true,
            label: o.hint == null ? o.label : '${o.label}. ${o.hint}',
            excludeSemantics: true,
            child: InkWell(
              key: Key('choice-${f.key}-${o.value}'),
              borderRadius: BorderRadius.circular(Radii.button),
              onTap: f.readOnly
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      widget.onChanged(o.value);
                    },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Hit.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (o.icon != null) ...[
                        Icon(
                          o.icon,
                          color: o.value == selected ? p.accent : p.muted,
                        ),
                        const SizedBox(width: Space.m),
                      ] else ...[
                        Icon(
                          o.value == selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: o.value == selected ? p.accent : p.muted,
                        ),
                      ],
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.label, style: AppText.body),
                            if (o.hint != null)
                              Text(
                                o.hint!,
                                style: AppText.secondary.copyWith(
                                  color: p.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (o.icon != null) ...[
                        const SizedBox(width: Space.s),
                        Icon(
                          o.value == selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: o.value == selected ? p.accent : p.muted,
                          size: 22,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (collapsed)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: Key('choice-${f.key}-more'),
              onPressed: () => setState(() => _expanded = true),
              child: Text(f.hint ?? TeamHe.more),
            ),
          ),
        if (widget.errorText != null)
          Text(
            widget.errorText!,
            style: AppText.secondary.copyWith(color: p.danger),
          ),
      ],
    );
  }

  Widget _colors(BuildContext context) {
    final f = widget.field;
    final p = context.palette;
    final selected = widget.values[f.key] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label, style: AppText.headline),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final o in f.options)
              Semantics(
                button: true,
                selected: o.value == selected,
                label: o.label,
                excludeSemantics: true,
                child: InkWell(
                  key: Key('color-${o.value}'),
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onChanged(o.value),
                  child: Container(
                    width: Hit.min,
                    height: Hit.min,
                    decoration: BoxDecoration(
                      color: Color(
                        int.parse('ff${o.value.substring(1)}', radix: 16),
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: o.value == selected ? p.ink : p.line,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _logo(BuildContext context) {
    final f = widget.field;
    final p = context.palette;
    final bytes = widget.values[f.key];
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.button),
            border: Border.all(color: p.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes is Uint8List && bytes.isNotEmpty
              ? Image.memory(bytes, fit: BoxFit.contain, semanticLabel: f.label)
              : Icon(Iconsax.gallery, color: p.muted),
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton(
                key: const Key('logo-pick'),
                onPressed: () async {
                  final picked = await f.pickLogo?.call();
                  if (picked != null) widget.onChanged(picked);
                },
                child: Text(f.label),
              ),
              if (bytes is Uint8List && bytes.isNotEmpty && f.hint != null)
                TextButton(
                  key: const Key('logo-remove'),
                  onPressed: () => widget.onChanged(Uint8List(0)),
                  child: Text(f.hint!),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
