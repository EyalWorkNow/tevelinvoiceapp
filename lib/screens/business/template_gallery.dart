// Invoice design gallery (branding screen, "תבנית החשבונית"): one thumbnail
// card per server template, rendered by POST /settings/branding/preview with
// the current draft's colours/font/logo and the card's template, rasterised to
// a PNG and cached in memory. Tapping a card selects that design.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../api/branding_api.dart';
import '../../api/client.dart';
import '../../state/business_context.dart';
import '../../ui/ds.dart';

/// The designs, in gallery order (ids = packages/document-renderer
/// DOCUMENT_TEMPLATES). Name + one-line hint, Hebrew.
const invoiceTemplates = <String, (String, String)>{
  // r5 (owner selection 2026-11-18): the default, then the new designs, then the originals.
  'summary': ('כרטיס הסכום', 'הסכום ותאריך הפירעון בראש המסמך, עם QR לתשלום'),
  'elegant': ('נייר מכתבים אלגנטי', 'סריף עברי, קישוט עדין ושורת ״בברכה״'),
  'swiss': ('רשת מינימלית', 'שחור על לבן, תוויות זעירות וסה״כ גדול'),
  'slip': ('סרט קבלה', 'טור צר כמו קבלת קופה, מתאים גם למדפסת תרמית'),
  'bold': ('בלוק צבע', 'בלוק מותג עמוק וכרטיס סה״כ בצבע המשני'),
  'clinic': ('קליניקה', 'רכה ומרגיעה, עם אייקונים ושורת פרטיות'),
  'legal': ('משרד עורכי דין', 'כותרות סריף וקו דק בצבע המשני'),
  'events': ('אירועים', 'כרטיס ״לתשלום עכשיו״ ולוח תשלומים'),
  'classic': ('קלאסית', 'טבלה עם מסגרות, מסודרת ומוכרת'),
  'modern': ('מודרנית', 'כותרת צבעונית עדינה ופינות מעוגלות'),
  'minimal': ('נקייה', 'הרבה אוויר וטיפוגרפיה שקטה'),
  'banner': ('פס מותג', 'פס כותרת מלא בצבע המותג'),
  'letterhead': ('נייר מכתבים', 'כותרת ממורכזת, אותיות סריף וקווים כפולים'),
  'compact': ('קבלה קומפקטית', 'טור צר וצפוף עם קווים מקווקווים'),
  'stripe': ('פס צד', 'פס צבעוני בצד הדף ורקעים בגוון המותג'),
};

/// PDF page 1 → PNG thumbnail. Replaceable in tests (no pdfium there).
Future<Uint8List?> Function(Uint8List pdf) templateThumbnailRasterizer =
    _rasterize;

