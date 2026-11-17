// Walkthrough driver (QA 2026-11-17): an INTERACTIVE remote control for a
// human-style walkthrough of the whole app. Testing only — no app code changes.
//
// The test starts the app (signed out, like a fresh install or a returning
// user) and then waits for command batches written by the host:
//   $CMD_DIR/cmd-<n>.json  = [ {"tap":"כניסה"}, {"enter":[0,"a@b.c"]}, {"shot":"x"}, ... ]
// and answers with $CMD_DIR/res-<n>.json: a log per action, the texts on the
// screen (with centres), the focused field, and every framework error
// (overflows, exceptions) that happened during the batch.
// A "shot" prints SHOT:<name>; the host loop saves `simctl io screenshot`.
//
// Run:
//   flutter test integration_test/walkthrough_driver_test.dart -d INT \
//     --dart-define=API_BASE=http://127.0.0.1:3051 \
//     --dart-define=MAILDIR=$HOME/invoiceproject-staging-int/mail \
//     --dart-define=CMD_DIR=<host dir>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:invoice/api/client.dart';
import 'package:invoice/main.dart' as app;
import 'package:invoice/router.dart' show navigatorKey, go;
import 'package:invoice/screens/document/sheets/s6_share.dart'
    show pdfSharer, textSharer;
import 'package:invoice/state/cache.dart';
import 'package:invoice/state/session.dart';
import 'package:invoice/ui/widgets/keypad.dart';
import 'package:invoice/util/allowed_urls.dart' show urlOpener;

import 'package:invoice/screens/auth/business_certificate_picker.dart';
import 'package:invoice/api/business_registration_api.dart';

import 'package:invoice/screens/people/import/customer_import_screen.dart'
    show pickImportFile, PickedImportFile, shareImportFile;
import 'package:invoice/screens/business/sheets/editor_configs.dart'
    show logoPicker;

import 'package:invoice/screens/expense/expense_capture_screen.dart';

import 'qa_compose_helpers.dart' as qa show devUser;

const String cmdDir = String.fromEnvironment('CMD_DIR');
const String mailDir = String.fromEnvironment('MAILDIR');

late WidgetTester t;
final List<String> errors = [];
final List<String> externals = [];
String step = 'start';

const FlutterSecureStorage keychain = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

Future<void> pumpMs(int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

class _OfflineClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    throw const SocketException('Network is unreachable (walkthrough)');
  }
}

http.Client? _realClient;

Finder byText(String s, {bool contains = false}) {
  if (s.startsWith('key:')) return find.byKey(ValueKey<String>(s.substring(4)));
  if (s.startsWith('tip:')) return find.byTooltip(s.substring(4));
  if (s.startsWith('sem:')) return find.bySemanticsLabel(s.substring(4));
  if (s.startsWith('~')) return find.textContaining(s.substring(1));
  if (s.startsWith('icon:')) {
    final name = s.substring(5);
    return find.byWidgetPredicate(
      (w) => w is Icon && w.icon != null && _iconName(w.icon!) == name,
    );
  }
  return contains ? find.textContaining(s) : find.text(s);
}

String _iconName(IconData d) => '${d.codePoint.toRadixString(16)}';

Finder pick(Finder f, int? index) {
  final ht = f.hitTestable();
  final use = ht.evaluate().isNotEmpty ? ht : f;
  if (index == null) return use.first;
  if (index < 0) return use.last;
  return use.at(index);
}

Future<Finder> waitFinder(Finder f, int ms) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    if (f.evaluate().isNotEmpty) return f;
    await t.pump(const Duration(milliseconds: 100));
  }
  return f;
}

List<Element> _editables() =>
    find.byType(EditableText).hitTestable().evaluate().toList();

