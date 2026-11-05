// Barrel (INT). Append-only: ONE export line per fake file.
//
//   import 'fakes/fake_api.dart';
//   final backend = FakeBackend()..install();
//   await signInAs(backend, Preset.employee, businessType: 'OSEK_PATUR');
export 'actions_fake.dart';
export 'business_fake.dart';
export 'fake_backend.dart';
export 'fake_launcher.dart';
export 'inbox_fake.dart';
export 'issue_fake.dart';
export 'me_fixtures.dart';
export 'people_fake.dart';
