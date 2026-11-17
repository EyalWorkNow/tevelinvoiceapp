// Photo / scan → PDF for "מסמך לחתימה": one JPEG (DCTDecode) per page, the
// page sized to the image's aspect inside A4 width (595 pt). Pure Dart, no
// PDF package: a JPEG can be embedded as-is.

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest edge of an embedded photo (≈ 240 dpi on A4).
const int maxScanSide = 2000;

/// Re-encodes any decodable image (HEIC excluded) to a baseline JPEG no
/// larger than [maxScanSide]. Null when the bytes are not an image.
Uint8List? normalizeToJpeg(Uint8List bytes, {int quality = 82}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxScanSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxScanSide)
        : img.copyResize(image, height: maxScanSide);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// (width, height, components) from a JPEG's SOF marker; null when not a JPEG.
(int, int, int)? jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final sof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (sof) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      final c = b[i + 9];
      return w > 0 && h > 0 ? (w, h, c) : null;
    }
    i += 2 + len;
  }
  return null;
}

/// A PDF with one page per JPEG in [jpegs] (each already a JPEG — see
/// [normalizeToJpeg]). Throws ArgumentError for a non-JPEG input.
Uint8List jpegsToPdf(List<Uint8List> jpegs) {
  if (jpegs.isEmpty) throw ArgumentError('no pages');
  final out = BytesBuilder();
  final offsets = <int>[];
  void raw(List<int> b) => out.add(b);
  void str(String s) => raw(latin1.encode(s));
  void obj(int n, void Function() body) {
    offsets.add(out.length);
    str('$n 0 obj\n');
    body();
    str('\nendobj\n');
  }

  // 1 = catalog, 2 = pages, then 3 objects per page (page, image, content).
  final n = jpegs.length;
  final kids = [for (var p = 0; p < n; p++) '${3 + p * 3} 0 R'].join(' ');
  str('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  obj(1, () => str('<< /Type /Catalog /Pages 2 0 R >>'));
  obj(2, () => str('<< /Type /Pages /Kids [$kids] /Count $n >>'));
  for (var p = 0; p < n; p++) {
    final jpeg = jpegs[p];
    final size = jpegSize(jpeg);
    if (size == null) throw ArgumentError('page $p is not a JPEG');
    final (w, h, c) = size;
    final space = c == 1
        ? '/DeviceGray'
        : c == 4
        ? '/DeviceCMYK /Decode [1 0 1 0 1 0 1 0]'
        : '/DeviceRGB';
    const pageW = 595.0;
    final pageH = (pageW * h / w).clamp(200.0, 2000.0);
    final pw = pageW.toStringAsFixed(2);
    final ph = pageH.toStringAsFixed(2);
    final page = 3 + p * 3, image = page + 1, content = page + 2;
    obj(
      page,
      () => str(
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pw $ph] '
        '/Resources << /XObject << /Im0 $image 0 R >> >> /Contents $content 0 R >>',
      ),
    );
    obj(image, () {
      str(
        '<< /Type /XObject /Subtype /Image /Width $w /Height $h '
        '/ColorSpace $space /BitsPerComponent 8 /Filter /DCTDecode '
        '/Length ${jpeg.length} >>\nstream\n',
      );
      raw(jpeg);
      str('\nendstream');
    });
    final draw = latin1.encode('q $pw 0 0 $ph 0 0 cm /Im0 Do Q');
    obj(content, () {
      str('<< /Length ${draw.length} >>\nstream\n');
      raw(draw);
      str('\nendstream');
    });
  }
  final xref = out.length;
  str('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    str('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  str(
    'trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n',
  );
  return out.toBytes();
}

/// Photos → PDF (top-level for compute()). Null when one is not an image.
Uint8List? imagesToPdf(List<Uint8List> images) {
  final jpegs = <Uint8List>[];
  for (final i in images) {
    final j = normalizeToJpeg(i);
    if (j == null) return null;
    jpegs.add(j);
  }
  return jpegs.isEmpty ? null : jpegsToPdf(jpegs);
}
