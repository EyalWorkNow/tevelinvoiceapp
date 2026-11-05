// Document branding and server-rendered previews.
// GET /settings/branding → {branding, canConfigure}. PUT replaces the WHOLE
// branding object, so a save always sends the current values back with the
// changed ones (template, font, notes set on the web are kept).

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'client.dart';

final _api = ApiClient.instance;

/// Server limit (packages/postgres/src/branding.ts MAX_LOGO_CHARS).
const int maxLogoChars = 700000;

/// Accent colours offered in the app (§13.2: "צבע").
const List<String> brandColors = [
  '#1f2a2e',
  '#0b6e4f',
  '#1d4ed8',
  '#7c3aed',
  '#be123c',
  '#c2410c',
  '#a16207',
  '#0f766e',
];

class Branding {
  const Branding(this.raw);

  factory Branding.fromJson(Map<String, dynamic> json) => Branding(
    Map<String, dynamic>.of(
      json['branding'] as Map<String, dynamic>? ?? const {},
    ),
  );

  final Map<String, dynamic> raw;

  String? get logoDataUri => raw['logoDataUri'] as String?;
  String get template => raw['template'] as String? ?? 'classic';
  String get fontFamily => raw['fontFamily'] as String? ?? 'sans';
  String get logoSize => raw['logoSize'] as String? ?? 'medium';
  bool get accentTableHeader => raw['accentTableHeader'] == true;
  String? get accentColor => raw['accentColor'] as String?;

  Uint8List? get logoBytes {
    final uri = logoDataUri;
    if (uri == null) return null;
    final comma = uri.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(uri.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}

Future<Branding> fetchBranding() async =>
    Branding.fromJson(await _api.get('/settings/branding'));

/// Saves logo and/or colour on top of [current]. [logoDataUri]: '' removes.
Future<Branding> saveBranding(
  Branding current, {
  String? logoDataUri,
  String? accentColor,
}) async {
  final body = <String, dynamic>{
    for (final k in const [
      'template',
      'fontFamily',
      'logoDataUri',
      'logoSize',
      'accentColor',
      'accentTableHeader',
      'headerNote',
      'footerNote',
    ])
      k: current.raw[k],
    if (logoDataUri != null)
      'logoDataUri': logoDataUri.isEmpty ? null : logoDataUri,
    'accentColor': ?accentColor,
  };
  return Branding.fromJson(await _api.put('/settings/branding', body));
}

/// Photo bytes → PNG data URI that fits the server limit (longest side ≤ 512,
/// halved until it fits). Null when the bytes are not an image.
String? logoDataUriFrom(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  var side = 512;
  while (true) {
    final resized = image!.width >= image.height
        ? img.copyResize(image, width: image.width > side ? side : image.width)
        : img.copyResize(
            image,
            height: image.height > side ? side : image.height,
          );
    final uri = 'data:image/png;base64,${base64Encode(img.encodePng(resized))}';
    if (uri.length <= maxLogoChars || side <= 64) {
      return uri.length <= maxLogoChars ? uri : null;
    }
    side ~/= 2;
    image = resized;
  }
}

/// Previewing a draft never saves settings or creates an issued document.
Future<Uint8List> previewBranding(Branding draft) => _api.postBytes(
  '/settings/branding/preview',
  draft.raw,
  accept: 'application/pdf',
);
