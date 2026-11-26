// Screenshot handshake with the host (simulator only): the test writes the
// shot name to [shotRequestPath]; the host script takes `simctl io screenshot`
// and deletes the file. Falls back to the SHOT: print when nobody listens.
import 'dart:io';

const shotRequestPath = String.fromEnvironment(
  'SHOT_REQUEST',
  defaultValue: '/tmp/tevel-shot-request',
);

Future<void> hostShot(String name) async {
  // ignore: avoid_print
  print('SHOT:$name');
  final f = File(shotRequestPath);
  try {
    f.writeAsStringSync(name);
  } on Object {
    return;
  }
  for (var i = 0; i < 100 && f.existsSync(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
