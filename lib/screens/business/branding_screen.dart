import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../api/branding_api.dart';
import '../../state/business_context.dart';
import '../../ui/app_page_route.dart';
import '../../ui/ds.dart';
import '../document/document_parts.dart' show pdfPreviewBuilder;
import 'sheets/editor_configs.dart' show logoPicker;

const _templates = {
  'classic': 'קלאסית',
  'modern': 'מודרנית',
  'minimal': 'נקייה',
};
const _fonts = {'sans': 'נקי', 'serif': 'מסורתי', 'rounded': 'מעוגל'};
const _logoSizes = {'small': 'קטן', 'medium': 'בינוני', 'large': 'גדול'};

class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key});
  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  Branding? _draft;
  Uint8List? _preview;
  Object? _error, _previewError;
  bool _saving = false, _previewLoading = false, _dirty = false;
  int _generation = 0, _pdfRevision = 0;
  Timer? _debounce;
  final _hex = TextEditingController(),
      _header = TextEditingController(),
      _footer = TextEditingController();
  String? _businessId;
  @override
  void initState() {
    super.initState();
    _businessId = businessContext.business?.businessId;
    businessContext.addListener(_businessChanged);
    _load();
  }

  void _businessChanged() {
    final id = businessContext.business?.businessId;
    if (id != _businessId) {
      _businessId = id;
      _generation++;
      _debounce?.cancel();
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    businessContext.removeListener(_businessChanged);
    _hex.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _draft = null;
      _preview = null;
      _error = null;
      _dirty = false;
    });
    try {
      final branding = await fetchBranding();
      if (!mounted || generation != _generation) return;
      _hex.text = branding.accentColor ?? '#1f2a2e';
      _header.text = branding.raw['headerNote'] as String? ?? '';
      _footer.text = branding.raw['footerNote'] as String? ?? '';
      setState(() => _draft = branding);
      _schedulePreview();
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    }
  }

  void _change(Map<String, dynamic> values) {
    if (_draft == null || _saving) return;
    setState(() {
      _draft = Branding({..._draft!.raw, ...values});
      _dirty = true;
      _error = null;
    });
    _schedulePreview();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _render(generation),
    );
  }

  Future<void> _render(int generation) async {
    final draft = _draft;
    if (draft == null) return;
    try {
      final bytes = await previewBranding(draft);
      if (!mounted || generation != _generation) return;
      setState(() {
        _preview = bytes;
        _pdfRevision++;
        _previewLoading = false;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _previewError = error;
          _previewLoading = false;
        });
      }
    }
  }

  Future<void> _pickLogo() async {
    try {
      final businessId = _businessId;
      final bytes = await logoPicker();
      if (bytes == null || !mounted || businessId != _businessId) return;
      final uri = logoDataUriFrom(bytes);
      if (uri == null) {
        setState(() => _error = 'יש לבחור תמונת PNG, JPEG או WebP תקינה.');
        return;
      }
      _change({'logoDataUri': uri});
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    if (_draft == null || _saving) return;
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(_hex.text)) {
      setState(() => _error = 'יש להזין צבע בפורמט #RRGGBB');
      return;
    }
    final businessId = _businessId;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await saveBranding(_draft!);
      if (mounted && businessId == _businessId) {
        setState(() {
          _draft = saved;
          _dirty = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('עיצוב המסמכים נשמר')));
      }
    } on Object catch (error) {
      if (mounted && businessId == _businessId) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fullPreview() {
    final bytes = _preview;
    if (bytes == null || _previewLoading || _previewError != null) return;
    Navigator.of(context).push(
      AppPageRoute<void>(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'תצוגה מקדימה · דוגמה',
                          style: AppText.title,
                        ),
                      ),
                      DesignBackButton(),
                    ],
                  ),
                ),
                Expanded(child: pdfPreviewBuilder(bytes)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _previewPanel() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _dirty ? 'דוגמה · טרם נשמר' : 'תצוגה מקדימה',
                style: AppText.secondary,
              ),
            ),
            IconButton(
              key: const Key('branding-preview-full'),
              tooltip: 'הגדלת התצוגה',
              onPressed:
                  _preview != null && !_previewLoading && _previewError == null
                  ? _fullPreview
                  : null,
              icon: const Icon(Icons.open_in_full_rounded),
            ),
          ],
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ColoredBox(
              color: Colors.white,
              child: Stack(
                children: [
                  if (_previewError != null)
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextButton.icon(
                          onPressed: _schedulePreview,
                          icon: const Icon(Icons.refresh),
                          label: const Text('התצוגה לא נטענה. נסה שוב'),
                        ),
                      ),
                    )
                  else if (_preview != null)
                    Positioned.fill(
                      child: KeyedSubtree(
                        key: ValueKey(_pdfRevision),
                        child: pdfPreviewBuilder(_preview!),
                      ),
                    ),
                  if (_previewLoading)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x99FFFFFF),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8D9EF),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Iconsax.colorfilter,
                    color: Color(0xFF614A68),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('עיצוב המסמכים', style: AppText.title),
                      SizedBox(height: 2),
                      Text('תצוגה מקדימה לפני שמירה', style: AppText.secondary),
                    ],
                  ),
                ),
                DesignBackButton(),
              ],
            ),
          ),
          if (_draft == null)
            Expanded(
              child: _error == null
                  ? const SkeletonList(rows: 4)
                  : ErrorView(error: _error!, onRetry: _load),
            )
          else
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Column(
                  children: [
                    SizedBox(
                      height: (box.maxHeight * .43).clamp(160.0, 330.0),
                      child: _previewPanel(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('branding-controls'),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: _controls(_draft!),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_draft != null)
            BottomActionArea(
              child: PrimaryButton(
                key: const Key('editor-save'),
                label: 'שמירת העיצוב',
                loadingText: _saving ? 'שומרים…' : null,
                onPressed: _save,
              ),
            ),
        ],
      ),
    ),
  );
  Widget _controls(Branding draft) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _controlHeading(
        'תבנית החשבונית',
        Iconsax.document_text,
        'בחרו סגנון נקי ותקני למסמכים שלכם',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final e in _templates.entries)
            ChoiceChip(
              key: Key('branding-template-${e.key}'),
              avatar: Icon(
                e.key == 'classic'
                    ? Icons.table_rows_outlined
                    : e.key == 'modern'
                    ? Icons.view_agenda_outlined
                    : Icons.notes_rounded,
                size: 20,
              ),
              label: Text(e.value),
              selected: draft.template == e.key,
              onSelected: _saving ? null : (_) => _change({'template': e.key}),
            ),
        ],
      ),
      const SizedBox(height: 22),
      _controlHeading(
        'צבעי המותג',
        Iconsax.color_swatch,
        'הצבע ישמש להדגשות עדינות בתבנית',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final color in brandColors)
            Semantics(
              button: true,
              selected: draft.accentColor == color,
              label: 'צבע $color',
              child: InkWell(
                key: Key('color-$color'),
                customBorder: const CircleBorder(),
                onTap: _saving
                    ? null
                    : () {
                        _hex.text = color;
                        _change({'accentColor': color});
                      },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(
                      int.parse(color.substring(1), radix: 16) | 0xff000000,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: draft.accentColor == color
                          ? DesignTokens.lavender
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: draft.accentColor == color
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 22,
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('branding-color-hex'),
        controller: _hex,
        enabled: !_saving,
        textDirection: TextDirection.ltr,
        maxLength: 7,
        decoration: const InputDecoration(
          labelText: 'צבע מותאם · #RRGGBB',
          helperText: 'אפשר לבחור צבע מהרשימה או להזין קוד צבע',
          prefixIcon: Icon(Iconsax.brush_1),
        ),
        onChanged: (value) {
          if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
            _change({'accentColor': value});
          }
        },
      ),
      const SizedBox(height: 12),
      _controlHeading(
        'לוגו העסק',
        Iconsax.gallery,
        'הוסיפו לוגו שיופיע בראש המסמך',
      ),
      const SizedBox(height: 12),
      if (draft.logoBytes != null)
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.memory(
              draft.logoBytes!,
              height: 64,
              width: 140,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(Icons.image_outlined),
            ),
          ),
        ),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton.icon(
            key: const Key('logo-pick'),
            onPressed: _saving ? null : _pickLogo,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('בחירת לוגו'),
          ),
          if (draft.logoDataUri != null)
            TextButton(
              key: const Key('logo-remove'),
              onPressed: _saving ? null : () => _change({'logoDataUri': null}),
              child: const Text('הסרת הלוגו'),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _controlHeading('גודל הלוגו', Iconsax.maximize_4, ''),
      Wrap(
        spacing: 8,
        children: [
          for (final e in _logoSizes.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: draft.logoSize == e.key,
              onSelected: _saving ? null : (_) => _change({'logoSize': e.key}),
            ),
        ],
      ),
      const SizedBox(height: 20),
      _controlHeading('סגנון הכתב', Iconsax.text, ''),
      Wrap(
        spacing: 8,
        children: [
          for (final e in _fonts.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: draft.fontFamily == e.key,
              onSelected: _saving
                  ? null
                  : (_) => _change({'fontFamily': e.key}),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Iconsax.brush_1),
        title: const Text('הדגשת כותרת הטבלה'),
        subtitle: const Text('הדגשה בצבע המותג שבחרתם'),
        value: draft.accentTableHeader,
        onChanged: _saving ? null : (v) => _change({'accentTableHeader': v}),
      ),
      TextField(
        key: const Key('branding-header-note'),
        controller: _header,
        enabled: !_saving,
        maxLength: 500,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'טקסט נוסף ליד פרטי העסק',
          helperText: 'לדוגמה: שעות פעילות או פרטי קשר',
          prefixIcon: Icon(Iconsax.message_text_1),
        ),
        onChanged: (v) => _change({'headerNote': v}),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('branding-footer-note'),
        controller: _footer,
        enabled: !_saving,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'הערה בתחתית המסמך',
          helperText: 'ההערה תופיע בתחתית המסמך, אם הוזנה',
          prefixIcon: Icon(Iconsax.note_2),
          alignLabelWithHint: true,
        ),
        onChanged: (v) => _change({'footerNote': v}),
      ),
      const SizedBox(height: 12),
      Text(
        'העיצוב יחול על מסמכים חדשים. פרטי העסק, המספור והסכומים נשמרים בכל התבניות; מקור שכבר הופק אינו משתנה.',
        style: AppText.secondary.copyWith(
          color: context.palette.muted,
          height: 1.5,
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            errorTextHe(_error!),
            style: AppText.body.copyWith(color: context.palette.danger),
          ),
        ),
    ],
  );

  Widget _controlHeading(String title, IconData icon, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 21, color: context.palette.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.headline),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle, style: AppText.secondary),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}
