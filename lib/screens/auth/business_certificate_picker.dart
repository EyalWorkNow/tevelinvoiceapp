import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/business_registration_api.dart';
import '../../api/expenses_api.dart' show prepareExpenseJpeg, isPdf;

/// Injectable, using the same native document/image pickers as expense capture.
Future<BusinessCertificateFile?> Function(BuildContext context)
pickBusinessCertificate = _pick;

Future<BusinessCertificateFile?> _pick(BuildContext context) async {
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('צילום תעודת עסק'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('בחירת תמונה'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('בחירת קובץ PDF'),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final BusinessCertificateFile file;
  if (source == 'pdf') {
    final bytes = await const MethodChannel(
      'tevel/pdf_picker',
    ).invokeMethod<Uint8List>('pickPdf');
    if (bytes == null) return null;
    if (!isPdf(bytes)) {
      throw const BusinessRegistrationInputException('יש לבחור קובץ PDF תקין');
    }
    file = BusinessCertificateFile(
      bytes: bytes,
      filename: 'business-certificate.pdf',
      mimeType: 'application/pdf',
    );
  } else {
    final image = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    file = BusinessCertificateFile(
      bytes: await prepareExpenseJpeg(await image.readAsBytes()),
      filename: 'business-certificate.jpg',
      mimeType: 'image/jpeg',
    );
  }
  if (file.bytes.length > maxBusinessCertificateBytes) {
    throw const BusinessRegistrationInputException(
      'הקובץ גדול מדי. הגודל המרבי הוא 4 MB',
    );
  }
  return file;
}