String focusInfo() {
  final f = FocusManager.instance.primaryFocus;
  if (f == null || f.context == null) return 'none';
  EditableText? et;
  f.context!.visitAncestorElements((e) {
    if (e.widget is EditableText) {
      et = e.widget as EditableText;
      return false;
    }
    return true;
  });
  if (et == null) {
    // The focus node may belong to an EditableText below the context.
    void walk(Element e) {
      if (et != null) return;
      if (e.widget is EditableText &&
          (e.widget as EditableText).focusNode == f) {
        et = e.widget as EditableText;
        return;
      }
      e.visitChildren(walk);
    }

    (f.context! as Element).visitChildren(walk);
  }
  if (et == null)
    return 'non-text:${f.debugLabel ?? f.context!.widget.runtimeType}';
  return 'TEXT kb=${et!.keyboardType.toJson()['name']} '
      'dec=${et!.keyboardType.toJson()['decimal']} '
      'value="${et!.controller.text}"';
}

List<String> screenTexts() {
  final out = <String>[];
  final seen = <String>{};
  final size = t.view.physicalSize / t.view.devicePixelRatio;
  for (final e in find.byType(RichText).hitTestable().evaluate()) {
    final w = e.widget as RichText;
    final s = w.text.toPlainText().replaceAll('\n', '⏎').trim();
    if (s.isEmpty) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final c = ro.localToGlobal(ro.size.center(Offset.zero));
    if (c.dx < 0 || c.dy < 0 || c.dx > size.width || c.dy > size.height) {
      continue;
    }
    final k = '$s@${c.dx.round()},${c.dy.round()}';
    if (seen.add(k)) out.add(k);
  }
  for (final e in _editables()) {
    final w = e.widget as EditableText;
    out.add(
      '[field:"${w.controller.text}" kb=${w.keyboardType.toJson()['name']}]',
    );
  }
  for (final e in find.byType(Tooltip).hitTestable().evaluate()) {
    final w = e.widget as Tooltip;
    if (w.message != null) out.add('{tip:${w.message}}');
  }
  return out;
}

/// Tappable semantics nodes without a label (VoiceOver would say "button").
List<String> unlabeledButtons() {
  final owner = t.binding.rootPipelineOwner;
  final out = <String>[];
  void visitOwner(PipelineOwner o) {
    final root = o.semanticsOwner?.rootSemanticsNode;
    if (root != null) {
      void v(SemanticsNode n) {
        final d = n.getSemanticsData();
        final tappable = d.hasAction(SemanticsAction.tap);
        if (tappable &&
            d.label.trim().isEmpty &&
            d.tooltip.trim().isEmpty &&
            d.value.trim().isEmpty &&
            !n.isInvisible) {
          final r = n.rect;
          out.add(
            'unlabeled tap @ ${r.center.dx.round()},${r.center.dy.round()} '
            'size ${r.width.round()}x${r.height.round()}',
          );
        }
        n.visitChildren((c) {
          v(c);
          return true;
        });
      }

      v(root);
    }
    o.visitChildren(visitOwner);
  }

  visitOwner(owner);
  return out;
}

Future<void> coldStart({bool wipe = false}) async {
  await t.runAsync(() async {
    if (wipe) {
      await AppCache.clearAll();
      await keychain.deleteAll();
      await AppCache.isFirstLaunch();
      await keychain.write(key: 'biometric_enabled', value: '0');
    }
  });
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 300));
  ApiClient.instance.clearCredentials();
  session
    ..status = SessionStatus.unknown
    ..expired = false
    ..offline = false
    ..account = null
    ..business = null
    ..me = null
    ..profile = null
    ..meFetchedAt = null;
  app.main();
  await pumpMs(4000);
}

Future<String?> latestCode(String to, DateTime since) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    final dir = Directory(mailDir);
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    for (final f in files) {
      if (f.statSync().modified.isBefore(since)) break;
      try {
        final m = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final subject = '${m['subject']}';
        if ('${m['to']}'.toLowerCase() == to.toLowerCase() &&
            RegExp(r'^\d{6}').hasMatch(subject)) {
          return subject.substring(0, 6);
        }
      } on Object {
        // being written
      }
    }
    await t.pump(const Duration(milliseconds: 300));
  }
  return null;
}

