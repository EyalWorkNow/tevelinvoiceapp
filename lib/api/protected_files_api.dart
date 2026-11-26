// §7 "קובץ מוגן בסיסמה" (server migration 0131).
//
//   GET  /documents/:id/protection               → state of the document + customer default
//   POST /documents/:id/protection/:sid/reveal   → {password}  ("הצג סיסמה", audited)
//   POST /documents/:id/protected-copy {password}→ the AES-256 PDF (share sheet "PDF")
//   PUT  /customers/:id/file-protection {always} → "תמיד ללקוח הזה"
//
// The e-mail / link sends take the password in their own calls
// (sendDocumentEmail / createShareLink in actions_api.dart).

import 'dart:typed_data';

import 'client.dart';

final _api = ApiClient.instance;

class ProtectedSend {
  const ProtectedSend({
    required this.id,
    required this.channel,
    required this.createdAt,
    this.recipient,
  });

  factory ProtectedSend.fromJson(Map<String, dynamic> j) => ProtectedSend(
    id: j['id'] as String,
    channel: j['channel'] as String? ?? 'EMAIL',
    createdAt: j['createdAt'] as String? ?? '',
    recipient: j['recipient'] as String?,
  );

  final String id;

  /// EMAIL · LINK · FILE.
  final String channel;
  final String createdAt;
  final String? recipient;
}

class DocumentProtection {
  const DocumentProtection({
    required this.available,
    required this.customerAlwaysProtect,
    required this.sends,
    this.customerId,
  });

  factory DocumentProtection.fromJson(Map<String, dynamic> j) =>
      DocumentProtection(
        available: j['available'] as bool? ?? false,
        customerId: j['customerId'] as String?,
        customerAlwaysProtect: j['customerAlwaysProtect'] as bool? ?? false,
        sends: [
          for (final s in (j['sends'] as List? ?? const []))
            ProtectedSend.fromJson(s as Map<String, dynamic>),
        ],
      );

  /// The server can protect files (it holds the key).
  final bool available;
  final String? customerId;
  final bool customerAlwaysProtect;

  /// Newest first.
  final List<ProtectedSend> sends;
}

Future<DocumentProtection> fetchDocumentProtection(String documentId) async =>
    DocumentProtection.fromJson(
      await _api.get('/documents/$documentId/protection'),
    );

Future<String> revealProtectedPassword(
  String documentId,
  String protectedSendId,
) async {
  final json = await _api.post(
    '/documents/$documentId/protection/$protectedSendId/reveal',
  );
  return json['password'] as String;
}

/// The protected copy itself, for the iOS share sheet ("PDF" with the
/// toggle on). A new copy (and server record) per call.
Future<Uint8List> fetchProtectedCopy(String documentId, String password) => _api
    .postBytes('/documents/$documentId/protected-copy', {'password': password});

Future<bool> setCustomerFileProtection(String customerId, bool always) async {
  final json = await _api.put('/customers/$customerId/file-protection', {
    'always': always,
  });
  return json['always'] as bool? ?? always;
}
