import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/client.dart';
import '../../api/expenses_api.dart';
import '../../api/models/models.dart';
import '../../router.dart' show openExpenses;
import '../../state/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/big_button.dart';
import '../../ui/widgets/error_view.dart';
import '../../util/labels/common_he.dart';
import '../../util/allowed_urls.dart';
import '../../util/labels/people_he.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

enum _Step { choose, preparing, uploading, scanning, done, failed }

/// Native iOS document picker (ios/Runner/AppDelegate.swift): the picked
/// PDF's bytes, or null when cancelled. Needs no permission.
const _pdfChannel = MethodChannel('tevel/pdf_picker');

/// Set by P2 "הוצאה חדשה מ-X" right before opening the capture: the next
/// captured expense gets this supplier pre-filled in E (consumed once).
Supplier? nextCaptureSupplier;

/// expenseId → supplier chosen before the capture (read by E).
final Map<String, Supplier> captureSupplierHints = {};

/// Expense capture (kept from V1; SPEC-v2 §2.3 "שמור לכידה"): camera /
/// gallery → JPEG ≤ 4MB, or a PDF as-is → sha256 → initiate / PUT bytes /
/// complete / poll. V2: no preview step (J4 ≤4 taps: ＋ · הוצאה · צילום ·
/// אשר) — the upload starts as soon as a file is picked, and a received
/// expense replaces this screen with its review card in E.
class ExpenseCaptureScreen extends StatefulWidget {
  const ExpenseCaptureScreen(
      {super.key, this.picker, this.pickPdf, this.autoOpenCamera = true});

  /// Injectable for tests.
  final ImagePicker? picker;
  final Future<Uint8List?> Function()? pickPdf;

  /// Open the camera right away (one tap less, like bit's scan).
  final bool autoOpenCamera;

  @override
  State<ExpenseCaptureScreen> createState() => _ExpenseCaptureScreenState();
}