Future<Uint8List?> _rasterize(Uint8List pdf) async {
  final doc = await PdfDocument.openData(pdf);
  try {
    final page = await doc.getPage(1);
    try {
      final image = await page.render(
        width: page.width * .6,
        height: page.height * .6,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      return image?.bytes;
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

// Thumbnails ignore the free-text notes (unreadable at this size), so typing a
// note never re-renders the gallery.
String _styleKey(Branding d) => [
  businessContext.business?.businessId,
  d.accentColor,
  d.secondaryColor,
  d.inkSave,
  d.fontFamily,
  d.logoSize,
  d.accentTableHeader,
  d.logoDataUri?.length,
  d.logoDataUri?.hashCode,
].join('|');

final _cache = <String, Uint8List>{}; // insertion-ordered (LRU)
void _remember(String key, Uint8List png) {
  _cache.remove(key);
  _cache[key] = png;
  while (_cache.length > 42) {
    _cache.remove(_cache.keys.first);
  }
}

/// Clears cached thumbnails (tests; business switch).
void clearTemplateThumbnails() => _cache.clear();

class TemplateGallery extends StatefulWidget {
  const TemplateGallery({
    super.key,
    required this.draft,
    required this.onSelected,
  });

  final Branding draft;

  /// Null while saving (cards disabled).
  final ValueChanged<String>? onSelected;

  @override
  State<TemplateGallery> createState() => _TemplateGalleryState();
}

class _TemplateGalleryState extends State<TemplateGallery> {
  final _thumbs = <String, Uint8List>{};
  final _failed = <String>{};

  /// Templates an older server rejects (422) are not offered.
  final _unsupported = <String>{};
  Timer? _debounce;
  int _generation = 0;
  String? _key;

  @override
  void initState() {
    super.initState();
    _refresh(immediate: true);
  }

  @override
  void didUpdateWidget(TemplateGallery old) {
    super.didUpdateWidget(old);
    if (_styleKey(widget.draft) != _key) _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    super.dispose();
  }

  void _refresh({bool immediate = false}) {
    _key = _styleKey(widget.draft);
    _failed.clear();
    for (final t in invoiceTemplates.keys) {
      final cached = _cache['$t|$_key'];
      if (cached != null) _thumbs[t] = cached;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    if (immediate) {
      _loadAll(generation);
    } else {
      _debounce = Timer(
        const Duration(milliseconds: 700),
        () => _loadAll(generation),
      );
    }
  }

  // One request at a time, the selected design first (server-friendly).
  Future<void> _loadAll(int generation) async {
    final key = _key!;
    final draft = widget.draft;
    final order = [
      draft.template,
      ...invoiceTemplates.keys.where((t) => t != draft.template),
    ];
    for (final t in order) {
      if (!mounted || generation != _generation) return;
      if (_unsupported.contains(t) || _cache.containsKey('$t|$key')) continue;
      try {
        final pdf = await previewBranding(
          Branding({...draft.raw, 'template': t}),
        );
        final png = await templateThumbnailRasterizer(pdf);
        if (png == null) throw StateError('empty thumbnail');
        _remember('$t|$key', png);
        if (!mounted || generation != _generation) return;
        setState(() {
          _thumbs[t] = png;
          _failed.remove(t);
        });
      } on ApiException catch (e) {
        if (!mounted || generation != _generation) return;
        setState(() {
          if (e.status == 422 && t != draft.template) {
            _unsupported.add(t);
          } else {
            _failed.add(t);
          }
        });
      } on Object {
        if (!mounted || generation != _generation) return;
        setState(() => _failed.add(t));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = invoiceTemplates.keys
        .where((t) => !_unsupported.contains(t))
        .toList();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      // Thumbnail (A4 ratio) + name line(s), grows with the text size.
      height: 196 + 48 * scale,
      child: ListView.separated(
        key: const Key('branding-template-gallery'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _TemplateCard(
          id: ids[i],
          selected: widget.draft.template == ids[i],
          thumbnail: _thumbs[ids[i]],
          failed: _failed.contains(ids[i]),
          onTap: widget.onSelected == null
              ? null
              : () => widget.onSelected!(ids[i]),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.id,
    required this.selected,
    required this.thumbnail,
    required this.failed,
    required this.onTap,
  });

  final String id;
  final bool selected, failed;
  final Uint8List? thumbnail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (name, hint) = invoiceTemplates[id]!;
    final border = selected ? p.accent : p.line;
    return Semantics(
      key: Key('branding-template-$id'),
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: 'תבנית $name. $hint',
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: 124,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    // The page itself is always white paper, also in dark mode.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: border,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumbnail != null)
                          Image.memory(
                            thumbnail!,
                            key: Key('branding-template-thumb-$id'),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          )
                        else if (failed)
                          const Center(
                            child: Icon(
                              Icons.description_outlined,
                              color: Color(0xFF9AA4A8),
                              size: 34,
                            ),
                          )
                        else
                          // Static page skeleton (no endless spinner animation).
                          const _PageSkeleton(),
                        if (selected)
                          PositionedDirectional(
                            top: 6,
                            end: 6,
                            child: Container(
                              key: Key('branding-template-check-$id'),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: p.accent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: p.accentInk,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(
                  color: selected ? p.ink : p.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double widthFactor, double height) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFE9ECEE),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
    return Semantics(
      label: 'טוען תצוגה',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar(.6, 10),
            bar(.4, 6),
            const SizedBox(height: 10),
            for (var i = 0; i < 4; i++) bar(1, 5),
            const SizedBox(height: 8),
            bar(.45, 8),
          ],
        ),
      ),
    );
  }
}
