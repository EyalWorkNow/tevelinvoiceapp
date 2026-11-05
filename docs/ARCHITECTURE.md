# תבל – חשבוניות · Mobile architecture (Flutter, iOS first)

Source of truth for product: `docs/SPEC-he.md`. Backend contract: spec §5–§6 + the
mobile CONTRACT (A–J) + `docs/API-MOBILE.md` (written by the backend integrator).

## Run

```
~/flutter/bin/flutter run -d "iPhone 17" --dart-define=API_BASE=http://127.0.0.1:3031
# optional: --dart-define=GOOGLE_IOS_CLIENT_ID=<ios client id>  (Google button hidden without it)
~/flutter/bin/flutter analyze      # must be 0 issues
~/flutter/bin/flutter test         # must be green
```
`API_BASE` defaults to `http://127.0.0.1:3031` (LOCAL dev API). Never point the
simulator at production, never at :3011 (service on the prod DB).

## Folder map

```
lib/
  main.dart                 MaterialApp (he-IL, RTL, light+dark), home = SplashScreen,
                            signed-in → signed-out transition → LoginScreen
  app_shell.dart            3 tabs בית / לקוחות / הגדרות + lime "+" (hidden for READ_ONLY)
  router.dart               every screen opener (openNewDocument, openDocument, …) + stack resets
  api/client.dart           ApiClient.instance: cookie→device-token auth, CSRF, X-Business-Id,
                            Idempotency-Key, JSON/bytes helpers, ApiException (Hebrew), events
  api/models.dart           Business, MobileAccount, Me, BusinessProfile, DashboardSummary,
                            DocumentSummary, DocumentDetail+DocumentLine, Customer, Item
  api/errors_he.dart        error code → Hebrew (verbatim web port + contract codes)
  api/<feature>_api.dart    squad-owned API functions (see ownership)
  state/session.dart        `session` (SessionController): token, account, business, me, profile
  state/cache.dart          AppCache: tiny JSON file cache (read-only data)
  util/money.dart           agorot ↔ '₪1,180.00', keypad input rules
  util/labels_he.dart       doc type / status / business type / role / payment method labels,
                            Tone, relative Hebrew dates
  ui/theme.dart             tokens (AppPalette via context.palette), Space, Radii, Hit, AppText
  ui/widgets/               big_button, amount_display, keypad, doc_tile, sheet (showAppSheet),
                            status_chip, empty_state, error_view (ErrorView, showErrorSnack,
                            errorTextHe), offline_banner
  screens/<area>/           one file per screen/sheet (stubs exist with final signatures)
test/                       money, labels, errors, client (MockClient), models, widgets
```

## Ownership

Shared files are owned by the **architect** — squads must NOT edit `lib/main.dart`,
`lib/app_shell.dart`, `lib/router.dart`, `lib/ui/**`, `lib/api/client.dart`,
`lib/api/models.dart`, `lib/api/errors_he.dart`, `lib/state/**`, `lib/util/money.dart`,
`lib/util/labels_he.dart`, `pubspec.yaml`. If you need a change (new field on a model,
new widget variant, new route, new package), write it in your report and the
integrator applies it. Add a squad-local model/widget inside your own folder only when
nobody else needs it.

