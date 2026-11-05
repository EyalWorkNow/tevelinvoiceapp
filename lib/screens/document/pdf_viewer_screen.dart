import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../ui/theme.dart';
import '../../util/labels/labels.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Full-screen PDF with pinch zoom (opened from the S6 preview).
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.bytes, required this.title});

  final Uint8List bytes;
  final String title;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _controller =
      PdfControllerPinch(document: PdfDocument.openData(widget.bytes));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: DocumentHe.pdfClose,
          icon: const Icon(Iconsax.close_circle),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      backgroundColor: context.palette.canvas,
      body: Semantics(
        label: 'תצוגת המסמך. אפשר להגדיל בצביטה',
        child: PdfViewPinch(
          controller: _controller,
          padding: Space.s,
          backgroundDecoration: BoxDecoration(color: context.palette.canvas),
        ),
      ),
    );
  }
}
