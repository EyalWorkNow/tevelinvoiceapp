import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';
import 'reports_api.dart';

const maxBusinessCertificateBytes = 4 * 1024 * 1024;

class BusinessRegistrationInputException implements Exception {
  const BusinessRegistrationInputException(this.message);
  final String message;
}

class BusinessCertificateFile {
  const BusinessCertificateFile({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

Future<void> completeBusinessRegistration({
  required String fullName,
  required Map<String, dynamic> profile,
  required BusinessCertificateFile certificate,
}) async {
  await ApiClient.instance.post('/business/registration', {
    'fullName': fullName.trim(),
    'profile': profile,
    'certificate': {
      'filename': certificate.filename,
      'mimeType': certificate.mimeType,
      'base64': base64Encode(certificate.bytes),
    },
  });
}

Future<Map<String, dynamic>?> fetchBusinessRegistration() async {
  final json = await ApiClient.instance.get('/business/registration');
  return json['registration'] as Map<String, dynamic>?;
}

Future<ExportFile> downloadBusinessCertificate(
  String filename,
  String mimeType,
) async => ExportFile(
  await ApiClient.instance.getBytes('/business/registration/certificate'),
  filename.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_'),
  mimeType,
);

Future<ExportFile> exportBusinessArchive() async => ExportFile(
  await ApiClient.instance.getBytes('/business/archive'),
  'tevel-business-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.zip',
  'application/zip',
);
