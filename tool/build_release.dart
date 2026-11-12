import 'dart:io';

import 'package:invoice/api/environment.dart';

/// Builds a reviewable artifact; never uploads to App Store Connect.
Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--unsigned')) {
    stderr.writeln('Usage: dart run tool/build_release.dart [--unsigned]');
    exitCode = 64;
    return;
  }
  final String origin;
  try {
    origin = productionApiUri(
      Platform.environment['API_BASE'] ?? 'https://invoice.crm.tevel.space',
    ).toString();
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final auth = SupabaseAuthSettings(
    url: Platform.environment['SUPABASE_AUTH_URL'] ?? '',
    publishableKey: Platform.environment['SUPABASE_AUTH_PUBLISHABLE_KEY'] ?? '',
  );
  try {
    if (auth.enabled) auth.origin;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final flutter = Platform.environment['FLUTTER_BIN'] ?? 'flutter';
  final unsigned = args.contains('--unsigned');
  final commands = <List<String>>[
    ['analyze', '--no-pub'],
    // The widget suite performs real filesystem work. Run files serially so
    // machine load cannot race its platform callbacks against frame pumping.
    ['test', '--no-pub', '--concurrency=1'],
    [
      'build',
      'ipa',
      '--release',
      '--no-pub',
      '--target=lib/main.dart',
      '--dart-define=API_BASE=$origin',
      if (auth.enabled) ...[
        '--dart-define=SUPABASE_AUTH_URL=${auth.origin}',
        '--dart-define=SUPABASE_AUTH_PUBLISHABLE_KEY=${auth.publishableKey}',
      ],
      if (unsigned)
        '--no-codesign'
      else
        '--export-options-plist=${Platform.environment['EXPORT_OPTIONS_PLIST'] ?? 'apple-review/ExportOptions.manual.plist'}',
    ],
  ];
  late DateTime buildStarted;
  for (final command in commands) {
    if (command.first == 'build') buildStarted = DateTime.now().toUtc();
    final process = await Process.start(
      flutter,
      command,
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      stderr.writeln('Release blocked: flutter ${command.first} failed.');
      exitCode = result;
      return;
    }
  }
  // Flutter can report an exportArchive error after successfully archiving.
  // Never accept an older IPA left in build/ as this run's output.
  final output = Directory('${root.path}/build/ios/ipa');
  final candidates = unsigned
      ? <File>[
          File('${root.path}/build/ios/archive/Runner.xcarchive/Info.plist'),
        ]
      : output.existsSync()
      ? output
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.ipa'))
            .toList()
      : <File>[];
  final freshArtifact = candidates.any(
    (file) =>
        file.existsSync() &&
        file.lastModifiedSync().toUtc().isAfter(
          buildStarted.subtract(const Duration(seconds: 1)),
        ),
  );
  if (!freshArtifact) {
    stderr.writeln(
      'Release blocked: no fresh ${unsigned ? 'archive' : 'IPA'} was produced.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Release artifact built from lib/main.dart for $origin.');
  stdout.writeln('Nothing was uploaded or submitted to Apple.');
}
