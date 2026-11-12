# iPhone motion and system notifications

In-app feedback uses `NotchNoticeHost` with finite, hand-drawn animation for document issuance, delivery, signing, payment, reminders, saving, errors, and quote approval. It supports reduced motion, larger text, VoiceOver actions, queued feedback, and privacy clearing on background/logout.

Outside the app, `TevelActivity` is a real WidgetKit/ActivityKit extension. It provides compact, minimal, expanded Dynamic Island and Lock Screen presentations. This is a separate OS-rendered SwiftUI surface; iOS controls prominence and expansion. Widget/Live Activity animations are limited to two seconds by Apple. Remote starts require iOS 17.2 or newer and may be limited by system policy/user settings. Other devices retain ordinary APNs alerts.

## Implemented flow

1. The user enables notifications for the current business under Management → Notifications. Permission is requested only after that action.
2. The native bridge emits APNs alert, ActivityKit push-to-start, and per-activity update tokens. The Flutter service registers them with `POST /mobile/push-tokens`, using the business attached to an activity without changing the UI's active business.
3. The backend stores scoped tokens associated with the existing device credential's hash. Quote acceptance, approval submission/rejection, first public PDF view, and expense extraction queue amount-free notices in the domain transaction. The existing `payment.recorded` outbox event is also consumed.
4. The worker checks current business membership, effective permissions, device expiry/revocation and MFA. It prefers a Live Activity when enabled, falls back to an ordinary alert for an invalid ActivityKit token, and records per-recipient receipts.
5. Push-to-start content includes a fixed Hebrew title/detail and a guarded route, without monetary amounts or customer names. The app forwards the update token back to the server, which schedules the terminal Live Activity to end after 90 seconds. Old unsent status notices expire after 10 minutes.
6. Foreground OS alerts use the animated in-app surface. Tapping an OS alert uses the existing authenticated route guard. Logout unregisters native remote notifications and ends activities; server dispatch also rejects revoked credentials.

The corresponding backend is `/Users/eyalatiya/Projects/invoiceproject⁩` (the final character in that directory name is U+2069).

## Production activation still required

The code and migrations are implemented locally; no production migration or deployment was performed. Separate user-approved, topic-specific Sandbox and Production APNs keys are stored outside Git with file mode 600. Real connectivity probes returned BadDeviceToken for intentionally invalid synthetic tokens, including Production alert and Live Activity requests. Actual device delivery has not been verified, and the Production key has not been installed on the remote server.

- Apply backend migrations `0091_mobile_push.sql` and `0092_customer_crm.sql` through the normal migration process. Both have been applied to isolated test databases and the local `invoice_local` database.
- The signed 1.0.0 (3) candidate and embedded `space.tevel.invoice.TevelActivity` extension now use verified App Store provisioning; the application has the Production APNs entitlement. See `PRODUCTION-QUALIFICATION.md` and `../apple-review/RELEASE-CANDIDATE.json`.
- Supply an APNs P8 signing key as a protected server file. Never commit it or include it in Flutter/widget assets.
- Configure both API and worker with `APNS_ENABLED=1`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY_PATH`, and optionally `APNS_BUNDLE_ID=space.tevel.invoice`. The API validates configuration for readiness without exposing the key.
- Deploy the API and worker together. Enable notifications on a signed-in physical iPhone and verify delivery while the app is backgrounded and terminated.

Without `APNS_ENABLED`, the worker returns a visible `APNS_NOT_CONFIGURED` retry state and the registration response reports that delivery is not configured. The settings screen exposes the incomplete connection.

`GET /mobile/push-status` checks the authenticated device and current business. Readiness does not imply successful Apple delivery. Document issuance, acknowledged delivery and verified signing now generate notices; CRM saves schedule follow-ups, visits and collection in the same transaction. The worker rereads CRM records before sending, so completed, cancelled or rescheduled items do not trigger stale notices.

Local API runs on port 3031. Backend `ops/install-mobile-dev-services.py` installs API and worker LaunchAgents with automatic recovery, restricted to `invoice_local` and the protected Sandbox credential. These are development services. Production inspection found no running worker and `APNS_ENABLED` unset. Review existing worker queues before enabling the Production worker, which also handles customer email. See `docs/backend-audit/FEATURE-MAP-he.md` for activation gates and remaining gaps.

## Local preview

Run `flutter run -d <simulator-id> -t tool/notch_preview.dart`. The preview uses isolated in-memory fixtures. The next-animation button cycles all eight motions. Its loopback-only development endpoint supports `?motion=approved`, `?native=start` and `?native=end` for recording. The native preview method is compiled only in Debug and does not simulate a real APNs delivery.

Apple references: [ActivityKit pushes](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [animation limits](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities).
