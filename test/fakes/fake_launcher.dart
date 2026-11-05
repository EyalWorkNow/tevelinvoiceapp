// Records every URL the app opens instead of launching it (INT; AT-10, AT-95).

import 'package:invoice/util/allowed_urls.dart';

class FakeLauncher {
  final List<Uri> opened = [];
  final List<Uri> inApp = [];

  /// Answer the app gets (false = "could not open").
  bool result = true;

  Uri? get last => opened.isEmpty ? null : opened.last;

  /// Replaces [urlOpener]; undo with [uninstall] (or addTearDown).
  void install() {
    urlOpener = (uri, {inApp = false}) async {
      (inApp ? this.inApp : opened).add(uri);
      return result;
    };
  }

  static void uninstall() => urlOpener = defaultUrlOpener;
}
