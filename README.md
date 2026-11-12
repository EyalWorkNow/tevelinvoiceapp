# Tevel Invoice for iPhone

Invoicing, expenses, CRM and business reports. The API and outbox worker live in the existing invoiceproject repository.

## Getting Started

After building the backend, run its supervised local installer `/usr/bin/python3 ops/install-mobile-dev-services.py`, then run `flutter run -t lib/main.dart`. It keeps the local API and worker alive independently of the terminal/chat. Debug uses http://127.0.0.1:3031; a physical device needs a server endpoint reachable from the phone. Release defaults to https://invoice.crm.tevel.space. Do not also start the manual API helper on that port.

`tool/notch_preview.dart` is an isolated Debug showcase with fake data. It is not the application backend. Use `lib/main.dart` for real work.

## Release candidate

Run `FLUTTER_BIN=/path/to/flutter/bin/flutter dart run tool/build_release.dart`. It requires analysis and the entire test suite to pass, fixes the real entrypoint, rejects unsafe API origins and requires a newly produced IPA. It never uploads to Apple. `--unsigned` builds a diagnostic archive that cannot be distributed. Xcode needs the Apple account and distribution profiles for both the app and TevelActivity.

See [release qualification](docs/PRODUCTION-QUALIFICATION.md), [feature/blocker map](docs/backend-audit/FEATURE-MAP-he.md), [CRM](docs/CUSTOMER-CRM.md) and [push activation](docs/NOTCH-NOTIFICATIONS.md). An archive alone does not qualify a release.

The new Frankfurt Supabase project's Auth bridge and activation order are
documented in [Supabase Auth](docs/SUPABASE-AUTH.md). Production authentication
stays unchanged until the API is deployed, users are explicitly linked and a
build is created with the Supabase settings.

## Flutter references

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