Future<String> runAction(Map<String, dynamic> a) async {
  final idx = a['i'] as int?;
  final wait = (a['wait'] as int?) ?? 600;
  if (a.containsKey('tap')) {
    final f = await waitFinder(
      byText('${a['tap']}', contains: a['c'] == true),
      (a['timeout'] as int?) ?? 6000,
    );
    if (f.evaluate().isEmpty) return 'NOT FOUND tap ${a['tap']}';
    final p = pick(f, idx);
    await t.ensureVisible(p).catchError((_) {});
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(p, warnIfMissed: false);
    await pumpMs(wait);
    return 'tapped ${a['tap']}';
  }
  if (a.containsKey('double')) {
    final p = pick(byText('${a['double']}'), idx);
    await t.tap(p, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 40));
    await t.tap(p, warnIfMissed: false);
    await pumpMs(wait);
    return 'double-tapped ${a['double']}';
  }
  if (a.containsKey('long')) {
    final p = pick(byText('${a['long']}'), idx);
    await t.longPress(p, warnIfMissed: false);
    await pumpMs(wait);
    return 'long-pressed ${a['long']}';
  }
  if (a.containsKey('tapAt')) {
    final xy = (a['tapAt'] as List).cast<num>();
    await t.tapAt(Offset(xy[0].toDouble(), xy[1].toDouble()));
    await pumpMs(wait);
    return 'tapAt $xy';
  }
  if (a.containsKey('enter')) {
    // [index among visible fields | label text, value]
    final spec = a['enter'] as List;
    Finder target;
    if (spec[0] is int) {
      final els = _editables();
      if ((spec[0] as int) >= els.length)
        return 'NO FIELD ${spec[0]} (have ${els.length})';
      final el = els[spec[0] as int];
      target = find.byElementPredicate((e) => identical(e, el));
    } else {
      final lab = byText('${spec[0]}');
      target = find.ancestor(of: lab, matching: find.byType(TextField));
      if (target.evaluate().isEmpty) {
        target = find.ancestor(of: lab, matching: find.byType(EditableText));
      }
      if (target.evaluate().isEmpty) return 'NO FIELD labelled ${spec[0]}';
      target = find.descendant(
        of: target.first,
        matching: find.byType(EditableText),
      );
    }
    await t.ensureVisible(target.first).catchError((_) {});
    await t.tap(target.first, warnIfMissed: false);
    await pumpMs(300);
    await t.enterText(target.first, '${spec[1]}');
    await pumpMs(wait);
    final els2 = target.evaluate();
    if (els2.isEmpty) return 'entered "${spec[1]}" (field gone after entry)';
    final et = els2.first.widget as EditableText;
    return 'entered "${spec[1]}" → now "${et.controller.text}" kb=${et.keyboardType.toJson()['name']}';
  }
  if (a.containsKey('keypad')) {
    for (final ch in '${a['keypad']}'.split('')) {
      if (ch == '<') {
        await t.tap(
          find
              .descendant(
                of: find.byType(Keypad),
                matching: find.byIcon(Icons.backspace_outlined),
              )
              .first,
        );
      } else {
        final k = find.descendant(
          of: find.byType(Keypad),
          matching: find.text(ch),
        );
        if (k.evaluate().isEmpty) return 'keypad has no "$ch"';
        await t.tap(k.first);
      }
      await t.pump(const Duration(milliseconds: 80));
    }
    await pumpMs(wait);
    return 'keypad ${a['keypad']}';
  }
  if (a.containsKey('go')) {
    unawaited(go('${a['go']}'));
    await pumpMs((a['wait'] as int?) ?? 2500);
    return 'go ${a['go']}';
  }
  if (a.containsKey('back')) {
    final nav = navigatorKey.currentState!;
    final bb = find.byType(BackButton).hitTestable();
    if (a['back'] == 'button' && bb.evaluate().isNotEmpty) {
      await t.tap(bb.first);
    } else {
      await nav.maybePop();
    }
    await pumpMs(wait);
    return 'back';
  }
  if (a.containsKey('swipeBack')) {
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    // RTL: the iOS back edge follows the text direction: from the right.
    final fromRight = a['swipeBack'] != 'left';
    final start = Offset(fromRight ? size.width - 2 : 2, size.height / 2);
    final g = await t.startGesture(start);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset((fromRight ? -1 : 1) * size.width / 14, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await pumpMs(wait);
    return 'swipe back from ${fromRight ? 'right' : 'left'}';
  }
  if (a.containsKey('drag')) {
    final spec = a['drag'] as List; // [text|null, dx, dy]
    final from = spec[0] == null
        ? (t.view.physicalSize / t.view.devicePixelRatio).center(Offset.zero)
        : t.getCenter(pick(byText('${spec[0]}'), idx));
    await t.dragFrom(
      from,
      Offset((spec[1] as num).toDouble(), (spec[2] as num).toDouble()),
    );
    await pumpMs(wait);
    return 'dragged';
  }
  if (a.containsKey('scrollTo')) {
    final target = byText('${a['scrollTo']}');
    for (var i = 0; i < 25 && target.hitTestable().evaluate().isEmpty; i++) {
      final sc = find.byType(Scrollable).hitTestable();
      if (sc.evaluate().isEmpty) break;
      await t.drag(
        sc.last,
        Offset(0, (a['up'] == true) ? 300 : -300),
        warnIfMissed: false,
      );
      await pumpMs(250);
    }
    if (target.evaluate().isNotEmpty) {
      await t.ensureVisible(target.first).catchError((_) {});
      await pumpMs(300);
    }
    return target.hitTestable().evaluate().isEmpty
        ? 'NOT FOUND scroll ${a['scrollTo']}'
        : 'scrolled to ${a['scrollTo']}';
  }
  if (a.containsKey('shot')) {
    // Host saves the screenshot on this line; give it time.
    await pumpMs(500);
    // ignore: avoid_print
    print('SHOT:${a['shot']}');
    await pumpMs(1800);
    return 'shot ${a['shot']}';
  }
  if (a.containsKey('pump')) {
    await pumpMs(a['pump'] as int);
    return 'waited';
  }
  if (a.containsKey('waitFor')) {
    final f = await waitFinder(
      byText('${a['waitFor']}'),
      (a['timeout'] as int?) ?? 20000,
    );
    return f.evaluate().isEmpty
        ? 'TIMEOUT waiting ${a['waitFor']}'
        : 'found ${a['waitFor']}';
  }
  if (a.containsKey('unfocus')) {
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpMs(300);
    return 'unfocused';
  }
  if (a.containsKey('focus')) return 'focus: ${focusInfo()}';
  if (a.containsKey('signin')) {
    // Returning user: token in the Keychain (no login UI / iOS save-password alert).
    final biz = a['biz'] as String?;
    final u = await t.runAsync(
      () => biz == null
          ? qa.devUser('${a['signin']}')
          : qa.devUser('${a['signin']}', businessId: biz),
    );
    await t.runAsync(() async {
      await AppCache.isFirstLaunch();
      await AppCache.clearAll();
      await keychain.write(key: 'biometric_enabled', value: '0');
      await keychain.write(key: 'device_token', value: u!.token);
      await keychain.write(key: 'business_id', value: u.businessId);
    });
    await coldStart();
    await pumpMs((a['wait'] as int?) ?? 3000);
    return 'signed in ${a['signin']} (${u!.businessId})';
  }
  if (a.containsKey('certInject')) {
    // The native photo/PDF picker cannot be driven: hand the app a file.
    final bytes = File('${a['certInject']}').readAsBytesSync();
    final pdf = '${a['certInject']}'.endsWith('.pdf');
    pickBusinessCertificate = (ctx) async => BusinessCertificateFile(
      bytes: bytes,
      filename: pdf ? 'business-certificate.pdf' : 'business-certificate.jpg',
      mimeType: pdf ? 'application/pdf' : 'image/jpeg',
    );
    return 'cert picker → ${bytes.length} bytes';
  }
  if (a.containsKey('importInject')) {
    final path = '${a['importInject']}';
    final bytes = File(path).readAsBytesSync();
    pickImportFile = () async => PickedImportFile(path.split('/').last, bytes);
    return 'import picker → ${path.split('/').last}';
  }
  if (a.containsKey('logoInject')) {
    final bytes = File('${a['logoInject']}').readAsBytesSync();
    logoPicker = () async => bytes;
    return 'logo picker → ${bytes.length} bytes';
  }
  if (a.containsKey('expenseNoCamera')) {
    // The capture screen as it is when the camera is unavailable; PDF from a file.
    final path = '${a['expenseNoCamera']}';
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ExpenseCaptureScreen(
            autoOpenCamera: false,
            pickPdf: () async => File(path).readAsBytesSync(),
          ),
        ),
      ),
    );
    await pumpMs(2000);
    return 'expense capture (no camera) pushed';
  }
  if (a.containsKey('cold')) {
    await coldStart(wipe: a['cold'] == 'wipe');
    return 'cold start ${a['cold']}';
  }
  if (a.containsKey('mfa')) {
    final since = DateTime.now().subtract(
      Duration(seconds: (a['since'] as int?) ?? 60),
    );
    final code = await latestCode('${a['mfa']}', since);
    if (code == null) return 'no code mail';
    final boxes = find.byType(EditableText).hitTestable();
    await t.enterText(boxes.first, code);
    await pumpMs(wait);
    return 'entered code $code';
  }
  if (a.containsKey('offline')) {
    if (a['offline'] == true) {
      _realClient ??= ApiClient.instance.httpClient;
      ApiClient.instance.httpClient = _OfflineClient();
    } else if (_realClient != null) {
      ApiClient.instance.httpClient = _realClient!;
    }
    return 'offline=${a['offline']}';
  }
  if (a.containsKey('size')) {
    final s = (a['size'] as List).cast<num>();
    t.view.devicePixelRatio = 2;
    t.view.physicalSize = Size(s[0] * 2.0, s[1] * 2.0);
    await pumpMs(wait);
    return 'size $s';
  }
  if (a.containsKey('resetSize')) {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    await pumpMs(wait);
    return 'size reset';
  }
  if (a.containsKey('dark')) {
    t.platformDispatcher.platformBrightnessTestValue = a['dark'] == true
        ? Brightness.dark
        : Brightness.light;
    await pumpMs(wait);
    return 'dark=${a['dark']}';
  }
  if (a.containsKey('textScale')) {
    t.platformDispatcher.textScaleFactorTestValue = (a['textScale'] as num)
        .toDouble();
    await pumpMs(wait);
    return 'textScale ${a['textScale']}';
  }
  if (a.containsKey('lifecycle')) {
    final b = t.binding;
    b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await Future<void>.delayed(
      Duration(milliseconds: (a['lifecycle'] as int?) ?? 1500),
    );
    b.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    b.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpMs(wait);
    return 'background+resume';
  }
  if (a.containsKey('a11y')) return 'a11y: ${unlabeledButtons().join(' | ')}';
  if (a.containsKey('externals')) {
    final s = externals.join(' || ');
    externals.clear();
    return 'externals: $s';
  }
  if (a.containsKey('route')) {
    final nav = navigatorKey.currentState;
    String? top;
    nav?.popUntil((r) {
      top = r.settings.name;
      return true;
    });
    return 'top route ${top ?? '?'} / ${find.byType(Scaffold).evaluate().map((e) => e.findAncestorWidgetOfExactType<Scaffold>()?.runtimeType).length} scaffolds';
  }
  if (a.containsKey('hitIcons')) {
    // icons on screen (codepoint hex) with centres, to tap by icon:<hex>
    final out = <String>[];
    for (final e in find.byType(Icon).hitTestable().evaluate()) {
      final w = e.widget as Icon;
      if (w.icon == null) continue;
      final c = t.getCenter(find.byWidget(w).first);
      out.add('${_iconName(w.icon!)}@${c.dx.round()},${c.dy.round()}');
    }
    return 'icons: ${out.join(' ')}';
  }
  return 'UNKNOWN action $a';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  urlOpener = (uri, {inApp = false}) async {
    externals.add('url $uri');
    return true;
  };
  pdfSharer = (bytes, name, {text}) async {
    externals.add('pdf $name (${bytes.length} bytes) text=$text');
    try {
      File('$cmdDir/$name').writeAsBytesSync(bytes);
    } on Object {
      // ignore
    }
  };
  textSharer = (text) async => externals.add('text $text');
  shareImportFile = (bytes, name, mime) async {
    externals.add('file $name (${bytes.length} bytes)');
    try {
      File('$cmdDir/$name').writeAsBytesSync(bytes);
    } on Object {
      // ignore
    }
  };

  testWidgets('walkthrough driver', (tester) async {
    t = tester;
    tester.ensureSemantics();
    final origOnError = FlutterError.onError;
    final origPlat = PlatformDispatcher.instance.onError;
    FlutterError.onError = (d) {
      final where = d
          .toString()
          .split('\n')
          .where((l) => l.contains('file:///') || l.contains('relevant'))
          .take(3)
          .join(' / ');
      errors.add(
        '[$step] ${d.exceptionAsString().split('\n').take(3).join(' ')} $where',
      );
    };
    PlatformDispatcher.instance.onError = (e, st) {
      errors.add(
        '[$step] uncaught $e ${st.toString().split('\n').take(4).join(' / ')}',
      );
      return true;
    };
    final done = Completer<void>();
    runZonedGuarded(
      () async {
        await coldStart(wipe: !const bool.fromEnvironment('KEEP'));
        var n = 1;
        while (true) {
          final f = File('$cmdDir/cmd-$n.json');
          if (!f.existsSync()) {
            await t.pump(const Duration(milliseconds: 250));
            continue;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
          List<dynamic> actions;
          try {
            actions = jsonDecode(f.readAsStringSync()) as List<dynamic>;
          } on Object catch (e) {
            File(
              '$cmdDir/res-$n.json',
            ).writeAsStringSync(jsonEncode({'bad': '$e'}));
            n++;
            continue;
          }
          final log = <String>[];
          var quit = false;
          var noDump = false;
          for (final raw in actions) {
            final a = (raw as Map).cast<String, dynamic>();
            if (a.containsKey('quit')) {
              quit = true;
              break;
            }
            if (a.containsKey('nodump')) {
              noDump = true;
              continue;
            }
            step = 'cmd$n:${jsonEncode(a)}';
            try {
              log.add(await runAction(a));
            } on Object catch (e) {
              log.add(
                'ERROR $a: ${e.toString().split('\n').take(3).join(' ')}',
              );
            }
          }
          final res = {
            'log': log,
            'errors': List<String>.from(errors),
            'externals': List<String>.from(externals),
            'focus': focusInfo(),
            if (!noDump) 'screen': screenTexts(),
          };
          errors.clear();
          File(
            '$cmdDir/res-$n.json',
          ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(res));
          n++;
          if (quit) break;
        }
        done.complete();
      },
      (e, st) => errors.add(
        '[$step] zone $e ${st.toString().split('\n').take(4).join(' / ')}',
      ),
    );
    await done.future;
    FlutterError.onError = origOnError;
    PlatformDispatcher.instance.onError = origPlat;
  }, timeout: const Timeout(Duration(hours: 8)));
}
