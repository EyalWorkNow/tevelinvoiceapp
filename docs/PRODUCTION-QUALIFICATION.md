# Production qualification — 2026-11-09

## Update — 2026-11-10

Backend `b6c6fe3` is now deployed on Oracle with the API and worker running.
The guarded rollout included an encrypted backup, successful restore rehearsal,
all pending migrations and 28 passing postflight checks (zero warnings/failures).
The approved Production APNs key is installed read-only for the service identity;
production StoreKit identifiers are configured. This does not prove device
delivery or an actual purchase.

Signed Build **1.0.0 (4)** replaces Build 3 as the internal candidate. Flutter
analysis, 791 mobile tests and two separately configured Auth tests passed.
Backend verification passed 410 unit tests and 2316 integration tests, plus
18 rollout guard checks. See `apple-review/RELEASE-CANDIDATE.json` for the
artifact hash and current gates. Build 3 is preserved under
`build/ios/candidates/1.0.0-3/`.

Supabase Auth is configured in Frankfurt. On 2026-11-11 the first user was
confirmed and explicitly mapped to the existing production Tevel account.
Real app login/MFA still needs verification with the owner. Supabase
recovery/deletion lifecycle, physical-device APNs, StoreKit purchase/restoration
and Apple upload/review remain gates. **This is not a public-release qualification.**

The following sections retain the earlier Build 3 assessment as historical
context; the update above supersedes their production activation status.

**Signed mobile release candidate prepared; production activation remains pending.** No App Store/TestFlight upload, public submission, production migration or production service restart was performed.

## Verified candidate

- Version 1.0.0 (3), entrypoint lib/main.dart, API origin https://invoice.crm.tevel.space.
- The complete guarded pipeline passed: Flutter analysis, **786 mobile tests with zero failures**, Release archive and App Store IPA export. Tests run serially because the widget harness performs real filesystem I/O.
- Both application and TevelActivity signatures passed codesign verification, including deep verification of embedded components. Both use App Store profiles with get-task-allow=false. The application's APNs entitlement is production.
- IPA: build/ios/ipa/תבל.ipa. SHA-256: 8e1e098cee20b00b9d15bcec8ba3ada41a65946809968146842d91a3742e93c0.
- apple-review/RELEASE-CANDIDATE.json records artifact size, hash, source fingerprint, signing profiles and the test results. This is a dirty working-tree candidate, not a clean committed release. No P8 or environment file was found inside the IPA.
- All **10 backend browser E2E workflows passed**, including expense ingestion, item creation, quote and credit/PDF. Test TypeScript compilation and focused backend ESLint passed. The entire backend integration suite was not rerun after the browser-harness corrections; earlier domain and access-matrix evidence remains in the feature map.

## What changed

Release endpoint validation rejects insecure/development origins before attaching credentials. The debug navigation listener binds loopback and is absent from Profile/Release. The fake animation showcase refuses non-Debug execution. Payment previews are now Debug-only; a business display name can no longer enable a payment demo in Release.

Document, customer and money widgets now render the same code in tests and in the app, preserving the actual design while fixing oversized amounts, privacy handling and enlarged-text overflow. Golden baselines were reviewed and updated for that unified design, without removing assertions. Filter chips, branding layouts, payment logos and VoiceOver business switching were corrected.

Action text now uses the existing label files. Tests cover explicit contact import and existing notification settings; async test helpers await real I/O and apply scroll layout before tapping. The complete mobile suite is green. Historical failing-run inventories remain in backend-audit/production-test-baseline.json alongside the passing qualification result.

## Apple signing and push

Xcode sign-in returned an unknown Apple error. Manual signing resolved the export without requiring further account sign-in. Tevel Invoice App Store and Tevel Activity App Store profiles were installed for team ARFSXMWT96 and the existing Distribution certificate, expiring 2027-05-31. The extension identifier was registered. ExportOptions.manual.plist is the release helper's default; EXPORT_OPTIONS_PLIST can select another explicit signing configuration.

A user-approved Production topic-specific APNs key, F9DJ2FL6P9, was created for space.tevel.invoice. It is outside Git in a protected local directory (700), with the P8 file mode 600. Real Production APNs probes returned BadDeviceToken for intentionally invalid synthetic alert and Live Activity tokens. No customer data was sent. Actual device delivery has not been verified, and this key has not been deployed to the remote server.

## Running servers

The local API was initially reachable, but the simulator ran the isolated animation showcase. It was replaced by the real main.dart application. The local API later stopped, so the API and worker were installed as per-user macOS LaunchAgents with KeepAlive, restricted to invoice_local and the Sandbox push credential. The API was deliberately terminated once and automatically recovered with a new PID. GET /health and /ready then returned 200. This fixes dependence on a terminal/chat background process. See the backend ops/install-mobile-dev-services.py and ops/mobile-dev-service.sh.

Read-only production inspection found API, PostgreSQL and ClamAV healthy, image tevel-invoice:5c3dbe1. The worker was not running and APNS_ENABLED was unset; only older Sandbox APNs variable names were present. SMTP provider/scanning configuration was present. No secret values or customer records were copied into this report.

## Production activation gates

1. Review and commit the backend release; deploy API/worker and migrations 0091–0092 through the controlled rollout/backup procedure. The new CRM server functionality has not been deployed in this run.
2. Install the approved Production APNs key on the target host for the service identity and enable API/worker configuration. The prepared ops/oracle/docker-compose.apns.yml mounts it read-only and rejects missing host paths. It was YAML-parsed locally; merged Docker Compose validation must run on the host. Review existing worker queues before activation, because the normal worker also handles customer email and automations.
3. Confirm Production StoreKit configuration (including APPLE_APP_ID/allowed environment), products, notifications and actual purchase/restoration. Those Production fields were absent from the inspected API environment; no payment or subscription was transacted.
4. Verify a signed physical iPhone: sign-in, business selection, document/quote/payment flows, expense scanning, CRM cross-device/offline recovery, and APNs/Live Activity delivery while backgrounded/terminated. Simulator, synthetic APNs probes and automated tests do not prove real device delivery.
5. Revalidate App Store metadata, privacy declarations, screenshots and reviewer access against this exact candidate before upload/submission. Live donation reporting and uniform submission remain gated/unimplemented as documented in backend-audit/FEATURE-MAP-he.md.

The mobile candidate passed its local release gates. This report does not claim that the live platform or all external integrations are production-enabled.
