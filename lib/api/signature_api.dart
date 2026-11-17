// "החתימה שלי": the member's hand-drawn signature (PNG ≤ 200 KB) that the
// server prints at the bottom of the quotes they send.
//   GET    /me/signature → {imagePngBase64, updatedAt} | 404 SIGNATURE_NOT_SET
//   PUT    /me/signature {imagePngBase64} → same shape
//   DELETE /me/signature → 204

import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';

/// Server limit for the PNG.
const int maxSignaturePngBytes = 200 * 1024;

class MySignature {
  const MySignature({required this.png, this.updatedAt});

  factory MySignature.fromJson(Map<String, dynamic> json) => MySignature(
    png: base64Decode(json['imagePngBase64'] as String? ?? ''),
    updatedAt: json['updatedAt'] as String?,
  );

  final Uint8List png;
  final String? updatedAt;
}

/// Null when the member has no signature yet.
Future<MySignature?> fetchMySignature() async {
  try {
    final json = await ApiClient.instance.get('/me/signature');
    final sig = MySignature.fromJson(json);
    return sig.png.isEmpty ? null : sig;
  } on ApiException catch (e) {
    if (e.code == 'SIGNATURE_NOT_SET') return null;
    rethrow;
  }
}

Future<MySignature> saveMySignature(Uint8List png) async {
  if (png.length > maxSignaturePngBytes) {
    throw ArgumentError.value(png.length, 'png', 'larger than 200 KB');
  }
  return MySignature.fromJson(
    await ApiClient.instance.put('/me/signature', {
      'imagePngBase64': base64Encode(png),
    }),
  );
}

Future<void> deleteMySignature() async {
  try {
    await ApiClient.instance.delete('/me/signature');
  } on ApiException catch (e) {
    if (e.code != 'SIGNATURE_NOT_SET' && e.status != 404) rethrow;
  }
}
