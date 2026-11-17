// "החתימה שלי": the member draws their signature with a finger; the server
// prints it at the bottom of the quotes they send (with their name and the
// business's ח.פ./ע.מ.). Reachable from "החשבון שלי" and "עיצוב המסמכים",
// and offered once on the first quote sent without one.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../api/signature_api.dart';
import '../../state/cache.dart';
import '../../state/session.dart';
import '../../ui/ds.dart';
import '../../util/labels/signature_he.dart';
import '../document/dialogs.dart' show toast;

const Color signatureInk = Color(0xFF1B2440);

/// Exported PNG size (logical ~600×200; trimmed to the ink and centred).
const Size signatureExportSize = Size(600, 200);

/// A smooth path through [points] (midpoint quadratic curves).
Path signaturePath(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) {
    path.lineTo(points.first.dx + .01, points.first.dy + .01);
    return path;
  }
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset(
      (points[i].dx + points[i + 1].dx) / 2,
      (points[i].dy + points[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  return path;
}

Paint _pen(double width) => Paint()
  ..color = signatureInk
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..style = PaintingStyle.stroke
  ..isAntiAlias = true;

/// The strokes as a PNG on a transparent background: whitespace trimmed,
/// the ink scaled to fit [size] and centred. Null when nothing was drawn.
Future<Uint8List?> exportSignaturePng(
  List<List<Offset>> strokes, {
  double strokeWidth = 3,
  Size size = signatureExportSize,
}) async {
  final points = [for (final s in strokes) ...s];
  if (points.isEmpty) return null;
  var bounds = Rect.fromPoints(points.first, points.first);
  for (final p in points) {
    bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
  }
  bounds = bounds.inflate(strokeWidth);
  final scale = math.min(
    4.0,
    math.min(
      size.width * .94 / bounds.width,
      size.height * .88 / bounds.height,
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas
    ..translate(size.width / 2, size.height / 2)
    ..scale(scale)
    ..translate(-bounds.center.dx, -bounds.center.dy);
  final pen = _pen((strokeWidth * scale).clamp(2.5, 7.0) / scale);
  for (final s in strokes) {
    canvas.drawPath(signaturePath(s), pen);
  }
  final image = await recorder.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// The white drawing pad. It claims every touch at once, so neither a
/// scroll view nor the back swipe takes a stroke away.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.controller});

  final SignatureController controller;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];

  bool get isEmpty => strokes.every((s) => s.isEmpty);

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  void _start(Offset p) {
    strokes.add([p]);
    notifyListeners();
  }

  void _add(Offset p) {
    if (strokes.isEmpty) return;
    final last = strokes.last;
    if (last.isNotEmpty && (last.last - p).distanceSquared < 1) return;
    last.add(p);
    notifyListeners();
  }
}

class _SignaturePadState extends State<SignaturePad> {
  int? _pointer;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      EagerGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            EagerGestureRecognizer.new,
            (_) {},
          ),
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_pointer != null) return; // one finger draws
        _pointer = e.pointer;
        widget.controller._start(e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _pointer) widget.controller._add(e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer == _pointer) _pointer = null;
      },
      onPointerCancel: (e) {
        if (e.pointer == _pointer) _pointer = null;
      },
      child: ClipRect(
        child: CustomPaint(
          painter: _PadPainter(widget.controller),
          size: Size.infinite,
        ),
      ),
    ),
  );
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.controller) : super(repaint: controller);

  final SignatureController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = _pen(3);
    for (final s in controller.strokes) {
      canvas.drawPath(signaturePath(s), pen);
    }
  }

  @override
  bool shouldRepaint(_PadPainter old) => true;
}

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _pad = SignatureController();
  MySignature? _saved;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _pad.addListener(_rebuild);
    unawaited(_load());
  }

  @override
  void dispose() {
    _pad
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await fetchMySignature();
      if (mounted) setState(() => _saved = s);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_pad.isEmpty) {
      toast(context, SignatureHe.empty);
      return;
    }
    setState(() => _saving = true);
    try {
      final png = await exportSignaturePng(_pad.strokes);
      if (png == null) return;
      final saved = await saveMySignature(png);
      if (!mounted) return;
      _pad.clear();
      setState(() => _saved = saved);
      toast(context, SignatureHe.saved);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(SignatureHe.deleteTitle),
            content: const Text(SignatureHe.deleteBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(SignatureHe.keep),
              ),
              TextButton(
                key: const Key('signature-delete-yes'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(SignatureHe.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!yes || !mounted) return;
    setState(() => _saving = true);
    try {
      await deleteMySignature();
      if (!mounted) return;
      setState(() => _saved = null);
      toast(context, SignatureHe.deleted);
    } on Object catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.page,
                Space.m,
                Space.page,
                Space.s,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        SignatureHe.title,
                        style: AppText.displayTitle,
                      ),
                    ),
                  ),
                  const DesignBackButton(),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                // The pad claims its own touches; the page scrolls elsewhere.
                padding: const EdgeInsets.fromLTRB(
                  Space.page,
                  Space.s,
                  Space.page,
                  Space.xl,
                ),
                children: [
                  Text(
                    SignatureHe.explain,
                    style: AppText.secondary.copyWith(
                      color: p.muted,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  AspectRatio(
                    aspectRatio: 3 / 1.25,
                    child: Container(
                      key: const Key('signature-pad'),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.line, width: 1.2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          // Signing line.
                          PositionedDirectional(
                            start: 24,
                            end: 24,
                            bottom: 34,
                            child: Container(
                              height: 1,
                              color: const Color(0xFFD5D8E0),
                            ),
                          ),
                          if (_pad.isEmpty)
                            const Center(
                              child: Text(
                                SignatureHe.padHint,
                                style: TextStyle(
                                  color: Color(0xFF9AA0AE),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: SignaturePad(controller: _pad),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.s),
                  Row(
                    children: [
                      TextButton.icon(
                        key: const Key('signature-clear'),
                        onPressed: _pad.isEmpty || _saving ? null : _pad.clear,
                        icon: const Icon(Iconsax.eraser_1),
                        label: const Text(SignatureHe.clear),
                      ),
                      const Spacer(),
                      if (_saved != null)
                        Flexible(
                          child: Text(
                            SignatureHe.replaceHint,
                            textAlign: TextAlign.end,
                            style: AppText.secondary.copyWith(color: p.muted),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  Text(SignatureHe.current, style: AppText.headline),
                  const SizedBox(height: Space.s),
                  if (_loading)
                    const SkeletonList(rows: 1)
                  else if (_error != null)
                    ErrorView(error: _error!, onRetry: _load)
                  else if (_saved == null)
                    Text(
                      SignatureHe.none,
                      key: const Key('signature-none'),
                      style: AppText.body.copyWith(color: p.muted),
                    )
                  else ...[
                    Container(
                      key: const Key('signature-saved'),
                      height: 110,
                      padding: const EdgeInsets.all(Space.s),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: p.line),
                      ),
                      child: Image.memory(
                        _saved!.png,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('signature-delete'),
                        onPressed: _saving ? null : _delete,
                        style: TextButton.styleFrom(foregroundColor: p.danger),
                        icon: const Icon(Iconsax.trash),
                        label: const Text(SignatureHe.delete),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            BottomActionArea(
              child: PrimaryButton(
                key: const Key('signature-save'),
                label: SignatureHe.save,
                loadingText: _saving ? SignatureHe.saving : null,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openSignatureScreen(BuildContext context) => Navigator.of(
  context,
).push<void>(MaterialPageRoute<void>(builder: (_) => const SignatureScreen()));

/// Replaceable in tests (the device cache is not set up in most of them).
Future<bool> Function(String name) signaturePromptSeen = (name) async =>
    await AppCache.read(name) == true;
Future<void> Function(String name) markSignaturePromptSeen = (name) =>
    AppCache.write(name, true);

/// Before a quote leaves: the first time the member sends one without a
/// saved signature, offer "הוסף חתימה" / "שלח בלי חתימה". Returns false
/// when the send should stop (dialog dismissed, screen gone). A server
/// without /me/signature, or no connection, never blocks a send.
Future<bool> ensureSignatureBeforeSend(BuildContext context) async {
  final flag = 'signature_prompted_${session.account?.userId ?? 'anon'}';
  try {
    if (await signaturePromptSeen(flag)) return true;
    if (await fetchMySignature() != null) return true;
  } on Object {
    return true;
  }
  if (!context.mounted) return false;
  final add = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(SignatureHe.promptTitle),
      content: const Text(SignatureHe.promptBody),
      actions: [
        TextButton(
          key: const Key('signature-prompt-skip'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text(SignatureHe.promptSkip),
        ),
        TextButton(
          key: const Key('signature-prompt-add'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(SignatureHe.promptAdd),
        ),
      ],
    ),
  );
  if (add == null) return false;
  try {
    await markSignaturePromptSeen(flag);
  } on Object {
    // best effort: at worst the question comes once more
  }
  if (add && context.mounted) await openSignatureScreen(context);
  return context.mounted;
}