| Squad | Owns |
|---|---|
| auth | `lib/screens/auth/*` (S0 splash, S1 login, G1 MFA sheet, G2 business picker, S2 onboarding), `lib/api/auth_api.dart`, `lib/util/biometric.dart` |
| home | `lib/screens/home/*` (S3 home + expanded activity list), `lib/screens/document/*` (S6 document detail incl. embedded PDF), `lib/api/documents_api.dart` (read side: dashboard, list, detail, pdf bytes) |
| new-document | `lib/screens/new_document/*` (S4 3-step flow: keypad, customer pick, summary/issue; S5 success screen), `lib/api/issue_api.dart` (create draft, finalize w/ idempotency, artifact, payment+allocation, preview, allocation polling per spec §6.3), `lib/util/vat.dart` (gross→net exact search + test with 1000 random amounts using server rounding: half away from zero, `packages/accounting-core/src/line-calculation.ts`), `lib/util/doc_type.dart` (spec table) + tests, resume-unfinished-issue banner logic |
| money-actions | `lib/screens/actions/*` (S7 QR payment request both modes, G3 record payment sheet, G4 cancel/credit sheet, share sheet: WhatsApp per spec §6.1 incl. share-link + wa.me + PDF-file fallback, email send + `/deliveries/:id/process`, consent prompt), `lib/api/actions_api.dart`, `lib/util/phone.dart` (Israeli phone → wa.me 972 format) + tests |
| customers-expense | `lib/screens/customers/*` (S8 list with Hebrew alphabet index + search, customer detail, new/edit customer sheet with native contact picker that needs NO contacts permission), `lib/screens/expense/*` (S10 camera/gallery/PDF → JPEG conversion (HEIC rejected by server) → sha256 → initiate/PUT bytes/complete/poll), `lib/api/customers_api.dart`, `lib/api/expenses_api.dart` |
| settings | `lib/screens/settings/*` (S9 settings list, business details edit (canConfigure), payment link + WhatsApp message template (template stored locally), Face ID toggle, logout, logout-all, delete account flow with typed confirmation explaining legal retention, privacy/terms links https://tevel.space/privacy and https://tevel.space/terms, support, open-in-browser https://invoice.crm.tevel.space/app/), `lib/api/settings_api.dart` |
| ios-platform | `ios/**` and `assets/**` only: app icon set from `invoiceproject/tevelinvoicelogo.png` (all sizes, no alpha on the 1024 marketing icon), launch screen (charcoal + logo), Info.plist (CFBundleDisplayName "תבל", he development region + CFBundleLocalizations he, NSCamera/NSPhotoLibrary/NSFaceID usage strings in Hebrew, ITSAppUsesNonExemptEncryption NO, LSApplicationQueriesSchemes whatsapp, ATS: localhost/127.0.0.1 ONLY via NSAllowsLocalNetworking), TARGETED_DEVICE_FAMILY=1, iOS deployment target ≥ 15 as plugins need, Runner.entitlements with com.apple.developer.applesignin, `ios/Runner/PrivacyInfo.xcprivacy` (NSPrivacyTracking false; email, name, phone, financial info, photos — App Functionality, linked, not tracking; required-reason APIs: UserDefaults CA92.1, file timestamp C617.1, system boot time 35F9.1 if used, disk space E174.1 if used) in the Runner target build phase, portrait-only on iPhone, plus `docs/APP-STORE.md` (Hebrew App Store Connect metadata, privacy nutrition label, review notes template with demo-account placeholders, age rating, export compliance, pre-submission checklist mapped to spec §10) |

## Stable interfaces (stubs already exist — fill them, keep the signatures)

| File | Signature |
|---|---|
| screens/auth/splash_screen.dart | `SplashScreen()` (minimal working version: restore → home/login) |
| screens/auth/login_screen.dart | `LoginScreen({bool sessionExpired = false})` |
| screens/auth/mfa_sheet.dart | `Future<bool> showMfaSheet(BuildContext, {bool enroll = false})` |
| screens/auth/business_picker_sheet.dart | `Future<Business?> showBusinessPicker(BuildContext)` — calls `session.selectBusiness` itself |
| screens/auth/onboarding_screen.dart | `OnboardingScreen()` |
| screens/home/home_screen.dart | `HomeScreen()` (tab, no back button) |
| screens/document/document_detail_screen.dart | `DocumentDetailScreen({required String id})` |
| screens/new_document/new_document_screen.dart | `NewDocumentScreen({Customer? customer, BigInt? presetAmountMinor, bool presetPaid = false})` |
| screens/new_document/issue_success_screen.dart | `IssueSuccessScreen({required DocumentDetail document, Customer? customer})` |
| screens/actions/payment_qr_screen.dart | `PaymentQrScreen({String? documentId, BigInt? amountMinor})` |
| screens/actions/record_payment_sheet.dart | `Future<bool> showRecordPaymentSheet(BuildContext, DocumentDetail doc)` |
| screens/actions/cancel_document_sheet.dart | `Future<bool> showCancelDocumentSheet(BuildContext, DocumentDetail doc)` |
| screens/actions/share_sheet.dart | `Future<void> showShareSheet(BuildContext, DocumentDetail doc, {Customer? customer})` |
| screens/customers/customers_screen.dart | `CustomersScreen()` (tab) |
| screens/customers/customer_detail_screen.dart | `CustomerDetailScreen({required Customer customer})` |
| screens/customers/customer_form_sheet.dart | `Future<Customer?> showCustomerFormSheet(BuildContext, {Customer? existing})` |
| screens/expense/expense_capture_screen.dart | `ExpenseCaptureScreen()` |
| screens/settings/settings_screen.dart | `SettingsScreen()` (tab) |
| screens/settings/delete_account_screen.dart | `DeleteAccountScreen()` |

Stubs may become StatefulWidget — keep the class name and constructor parameters.

Navigation (router.dart): `openNewDocument(ctx, {customer, presetAmountMinor, presetPaid})`,
`openIssueSuccess(ctx, {document, customer})` (replaces the current route),
`openDocument(ctx, id)`, `openPaymentQr(ctx, {documentId, amountMinor})`,
`openExpenseCapture(ctx)`, `openCustomer(ctx, customer)`, `openDeleteAccount(ctx)`,
`openOnboarding(ctx)`, `resetToHome({tab})`, `resetToLogin({expired})`,
`resetToOnboarding()`, `selectTab(AppTab)`. Screens never call `Navigator.push` with
another squad's screen directly — use these.

## Auth & session (how the pieces fit)

1. **Sign-in (cookie phase).** `auth_api.dart` calls `ApiClient.instance.post('/auth/login' | '/auth/google' | '/auth/apple', …)`.
   The client captures `Set-Cookie: tvl_session` and any `csrfToken` in a JSON body
   automatically (also on MFA / rotation), and sends `Cookie` + `X-CSRF-Token` on non-GET.
   `mfaRequired: true` (or a 403 `MFA_REQUIRED`, also broadcast on `ApiClient.instance.events`)
   → `showMfaSheet`.
2. **Device token.** When the cookie session is MFA-satisfied: `await session.completeSignIn()`.
   It calls `POST /auth/device-token` (CONTRACT B), stores the token in the Keychain
   (`first_unlock_this_device`), drops the cookie, loads `GET /mobile/session` and
   auto-selects the business (stored choice, or the only one). Then route:
   `session.needsBusinessPick` → `showBusinessPicker`; `session.hasNoBusiness` → explain
   + open in browser (no business to scope to); `session.needsOnboarding` → S2; else `resetToHome()`.
3. **After sign-in** every request carries `Authorization: Bearer inv_…` and
   `X-Business-Id` (automatic for every path except `/auth/*` and `/mobile/*`).
4. **Cold start.** `session.restore()` (SplashScreen). Offline → signed in from the cached
   account with `session.offline = true` (writes disabled, show `OfflineBanner`).
5. **Expiry.** Any 401 outside `/auth/*` → `ApiEvent.sessionExpired` → session wipes
   Keychain + cache → main.dart resets to `LoginScreen(sessionExpired: true)`.
6. **Sign out.** `session.signOut()` (POST /mobile/logout + local wipe).
   After `POST /mobile/account/delete`: `session.signOutLocally()`.
   `/auth/logout-all` needs a cookie session; with a device token use the CONTRACT
   endpoints (settings squad: report if a bearer logout-all is needed).

`session` fields: `status`, `expired`, `offline`, `account` (userId, email, displayName,
businesses), `business`, `me` (role, canFinalize, canConfigure, `needsApproval(total)`,
`isReadOnly`, onboardingCompleted), `profile` (businessType, `isVatExempt`,
`paymentLinkUrl`, identityLocked, `raw`). Listen with `ListenableBuilder(listenable: session, …)`.
Refresh after edits: `session.refreshBusiness()` / `session.refreshAccount()`.

## Conventions

- **Hebrew strings inline** in the widget (no l10n files). Every UI string Hebrew; RTL is
  automatic from the he-IL locale. Numbers/amounts: wrap in `Directionality(ltr)` or use
  `AmountDisplay` / `formatMoney` (already LTR-safe in widgets).
- **Money = `BigInt` agorot**, never `double` (not even for animation). Server strings →
  `BigInt.parse`. Requests send money as decimal strings (`'118000'`), quantities as
  `quantityMicros` strings, VAT as basis-point ints.
- **API calls** live in your own `lib/api/<feature>_api.dart` as **top-level functions**
  using `ApiClient.instance` and returning models:
  ```dart
  final _api = ApiClient.instance;
  Future<List<Customer>> fetchCustomers() async {
    final json = await _api.get('/customers');
    return [for (final c in json['customers'] as List) Customer.fromJson(c as Map<String, dynamic>)];
  }
  ```
  Money-moving calls (finalize, credit, payments, receipts) take an Idempotency-Key:
  create it once with `ApiClient.newIdempotencyKey()`, persist it with the pending step
  (AppCache) and re-send the SAME key on retry.
- **Errors.** Everything throws `ApiException {status, code, messageHe}`; `status == 0`
  (`isNetwork`) = no connection. Screens: `ErrorView(error: e, onRetry: …)`; actions:
  `showErrorSnack(context, e)`. Branch on `e.code`, never on text. New codes → report to
  the integrator for `errors_he.dart`.
- **State:** plain `StatefulWidget` + `setState`, or a local `ChangeNotifier`. No
  riverpod/bloc/go_router/dio. Packages = spec §7.2 only (already in pubspec).
- **Cache:** `AppCache.read/write('<name>_${session.business!.businessId}', json)` for
  read-only data (dashboard, customers, recent documents). Wiped on sign-out.
  Small per-device prefs (Face ID toggle, WhatsApp template) may also live in AppCache
  (or the Keychain if sensitive).
- **UI:** use `context.palette`, `Space`, `Radii`, `AppText`, `BigButton`, `showAppSheet`
  + `SheetTitle`, `StatusChip`, `DocTile`, `EmptyState`. Touch targets ≥ 44pt; add
  `Semantics` labels in Hebrew on icon-only buttons.
- **Tests:** pure logic in `test/<feature>_test.dart`; HTTP via
  `ApiClient.instance.httpClient = MockClient(...)` (see `test/client_test.dart`).
- **Done = ** `flutter analyze` 0 issues + `flutter test` green + your report lists
  needed shared-file changes.

## Known gaps for squads

- `GET /dashboard` `recent` rows have no customer name and no balance
  (`DocumentSummary.customerName/balanceMinor == null`). Home may prefer
  `GET /documents` for the feed, or ask backend to extend `recent`.
- `GET /documents` is capped at 100 rows server-side (no paging).
- App-switcher privacy overlay (spec §11) and Face ID lock-after-5-min are not wired
  yet — auth squad (`lib/util/biometric.dart`) proposes the hook; integrator adds it to main.dart.