class _ExpenseCaptureScreenState extends State<ExpenseCaptureScreen> {
  late final ImagePicker _picker = widget.picker ?? ImagePicker();
  _Step _step = _Step.choose;
  Uint8List? _jpeg; // the PDF itself when [_isPdf]
  bool _isPdf = false;
  ExpenseUploadResult? _result;
  Object? _error;
  String? _pickProblem;
  bool _cameraDenied = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenCamera && !session.offline) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick(ImageSource.camera, quiet: true));
    }
  }

  Future<void> _pick(ImageSource source, {bool quiet = false}) async {
    setState(() {
      _pickProblem = null;
      _cameraDenied = false;
    });
    final XFile? file;
    try {
      // maxWidth + imageQuality make iOS hand back a JPEG (not HEIC).
      file = await _picker.pickImage(
        source: source,
        maxWidth: maxExpenseSide.toDouble(),
        maxHeight: maxExpenseSide.toDouble(),
        imageQuality: 85,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final denied = e.code.contains('access_denied');
      setState(() {
        _step = _Step.choose;
        _cameraDenied = denied && source == ImageSource.camera;
        if (!quiet || denied) {
          _pickProblem = denied
              ? (source == ImageSource.camera
                  ? ExpenseHe.noCameraAccess
                  : ExpenseHe.noPhotosAccess)
              : (source == ImageSource.camera
                  ? ExpenseHe.cameraUnavailable
                  : ExpenseHe.galleryFailed);
        }
      });
      return;
    }
    if (file == null || !mounted) return; // cancelled: stay on the chooser
    setState(() => _step = _Step.preparing);
    try {
      final jpeg = await prepareExpenseJpeg(await file.readAsBytes());
      if (!mounted) return;
      _jpeg = jpeg;
      _isPdf = false;
      await _send();
    } on Object {
      if (!mounted) return;
      setState(() {
        _step = _Step.choose;
        _pickProblem = ExpenseHe.imageUnreadable;
      });
    }
  }

  Future<void> _pickPdf() async {
    setState(() {
      _pickProblem = null;
      _cameraDenied = false;
    });
    final Uint8List? bytes;
    try {
      bytes = await (widget.pickPdf ?? () => _pdfChannel.invokeMethod<Uint8List>('pickPdf'))();
    } on Exception {
      // PlatformException, or MissingPluginException off iOS.
      if (mounted) setState(() => _pickProblem = ExpenseHe.filesFailed);
      return;
    }
    if (bytes == null || !mounted) return; // cancelled: stay on the chooser
    if (!isPdf(bytes) || bytes.length > maxExpensePdfBytes) {
      setState(() => _pickProblem = isPdf(bytes!)
          ? ExpenseHe.fileTooBig
          : ExpenseHe.pdfInvalid);
      return;
    }
    _jpeg = bytes;
    _isPdf = true;
    await _send();
  }

  Future<void> _send() async {
    final jpeg = _jpeg;
    if (jpeg == null) return;
    setState(() {
      _step = _Step.uploading;
      _error = null;
    });
    try {
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'receipt-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}${two(now.second)}.${_isPdf ? 'pdf' : 'jpg'}';
      final result = await uploadExpense(jpeg,
          filename: name,
          contentType: _isPdf ? 'application/pdf' : 'image/jpeg',
          // Closing the screen stops the scan polling (the upload is already in).
          cancelled: () => !mounted, onStage: (stage) {
        if (mounted && stage == ExpenseUploadStage.scanning) {
          setState(() => _step = _Step.scanning);
        }
      });
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final id = result.expenseId;
      final hint = nextCaptureSupplier;
      nextCaptureSupplier = null;
      if (id != null && !result.stillScanning) {
        await rememberMyExpense(id);
        if (hint != null) captureSupplierHints[id] = hint;
        if (!mounted) return;
        await openExpenses(context, expenseId: id, replace: true);
        return;
      }
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } on Object catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      setState(() {
        _error = e;
        _step = _Step.failed;
      });
    }
  }

  void _restart() => setState(() {
        _jpeg = null;
        _isPdf = false;
        _result = null;
        _error = null;
        _step = _Step.choose;
      });

  bool get _busy =>
      _step == _Step.preparing || _step == _Step.uploading || _step == _Step.scanning;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(ExpenseHe.captureTitle),
          leading: _busy
              ? null
              : IconButton(
                  tooltip: CommonHe.close,
                  icon: const Icon(Iconsax.close_circle),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(key: ValueKey(_step), child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final p = context.palette;
    switch (_step) {
      case _Step.choose:
        return _scrollColumn([
          const SizedBox(height: Space.xl),
          _Frame(child: Icon(Iconsax.receipt_item, size: 72, color: p.muted)),
          const SizedBox(height: Space.xl),
          Text(ExpenseHe.captureHeadline,
              style: AppText.title, textAlign: TextAlign.center),
          const SizedBox(height: Space.s),
          Text(ExpenseHe.captureSub,
              style: AppText.body.copyWith(color: p.muted), textAlign: TextAlign.center),
          if (_pickProblem != null) ...[
            const SizedBox(height: Space.l),
            Text(_pickProblem!,
                style: AppText.body.copyWith(color: p.warn), textAlign: TextAlign.center),
            if (_cameraDenied)
              TextButton(
                onPressed: () => launchAllowed(Uri.parse('app-settings:')),
                child: const Text(ExpenseHe.openSettings),
              ),
          ],
          if (session.offline) ...[
            const SizedBox(height: Space.l),
            Text(ExpenseHe.offlineCapture,
                style: AppText.body.copyWith(color: p.warn), textAlign: TextAlign.center),
          ],
          const SizedBox(height: Space.xxl),
          BigButton(
            label: ExpenseHe.shoot,
            icon: Iconsax.camera,
            onPressed: session.offline ? null : () => _pick(ImageSource.camera),
          ),
          const SizedBox(height: Space.m),
          BigButton(
            label: ExpenseHe.fromGallery,
            icon: Iconsax.gallery,
            variant: BigButtonVariant.secondary,
            onPressed: session.offline ? null : () => _pick(ImageSource.gallery),
          ),
          const SizedBox(height: Space.m),
          BigButton(
            label: ExpenseHe.pickPdf,
            icon: Iconsax.document_text,
            variant: BigButtonVariant.secondary,
            onPressed: session.offline ? null : _pickPdf,
          ),
        ]);
      case _Step.preparing:
        return const _Busy(text: ExpenseHe.preparing);
      case _Step.uploading:
        return const _Busy(text: ExpenseHe.uploading);
      case _Step.scanning:
        return const _Busy(text: ExpenseHe.scanning);
      case _Step.done:
        final r = _result!;
        return _scrollColumn([
          const SizedBox(height: Space.xxl),
          const _SuccessMark(),
          const SizedBox(height: Space.xl),
          Semantics(
            liveRegion: true,
            child: Text(r.stillScanning ? ExpenseHe.received : ExpenseHe.captured,
                style: AppText.title, textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.s),
          Text(
            r.stillScanning
                ? ExpenseHe.stillScanning
                : ExpenseHe.willAppear,
            style: AppText.body.copyWith(color: p.muted),
            textAlign: TextAlign.center,
          ),
          if (r.duplicate) ...[
            const SizedBox(height: Space.m),
            Text(ExpenseHe.uploadedBefore,
                style: AppText.body.copyWith(color: p.warn), textAlign: TextAlign.center),
          ],
          const SizedBox(height: Space.xxl),
          BigButton(label: ExpenseHe.finish, onPressed: () => Navigator.of(context).pop()),
          const SizedBox(height: Space.m),
          BigButton(
            label: ExpenseHe.captureAnother,
            icon: Iconsax.camera,
            variant: BigButtonVariant.secondary,
            onPressed: () {
              _restart();
              _pick(ImageSource.camera);
            },
          ),
        ]);
      case _Step.failed:
        final e = _error;
        final code = e is ApiException ? e.code : '';
        final blocked = code == 'SCANNER_INFECTED';
        final reshoot = blocked || code == 'UPLOAD_REJECTED';
        return _scrollColumn([
          const SizedBox(height: Space.xxl),
          Icon(blocked ? Iconsax.shield_cross : Iconsax.danger,
              size: 64, color: blocked ? p.danger : p.muted),
          const SizedBox(height: Space.l),
          Semantics(
            liveRegion: true,
            child: Text(
                blocked
                    ? ExpenseHe.blocked
                    : (e is ApiException && e.isNetwork ? CommonHe.offlineButton : ExpenseHe.sendFailed),
                style: AppText.title,
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: Space.s),
          Text(
            blocked ? ExpenseHe.blockedHint : errorTextHe(e ?? ''),
            style: AppText.body.copyWith(color: p.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xxl),
          if (!reshoot) ...[
            BigButton(label: CommonHe.retry, onPressed: _send),
            const SizedBox(height: Space.m),
          ],
          BigButton(
            label: ExpenseHe.reshoot,
            icon: Iconsax.camera,
            variant: reshoot ? BigButtonVariant.primary : BigButtonVariant.secondary,
            onPressed: () {
              _restart();
              _pick(ImageSource.camera);
            },
          ),
        ]);
    }
  }

  Widget _scrollColumn(List<Widget> children) => SingleChildScrollView(
        padding: const EdgeInsets.all(Space.page),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// Dashed-feel receipt frame (visual guide).
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Container(
        width: 160,
        height: 200,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: p.line, width: 2),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: text,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Space.l),
            Text(text, style: AppText.headline, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SuccessMark extends StatelessWidget {
  const _SuccessMark();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduce ? 1 : 0.4, end: 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: CircleAvatar(
          radius: 44,
          backgroundColor: p.accent,
          child: Icon(Iconsax.tick_circle, size: 52, color: p.accentInk),
        ),
      ),
    );
  }
}
