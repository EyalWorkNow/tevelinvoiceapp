# Tevel mobile API reference (single source for the iOS app)

Backend: `~/Projects/invoiceproject⁩`. V1 mobile additions: branch `feat/mobile-api` (commits 19031e6, a3b5879, a33aabc, 8f3de61). **V2: branch `feat/mobile-api-v2`** (sections "V2 · …" below; integration status, role presets and the smoke log are in **"V2 · שילוב ובדיקות (INT)"** at the end).
Everything below was verified against the local dev API on 2026-10-30, unless marked *(not smoke-tested)*. The dev API on :3031 runs the V2 branch since 2026-10-30 18:57 (migrations 0058–0077 applied to `invoice_local`).

## 1. Environments

| | Base URL | Notes |
|---|---|---|
| **dev** (simulator) | `http://127.0.0.1:3031` | Local API on the local DB `invoice_local`. Start or stop it with `~/Projects/invoiceproject⁩/ops/run-mobile-dev.sh [stop]`. Log: `/tmp/invoiceproject-mobile-dev.log`. |
| **prod** | `https://invoice.crm.tevel.space` | The new endpoints are **not deployed yet**. Do not point the simulator at prod. |

Never use ports 3001, 3011 or 3021. 3011 is a service that runs on the production database.

On the dev server: SHAAM is off (`/documents/:id/allocation` stays `NOT_EVALUATED`), no e-mail is really sent (see §3), uploads are not virus-scanned, and self-signup is on.

## 2. Dev accounts (`scripts/seed-mobile-dev.ts`, idempotent)

Password for all accounts: **`Mobile12345678`**

| E-mail | Role | Business | MFA |
|---|---|---|---|
| `mobile-owner@tevel.test` | OWNER (preset בעלים) | סטודיו תבל לדוגמה (`OSEK_MURSHE`, `3b773037-e71d-49bd-a951-76845e4abe07`) | e-mail code |
| `mobile-partner@tevel.test` | ADMIN (preset שותף) | the same business | e-mail code |
| `mobile-employee@tevel.test` | EMPLOYEE + `document:finalize` + `payment:record` + `allocation:request` (preset עובד + מפיק בעצמו) | the same business | e-mail code (**since BE-03a**: finalize/payment holders need MFA) |
| `mobile-staff@tevel.test` | EMPLOYEE (preset עובד) | the same business | none |
| `mobile-accountant@tevel.test` | READ_ONLY + `expense:record` + `expense:approve` (preset רואה חשבון, P0) | the same business | none |
| `mobile-cpa-full@tevel.test` | ACCOUNTANT (tag רו״ח – מלא) | the same business | e-mail code |
| `mobile-cpa-rep@tevel.test` | ACCOUNTANT_REP (preset רואה חשבון (מייצג), BE-04) | the same business | e-mail code |
| `mobile-viewer@tevel.test` | READ_ONLY (preset צפייה בלבד) | the same business | none |
| `mobile-patur@tevel.test` | OWNER | דנה כהן – עיצוב (`OSEK_PATUR`, `c934a7a8-df74-433d-a5e2-e342c16142b1`) | e-mail code |

The server role+grants per preset follow SPEC-v2 §4.3/§4.4. All 9 accounts exist on the dev server (seeded 2026-10-30 by INT; the seed is idempotent and the business ids above stay the same).

Both businesses have `paymentLinkUrl = https://example.com/pay/tevel-demo`, 2–3 customers and sample documents (paid, open and draft).
To re-seed (the API must be running): `cd ~/Projects/invoiceproject* && DATABASE_URL=postgresql://localhost:5432/invoice_local pnpm exec tsx scripts/seed-mobile-dev.ts`

## 3. Getting MFA codes in dev

The dev server runs with `EMAIL_MODE=file`. Every e-mail it "sends" is written as JSON to
`~/invoiceproject-mobile-dev-storage/outgoing-emails/file-<ts>-<n>.json`. The code is the first 6 digits of `subject`:

```bash
jq -r .subject "$(ls -t ~/invoiceproject-mobile-dev-storage/outgoing-emails/*.json | head -1)" | grep -oE '^[0-9]{6}'
```

Document e-mails (`/documents/:id/send`) land in the same folder. They list the PDF attachment by size; the bytes are not written.

## 4. Conventions

- **Money**: agorot as decimal strings (`"118000"` = ₪1,180.00). Parse with `BigInt`, never `double`.
- **Quantity**: `quantityMicros` string (`"1000000"` = 1). **VAT**: `taxRateBasisPoints` int (`1800` = 18%).
- Responses mix `snake_case` (`/documents/:id`, `/dashboard`, `/customers`) and `camelCase` (`/documents`, `/me`, `/mobile/*`). Write one model per response.
- **Errors** always look like `{"error":"CODE","message":"english…","requestId":"uuid"}`. Map `error` through §9. Never show `message` to the user.
- `Idempotency-Key: <uuid v4>` is **required** on `/documents/:id/finalize`, `/documents/:id/credit`, `/payments` and `/receipts`. Reuse the same key when retrying the same logical action.
- Every POST/PUT/PATCH body is JSON (`Content-Type: application/json`). `{}` is fine when there are no fields.

## 5. Authentication flow

```
email+password ─► POST /auth/login ──┬─ status PASSWORD_OK ─────────────┐
Apple          ─► POST /auth/apple  ─┤                                  │
Google         ─► POST /auth/google ─┴─ status MFA_REQUIRED             │
                                         │                              │
                     POST /auth/mfa/email/send {purpose:"LOGIN"}        │
                     POST /auth/mfa/email/verify {code}                 │
                     (or POST /auth/mfa {code} for TOTP/recovery code)  │
                                         ▼                              ▼
                               POST /auth/device-token {deviceName}  → 201 {token}
                                    403 MFA_REQUIRED? → enrollment (below)
                                         ▼
               Keychain: token.   GET /mobile/session → businesses → pick → X-Business-Id
```

**Phase 1, cookie session (sign-in only).** Every sign-in response sets `Set-Cookie: tvl_session=…` and returns a `csrfToken` in the body. Send it back as `Cookie: tvl_session=<v>` plus `X-CSRF-Token: <csrfToken>` on every non-GET. **Every response that has a `Set-Cookie` or a `csrfToken` replaces the stored value.** MFA verify rotates both.

**Phase 2, bearer (everything else).** Send `Authorization: Bearer inv_…`. Business routes also need `X-Business-Id: <uuid>`. The bearer needs no CSRF. The server remembers whether the token was minted from an MFA-verified session; a token minted **without** MFA (e.g. by an EMPLOYEE) gets `403 MFA_REQUIRED` on business routes once that user's role in the business becomes OWNER/ADMIN/ACCOUNTANT or the user enrols MFA. Then the app signs in again (S1 → MFA → new device token); `/mobile/session` keeps working meanwhile. `/auth/*` and `/mobile/*` take no `X-Business-Id`. The token lasts 90 days. A `401` on any bearer call means the token is gone: clear the Keychain and show S1 ("פג תוקף ההתחברות").

> The session-only routes `/auth/whoami`, `/auth/my-businesses`, `/auth/logout-all` and `/auth/password/change` do **not** accept a bearer. Use `/mobile/session` and `/mobile/logout` instead. There is no bearer "log out on all devices" yet (gap).

**Enrollment (a new owner, e.g. after an Apple/Google self-signup).** OWNER, ADMIN and ACCOUNTANT must use MFA. If login returned `PASSWORD_OK` but `/auth/device-token` returns `403 MFA_REQUIRED`:
`POST /auth/mfa/email/send {"purpose":"ENROLL"}` → `POST /auth/mfa/email/verify {"code","purpose":"ENROLL"}` → take the new `csrfToken` and cookie → `POST /auth/device-token` succeeds. (Verified on dev.)

### 5.1 `POST /auth/login`
```json
→ {"email":"mobile-owner@tevel.test","password":"Mobile12345678"}
← 200 {"status":"MFA_REQUIRED","mfaRequired":true,"csrfToken":"ec1f…","businesses":[]}
← 200 {"status":"PASSWORD_OK","mfaRequired":false,"csrfToken":"7a61…",
       "businesses":[{"businessId":"3b77…","legalName":"סטודיו תבל לדוגמה","role":"EMPLOYEE"}]}
```
On `MFA_REQUIRED`, `businesses` is empty. Get the list from `/mobile/session` after the device token is issued.
Errors: `401 INVALID_CREDENTIALS`, `429 RATE_LIMITED`.

### 5.2 `POST /auth/apple` (new; contract A)
```json
→ {"identityToken":"<JWT from sign_in_with_apple>","fullName":"דנה כהן"}   // fullName optional, send it on first sign-in
← 200  same shape as /auth/login (+ Set-Cookie)
```
The server checks the token against Apple's JWKS: iss `https://appleid.apple.com`, aud `space.tevel.invoice` (= bundle id), exp, `email_verified`.
The **first** sign-in must carry the e-mail, because that is how accounts are linked. Later sign-ins match on Apple `sub`.
Errors: `401 APPLE_TOKEN_INVALID`, `403 NO_LINKED_ACCOUNT`, `403 APPLE_IDENTITY_MISMATCH`, `503 APPLE_SIGNIN_DISABLED`.
Smoke-tested only with a bogus token (→ 401 APPLE_TOKEN_INVALID). A real Apple token needs a device or simulator signed into an Apple ID.

### 5.3 `POST /auth/google`
`{"idToken":"<Firebase ID token>"}` → same shape as login. *(not smoke-tested; existing route.)* Errors: `GOOGLE_TOKEN_INVALID`, `NO_LINKED_ACCOUNT`, `GOOGLE_IDENTITY_MISMATCH`, `GOOGLE_SIGNIN_DISABLED`.

### 5.4 MFA (cookie + CSRF)
```json
POST /auth/mfa/email/send    → {"purpose":"LOGIN"}                  ← 200 {"sentTo":"mo***@tevel.test","resendAfterSeconds":45}
POST /auth/mfa/email/verify  → {"code":"123456"}                    ← 200 {"status":"ok","recoveryCodes":null,"csrfToken":"68df…"} + Set-Cookie
POST /auth/mfa/email/verify  → {"code":"123456","purpose":"ENROLL"} ← same; recoveryCodes may be non-null → show once
POST /auth/mfa               → {"code":"123456"}  (TOTP or recovery code)
                             ← 200 {"status":"AUTHENTICATED","csrfToken":"…","businesses":[…]} + Set-Cookie
```
Errors: `MFA_CODE_INVALID`, `MFA_LOCKED` (15 min), `MFA_EMAIL_THROTTLED` (resend too soon), `MFA_NOT_ENROLLED`, `MFA_EMAIL_UNAVAILABLE`.

### 5.5 `POST /auth/device-token` (new; contract B). Cookie + CSRF, MFA-satisfied session
```json
→ {"deviceName":"iPhone של דנה"}      // 1–80 printable chars
← 201 {"token":"inv_8df4…(68 chars)","tokenId":"cdf2417c-…","expiresAt":"2027-01-28T04:40:02.898Z"}
```
Errors: `403 MFA_REQUIRED` (see enrollment), `422 VALIDATION`, `401 SESSION_INVALID`. Once you hold the token, you may drop the cookie.
The token stores whether this session was MFA-verified (`api_tokens.mfa_verified`, migration 0057). See Phase 2 above for when a non-MFA token is later refused.

### 5.6 `GET /mobile/session` (new; contract C). Bearer, no X-Business-Id
```json
← 200 {"userId":"e8eb…","email":"mobile-owner@tevel.test","displayName":"אורי בעלים",
       "businesses":[{"businessId":"3b77…","legalName":"סטודיו תבל לדוגמה","role":"OWNER"}]}
← 401 {"error":"UNAUTHENTICATED",…}   // revoked or expired → S1
```

### 5.7 `POST /mobile/logout` (new; contract D). Bearer
`{}` → `200 {"status":"ok"}`. This revokes only this token.

### 5.8 `POST /mobile/account/delete` (new; contract E). Bearer
```json
→ {"confirm":"DELETE", "password":"…"}                 // exactly ONE fresh proof of identity:
→ {"confirm":"DELETE", "appleIdentityToken":"eyJ…"}     //   a NEW Sign in with Apple (iat ≤ 10 min, same Apple ID)
→ {"confirm":"DELETE", "googleIdToken":"eyJ…"}          //   a Firebase ID token after re-sign-in (auth_time ≤ 10 min, same Google account)
← 200 {"status":"deleted"}
← 422 {"error":"CONFIRMATION_REQUIRED"}   // confirm is not exactly "DELETE"
← 403 {"error":"REAUTH_REQUIRED"}         // no proof, or more than one
← 403 {"error":"REAUTH_FAILED"}           // wrong password / stale or foreign Apple/Google token (the bearer stays valid)
```
The bearer alone is **not** enough (it is long-lived; deletion is irreversible and can close a business). The confirm screen asks for the password, or runs Sign in with Apple / Google again (for Google call `reauthenticateWithCredential` so `auth_time` is fresh), then sends the result. The proof must match how the account signs in: an Apple token must be for the linked Apple ID, a Google token for the linked Google account. Failed proofs are logged as `auth.account_delete_reauth_failed`; the route has the auth rate limit per IP and per token. `REAUTH_FAILED` is a 403, so do **not** clear the Keychain on it.
This revokes all sessions, tokens and memberships and anonymises the user. If the user was the only OWNER, the business is CLOSED. Documents are kept (legal retention). After this, login returns `INVALID_CREDENTIALS`. Verified on dev.

### 5.9 Password reset
`POST /auth/password/forgot {"email"}` → `202 {"status":"ok"}`. Always show "אם החשבון קיים, נשלח מייל". The reset link opens the **web** app.

## 6. Business-scoped routes (Bearer + `X-Business-Id`)

### 6.1 `GET /me`
```json
{"userId":"e8eb…","role":"OWNER","mfaEnrolled":false,"onboarding":{"completed":true,"step":1},
 "canFinalize":true,"canConfigure":true,"canApproveExpenses":true,
 "approvalPolicy":{"mode":"NONE","thresholdMinor":"0","selfApprovalAllowed":false}}
```
`mfaEnrolled` is always `false` under a bearer, because it is read from the cookie session. Do not use it.

### 6.2 `GET /dashboard`
```json
{"summary":{"month_income":"472000","month_income_count":3,"month_expenses":"0","unpaid_count":2,
  "unpaid_balance":"354000","review_count":0,"open_quotes":0,"pending_approval":0},
 "recent":[{"id":"9efd…","document_type":"TAX_INVOICE","status":"SENT","document_number":"3",
            "issue_date":"2026-10-30","total_minor":"118000","currency":"ILS"}, …8 newest incl. DRAFT]}
```
⚠ Known server behaviour: `month_income` and `unpaid_*` count **every** finalized document type. A `RECEIPT` (400) issued for an invoice has `balance_minor = total`, so it counts twice in income and shows up as "unpaid". Until the server fixes this, compute "ממתינים לתשלום" in the app from `/documents?unpaid=1`, keeping only `TRANSACTION_INVOICE`, `TAX_INVOICE` and `TAX_INVOICE_RECEIPT`.

### 6.3 Documents
`GET /documents?unpaid=1&customerId=&documentType=&status=&documentNumber=&issuedFrom=&issuedTo=` (max 100, newest first)
```json
{"total":1,"documents":[{"id":"d86c…","documentType":"TAX_INVOICE","status":"ARCHIVED","documentNumber":"2",
  "customerId":"b96c…","customerName":"מאפיית השכונה בע\"מ","issueDate":"2026-10-30","currency":"ILS",
  "totalMinor":"236000","balanceMinor":"236000"}]}
```
`GET /documents/:id`
```json
{"document":{"id":"a449…","document_type":"TAX_INVOICE_RECEIPT","status":"ARCHIVED","document_number":"1","currency":"ILS",
  "issue_date":"2026-10-30","subtotal_minor":"100000","tax_total_minor":"18000","total_minor":"118000",
  "paid_total_minor":"118000","balance_minor":"0","allocation_number":null,"customer_id":"9283…","supplier_id":null,
  "warehouse_id":null,"target_warehouse_id":null,"numbering_scope_key":"default","snapshot_hash":"b464…"},
 "lines":[{"position":1,"item_id":null,"description":"עיצוב לוגו","quantity":"1.000000","quantity_micros":"1000000",
  "unit_price_minor":"100000","discount_minor":"0","subtotal_minor":"100000","tax_rate_basis_points":1800,
  "tax_amount_minor":"18000","total_minor":"118000"}]}
```
Statuses: `DRAFT` → (`PENDING_APPROVAL`) → `FINALIZED` → `ARCHIVED` (original PDF stored) → `SENT` (e-mailed).

**Issue sequence (S4):**
```json
POST /documents
→ {"documentType":"TAX_INVOICE","customerId":"9283…","currency":"ILS","fiscalContext":"default",
   "lines":[{"description":"עיצוב לוגו","quantityMicros":"1000000","unitPriceMinor":"100000","taxRateBasisPoints":1800}]}
   // optional per line: "discountMinor":"0","itemId":"…"; optional: "issueDate":"YYYY-MM-DD"
← 201 {"id":"9efd…","status":"DRAFT"}

POST /documents/:id/finalize   [Idempotency-Key]   → {"scopeKey":"default"}
← 200 {"status":"FINALIZED","documentNumber":"3","snapshotHash":"c57c…","reused":false}
   // other statuses: WAITING_FOR_ALLOCATION, APPROVAL_REQUIRED (see spec §6.3 / submit)

POST /documents/:id/artifact   → {}
← 201 {"artifactId":"129f…","storageKey":"…","sha256":"034c…","byteSize":70204,"signing":"NOT_APPLICABLE"}

GET  /documents/:id/pdf        ← 200 application/pdf (the ORIGINAL; ?type=COPY for a marked copy)
```
Other routes:
- `PUT /documents/:id` takes the same body as create and works on drafts only.
- `DELETE /documents/:id` deletes a draft and returns `{"status":"deleted"}`.
- `POST /documents/preview` takes the create body and returns `200 application/pdf` with a watermark.

`scopeKey` = `"default"`. If the business has no `default`, use the first entry from `GET /sequences` → `{"sequences":[{"numbering_scope_key":"default","numbering_policy_version":"v1","next_number":"4"}]}`.

**Exempt dealer (OSEK_PATUR), new (contract I):** a VAT document type returns `422 DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS` (TAX_INVOICE / CONCENTRATED_INVOICE / TAX_INVOICE_RECEIPT). Any line with `taxRateBasisPoints > 0` returns `422 EXEMPT_BUSINESS_VAT_FORBIDDEN`. These are checked on create, update and finalize. NONPROFIT is **not** restricted.

### 6.4 Payments and receipts
```json
POST /payments [Idempotency-Key]
→ {"method":"CASH","amountMinor":"118000","currency":"ILS","paymentDate":"2026-10-30","reference":"…"}
   // method: CASH | BANK_TRANSFER | CREDIT_CARD | CHECK | DIRECT_DEBIT | OTHER
   // CHECK requires bankNumber, branchNumber, accountNumber, reference (= cheque no.)
← 201 {"paymentId":"…","reused":false}
POST /documents/:id/payments → {"paymentId":"…","amountMinor":"118000"}  ← 200 {"allocated":true}
POST /receipts [Idempotency-Key]
→ {"paymentIds":[{"id":"…"}],"scopeKey":"default","forDocumentId":"…","customerId":"…"}
← 201 {"receiptDocumentId":"…","outcome":{"status":"FINALIZED","documentNumber":"2",…}}
   // then POST /documents/<receiptDocumentId>/artifact
```
Credit note (G4), not smoke-tested: `POST /documents/:id/credit [Idempotency-Key] {"scopeKey":"default","lines":[…original lines…]}` → `201 {"creditDocumentId","outcome"}`. Then call `/artifact` on the credit note.

### 6.5 Share link and public page, new (contract F, WhatsApp)
```json
POST /documents/:id/share-link → {}
← 201 {"url":"http://127.0.0.1:3031/d/1v6ljaWNnD8TKHQKChXY9dvgFeIwg8udKI6GfePhZys","expiresAt":"2026-11-29T04:40:03.381Z"}
← 409 ARTIFACT_REQUIRED   // draft, or no original yet → call /artifact first
```
- The link lasts 30 days. Each call creates a new link.
- The public page `GET /d/<token>` is Hebrew RTL. It shows the business, the document type and number, the date, the total and the balance. It has a "הורדת המסמך (PDF)" button → `/d/<token>/pdf` (the original bytes, inline). It also has "לתשלום" (`paymentLinkUrl`) **only** when balance > 0. The page is no-store and noindex.
- An unknown, expired or revoked token gets a Hebrew 404.
- Downloads are counted on the link (`share_links.download_count`, `first_downloaded_at`). Only the first download is written to the audit log.
- In prod the URL is `https://invoice.crm.tevel.space/d/<token>`. Ops still has to make the proxy route `/d/*` to the API.
- WhatsApp: `https://wa.me/9725XXXXXXXX?text=<urlencoded message + url>`.

### 6.6 E-mail (contract J)
```json
POST /documents/:id/send → {"recipient":"dana@example.test","paymentUrl":"https://example.com/pay/tevel-demo"}  // paymentUrl optional
← 202 {"deliveryId":"e887…"}
POST /deliveries/:deliveryId/process → {}
← 200 {"status":"SENT","attemptCount":1}      // safe to repeat; also RETRY_SCHEDULED / FAILED
```
Always call `/process` right after `/send`. In prod a worker may already have sent it; the call is idempotent. Errors: `DOCUMENT_NOT_DELIVERABLE`, `CONSENT_REQUIRED` (→ `POST /customers/:id/consent {"method":"VERBAL_IN_APP"}`, not smoke-tested).

### 6.7 Customers
```json
GET  /customers  ← {"customers":[{"id":"9283…","name":"דנה כהן","tax_id":null,"email":"dana@example.test",
                    "phone":"0501234567","archived_at":null,"vat_dealer_status":"UNKNOWN"}]}   // includes archived — filter archived_at
POST /customers  → {"name":"לקוח","customerType":"INDIVIDUAL"|"BUSINESS","phone","email","taxId","vatDealerStatus"} ← 201 {"id"}
PATCH /customers/:id (new; H) → any subset of {name,email,phone,taxId,vatDealerStatus,customerType}; null clears ← 200 {"id"}
POST /customers/:id/archive (new; H) → {}  ← 200 {"archived":true}   (idempotent)
```
Errors: `404 CUSTOMER_NOT_FOUND`, `403 DOCUMENT_ACTION_FORBIDDEN` (READ_ONLY).

### 6.8 Business profile (G: `paymentLinkUrl`) and onboarding
```json
GET /business/profile ← {"canConfigure":true,"profile":{"legalName":"סטודיו תבל לדוגמה","tradingName":null,
  "businessType":"OSEK_MURSHE","taxId":"000000042","address":{"street":"רחוב הרצל 1","number":"","city":"תל אביב","postalCode":null},
  "phone":"0501111111","email":"…","website":null,…,"paymentLinkUrl":"https://example.com/pay/tevel-demo",
  "onboarding":{"step":1,"completedAt":null,"completed":true},"identityLocked":true}}
PUT /business/profile → any subset, e.g. {"paymentLinkUrl":"https://…"} or {"paymentLinkUrl":null}  ← 200 {"profile":{…}}
   // invalid link (not https / whitespace / >2000) → 400 VALIDATION (not 422)
PUT /business/onboarding → {"step":2} | {"completed":true}  ← 200 {"onboarding":{…}}
```
`identityLocked: true` means the business type and tax id can no longer change, because documents already exist.

### 6.9 Other reads
- `GET /items` → `{"items":[…]}`
- `GET /tax-rates` → `{"rates":[{"tax_code":"VAT","rate_basis_points":1800}]}`
- `GET /expense-categories` → `{"categories":[{"id","name","is_default"}]}`
- `GET /documents/:id/allocation` → `{"state":"NOT_EVALUATED","labelHe":"טרם נבדק","evaluation":null,"allocationNumber":null,…}`

### 6.10 Expense upload (S10). *Not smoke-tested in this pass*
```json
POST /expenses/uploads/initiate → {"filename":"r.jpg","contentType":"image/jpeg","sizeBytes":123456,"sha256":"<hex>"}
← 201 {"uploadId","status":"SCAN_PENDING","expiresAt","upload":{"kind":"api"|"signed","method":"PUT","url","headers"}}
PUT  <upload.url>  (kind "api": relative to the base URL, same auth headers + upload.headers; raw bytes) ← 204
POST /expenses/uploads/:id/complete → {}  ← 201 {"expenseId","status","sha256","duplicateOfExpenseId","uploadId"} | 202 {"status":"SCAN_PENDING",…}
GET  /expenses/uploads/:id  ← {"uploadId","status","expenseId",…}   // poll on 202
```
HEIC is rejected, so convert to JPEG first. Errors: `UPLOAD_REJECTED`, `SCANNER_INFECTED`, `SCAN_FAILED`, `UPLOAD_EXPIRED`.

## 7. Rate limits
- Auth routes (login, apple, google, device-token): 10 per minute per IP in prod (60 on dev).
- Everything else: 100 per 10 s (300 on dev).
- The public `/d/*`: 60 per minute per IP. `/d/<token>/pdf` also has 60 per minute per link (across all IPs).
- `/mobile/account/delete`: the auth limit, per IP and per bearer token.
- Over the limit you get `429 RATE_LIMITED`.

## 8. Status → app behaviour
| HTTP | Action |
|---|---|
| 401 | Clear the token, go to S1 ("פג תוקף ההתחברות") |
| 403 `MFA_REQUIRED` | G1 (verify or enroll) |
| 403 `DOCUMENT_ACTION_FORBIDDEN` | Show the Hebrew message (missing permission) |
| 409 / 422 | Show the Hebrew message from §9 |
| 429 | Wait and retry, "יותר מדי ניסיונות, נסו בעוד דקה" |
| 503 | "השירות לא זמין זמנית" |

## 9. Error codes → Hebrew
The full list is copied from `apps/web/src/api.ts` (`ERROR_MESSAGES_HE`). The codes the mobile flow can hit:

| Code | Hebrew |
|---|---|
| INVALID_CREDENTIALS | האימייל או הסיסמה שגויים |
| UNAUTHENTICATED | נדרשת התחברות מחדש |
| SESSION_INVALID | פג תוקף החיבור — התחבר מחדש |
| CSRF_INVALID | פג תוקף הטופס — רענן את הדף ונסה שוב |
| MFA_REQUIRED | נדרש קוד אימות דו-שלבי |
| MFA_CODE_INVALID | קוד האימות שגוי |
| MFA_LOCKED | יותר מדי ניסיונות שגויים. נסו שוב בעוד 15 דקות |
| MFA_NOT_ENROLLED | אימות דו-שלבי לא הוגדר לחשבון זה |
| MFA_EMAIL_THROTTLED | נשלח קוד לפני רגע — המתן מעט לפני שליחה חוזרת |
| MFA_EMAIL_UNAVAILABLE | שליחת קודים במייל אינה זמינה בשרת זה |
| GOOGLE_TOKEN_INVALID | אימות Google נכשל — נסה שוב |
| GOOGLE_IDENTITY_MISMATCH | החשבון מקושר לזהות Google אחרת — פנו למנהל העסק |
| GOOGLE_SIGNIN_DISABLED | התחברות Google אינה מופעלת בשרת |
| NO_LINKED_ACCOUNT | אין חשבון פעיל המשויך לכתובת זו. פנה למנהל המערכת. *(the web text says "Google"; use this neutral wording)* |
| **APPLE_TOKEN_INVALID** *(new, not in web)* | אימות Apple נכשל — נסו שוב |
| **APPLE_IDENTITY_MISMATCH** *(new)* | החשבון מקושר לזהות Apple אחרת — פנו למנהל העסק |
| **APPLE_SIGNIN_DISABLED** *(new)* | התחברות Apple אינה מופעלת בשרת |
| **CONFIRMATION_REQUIRED** *(new)* | יש להקליד את מילת האישור כדי למחוק את החשבון |
| **REAUTH_REQUIRED** *(new)* | כדי למחוק את החשבון יש לאמת שוב את הזהות (סיסמה, Apple או Google) |
| **REAUTH_FAILED** *(new)* | לא הצלחנו לאמת את הזהות — נסו שוב |
| RATE_LIMITED | יותר מדי בקשות — המתן רגע ונסה שוב |
| VALIDATION | קלט לא תקין — בדוק את השדות ונסה שוב |
| PASSWORD_POLICY | סיסמה חלשה: לפחות 12 תווים, לא תו חוזר, לא סיסמה נפוצה |
| BUSINESS_REQUIRED | יש לבחור עסק לפני הפעולה |
| DOCUMENT_ACTION_FORBIDDEN | אין לתפקיד שלך הרשאה לפעולה זו. פנו לבעל העסק. |
| DOCUMENT_NOT_FOUND | המסמך לא נמצא |
| CUSTOMER_NOT_FOUND | הלקוח לא נמצא |
| EXEMPT_BUSINESS_VAT_FORBIDDEN | עוסק פטור אינו גובה מע"מ — יש להפיק את המסמך ללא מע"מ |
| DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS | עוסק פטור אינו רשאי להפיק חשבונית מס — הפיקו חשבון עסקה או קבלה |
| ARTIFACT_REQUIRED | חסר קובץ מקור לפעולה זו |
| DOCUMENT_ALREADY_FINALIZED | המסמך כבר הופק — לא ניתן לערוך או להפיק שוב |
| DOCUMENT_INVALID_TRANSITION | לא ניתן לבצע מעבר סטטוס זה למסמך |
| DOCUMENT_NOT_DELIVERABLE | לא ניתן לשלוח מסמך זה — הורידו PDF תחילה |
| DOCUMENT_ALLOCATION_LOCKED | המסמך נעול בזמן בקשת מספר הקצאה מרשות המסים |
| APPROVAL_REQUIRED | המסמך דורש אישור לפני הפקה |
| VAT_RATE_NOT_STATUTORY | שיעור המע"מ בשורה אינו השיעור הסטטוטורי לתאריך המסמך |
| PAYMENT_AMOUNT_INVALID | סכום התשלום אינו תקין |
| PAYMENT_OVERALLOCATED | סכום התשלום עולה על היתרה לתשלום |
| PAYMENT_CHECK_DETAILS_REQUIRED | תשלום בהמחאה מחייב מספר בנק, סניף, חשבון ומספר המחאה |
| CREDIT_LIMIT_EXCEEDED | סכום הזיכוי עולה על היתרה שניתן לזכות במסמך המקור |
| CONSENT_REQUIRED | נדרשת הסכמה לפני ביצוע הפעולה |
| IDEMPOTENCY_CONFLICT | הפעולה כבר בוצעה — רענן את הדף |
| IDEMPOTENCY_KEY_REQUIRED | שגיאה טכנית בבקשה — נסה שוב |
| DELIVERY_NOT_FOUND | המשלוח לא נמצא |
| SHAAM_AUTHORIZATION_REQUIRED | נדרש חיבור לרשות המסים (הגדרות → חשבוניות ישראל) |
| SHAAM_TEMPORARILY_UNAVAILABLE | רשות המסים אינה זמינה כרגע — נסה שוב בעוד רגע |
| ALLOCATION_PENDING | בקשת ההקצאה ממתינה לרשות המסים |
| UPLOAD_REJECTED | הקובץ נדחה — מותרים PDF או תמונה בגודל סביר |
| SCANNER_INFECTED | הקובץ נחסם — זוהה תוכן זדוני |
| SCAN_FAILED | הסריקה נכשלה — נסו להעלות שוב |
| UPLOAD_EXPIRED | חלון ההעלאה פג — נסו להעלות שוב |
| PAYLOAD_TOO_LARGE | הקובץ או הבקשה גדולים מדי |
| DB_UNAVAILABLE | השרת אינו זמין כרגע — נסה שוב בעוד רגע |
| INTERNAL | תקלה בשרת |
| *(any other)* | שגיאה לא צפויה |

## 10. Known gaps (as of 2026-10-30)
1. The new endpoints exist only on `feat/mobile-api` / `feat/mobile-api-v2` and the local dev server; **prod is not deployed**. The prod proxy must also forward `/d/*` and (V2) `/q/*` and `/m/*`.
2. ~~Dashboard income and unpaid figures count receipts (see §6.2).~~ Fixed in V2 (BE-01).
3. ~~No bearer "log out on all devices"~~ (`POST /mobile/logout-all`), ~~no share-link revoke~~ (BE-12), ~~English e-mail subject~~ (BE-13): fixed.
4. Apple sign-in has been verified only with unit tests (mock JWKS), not with a real Apple token.

## V2 · מסמכים וכסף (SRV-2: BE-01, BE-10a, BE-36; P1: BE-06, 07, 08, 10, 11, 12, 13, 14, 26, 36-void)
Server branch `feat/mobile-api-v2`. The handlers live in `apps/api/src/routes/v2/documents.ts` and are registered at the head of `ROUTES`, so they replace the V1 handlers for the same paths. Responses are supersets of V1: no V1 field was renamed. Money is a string of agorot. **Amounts include VAT** (`total_minor`).

### `GET /dashboard` (BE-01)
`summary` keeps every V1 key and adds `unpaid_total`, `overdue_count` and `overdue_total`.
| field | meaning |
|---|---|
| `month_income` / `month_income_count` | Authorized dealer, company or partnership: Σ(305, 320) − Σ(330). Exempt dealer or nonprofit: Σ(400, 405). Only finalized documents whose `issue_date` falls in the current month count. The count is the number of income documents and does not include credit notes. |
| `unpaid_count` / `unpaid_total` (`unpaid_balance` = V1 alias, same value) | 300/305 that are finalized, not voided, with `balance_minor > 0`. The balance is reduced by payments **and credits** (BE-36). Receipts, 320 and 100 are never unpaid. |
| `overdue_count` / `overdue_total` | The unpaid documents whose `due_date` is before today, or `issue_date + 30` when there is no due date. |
Everything is aggregated in SQL, with no row cap. `recent` is unchanged.

### `GET /documents` (BE-10a)
- `limit`: default 100, clamped to 1..500. A value that is not a number gets `422 VALIDATION`. The response echoes `limit` next to `total`, where `total` counts all matches, ignoring the limit.
- `unpaid=1` returns open receivables only: 300/305, finalized, not voided, `balanceMinor > 0`. This is the same population as `/dashboard` `unpaid_*`. In V1 it also returned receipts.
- New row fields:
  - `creditedMinor`: Σ of finalized 330s against this document.
  - `openMinor`: for a finalized, non-voided 300/305 this is `max(0, total − paid − credited)` (equal to `balanceMinor`). It is `"0"` for every other type and for drafts.
  - `cancelled`: `voidedAt != null || creditedMinor >= totalMinor`. When it is true the app shows "בוטל".
  - `voidedAt`: always null until the P1 void endpoint.
  - `dueDate`: `YYYY-MM-DD` or null.
  - `createdBy`: user id.
  - `submittedBy`: user id or null.
  - `sentAt`: the first sent e-mail delivery or the first share link created, whichever is earlier, as ISO-8601. Null means the document was never sent.
  - `rejection`: `{reason, by, at}` or null. It is non-null only while the document is a non-finalized draft whose latest approval action was a rejection.
- Other filters (`documentType`, `status`, `customerId`, `issuedFrom`, `issuedTo`, `documentNumber`) work as in V1. `customerId` must be a UUID and dates must be `YYYY-MM-DD`; otherwise the server returns `422`.

### `GET /documents/:id`
`document` gets new snake_case fields: `credited_minor`, `open_minor`, `cancelled`, `voided_at`, `void_reason`, `due_date`, `original_document_id`, `created_by`, `submitted_by`, `submitted_at` and `rejection`. A malformed id returns `404 DOCUMENT_NOT_FOUND`. For S8, the maximum credit is `total_minor − credited_minor`.

### Credit → original balance (BE-36, migration 0058)
- When a 330 finalizes, the original gets `credited_minor += credit total` and `balance_minor = max(0, total − paid − credited)`. This applies both to a direct finalize and to finalize after allocation. A trigger on the `CREDITS` link does it in the same transaction.
- Existing credits were backfilled.
- After a credit, a payment allocation also clamps the balance at 0.
- **`balance_minor` already includes credits, so `openMinor` does not subtract `credited` a second time.** This is how SPEC §8.2.5 / §15.5 `max(0, balance − credited)` is implemented. Example: 1,180 with a credit of 200 gives `creditedMinor=20000`, `openMinor=98000`.
- The DB guard allows only three columns to change on a finalized document: `credited_minor` (it can only grow), and `voided_at` and `void_reason` (set once). Every other accounting field stays frozen. The cumulative credit limit (`CREDIT_LIMIT_EXCEEDED`, 409) is unchanged.

### P1 additions (SRV-2)
Handlers: `apps/api/src/routes/v2/{documents,payments,quotes}.ts`. Migrations 0060, 0061, 0062, 0064, 0065, 0066. Integration test: `apps/api/test/v2-documents-p1.int.test.ts`.

**Due date + note (BE-07, 0061)** 🛂
- `POST /documents` and `PUT /documents/:id` accept `dueDate` (`YYYY-MM-DD`, not before `issueDate`) and `notes` (trimmed, ≤ 500 chars). On PUT, a missing field keeps the stored value, and `null` or `""` clears it. Otherwise `422 VALIDATION`.
- Both are frozen at finalize. The PDF prints "לתשלום עד: …" and "הערות: …" only when they are set, so printouts without them are byte-for-byte the same template.
- `GET /documents/:id` has `due_date`, `notes`, `overdue`. List rows have `dueDate`, `notes`, `overdue`.

**Search and paging (BE-10, 0064)**: `GET /documents` additionally takes:
- `q` (≤ 100 chars): customer name or line description (contains, case-insensitive, `%`/`_` are literal), or an exact document or allocation number when it is all digits.
- `offset` (default 0), `minTotal`, `maxTotal` (agorot, incl. VAT).
- `overdue=1`: open 300/305 whose `due_date`, or `issue_date + 30` when there is none, is before today. This is the same rule as `/dashboard` `overdue_*`.

The response is `{total, limit, offset, documents}`. `limit` keeps the BE-10a default of 100.

**Document detail** `GET /documents/:id` (two SQL statements) adds:
- `payments[]`: `{id, method, amountMinor, allocatedMinor, paymentDate, reference, receiptDocumentId, voidedAt}`. These are the payments allocated to this document; on a receipt, the payments it covers. `allocatedMinor` is null on a receipt.
- `linkedDocuments[]`: `{id, type, number, status, totalMinor, relation}`. `relation` says what the OTHER document is to this one:
  - `RECEIPT`: a receipt for this.
  - `CREDIT`: a 330 crediting this.
  - `CONVERTED_TO`: this was converted into it.
  - `RECEIPT_FOR`, `CREDIT_FOR`, `CONVERTED_FROM`: the reverse directions.
- `timeline[]`: `{at, event, by, byEmail, detail}`, the document's audit trail, oldest first, at most 200. Typical `event` values:
  - `document.draft_created`, `document.draft_updated`, `document.cloned`
  - `document.approval_submitted|approved|rejected`
  - `document.finalized`, `document.allocation_requested|cancelled`
  - `document.artifact_generated`, `document.signed`
  - `document.shared`, `document.share_downloaded` (first view of the link), `document.share_revoked`
  - `document.send_requested`, `document.sent`, `document.send_failed`
  - `payment.allocated`, `document.credited`, `document.voided`

  `detail` is a whitelist: recipient, channel, amountMinor, creditDocumentId, reason, paymentId, sourceId, revoked, and similar.
- `converted_from_document_id`: on a draft cloned with `link`.

**Clone / linked conversion (BE-08, 0062)**: `POST /documents/:id/clone {documentType?, link?}` returns `201 {id, documentType, convertedFromDocumentId}`.
- The new draft has the source's customer or supplier, lines (with their VAT rates and items) and note. The issue date is empty, so it becomes today at finalize.
- `link:true` requires a finalized source (`409 DOCUMENT_NOT_FINAL`). The `CONVERTED_FROM` link is written when the new document is **finalized**, so a linked draft can still be deleted. This is how a 300 → 305 conversion clears `TAX_INVOICE_DUE`.
- Targets 330/400/405 return `422 CLONE_TYPE_NOT_ALLOWED`. Requires `document:draft:write`.

**Void (BE-36 P1)**: `POST /documents/:id/void {reason}` returns `200 {id, voidedAt}`.
- Only finalized 300/100/500 with no payment allocated and no receipt for them. Requires `document:cancel`.
- The status stays as it is, and `cancelled=true` (shown as "בוטל").
- Errors:
  - `422 DOCUMENT_VOID_NOT_ALLOWED`: another type, or a draft.
  - `409 DOCUMENT_HAS_PAYMENTS`
  - `409 DOCUMENT_ALREADY_VOIDED`

**Share links (BE-12)**
- `POST /documents/:id/share-link/revoke` returns `200 {revoked: n}` and revokes every live link of the document. The public page then answers 404. Requires `document:send`.
- Timeline: see above.

**E-mail (BE-13)**
- The subject is now `"{סוג} {מספר} מאת {שם עסקי או שם משפטי}"`, e.g. "חשבונית מס 3 מאת מוסך כהן". In V1 it was `TAX_INVOICE 3`.
- Copy to the owner: `GET/PUT /settings/document-email {ccOwnerEmail:boolean}`. PUT requires `business:configure`. When it is on, every document e-mail is BCC'd to the active OWNER(s), except one who is the recipient.

**Allocation cancel (BE-26)**: `POST /documents/:id/allocation/cancel {reason?}` returns `200 {id, status:"READY_TO_FINALIZE"}`.
- It works only while no official number is reserved, i.e. the legacy allocation-rules path. Under the live Israel Invoices module the number is reserved at lock time, so the answer is `409 ALLOCATION_NUMBER_RESERVED`. Use `/allocation/decision` instead.
- Not waiting for allocation → `409 ALLOCATION_PENDING`. Requires `document:finalize`.

**Payments (BE-11, 0065)**
- `GET /payments?from=&to=&method=&offset=&limit=(50)&includeVoided=1` returns `{total, limit, offset, payments:[…]}`. Each payment is:

  `{id, method, amountMinor, currency, paymentDate, reference, customerId, customerName, allocations:[{documentId, documentType, documentNumber, amountMinor}], receiptDocumentId, receiptDocumentNumber, recordedBy, recordedAt, voidedAt, voidReason}`

  Voided payments are hidden unless `includeVoided=1`.
- `POST /payments/:id/void {reason}` returns `200 {id, voidedAt, reused}`, and is idempotent. Requires `payment:record`.
  - Only a payment that is in **no** finalized document and **no** receipt can be voided. Otherwise `409 PAYMENT_LOCKED_IN_DOCUMENT`. The remedy is a credit for a 320, or cancelling the receipt on the web.
  - A voided payment can never be allocated or receipted again (`409 PAYMENT_VOIDED`).
  - Unknown id → `404 PAYMENT_NOT_FOUND`.
- Receipts now record which payments they cover (`payment_receipts`, backfilled from the audit trail).

**More payment methods (BE-14, 0066)** 🛂
- `POST /payments` accepts `BIT`, `PAYBOX`, `WITHHOLDING_TAX`, `APPLE_PAY`, `GOOGLE_PAY` **only when the server runs with `PAYMENT_METHODS_EXTENDED=1`**. Otherwise it answers `422 PAYMENT_METHOD_NOT_ENABLED`, and the app keeps sending `BANK_TRANSFER` (§9.1).
- The Uniform Format mapping for these methods is deliberately not defined until compliance signs it; an export that contains one fails closed.

**Quotes (BE-06, 0060)**
- `POST /quotes` and `PUT /quotes/:id` lines may carry `taxRateBasisPoints` (integer or null) and `itemId`.
  - PUT is allowed while the quote is `DRAFT` **or `SENT`**; a `SENT` quote stays `SENT` and the edit is audited.
  - Other statuses → `409 QUOTE_INVALID_TRANSITION`.
  - An exempt dealer with a rate above 0 → `422 EXEMPT_BUSINESS_VAT_FORBIDDEN`.
- `GET /quotes/:id` returns `{quote:{id, status, customerId, customerName, currency, validUntil, notes, convertedDocumentId, createdBy, createdAt, updatedAt, netMinor, taxMinor, totalMinor, hasLinesWithoutRate, sentAt}, lines:[{position, description, quantity, quantityMicros, unitPriceMinor, discountMinor, netMinor, taxRateBasisPoints, taxMinor, totalMinor, itemId}]}`.
  - `totalMinor` includes VAT.
  - V1 `GET /quotes` `totalMinor` is still the **net** amount.
- `POST /quotes/:id/convert {documentType, taxRateBasisPoints?}`: each line keeps its own rate. The body rate is required only when some line has none, otherwise `422`. Items are carried over.
- `POST /quotes/:id/clone` returns `201 {id}`: a new `DRAFT`, valid until today + 14.
- `GET /quotes/:id/pdf`: rendered on demand from the live quote, never stored, and not an accounting artifact.
- `POST /quotes/:id/share-link` returns `201 {url, expiresAt}`, valid for 30 days.
  - Allowed for `DRAFT`, `SENT` or `ACCEPTED` quotes; otherwise `409`.
  - The public page `/d/:token` shows the quote (lines, total, valid until). `/d/:token/pdf` returns the quote PDF.
  - `quote.sentAt` is the first link.

**New error codes → Hebrew (also in `apps/web/src/api.ts`)**
| code | HTTP | עברית |
|---|---|---|
| `PAYMENT_LOCKED_IN_DOCUMENT` | 409 | התשלום כלול במסמך שהופק. לביטול – הפק זיכוי, או בטל את הקבלה במחשב. |
| `PAYMENT_VOIDED` | 409 | התשלום בוטל ולא ניתן להשתמש בו. |
| `PAYMENT_NOT_FOUND` | 404 | התשלום לא נמצא. |
| `PAYMENT_METHOD_NOT_ENABLED` | 422 | אמצעי התשלום עדיין לא זמין. רשום אותו כהעברה בנקאית. |
| `DOCUMENT_VOID_NOT_ALLOWED` | 422 | אפשר לבטל כך רק חשבון עסקה, הזמנה או הזמנת רכש שהופקו. |
| `DOCUMENT_ALREADY_VOIDED` | 409 | המסמך כבר בוטל. |
| `DOCUMENT_HAS_PAYMENTS` | 409 | יש תשלום על המסמך. בטל קודם את הקבלה במחשב. |
| `CLONE_TYPE_NOT_ALLOWED` | 422 | אי אפשר לשכפל לסוג המסמך הזה. |
| `ALLOCATION_NUMBER_RESERVED` | 409 | המספר כבר שמור ברשות המסים – אי אפשר לבטל את הבקשה. בחר "המשך בלי מספר" או נסה שוב. |

## V2 · הרשאות וזהות (SRV-1: BE-02, BE-03a, BE-37; P1: BE-41; P2: BE-03, BE-04, BE-49)
Server branch `feat/mobile-api-v2`. `GET /me` lives in `apps/api/src/routes/v2/me.ts` and is registered at the head of `ROUTES`. The domain guards (BE-03a/BE-37) are inside the shared domain functions, so they apply to the V1 and V2 routes alike.

### `GET /me` (BE-02): a V1 superset
Every V1 field keeps its name and meaning: `userId`, `role`, `mfaEnrolled`, `onboarding{completed,step}`, `canFinalize`, `canConfigure`, `canApproveExpenses` and `approvalPolicy{mode,thresholdMinor,selfApprovalAllowed}`.
New fields:
| field | meaning |
|---|---|
| `isOwner` | `role == "OWNER"` |
| `permissions[]` | **The effective list**: role permissions ∪ extra grants (the same computation as `isAuthorized`). Unknown and non-grantable extras never appear. The order is fixed: `document:read, document:draft:write, document:finalize, document:send, payment:record, expense:record, expense:approve, business:configure, membership:manage, document:cancel, approval:decide`. `caps.dart` reads only this list. |
| `businessType` | `OSEK_PATUR` / `OSEK_MURSHE` / `COMPANY` / `PARTNERSHIP` / `NONPROFIT` |
| `vatReporting` | `MONTHLY` / `BIMONTHLY` / `NONE` / null |
| `memberCount` | Active members of the business, including the caller. |
| `approvalPolicy.includesVat` | Always `true`. The threshold is compared with `total_minor` using `>=`. |
| `approvalPolicy.otherApproverExists` | Whether an active member other than the caller holds `approval:decide`. When it is false, §13.6 hides the "self-approval" row and sends `selfApprovalAllowed:true`. |
| `shaam` | The same fields as `GET /shaam/status`: `environment, status, authorizedVatNumber, authorizedSubjectHint, lastVerifiedAt, refreshTokenExpiresAt, lastErrorCode, killSwitch, manualEntryEnabled, canConfigure`. When the server has SHAAM off, `status` is `"DISABLED"`. |
| `signing` | `{configured, enabled, unlocked}`. `configured` means an ACTIVE signing identity exists. `enabled` means computerized signing is turned on in the settings. `unlocked` means the signing session is open on this server. |
| `exports.uniformFormatReady` | The server has a configured uniform-format identity **and** a VERIFIED compliance decision exists for today. |
| `rules` | `{exemptCeilingMinor:"12000000", exemptCeilingYear:2026, yearTurnoverMinor}`. The ceiling is a constant in `packages/shared/src/regulatory-constants.ts`, with its source cited there and a yearly update required. `yearTurnoverMinor` is income for the current calendar year (Israel date): exempt dealer or nonprofit = Σ(400, 405); everyone else = Σ(305, 320) − Σ(330). |
| `enforcement.readGating` | `true` since BE-03 (P2): amounts, reports and exports are gated on the server (see BE-03 below). |
There is no `plan` field.

### New permissions (BE-03a)
- `document:cancel` and `approval:decide` belong to **OWNER, ADMIN and ACCOUNTANT only**. They are **never granted** as extras: `PUT /business/members/:id/permissions` returns `400 VALIDATION`, the same as `business:configure` and `membership:manage`. `GET /business/members` → `grantablePermissions` does not list them.
- `POST /documents/:id/credit` requires `document:cancel`; `document:finalize` is no longer enough. Finalizing a `CREDIT_DOCUMENT` through any other path also requires `document:cancel`.
- `POST /documents/:id/approve` and `/reject` require `approval:decide`.
- Without the permission the server returns `403 DOCUMENT_ACTION_FORBIDDEN`. Per §4.6, refresh `/me` after this error.

### Critical guards (BE-03a)
| case | error |
|---|---|
| Credit for a type other than 305/320 (400, 405, 300, 330, …), or any credit in an exempt dealer business | `422 CREDIT_SOURCE_TYPE_INVALID` |
| `POST /documents` or `PUT /documents/:id` with `issueDate` before today (Israel date) by anyone except OWNER. An empty `issueDate` means today and is allowed. | `403 BACKDATING_OWNER_ONLY` |
| MFA is required for OWNER, ADMIN and ACCOUNTANT **and for every member who holds `document:finalize` or `payment:record`**, whether through the role or as an extra grant. On a cookie session without MFA, business routes return `403 MFA_REQUIRED` and `/auth/device-token` is refused. A device token issued without MFA stops working (`403 MFA_REQUIRED`, "sign in again") as soon as the member receives "self-issuer". | `403 MFA_REQUIRED` |

### Approvals (BE-37)
- **System documents are exempt from the threshold.** A receipt from `POST /receipts` and a credit from `POST /documents/:id/credit` are issued without `APPROVAL_REQUIRED`. The `APPROVAL_REQUIRED` fallback in S5/S8 is no longer needed on this server.
- **Single approver.** When no other active approver exists, `approve` lets the submitter approve their own document even with `selfApprovalAllowed=false`.
- `PUT /settings/approval {mode:"THRESHOLD", selfApprovalAllowed:false}` when there is no other approver returns `422 APPROVAL_NO_OTHER_APPROVER`. An EMPLOYEE, even one with "self-issuer", does not count as an approver.
- **Rejection.** The document returns to `DRAFT`, and **`submitted_by` / `submitted_at` are now kept** (in V1 they were cleared), so the submitter's `MY_REJECTED` card can show the document as theirs. `GET /documents` (`submittedBy`, `rejection`) and `GET /documents/:id` (`submitted_by`, `rejection`) show the reason (SRV-2's route). On the server, `getApprovalInfo(client, scope, ids)` returns `{submittedBy, submittedByEmail, submittedAt, rejection{reason, by, byEmail, at}|null}` for the inbox (BE-05). After a new submit, `rejection` becomes null.

### New error codes → Hebrew
| Code | Hebrew |
|---|---|
| BACKDATING_OWNER_ONLY (403) | רק בעל העסק יכול להפיק מסמך בתאריך עבר |
| CREDIT_SOURCE_TYPE_INVALID (422) | אפשר להפיק זיכוי רק לחשבונית מס או לחשבונית מס-קבלה |
| APPROVAL_NO_OTHER_APPROVER (422) | כדי לחייב אישור של אדם אחר צריך חבר צוות נוסף שמורשה לאשר מסמכים |

### Invitations (BE-41, P1)
Route file `apps/api/src/routes/v2/team.ts` (head of `ROUTES`); domain in `packages/postgres/src/members.ts`; migration 0075 (`invitations.permissions`).
- `POST /business/members/invite {email, role, note?, permissions?[]}` → `201 {invitationId, link, inviteUrl, expiresAt, role, permissions}`.
  - `permissions` is optional (missing/null = `[]`). Only `grantablePermissions` are accepted; `document:cancel`, `approval:decide`, `business:configure`, `membership:manage` or an unknown name → `400 VALIDATION`; not an array of strings → `422 VALIDATION`.
  - The server stores only extras the role does not already include, so the response `permissions` can be shorter than what was sent (e.g. EMPLOYEE + `document:read` → `[]`).
  - Presets in one call: "עובד" `{role:"EMPLOYEE"}` · "מפיק בעצמו" `{role:"EMPLOYEE", permissions:["document:finalize","payment:record"]}` · "רואה חשבון" (until BE-04) `{role:"READ_ONLY", permissions:["expense:record","expense:approve"]}` – the P0 follow-up `PUT …/permissions` after joining is no longer needed.
  - On acceptance the membership gets exactly the invitation's grants (a previously removed member does **not** get their old grants back). A self-issuer then needs MFA (BE-03a).
- `POST /business/invitations/:id/resend` (no body) → `200` with the same shape. New token, a fresh 7-day expiry, the e-mail is sent again; **the previous link stops working** (`INVITATION_INVALID`). Allowed for pending invitations and for expired ones (not revoked, not accepted). Revoked/superseded/accepted, another business's id or a malformed id → `400 NOT_FOUND` (same as V1 revoke). An address that is already an active member → `409 MEMBER_EXISTS`. Requires `membership:manage` (else `403 DOCUMENT_ACTION_FORBIDDEN`).
- `inviteUrl` = `https://<APP_ORIGIN host>/m/invite/<token>` – the universal link for "שלח קישור בווטסאפ" (share sheet, plain text). The e-mail carries it too (plus the V1 web `link` as a fallback). Until AASA (BE-00 §5) the link opens in the browser: the server answers `302 → /app/#/invite?token=<token>` (the web invite page). This redirect is served only where the API serves the web bundle (`WEB_DIST` set; production/Vercel proxies all paths to the API).
- `GET /business/members` additions: every `invitations[]` row has `permissions[]`; new `expiredInvitations[]` (same row shape) = expired in the last 30 days, not revoked/accepted – the "פג תוקף · שלח שוב" rows. `invitations[]` still lists only live ones.
- `GET /auth/invite/:token` (public preview) adds `permissions[]`. Expired → `410 INVITATION_EXPIRED`, revoked/superseded → `410 INVITATION_REVOKED`; unknown token, a token replaced by a resend, or an already-used invitation stay `410 INVITATION_INVALID`.

| Code | Hebrew |
|---|---|
| INVITATION_EXPIRED (410) | ההזמנה כבר לא בתוקף. בקש מהמזמין לשלוח שוב |
| INVITATION_REVOKED (410) | ההזמנה בוטלה. בקש מהמזמין לשלוח שוב |

### Full permissions, representing accountant, ownership transfer (BE-03, BE-04, BE-49, P2)
Server: `packages/security/src/rbac.ts` (roles/permissions), `apps/api/src/routes/v2/access.ts` (**one rule per authenticated route**, wrapped around `ROUTES`), `packages/postgres/src/ownership.ts`, migrations **0059** (`membership_role` += `ACCOUNTANT_REP`) and **0077** (`ownership_transfers`). The generated matrix `apps/api/test/v2-rbac-matrix.int.test.ts` checks every authenticated route × 8 presets (1,280+ cases) and fails when a route has no rule.

**New permissions** (they appear in `/me.permissions` in this order after `approval:decide`): `money:read, report:read, export:run, customer:manage, supplier:manage, item:manage, payment:refund, allocation:request, settings:numbering, customer:accountKey`. Never grantable (→ `400 VALIDATION` on `PUT …/permissions` and on invite): `payment:refund`, `settings:numbering`, `customer:accountKey` (plus the four from BE-03a).

| preset | role | permissions |
|---|---|---|
| בעלים / שותף | OWNER / ADMIN | everything **except** `settings:numbering`, `customer:accountKey` |
| רו״ח – מלא | ACCOUNTANT | V1 set + `document:cancel, approval:decide` + `money:read, report:read, export:run, customer:manage, supplier:manage, item:manage, allocation:request` |
| **רואה חשבון (מייצג)** | **ACCOUNTANT_REP** (new) | `document:read, expense:record, expense:approve, money:read, report:read, export:run, allocation:request, settings:numbering, customer:accountKey` — **no** `document:send`, no drafting/issuing. MFA required. |
| עובד | EMPLOYEE | unchanged (`document:read, document:draft:write, document:send, expense:record`) |
| צפייה בלבד | READ_ONLY | `document:read, money:read` |

The P0 accountant preset (READ_ONLY + `expense:record`,`expense:approve`) keeps working but now also has `money:read`; it has **no** `report:read`/`export:run` → from BE-04 invite `{role:"ACCOUNTANT_REP"}` instead (no automatic migration, §19 Q2). Role label: `רואה חשבון (מייצג)`. `/me.enforcement.readGating` is now **`true`**.

**Read gating (no `money:read`, i.e. EMPLOYEE)** — refusals are `403 DOCUMENT_ACTION_FORBIDDEN` (refresh `/me`, §4.6):
| route | behaviour |
|---|---|
| `GET /dashboard`, `GET /mobile/inbox`, `GET /payments`, `GET /customers`, `GET /customers/:id` | every money field (`*Minor`, `*_minor`, `month_income`, `month_expenses`, `unpaid_*`, `overdue_total`, `money`) is `null`; counts stay |
| `GET /documents`, `GET /quotes` | money fields `null` **except rows the caller created** (`createdBy`/`created_by` = me) |
| `GET /documents/:id`, `GET /quotes/:id` | amounts `null` unless the caller created it |
| `GET /approvals` | `totalMinor` `null` except rows whose `createdBy` is the caller (each row now carries `createdBy`) |
| `GET /documents/:id/pdf`, `POST /documents/:id/artifact`, `POST /documents/:id/send`, `POST /documents/:id/share-link`, `GET /quotes/:id/pdf`, `POST /quotes/:id/share-link` | 403 unless the caller created the document/quote (an id the caller cannot see still answers 404) |
| `GET /customers/:id/statement*` | `money:read` |

**Write gating**
| route | needs |
|---|---|
| `/exports/*` | `export:run` (READ_ONLY and EMPLOYEE can no longer export XLSX) ; `/exports/accountant` also `expense:record` |
| `/reports/*` | `report:read` (+ `export:run` for non-JSON formats and `/send`) |
| `PATCH /customers/:id` | per field: `accountKey` → `customer:accountKey` (ACCOUNTANT_REP only); `vatDealerStatus`, `taxId` → `customer:manage` **or** `document:draft:write` (the §4.9 "is the customer an authorized dealer?" dialog keeps working for employees); any other field → `customer:manage` |
| `POST /customers/:id/archive` | `customer:manage` |
| `POST /items`, `PATCH /items/:id`, `POST /items/:id/archive|restore` | `item:manage` (creating included — matches the app's "save as item" gate `Cap.itemManage`; EMPLOYEE/self-issuer get 403) |
| `PATCH/archive/restore /suppliers/:id` | `supplier:manage` (creating a supplier stays `expense:record`) |
| `POST /documents/:id/allocation` and `/allocation/{request,reconcile,decision,manual,cancel}` | `allocation:request` (was `document:finalize`). **The "מפיק בעצמו" toggle should now send `["document:finalize","payment:record","allocation:request"]`**, otherwise the self-issuer cannot retry a failed allocation. `GET …/allocation` and `/allocation/evaluate` stay `document:read`. |
| `PUT /sequences/:scopeKey/start` | `business:configure` **or** `settings:numbering` (same untouched-scope rule) |

**Ownership transfer (BE-49)** — `POST /business/ownership/transfer`, OWNER only (anyone else `403 DOCUMENT_ACTION_FORBIDDEN`). Two steps, same route:
1. `{toUserId}` → `202 {status:"CODE_SENT", sentTo:"ow***@x.com", expiresAt}`. A 6-digit code is e-mailed **to the owner** (the fresh second factor); valid 10 minutes, a new request cancels the previous code, at most one request per minute (`429 OWNERSHIP_CODE_THROTTLED`).
2. `{toUserId, code}` → `200 {status:"TRANSFERRED", ownerUserId, previousOwnerUserId, previousOwnerRole:"ADMIN"}`. The target becomes OWNER (extra grants cleared), the caller becomes ADMIN, audited `business.ownership_transferred`, the new owner gets an e-mail. Wrong code → `422 OWNERSHIP_CODE_INVALID` (5 tries, then the code is burnt); expired/used/burnt/other target → `410 OWNERSHIP_CODE_EXPIRED`.
Errors: `toUserId` = self → `400 VALIDATION`; not an active member → `404 MEMBER_NOT_FOUND`; already owner → `409 ALREADY_OWNER`; `code` not 6 digits → `422 VALIDATION`. After the transfer the former owner is no longer the sole owner, so `POST /mobile/account/delete` no longer closes the business (§13.15 "העבר בעלות"). The new owner needs MFA at the next sign-in.

| Code | Hebrew |
|---|---|
| MEMBER_NOT_FOUND (404) | החבר לא נמצא בעסק או שאינו פעיל |
| ALREADY_OWNER (409) | החבר הזה כבר בעלים של העסק |
| OWNERSHIP_CODE_THROTTLED (429) | נשלח קוד לפני רגע — נסה שוב בעוד דקה |
| OWNERSHIP_CODE_INVALID (422) | הקוד שגוי |
| OWNERSHIP_CODE_EXPIRED (410) | הקוד פג או נוצל — בקש קוד חדש |

## V2 · אנשים, הוצאות ודוחות (SRV-3: BE-05, BE-09, BE-15, BE-23, BE-24, BE-25, BE-35)
Server branch `feat/mobile-api-v2`. Route files: `apps/api/src/routes/v2/{inbox,customers,donations,mobile}.ts` (head of `ROUTES`, so `GET /customers`, `PATCH /customers/:id` and `GET /items` replace their V1 handlers as V1-compatible supersets). Domain: `packages/postgres/src/{inbox,items,customers,business-profile}.ts`. Migrations **0063** (customers + inbox indexes, `pg_trgm`) and **0067** (`catalog_items.archived_at`).

### `GET /mobile/inbox?limit=10` (BE-05). Bearer + `X-Business-Id`
`/mobile/*` paths that are not account-level (`session`, `businesses`, `logout*`, `account/delete`) now fall through to the business routes, so this route needs `X-Business-Id`.
```json
{"generatedAt":"…",
 "money":{"openMinor":"177000","overdueMinor":"118000"} | null,
 "cards":[{"kind":"OVERDUE","priority":50,"count":1,"amountMinor":"118000","documentIds":["…"],
           "action":"SEND_REMINDERS",
           "detail":{"documentId":"…","documentType":"TAX_INVOICE","status":"FINALIZED","customerName":"דנה כהן","totalMinor":"118000"}}],
 "recent":[{"id","documentType","status","documentNumber","customerName","totalMinor","openMinor","issueDate","cancelled"}]}
```
- `limit` (1..20, default 10) caps **cards** (already sorted by `priority` desc). `recent` is always the 5 newest documents. Bad `limit` → `422 VALIDATION`.
- Money = `total_minor` (VAT incl.) with the exact `/dashboard` (BE-01) definitions: open = finalized, not voided 300/305 with `balance_minor > 0`; overdue = open and `coalesce(due_date, issue_date + 30) < today`. `money` is `null` for EMPLOYEE (`money.view`, a UI convenience until BE-03); card `amountMinor` is then `null` too.
- `detail` describes the **first** (most urgent) document of the card – enough for the one-line title; `documentIds` holds up to 20, most urgent first.

| kind | priority | action | who gets it (server-filtered) | source |
|---|---|---|---|---|
| `APPROVAL_NEEDED` | 100 | `OPEN` | `approval:decide` | status `PENDING_APPROVAL` (oldest first) |
| `MY_REJECTED` | 90 | `FIX` | `document:draft:write`, only the submitter | DRAFT whose latest approval action is `REJECTED` and `submitted_by = me`; `detail.rejection = {reason, by, byEmail, at}` |
| `TAX_INVOICE_DUE` | 80 | `ISSUE_TAX_INVOICE` | `document:finalize`, not `OSEK_PATUR`/`NONPROFIT` | finalized, not voided 300 with `paid > 0` and balance 0, with no finalized 305/320 linked (`document_links CONVERTED_FROM` either direction, or `original_document_id`); `detail.dueBy` = last payment date + 14 |
| `ALLOCATION_PROBLEM` | 70 | `RETRY_ALLOCATION` | `document:finalize` | status `WAITING_FOR_ALLOCATION` |
| `SIGNING_LOCKED` | 60 | `SIGN` | `document:finalize` (EMPLOYEE: only documents they created/finalized) | status `ARTIFACT_PENDING` |
| `UNFINISHED` | 55 | `CONTINUE` | `document:draft:write` (EMPLOYEE: only `created_by = me`) | `DRAFT`/`VALIDATING`/`READY_TO_FINALIZE`, newest first; a rejected draft is **not** here (it is its submitter's `MY_REJECTED`). The app adds its local "issue interrupted" journal itself. |
| `OVERDUE` | 50 | `SEND_REMINDERS` | `document:send` + money view | overdue set above; `amountMinor` = Σ open balance |
| `EXPENSE_REVIEW` | 40 | `REVIEW` | `expense:approve` | expenses `NEEDS_REVIEW`/`READY_TO_APPROVE`; ids in `expenseIds` (`documentIds` is `[]`), `detail` null |
| `SHAAM_RENEW` | 20 | `RENEW_SHAAM` | `business:configure`, SHAAM enabled | `EXPIRED`/`REAUTH_REQUIRED`, or `CONNECTED` with `refreshTokenExpiresAt` within 14 days; `detail{shaamStatus, refreshTokenExpiresAt}` |
| `SETUP` | 10 | `SETUP` | one at a time | `detail.step`: `RECOVERY_CODES` (any member with a second factor and 0 unused recovery codes) → `LOGO` → `PAYMENT_LINK` (`business:configure`) → `TEAM_MEMBER` (`membership:manage`, only member). The ✕ is local. |

Since P2: `QUOTE_ACCEPTED` (BE-21) and `CONTINUITY_GAP` (BE-18) **are produced** (see the P2 section). Not produced: `PAYMENT_RECEIVED` (BE-28b, P3) and `REPORT_READY` (never; reports are e-mailed). READ_ONLY gets no cards. Cost: 2 SQL statements (+1 SHAAM row read for `business:configure`); measured p50 28 ms / p95 30 ms on a business with 50,000 documents (local Postgres).

### Customers (BE-09)
`GET /customers?q=&status=ACTIVE|ARCHIVED&sort=name|recent&offset=&limit=` → `{total, offset, limit, customers:[…]}`
- Without parameters: every customer (active + archived), sorted by name, up to 500 – the V1 behaviour. `limit` 1..500, `offset` ≥ 0; bad values → `422 VALIDATION`.
- `q`: name contains (trigram index), e-mail starts with; when `q` has ≥ 3 digits also tax id / phone digits contain them ("050-123" finds "0501234567"). `%`/`_` are literal.
- `sort=recent`: latest document first (customers without documents last, then by name).
- Each row keeps the V1 snake_case fields (`id, name, tax_id, email, phone, archived_at, vat_dealer_status, customer_type`) and adds: `balanceMinor` (Σ open 300/305 balances), `creditMinor` (Σ over 300/305/320 of `max(0, paid + credited − total)` – e.g. a credit on a paid invoice), `lastDocumentAt`, `lastLineDescription` (first line of the newest document – F8 default), `isWalkIn`, `consent{granted}`.

`GET /customers/:id` → 
```json
{"customer":{"id","name","customerType","taxId","email","phone","vatDealerStatus","archivedAt","isWalkIn",
             "address":{"street","number","city","postalCode"}|null,"contactPerson","paymentTerms","notes","accountKey",
             "consent":{"granted":true,"method":"APP_TOGGLE","at":"…"}},
 "stats":{"openMinor","overdueMinor","creditMinor","documentsCount","lastDocumentAt"}}
```
`documentsCount` = finalized documents. Malformed / unknown / another business's id → `404 CUSTOMER_NOT_FOUND`. Readable by every member (money gating is BE-03).

`PATCH /customers/:id` – V1 fields plus:
| field | value |
|---|---|
| `address` | `{street?, number?, city, postalCode?}` or `null` (clear). `city` required when anything is set; postal code checked. |
| `contactPerson` | text ≤ 200 or `null`/`""` |
| `paymentTerms` | `IMMEDIATE` (מיידי) · `EOM` (שוטף) · `EOM_30` · `EOM_45` · `EOM_60` · `EOM_90` (שוטף+N) or `null` |
| `notes` | text ≤ 2000 or `null`/`""` |
| `isWalkIn` | boolean. `true` **moves** the business's single "לקוח מזדמן" flag to this customer (the previous one is cleared). |
| `accountKey` | requires `customer:accountKey` = **ACCOUNTANT_REP only** (BE-04). Everyone else, the owner included → `403 DOCUMENT_ACTION_FORBIDDEN`. |
Write permission (since BE-03): per field, see "Write gating" in the SRV-1 section (`customer:manage`; `vatDealerStatus`/`taxId` also `document:draft:write`).

### Items (BE-15)
- `GET /items?q=&includeArchived=1` → `{items:[…]}`: V1 fields (`id, sku, name, item_type, unit, default_unit_price_minor, currency, is_active`) + `description`, `archivedAt`. Archived items are **hidden by default** (V1 listed them); `q` = name/SKU/description contains. Up to 500, by name.
- `PATCH /items/:id {name?, sku?, description?, unit?, itemType?, defaultUnitPriceMinor?}` → `{id}`. Validation → `422`; unknown/other business → `404 ITEM_NOT_FOUND`.
- `POST /items/:id/archive` / `POST /items/:id/restore` → `{id, archived}` (idempotent; keeps `is_active` in step).
- Permission (since BE-03): `item:manage` for create (`POST /items`), PATCH, archive and restore, else `403`. Issued documents never change (lines carry their own text and price).

### §46 donation reporting (BE-23)
- `PUT /business/profile {section46ApprovalNumber}` already existed (V1).
- `POST /documents/:id/donation-report {complianceDecisionId, donationId?}` → `200 {status:"REPORTED", reportNumber} | {status:"REJECTED", reasonCode} | {status:"UNKNOWN"}`. Repeat = same answer, no second report. `donationId` defaults to `R-<documentId>`.
- `POST /documents/:id/donation-report/cancel {complianceDecisionId, cancellationDonationId?}` (default `C-<documentId>`) – reports the cancellation of a reported receipt.
- `GET /documents/:id/donation-report` → `{reports:[{donationId, requestType:"REPORT"|"CANCEL", status:"PENDING"|"REPORTED"|"REJECTED"|"UNKNOWN"|"CANCELLED", reportNumber, originalReportNumber, attemptCount, lastErrorCode, submittedAt, completedAt}]}`.
- Needs `document:finalize` (`403`). `complianceDecisionId` must be a VERIFIED decision (`409 COMPLIANCE_DECISION_NOT_VERIFIED`) – the app has no such id today, so this is an accountant/back-office action.
- **The live Israel Donations port is not connected anywhere** (DONATE-001). Until it is wired at start-up, both POSTs answer `503 DONATION_REPORTING_DISABLED` and record nothing. The "קבלה על תרומה" tile still depends only on `section46ApprovalNumber` (§4.7).

### Business list (BE-24)
- `GET /mobile/businesses?q=&offset=&limit=` (Bearer, **no** `X-Business-Id`) and `GET /auth/my-businesses?q=&offset=&limit=` (cookie) → `{total, offset, limit, businesses:[{businessId, legalName, role}]}`. `q` = legal name contains (case-insensitive). No `limit` = all matches (V1). `limit` 1..200; bad values → `422`. Order: legal name. S14 uses `/mobile/businesses` with search when > 7.

### Onboarding (BE-25)
- `POST /auth/apple` / `POST /auth/google` accept optional `businessType` (`OSEK_PATUR|OSEK_MURSHE|COMPANY|PARTNERSHIP|NONPROFIT`). It is used **only** when self-signup creates a new business (ignored for an existing user); default `OSEK_MURSHE`. Invalid → `422 VALIDATION` (checked before sign-in).
- `GET/PUT /business/profile` → `profile.defaultLineDescription` (text ≤ 200, `""`/`null` clears). F8: description = last for the customer (`lastLineDescription`), else this, else "שירותים".

### Continue on the computer (BE-35)
`POST /mobile/web-handoff {topic}` (Bearer + `X-Business-Id`) → `202 {status:"SENT", topic}` and an e-mail to the user's own address: subject "תבל — להמשך במחשב: {נושא}", body with `<APP_ORIGIN>/#/<page>`.
| topic | page | allowed for |
|---|---|---|
| `MORE_DOCUMENT_TYPES` | documents | `document:draft:write` |
| `INVENTORY`, `ADVANCED_BRANDING`, `MESSAGE_TEMPLATES`, `TAX_AUTHORITY`, `BUSINESS_TYPE_CHANGE`, `CSV_IMPORT`, `CUSTOMER_MERGE`, `SIGNING_CERTIFICATE`, `API_INTEGRATIONS` | inventory / design / settings / customers | `business:configure` |
| `CUSTOM_PERMISSIONS` | settings | `membership:manage` |
| `RECEIPT_CANCEL` | documents | `document:cancel` |
| `UNIFORM_FORMAT`, `BOOKKEEPING_CERTIFICATES` | exports / settings | `business:configure` or `expense:approve` (accountant preset) |
| `LOGIN_EMAIL_CHANGE` | settings | every member |
Unknown topic → `422 VALIDATION`; not allowed → `403 DOCUMENT_ACTION_FORBIDDEN`; more than 5 per user per business per hour → `429 WEB_HANDOFF_THROTTLED`; no e-mail on the account → `409 EMAIL_MISSING`; mail provider down → `503 EMAIL_UNAVAILABLE`. Never a subscription/purchase topic.

### New error codes → Hebrew
| Code | Hebrew |
|---|---|
| ITEM_NOT_FOUND (404) | הפריט לא נמצא |
| WEB_HANDOFF_THROTTLED (429) | נשלחו יותר מדי קישורים בשעה האחרונה. נסה שוב מאוחר יותר. |
| EMAIL_MISSING (409) | לחשבון אין כתובת אימייל |
| EMAIL_UNAVAILABLE (503) | לא הצלחנו לשלוח את המייל. נסה שוב. |
| DONATION_REPORTING_DISABLED (503) | דיווח תרומות לרשות המסים עדיין לא מחובר |
| DONATION_REPORTING_TRANSIENT (503) | מערכת דיווח התרומות לא זמינה כרגע. נסה שוב. |
| DONATION_REPORT_NOT_APPLICABLE (422) | רק קבלה על תרומה מדווחת למערכת התרומות |
| DONATION_NOT_REPORTED (409) | הקבלה עוד לא דווחה, ולכן אין מה לבטל |
| SECTION46_APPROVAL_REQUIRED (422) | חסר מספר אישור לפי סעיף 46 בפרטי העסק |
| FINALIZATION_EVIDENCE_MISSING (409) | המסמך עוד לא הופק |

### P2 additions (SRV-3: BE-16, 17, 18, 19, 21, 22, 40, 43, 44)
Route files `apps/api/src/routes/v2/{expenses,reports,business,quote-accept}.ts`; domain `packages/postgres/src/{suppliers,expenses-v2,reports,statement,reminders,quote-acceptance,accountant-automation,businesses}.ts`. Migrations **0068** (suppliers + expenses), **0069** (report index), **0070** (reminders), **0072** (quote acceptance), **0073** (accountant automation), **0074** (business type change + `issuer_snapshot.businessType`). 0071 (BE-20 push) is not used. Worker: `apps/worker/src/automation-consumer.ts` (every `AUTOMATION_INTERVAL_MS`, default 15 min).

#### Suppliers (BE-16)
- `GET /suppliers?q=&status=ACTIVE|ARCHIVED&offset=&limit=` → `{total, offset, limit, suppliers:[{id, name, tax_id, email, phone, archived_at, expensesCount, approvedTotalMinor, lastExpenseAt}]}`. V1 superset: without parameters every supplier (active + archived) by name, up to 500. `q` like customers (name contains, e-mail starts, ≥3 digits → tax id / phone). `approvedTotalMinor` = Σ approved expenses incl. VAT (`null` without money view).
- `GET /suppliers/:id` → `{supplier:{id, name, taxId, email, phone, address|null, contactPerson, notes, paymentTerms, defaultCategoryId, archivedAt, createdAt}, stats:{expensesCount, approvedTotalMinor, vatTotalMinor, pendingCount, lastExpenseAt}}`.
- `PATCH /suppliers/:id {name?, taxId?, email?, phone?, address?, contactPerson?, notes?, paymentTerms?, defaultCategoryId?}` → `{id}` (`null`/`""` clears; empty body → `422`). Approved expenses keep the supplier name/tax id they were approved with.
- `POST /suppliers/:id/archive` · `/restore` → `{id, archived}`.
- Write permission: `supplier:manage` (BE-03; before BE-03: `expense:record`). Creating stays `POST /suppliers` (`expense:record`). Unknown / other business → `404 SUPPLIER_NOT_FOUND`.

#### Expenses list / edit / delete (BE-44)
- `GET /expenses?q=&mine=1&status=&from=&to=&offset=&limit=50` → `{total, mine, offset, limit, expenses:[{id, status, supplierId, supplierName, supplierTaxId, documentType, documentNumber, expenseDate, currency, subtotalMinor, vatMinor, totalMinor, categoryId, categoryName, allocationNumber, paymentMethod, duplicateOfExpenseId, originalFilename, createdBy, createdByEmail, createdAt, approvedAt, rejectedAt, deletedAt, editedAfterApproval}]}`. Newest first; `limit` ≤ 200. A member **without** `expense:approve` always gets only the expenses they captured (`mine:true` in the answer). `DELETED` rows appear only with `status=DELETED`. `q`: supplier name / category contains, document number starts, digits → supplier tax id or exact amount.
- `PATCH /expenses/:id` – the `/expenses/:id/draft` body, every field optional and **merged** with the stored values, plus `reason?`. On `NEEDS_REVIEW`/`READY_TO_APPROVE` it is the normal review path (answer `{id, status, errors, warnings, taxIdValid, revisionId:null}`). On `APPROVED` it needs `expense:approve`, the merged values must still be complete (`409 EXPENSE_VALIDATION_FAILED`), the expense **stays APPROVED**, a before-image revision is stored and the audit event is `expense.edited_after_approval` (`revisionId` returned). A duplicate supplier + number → `409 EXPENSE_DUPLICATE`. Other statuses → `409 EXPENSE_NOT_EDITABLE`.
- Own-only scope on the V1 by-id expense routes too: without `expense:approve`, `GET /expenses/:id/source`, `PATCH /expenses/:id/draft`, `POST /expenses/:id/extract|duplicate|undo-duplicate` on another member's expense → `404 EXPENSE_NOT_FOUND`; `GET /expenses/:id/extraction` → `{extraction:null}`.
- `DELETE /expenses/:id {reason?}` (soft) → `{id, deletedAt, reused}`. Status becomes `DELETED` (evidence kept; drops out of exports, `/dashboard`, reports). Approved → needs `expense:approve`. Still scanning/reading → `409 EXPENSE_BUSY`. Idempotent.
- An employee touching someone else's expense gets `404 EXPENSE_NOT_FOUND`. The database refuses any change to an approved expense that has no revision in the same transaction.

#### Customer statement / כרטסת (BE-17)
- `GET /customers/:id/statement?from=&to=` (default: 1 Jan this year → today) → `{customer:{id,name,taxId,email}, from, to, currency:"ILS", openingBalanceMinor, closingBalanceMinor, totals:{debitMinor, creditMinor}, rows:[{date, kind:"DOCUMENT"|"PAYMENT", documentId, documentType, documentNumber, paymentId, method, reference, receiptDocumentId, receiptNumber, description, debitMinor, creditMinor, balanceMinor}]}`.
  Debit = finalized, not voided 305/320 and 300 not converted to a 305/320; credit = 330 and every non-voided payment of the customer. A paid 320 nets to 0. עוסק פטור / עמותה: a receipt with no invoice behind it shows debit = credit (a sale). Positive balance = the customer owes; the closing balance equals the customer's `balanceMinor` (BE-09) when there are no advances.
- `GET /customers/:id/statement.pdf?from=&to=` (or `?format=pdf`) → PDF.
- `POST /customers/:id/statement/send {channel:"EMAIL", from?, to?, recipient?}` → `202 {sent, channel, recipient, from, to}` – PDF to the customer e-mail (or `recipient`). No e-mail → `409 CUSTOMER_EMAIL_MISSING`. A `recipient` other than the customer's e-mail or the caller's own needs `business:configure` (else `403`). Report + statement e-mails: at most 20 per member per hour → `429 SEND_LIMIT_REACHED`.
- Read needs `document:read` + money view (`money:read` after BE-03; EMPLOYEE `403`); send also `document:send`.

#### Reports (BE-18)
`GET /reports/{income|expenses|vat|pnl|advances|receivables|items|customers|continuity}?from=&to=&groupBy=&format=json|csv|xlsx|pdf` (default period: 1 Jan → today; ≤ 5 years) →
```json
{"kind":"income","title":"הכנסות","from":"2026-10-01","to":"2026-10-30","businessType":"OSEK_MURSHE","groupBy":"month",
 "generatedAt":"…","kpis":[{"key":"totalMinor","label":"סה״כ הכנסות (כולל מע״מ)","type":"money","value":"215200"}],
 "columns":[{"key":"label","label":"חודש","type":"text"},{"key":"totalMinor","label":"סה״כ","type":"money"}],
 "rows":[{"label":"2026-10","count":4,"netMinor":"190000","vatMinor":"25200","totalMinor":"215200"}],"notes":["…"]}
```
Cell/KPI `type`: `money` (minor string), `number`, `percent` (basis points), `date`, `text`. The client renders KPIs + table generically (R2).
| kind | content | groupBy |
|---|---|---|
| `income` | 305 + 320 − 330 (פטור/עמותה: 400 + 405), net/VAT/total | `month` (default) · `customer` · `type` |
| `expenses` | approved expenses | `category` (default) · `supplier` · `month` |
| `vat` | per month: taxable / zero-rated sales (by line rate), output VAT, inputs, input VAT, payable. `422 REPORT_NOT_APPLICABLE` for עוסק פטור | — |
| `pnl` | per month: income (net) − expenses (net; פטור: incl. VAT) | — |
| `advances` | per month turnover × `profile.advanceRateBasisPoints` (null when not set) | — |
| `receivables` | as of `to`: open 300/305 per customer, buckets `notDueMinor`, `days0to30Minor` (1–30 days late), `days31to60Minor`, `days61to90Minor`, `days90PlusMinor` (late = from due date, else issue + 30) | — |
| `items` | lines sold (305/320 − 330; פטור: 300), by item or description, ≤ 500 rows | — |
| `customers` | income per customer + today's open balance | — |
| `continuity` | numbering gaps per scope (all time) | — |
- `format=csv` (UTF-8 BOM, decimals) / `xlsx` / `pdf` → file download.
- `POST /reports/:kind/send {to?, fromDate?, toDate?, groupBy?, format?: pdf|xlsx|csv}` → `202`; `to` defaults to `profile.accountant.email` (none → `409 ACCOUNTANT_EMAIL_MISSING`). A `to` other than the accountant's or the caller's own e-mail needs `business:configure` (else `403`); 20 per member per hour (`429 SEND_LIMIT_REACHED`).
- Permission: `report:read` (+ `export:run` for files and send). Before BE-03: OWNER/ADMIN/ACCOUNTANT or the P0 accountant preset.
- `PUT /business/profile {advanceRateBasisPoints: 0..10000 | null}`; `GET /business/profile` returns it, plus a read-only `ccOwnerEmail` (BE-13 setting).

#### Reminders (BE-19)
- `GET /settings/reminders` → `{enabled, enabledBy, enabledAt, schedule:{daysBeforeDue:3, everyDays:7, timesAfterDue:3, hour:"09:00", timeZone:"Asia/Jerusalem", skipShabbatAndHolidays:true}}`; `PUT {enabled}` (`business:configure`). The member who turns it on is the sender on record.
- Automatic (worker): open 300/305 with a customer e-mail get reminders at due −3, +4, +11, +18 days (due = due date, else issue + 30), from 09:00 Israel time, never on Shabbat / יום טוב / יום העצמאות, never two within 6 days. Each is the original PDF with subject "תזכורת: חשבונית מס N מאת {עסק}" and a fixed friendly text (+ the payment link when the business has one). Consent rules as for every document e-mail.
- `POST /reminders/send {documentIds[1..100]}` (`document:send`) → `{sent, skippedNoEmail, skippedNoConsent, noEmailDocumentIds, noConsentDocumentIds, skipped:[{documentId, reason:"NOT_OPEN"|"NOT_DELIVERABLE"|"NOT_PERMITTED"|"RECENTLY_REMINDED"}], deliveries:[{documentId, deliveryId, status}]}` – sends now. The app offers WhatsApp for `noEmailDocumentIds` + `noConsentDocumentIds`. `NOT_PERMITTED` = another member's document and the caller lacks `money:read` (same rule as `POST /documents/:id/send`); `RECENTLY_REMINDED` = the document got a reminder (manual or automatic) in the last 24 h.

#### Public quote acceptance (BE-21)
- The quote's share link token (`POST /quotes/:id/share-link`, BE-06) also opens **`/q/:token`**: the quote + "שם מלא" + "אני מאשר/ת את ההצעה". **Share `/q/<token>` for quotes** (same token as `/d/<token>`).
- `POST /q/:token/accept` (HTML form, or JSON `{fullName, version}` → `{status:"ACCEPTED", fullName, acceptedAt, reused}`). Quote → `ACCEPTED`; name, IP, user agent, time and the quote content are kept 7 years. Never "נחתמה". Accepting again returns the first acceptance. `version` = the content version the page showed (hidden form field); a quote edited after the page opened (or no `version`) → `409 QUOTE_CHANGED` and the page is shown again with the new content. Errors: `422 VALIDATION` (name 2–120), `409 QUOTE_EXPIRED` (past `validUntil`), `409 QUOTE_NOT_ACCEPTABLE` (converted / rejected), `404` (bad / expired / revoked link), `429` (10 per hour per IP and per link).
- Inbox card `QUOTE_ACCEPTED` (priority 45, action `CONVERT_QUOTE`, `quoteIds[]`, `detail{quoteId, customerName, acceptedBy, acceptedAt}`; `document:draft:write`; last 30 days, not yet converted).
- Ops: `/q/*` must be proxied to the API like `/d/*` (Vercel/Caddy).

#### Accountant automation (BE-22)
- `GET /settings/accountant-automation` → `{sendReports:{every:"MONTH"|"BIMONTH", dayOfMonth}|null, forwardEveryDocument, configuredBy, configuredAt, forwardSince, accountantEmail, lastPeriodSent:{from,to,at}|null}`.
- `PUT {sendReports, forwardEveryDocument}` (`business:configure`; `dayOfMonth` 1–28; turning anything on without `profile.accountant.email` → `409 ACCOUNTANT_EMAIL_MISSING`).
- Worker: on `dayOfMonth` it e-mails the previous month (BIMONTH: the VAT period Jan–Feb, Mar–Apr, … in the following month) as one XLSX (income, expenses, VAT, receivables, P&L). `forwardEveryDocument`: each document finalized after the switch is e-mailed with its PDF. Each period / document once. The full ZIP stays `POST /exports/accountant`.
- Inbox card `CONTINUITY_GAP` (priority 38, action `OPEN_REPORT`, `detail{scopeKey, gapFrom, gapTo}`) for members who read reports and do not issue (accountant presets). `REPORT_READY` is not produced (reports are e-mailed, there is no stored report job).

#### Another business (BE-40)
`POST /businesses {businessType, legalName, taxId?}` → `201 {businessId, tenantId, legalName, businessType, role:"OWNER"}`. Any signed-in member; the new business is the caller's own (separate tenant). Then switch with `X-Business-Id` (it appears in `GET /mobile/businesses`). Bad type / name / tax-id checksum → `422 VALIDATION`. Optional header `Idempotency-Key` (8–200 chars, per user): a retry with the same key → `200` with the same business and `reused:true` (the app should keep one key while the S14 add-business form is open). At most 5 new businesses per user per 24 h → `429 BUSINESS_CREATE_LIMIT`. Response now also has `reused`.

#### Business type change (BE-43) 🛂
- `GET /business/type-change` → `{businessType, pending:{id,newType,effectiveDate,requestedAt}|null, history:[…]}`.
- `POST /business/type-change {newType:"OSEK_MURSHE", effectiveDate}` (`business:configure`): only עוסק פטור → עוסק מורשה (`422 BUSINESS_TYPE_CHANGE_NOT_SUPPORTED`, else "המשך במחשב"); `effectiveDate` within the last year / next 90 days (`422`); a finalized document dated on/after it → `409 BUSINESS_TYPE_CHANGE_CONFLICT`; one scheduled change at a time (`409 BUSINESS_TYPE_CHANGE_PENDING`). Date ≤ today → applied now (`200`, `applied:true`); future → scheduled (`202`), applied by the worker on that date. VAT reporting defaults to `BIMONTHLY`. Issued documents keep their type (`issuer_snapshot.businessType`): copies still print "עוסק פטור", and their 300s never raise `TAX_INVOICE_DUE`.
- `DELETE /business/type-change` cancels the scheduled change (`404 BUSINESS_TYPE_CHANGE_NOT_FOUND`).
- After a change: refresh `/me` (businessType) — "קיבלתי" → 320, "בקש" → 305.

#### New error codes → Hebrew (P2)
| Code | Hebrew |
|---|---|
| SUPPLIER_NOT_FOUND (404) | הספק לא נמצא |
| EXPENSE_BUSY (409) | ההוצאה עדיין בעיבוד. נסה שוב בעוד רגע. |
| EXPENSE_DUPLICATE (409) | כבר קיימת הוצאה מאושרת מאותו ספק עם אותו מספר מסמך |
| EXPENSE_DELETED (409) | ההוצאה נמחקה |
| REPORT_NOT_FOUND (404) | הדוח לא נמצא |
| REPORT_NOT_APPLICABLE (422) | הדוח אינו רלוונטי לסוג העסק (לעוסק פטור אין דוח מע"מ) |
| ACCOUNTANT_EMAIL_MISSING (409) | חסר מייל של רואה החשבון בפרטי העסק |
| CUSTOMER_EMAIL_MISSING (409) | ללקוח אין כתובת אימייל |
| QUOTE_EXPIRED (409, public page) | תוקף הצעת המחיר פג |
| QUOTE_NOT_ACCEPTABLE (409, public page) | הצעת המחיר אינה זמינה לאישור |
| BUSINESS_TYPE_CHANGE_NOT_SUPPORTED (422) | באפליקציה אפשר לעבור רק מעוסק פטור לעוסק מורשה. לשינוי אחר – המשך במחשב. |
| BUSINESS_TYPE_CHANGE_CONFLICT (409) | כבר הופקו מסמכים כעוסק פטור מתאריך התחולה ואילך. בחר תאריך מאוחר יותר. |
| BUSINESS_TYPE_CHANGE_PENDING (409) | כבר נקבע שינוי סוג עסק. אפשר לבטל אותו ולקבוע מחדש. |
| BUSINESS_TYPE_CHANGE_NOT_FOUND (404) | אין שינוי סוג עסק מתוזמן |

## V2 · שילוב ובדיקות (INT: server integrator, 2026-10-30)
Server branch `feat/mobile-api-v2` = `15a904b` (V1 mobile) + 7 squad commits (`129b496` SRV-2 P0 · `78f06ec` SRV-1 P0 · `390ec0f` SRV-1 P1 · `b0cca59` SRV-2 P1 · `d8a93d2` SRV-3 P1 · `4586988` SRV-1 P2 · `5222b4d` SRV-3 P2) + the INT commit (seed preset `mobile-cpa-rep`, `scripts/smoke-mobile-v2.mjs`). Out of scope and **not on the server**: BE-20 push (migration 0071 left free), BE-42 ITA OAuth, BE-00 ops/deploy, P3 (BE-28*).

### Dev server state
- `invoice_local` migrated with **0058–0070, 0072–0077** (19 migrations; backup of the pre-V2 DB: `/tmp/invoice_local_pre_v2_202610301855.dump`). The dev API on `http://127.0.0.1:3031` was restarted from the V2 working tree (`ops/run-mobile-dev.sh`).
- ⚠ The dev build also contains the **owner's own uncommitted quote-design work** (`packages/postgres/src/quotes.ts`, migration 0050): `GET /quotes` rows carry `title` and `designTemplate`. Those two fields are **not** on the V2 branch; do not depend on them.
- `ROUTES = withAccessPolicy([ …V2_DOCUMENT, V2_PAYMENT, V2_QUOTE, V2_ME, V2_TEAM, V2_INBOX, V2_CUSTOMER, V2_DONATION, V2_MOBILE, V2_EXPENSE, V2_REPORT, V2_BUSINESS, …V1 ])`. First match wins, so every V2 handler replaces the V1 one for the same path. Every authenticated route has exactly one rule in `apps/api/src/routes/v2/access.ts`; a refusal from that table is always `403 DOCUMENT_ACTION_FORBIDDEN` (→ refresh `/me`, SPEC §4.6).
- Public pages served by the API: `/d/:token` (+`/pdf`), `/q/:token` (+`POST /accept`), `/m/invite/:token` (302 → web invite).

### Role presets (dev credentials)
Password for every account: **`Mobile12345678`**. Business "סטודיו תבל לדוגמה" `3b773037-e71d-49bd-a951-76845e4abe07` (`OSEK_MURSHE`) unless noted. `/me.permissions` below is what the dev server actually returned on 2026-10-30.

| e-mail | preset (UI) | server role + extra grants | MFA | `/me.permissions` |
|---|---|---|---|---|
| `mobile-owner@tevel.test` | בעלים | OWNER | e-mail | everything except `settings:numbering`, `customer:accountKey` (19) |
| `mobile-partner@tevel.test` | שותף | ADMIN | e-mail | same as owner (19) |
| `mobile-employee@tevel.test` | עובד + מפיק בעצמו | EMPLOYEE + `document:finalize`, `payment:record`, `allocation:request` | e-mail | `document:read, document:draft:write, document:finalize, document:send, payment:record, expense:record, allocation:request` |
| `mobile-staff@tevel.test` | עובד | EMPLOYEE | none | `document:read, document:draft:write, document:send, expense:record` |
| `mobile-accountant@tevel.test` | רואה חשבון (P0, legacy) | READ_ONLY + `expense:record`, `expense:approve` | none | `document:read, expense:record, expense:approve, money:read` |
| `mobile-cpa-full@tevel.test` | רו״ח – מלא | ACCOUNTANT | e-mail | `document:read, document:draft:write, document:finalize, document:send, payment:record, expense:record, expense:approve, document:cancel, approval:decide, money:read, report:read, export:run, customer:manage, supplier:manage, item:manage, allocation:request` |
| `mobile-cpa-rep@tevel.test` | רואה חשבון (מייצג) | ACCOUNTANT_REP | e-mail | `document:read, expense:record, expense:approve, money:read, report:read, export:run, allocation:request, settings:numbering, customer:accountKey` |
| `mobile-viewer@tevel.test` | צפייה בלבד | READ_ONLY | none | `document:read, money:read` |
| `mobile-patur@tevel.test` | בעלים (עוסק פטור "דנה כהן – עיצוב" `c934a7a8-df74-433d-a5e2-e342c16142b1`) | OWNER | e-mail | as owner |

Sign-in with curl (MFA code = first 6 characters of the newest dev e-mail's `subject`, §3):
```bash
API=http://127.0.0.1:3031; J=/tmp/c.jar
CSRF=$(curl -s -c $J -H 'content-type: application/json' -d '{"email":"mobile-owner@tevel.test","password":"Mobile12345678"}' $API/auth/login | jq -r .csrfToken)
CSRF=$(curl -s -b $J -c $J -H "x-csrf-token: $CSRF" -H 'content-type: application/json' -d '{"purpose":"LOGIN"}' $API/auth/mfa/email/send >/dev/null; \
       CODE=$(jq -r .subject "$(ls -t ~/invoiceproject-mobile-dev-storage/outgoing-emails/*.json | head -1)" | cut -c1-6); \
       curl -s -b $J -c $J -H "x-csrf-token: $CSRF" -H 'content-type: application/json' -d "{\"code\":\"$CODE\"}" $API/auth/mfa/email/verify | jq -r .csrfToken)
TOKEN=$(curl -s -b $J -H "x-csrf-token: $CSRF" -H 'content-type: application/json' -d '{"deviceName":"curl"}' $API/auth/device-token | jq -r .token)
curl -s -H "authorization: Bearer $TOKEN" -H 'x-business-id: 3b773037-e71d-49bd-a951-76845e4abe07' $API/me | jq
```
(For `staff`, `accountant`, `viewer` skip the two MFA calls.)

`GET /me` as `mobile-cpa-rep` (verbatim):
```json
{"userId":"14ac44a7-…","role":"ACCOUNTANT_REP","isOwner":false,"mfaEnrolled":false,
 "permissions":["document:read","expense:record","expense:approve","money:read","report:read","export:run","allocation:request","settings:numbering","customer:accountKey"],
 "businessType":"OSEK_MURSHE","vatReporting":null,"memberCount":9,"onboarding":{"completed":true,"step":1},
 "canFinalize":false,"canConfigure":false,"canApproveExpenses":true,
 "approvalPolicy":{"mode":"NONE","thresholdMinor":"0","includesVat":true,"selfApprovalAllowed":false,"otherApproverExists":true},
 "shaam":{"environment":null,"status":"DISABLED","authorizedVatNumber":null,"authorizedSubjectHint":null,"lastVerifiedAt":null,"refreshTokenExpiresAt":null,"lastErrorCode":null,"killSwitch":false,"manualEntryEnabled":false,"canConfigure":false},
 "signing":{"configured":false,"enabled":false,"unlocked":false},"exports":{"uniformFormatReady":false},
 "rules":{"exemptCeilingMinor":"12000000","exemptCeilingYear":2026,"yearTurnoverMinor":"3103400"},
 "enforcement":{"readGating":true}}
```

### Read matrix (dev server, 2026-10-30; HTTP status per preset)
`·$` = amounts present, `·n` = amounts `null` (read gating); inbox `Nc` = number of cards. `-` = not applicable (another business).

| GET | owner | partner | employee+self | staff | accountant (P0) | cpa-full | cpa-rep | viewer | patur |
|---|---|---|---|---|---|---|---|---|---|
| `/me` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/dashboard` | 200·$ | 200·$ | 200·n | 200·n | 200·$ | 200·$ | 200·$ | 200·$ | 200·$ |
| `/documents?limit=3` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/documents/:id` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | - |
| `/mobile/inbox?limit=10` | 200·3c$ | 200·3c$ | 200·2cn | 200·0cn | 200·1c$ | 200·3c$ | 200·2c$ | 200·0c$ | 200·1c$ |
| `/customers?limit=3` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/customers/:id` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | - |
| `/customers/:id/statement` | 200 | 200 | **403** | **403** | 200 | 200 | 200 | 200 | - |
| `/items` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/suppliers?limit=3` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/expenses?limit=3`, `/expenses/inbox` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | **403** | 200 |
| `/payments?limit=3` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/quotes` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/business/members` | 200 | 200 | **403** | **403** | **403** | **403** | **403** | **403** | 200 |
| `/business/profile` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/settings/document-email` | 200 | 200 | **403** | **403** | **403** | **403** | **403** | **403** | 200 |
| `/settings/reminders` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/settings/accountant-automation` | 200 | 200 | **403** | **403** | **403** | 200 | 200 | **403** | 200 |
| `/business/type-change` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |
| `/reports/income`, `/reports/receivables` | 200 | 200 | **403** | **403** | **403** | 200 | 200 | **403** | 200 |
| `/approvals` | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 | 200 |

For `staff` (no `money:read`) every amount in `/dashboard`, `/mobile/inbox`, `/payments`, `/customers`, `/suppliers`, `/quotes`, `/approvals` and other people's documents is `null`; its own drafts keep their amounts (`total_minor:"3540"` on its own draft, `null` on someone else's). Example `GET /dashboard` as staff:
```json
{"summary":{"month_income":null,"month_income_count":29,"month_expenses":null,"unpaid_count":7,"unpaid_balance":null,"unpaid_total":null,
 "overdue_count":0,"overdue_total":null,"review_count":1,"open_quotes":1,"pending_approval":0},"recent":[…]}
```

### Smoke run of every V2 endpoint
`node scripts/smoke-mobile-v2.mjs` (server repo; dev only, creates test data in the dev business). Last run 2026-10-30 17:04 UTC: **126 checks OK, 0 failed** (9 sign-ins + the matrix above + 117 calls). Highlights, verbatim (ids shortened):

| who | call | → | body |
|---|---|---|---|
| owner | `POST /documents {documentType:"TAX_INVOICE", customerId, dueDate, notes, lines}` | 201 | `{"id":"ff6e…","status":"DRAFT"}` |
| owner | `PUT /documents/:id` · `POST …/clone {}` · `DELETE` clone | 200 · 201 · 200 | `{"id":"67c0…","documentType":"TAX_INVOICE","convertedFromDocumentId":null}` |
| owner | `POST …/finalize {scopeKey:"default"}` [Idempotency-Key] | 200 | `{"status":"FINALIZED","documentNumber":"43","snapshotHash":"05da…","reused":false}` |
| staff | `POST …/credit` | 403 | `DOCUMENT_ACTION_FORBIDDEN` (lacks `document:cancel`) |
| owner | `POST …/credit {scopeKey, lines:[200.00 + VAT]}` | 201 | `{"creditDocumentId":"9de5…","outcome":{"status":"FINALIZED","documentNumber":"50",…}}` → original `credited_minor:"23600"`, `open_minor:"94400"`, `cancelled:false` |
| owner | `POST /documents/<credit>/credit` | 422 | `CREDIT_SOURCE_TYPE_INVALID` |
| owner | `POST …/share-link` → `POST …/share-link/revoke` | 201 → 200 | `{"url":"http://127.0.0.1:3031/d/KMCx…","expiresAt":"2026-11-29T…"}` → `{"revoked":1}` |
| owner | `GET /documents?q=בדיקת&limit=2` · `?overdue=1` · `?limit=abc` | 200 · 200 · 422 | `{"total":18,"limit":2,"offset":0,"documents":[…]}` |
| partner | `POST /documents {issueDate: yesterday}` | 403 | `BACKDATING_OWNER_ONLY` (owner: 201) |
| employee+self / owner | `POST /documents/<300>/void {reason}` | 403 / 200, again 409 | `{"id":"18a6…","voidedAt":"2026-10-30T17:04:10.173Z"}` / `DOCUMENT_ALREADY_VOIDED` |
| owner | `POST /payments {method:"CASH"…}` · `{method:"BIT"}` | 201 · 422 | `{"paymentId":"c8ad…","reused":false}` · `PAYMENT_METHOD_NOT_ENABLED` |
| owner | `POST /payments/:id/void {reason}` · unknown id | 200 · 404 | `{"id":"c8ad…","voidedAt":"…","reused":false}` · `PAYMENT_NOT_FOUND` |
| staff | `POST /documents/:id/finalize` · `GET /documents/<other's>/pdf` | 403 · 403 | lacks `document:finalize` · lacks `money:read` |
| cpa-rep | `POST /documents` · `POST …/send` | 403 · 403 | lacks `document:draft:write` · lacks `document:send` |
| patur | `POST /documents {documentType:"TAX_INVOICE"}` | 422 | `DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS` |
| owner | `POST /quotes` → `GET` → `PUT` → `GET …/pdf` → `POST …/clone` → `POST …/share-link` | 201→200→200→200 (PDF 58 KB)→201→201 | share `url` is `/d/<token>`; **share `/q/<token>` for quotes** |
| public | `GET /q/<token>` · `POST /q/<token>/accept {fullName:"א"}` · `{fullName:"דנה כהן"}` ×2 · unknown token | 200 HTML · 422 · 200, 200 · 404 | `{"status":"ACCEPTED","fullName":"דנה כהן","acceptedAt":"…","reused":false}` then `reused:true` |
| owner | `POST /quotes/:id/convert {documentType:"TAX_INVOICE"}` | 201 | `{"documentId":"707e…"}` |
| owner / cpa-rep | `PATCH /customers/:id {accountKey}` | 403 / 200 | only ACCOUNTANT_REP holds `customer:accountKey` |
| staff | `PATCH /customers/:id {notes}` · `{vatDealerStatus}` | 403 · 200 | per-field rule |
| owner | `GET /customers/:id/statement.pdf` · `POST …/statement/send {channel:"EMAIL"}` | 200 (73 KB) · 202 | `{"sent":true,"channel":"EMAIL","recipient":"dana@example.test","from":"2026-01-01","to":"2026-10-30"}` |
| owner / staff | `POST /items` → `PATCH` → `archive` → `restore` | 201→200→200→200 / PATCH 403 | `{"id":"b817…","archived":true}` |
| owner / staff | `POST /suppliers` → `GET /suppliers/:id` → `PATCH` → `archive` → `restore` | 201→200→200→200→200 / PATCH 403 | |
| owner / viewer | `PATCH /expenses/:id {reason}` (no field) · `DELETE /expenses/<unknown>` | 422 `nothing to update` / 403 · 404 | `EXPENSE_NOT_FOUND` |
| owner | `GET /reports/{income,expenses,vat,pnl,advances,receivables,items,customers,continuity}` | 200 ×9 | `{"kind":"income","title":"הכנסות","kpis":[{"key":"totalMinor","label":"סה״כ הכנסות (כולל מע״מ)","type":"money","value":"3103400"},…],"columns":[…],"rows":[…],"notes":[…]}` |
| owner | `?format=csv` · `xlsx` · `pdf` · `/reports/nope` | 200 · 200 · 200 · 404 | `REPORT_NOT_FOUND` |
| patur · cpa-rep · accountant (P0) · viewer | `GET /reports/vat` · `GET /reports/income?format=xlsx` · `GET /reports/income` · `POST /exports/excel` | 422 · 200 · 403 · 403 | `REPORT_NOT_APPLICABLE` · – · lacks `report:read` · lacks `export:run` |
| owner | `POST /reports/income/send {to}` | 202 | `{"sent":true,"to":"cpa@example.test","kind":"income","format":"pdf","from":"2026-01-01","toDate":"2026-10-30"}` |
| owner / staff | `GET`·`PUT /settings/reminders` · `POST /reminders/send {documentIds}` | 200·200·200 / PUT 403 | `{"sent":0,…,"skipped":[{"documentId":"ad9a…","reason":"NOT_OPEN"}],"deliveries":[]}` |
| owner | `GET`·`PUT /settings/accountant-automation {sendReports:null, forwardEveryDocument:false}` · `GET`·`PUT /settings/document-email` | 200 ×4 | `{"ccOwnerEmail":false}` |
| owner | `POST /business/members/invite {email, role:"EMPLOYEE", permissions:[finalize,payment,allocation]}` → resend → revoke | 201 → 200 → 200 | `{"invitationId":"e497…","link":"…/#/invite?token=…","inviteUrl":"http://127.0.0.1:3031/m/invite/…","expiresAt":"…",…}` |
| owner / staff | invite with `permissions:["document:cancel"]` / any invite | 400 `VALIDATION` / 403 | |
| partner / owner | `POST /business/ownership/transfer {toUserId}` · `{toUserId, code:"000000"}` | 403 / 202 (429 when repeated within a minute) · 422 `OWNERSHIP_CODE_INVALID` | |
| owner / staff | `POST /mobile/web-handoff {topic:"INVENTORY"}` · `{topic:"NOPE"}` | 202 / 403 · 422 | `{"status":"SENT","topic":"INVENTORY"}` |
| patur | `GET` → `POST /business/type-change {newType:"OSEK_MURSHE", effectiveDate:+30d}` → `DELETE` | 200 → 202 → 200 | `{"businessType":"OSEK_PATUR","pending":{"id":"92e7…","newType":"OSEK_MURSHE","effectiveDate":"2026-11-29",…},"history":[…]}` |
| owner (murshe) | `POST /business/type-change {newType:"COMPANY"}` | 422 | `BUSINESS_TYPE_CHANGE_NOT_SUPPORTED` |
| owner | `POST /documents/:id/donation-report` | 503 | `DONATION_REPORTING_DISABLED` (port not wired, DONATE-001) |
| owner | `POST /businesses {legalName:"x"}` · `GET /mobile/businesses?limit=5` | 422 · 200 | `{"total":1,"offset":0,"limit":5,"businesses":[{"businessId":"3b77…","legalName":"סטודיו תבל לדוגמה","role":"OWNER"}]}` |

### Integration notes (read before coding against V2)
1. **`GET /documents/:id`: `payments[]`, `linkedDocuments[]`, `timeline[]`, `notes`, `overdue`, `cancelled`, `rejection` are fields of `document`**, not top-level. The response is still `{document, lines}`.
2. **Quotes:** `POST /quotes/:id/share-link` returns a `/d/<token>` URL. For WhatsApp share `<origin>/q/<token>` (same token) so the customer can accept.
3. **List envelopes** are `{total, limit, offset, <rows>}` (key order varies; parse by name). Defaults: documents 100, payments 50, expenses 50, customers/suppliers all (≤ 500) when no `limit` is sent.
4. **Self-issuer toggle** must send `["document:finalize","payment:record","allocation:request"]`. New accountants: invite `{role:"ACCOUNTANT_REP"}`; the P0 READ_ONLY + expense preset has no reports/exports.
5. **Read gating is live** (`/me.enforcement.readGating = true`): treat every `*Minor`/`*_minor` money field as nullable everywhere.
6. Every V2 refusal from the rule table is `403 DOCUMENT_ACTION_FORBIDDEN`; domain refusals keep their own codes (table below). An id you cannot see is `404`, never `403`.
7. Dev rate limit: 300 requests / 10 s per IP (prod 100 / 10 s). The smoke script throttles itself.

### All V2 error codes → Hebrew (for `lib/util/errors_he.dart`)
Same texts as `ERROR_MESSAGES_HE` in `apps/web/src/api.ts` on `feat/mobile-api-v2` (checked: every error code the V2 server code throws has a Hebrew entry; the only exceptions are the public `/q/` page, which renders Hebrew itself, and internal outcome kinds).

| code | HTTP | עברית |
|---|---|---|
| BACKDATING_OWNER_ONLY | 403 | רק בעל העסק יכול להפיק מסמך בתאריך עבר |
| CREDIT_SOURCE_TYPE_INVALID | 422 | אפשר להפיק זיכוי רק לחשבונית מס או לחשבונית מס-קבלה |
| APPROVAL_NO_OTHER_APPROVER | 422 | כדי לחייב אישור של אדם אחר צריך חבר צוות נוסף שמורשה לאשר מסמכים |
| INVITATION_EXPIRED | 410 | ההזמנה כבר לא בתוקף — בקש מהמזמין לשלוח שוב |
| INVITATION_REVOKED | 410 | ההזמנה בוטלה — בקש מהמזמין לשלוח שוב |
| MEMBER_NOT_FOUND | 404 | החבר לא נמצא בעסק או שאינו פעיל |
| ALREADY_OWNER | 409 | החבר הזה כבר בעלים של העסק |
| OWNERSHIP_CODE_THROTTLED | 429 | נשלח קוד לפני רגע — נסה שוב בעוד דקה |
| OWNERSHIP_CODE_INVALID | 422 | הקוד שגוי |
| OWNERSHIP_CODE_EXPIRED | 410 | הקוד פג או נוצל — בקש קוד חדש |
| PAYMENT_LOCKED_IN_DOCUMENT | 409 | התשלום כלול במסמך שהופק. לביטול – הפק זיכוי, או בטל את הקבלה במחשב. |
| PAYMENT_VOIDED | 409 | התשלום בוטל ולא ניתן להשתמש בו. |
| PAYMENT_NOT_FOUND | 404 | התשלום לא נמצא. |
| PAYMENT_METHOD_NOT_ENABLED | 422 | אמצעי התשלום עדיין לא זמין. רשום אותו כהעברה בנקאית. |
| DOCUMENT_VOID_NOT_ALLOWED | 422 | אפשר לבטל כך רק חשבון עסקה, הזמנה או הזמנת רכש שהופקו. |
| DOCUMENT_ALREADY_VOIDED | 409 | המסמך כבר בוטל. |
| DOCUMENT_HAS_PAYMENTS | 409 | יש תשלום על המסמך. בטל קודם את הקבלה במחשב. |
| CLONE_TYPE_NOT_ALLOWED | 422 | אי אפשר לשכפל לסוג המסמך הזה. |
| ALLOCATION_NUMBER_RESERVED | 409 | המספר כבר שמור ברשות המסים – אי אפשר לבטל את הבקשה. בחר "המשך בלי מספר" או נסה שוב. |
| ITEM_NOT_FOUND | 404 | הפריט לא נמצא |
| WEB_HANDOFF_THROTTLED | 429 | נשלחו יותר מדי קישורים בשעה האחרונה. נסה שוב מאוחר יותר. |
| EMAIL_MISSING | 409 | לחשבון אין כתובת אימייל |
| EMAIL_UNAVAILABLE | 503 | לא הצלחנו לשלוח את המייל. נסה שוב. |
| DONATION_REPORTING_DISABLED | 503 | דיווח תרומות לרשות המסים עדיין לא מחובר |
| DONATION_REPORTING_TRANSIENT | 503 | מערכת דיווח התרומות לא זמינה כרגע. נסה שוב. |
| DONATION_REPORT_NOT_APPLICABLE | 422 | רק קבלה על תרומה מדווחת למערכת התרומות |
| DONATION_NOT_REPORTED | 409 | הקבלה עוד לא דווחה, ולכן אין מה לבטל |
| SECTION46_APPROVAL_REQUIRED | 422 | חסר מספר אישור לפי סעיף 46 בפרטי העסק |
| FINALIZATION_EVIDENCE_MISSING | 409 | המסמך עוד לא הופק |
| SUPPLIER_NOT_FOUND | 404 | הספק לא נמצא |
| EXPENSE_BUSY | 409 | ההוצאה עדיין בעיבוד. נסה שוב בעוד רגע. |
| EXPENSE_DUPLICATE | 409 | כבר קיימת הוצאה מאושרת מאותו ספק עם אותו מספר מסמך |
| EXPENSE_DELETED | 409 | ההוצאה נמחקה |
| REPORT_NOT_FOUND | 404 | הדוח לא נמצא |
| REPORT_NOT_APPLICABLE | 422 | הדוח אינו רלוונטי לסוג העסק (לעוסק פטור אין דוח מע"מ) |
| ACCOUNTANT_EMAIL_MISSING | 409 | חסר מייל של רואה החשבון בפרטי העסק |
| CUSTOMER_EMAIL_MISSING | 409 | ללקוח אין כתובת אימייל |
| QUOTE_EXPIRED | 409 | תוקף הצעת המחיר פג |
| QUOTE_NOT_ACCEPTABLE | 409 | הצעת המחיר אינה זמינה לאישור |
| BUSINESS_TYPE_CHANGE_NOT_SUPPORTED | 422 | באפליקציה אפשר לעבור רק מעוסק פטור לעוסק מורשה. לשינוי אחר – המשך במחשב. |
| BUSINESS_TYPE_CHANGE_CONFLICT | 409 | כבר הופקו מסמכים כעוסק פטור מתאריך התחולה ואילך. בחר תאריך מאוחר יותר. |
| BUSINESS_TYPE_CHANGE_PENDING | 409 | כבר נקבע שינוי סוג עסק. אפשר לבטל אותו ולקבוע מחדש. |
| BUSINESS_TYPE_CHANGE_NOT_FOUND | 404 | אין שינוי סוג עסק מתוזמן |

Existing codes the V2 routes also return (already in §9 / web): `DOCUMENT_ACTION_FORBIDDEN` (403) אין לתפקיד שלך הרשאה לפעולה זו. פנו לבעל העסק. · `VALIDATION` (400/422) · `NOT_FOUND` · `DOCUMENT_NOT_FOUND` המסמך לא נמצא · `CUSTOMER_NOT_FOUND` הלקוח לא נמצא · `QUOTE_NOT_FOUND` הצעת המחיר לא נמצאה · `EXPENSE_NOT_FOUND` ההוצאה לא נמצאה · `EXPENSE_NOT_EDITABLE` הוצאה זו אינה ניתנת לעריכה במצבה הנוכחי (כפולה / מאושרת / נדחתה) · `EXPENSE_VALIDATION_FAILED` ההוצאה חסרה נתונים לאישור (ספק, סכום או תאריך) · `DOCUMENT_NOT_FINAL` הפעולה דורשת מסמך סופי · `QUOTE_INVALID_TRANSITION` לא ניתן לבצע מעבר סטטוס זה להצעת המחיר · `CREDIT_LIMIT_EXCEEDED` סכום הזיכוי עולה על היתרה שניתן לזכות במסמך המקור · `ALLOCATION_PENDING` בקשת ההקצאה ממתינה לרשות המסים · `COMPLIANCE_DECISION_NOT_VERIFIED` הפעולה דורשת אישור ציות מאומת · `MEMBER_EXISTS` הכתובת הזו כבר משתמש בעסק · `INVITATION_INVALID` ההזמנה פגה, בוטלה או כבר נוצלה — בקש הזמנה חדשה · `MFA_REQUIRED` נדרש קוד אימות דו-שלבי.

### CI on `feat/mobile-api-v2` (INT, 2026-10-30)
| step | working tree (incl. owner's uncommitted files) | clean checkout of HEAD |
|---|---|---|
| `format:check` | 18 files flagged, **none changed on this branch** (owner's uncommitted files + 9 that are identical on `main`) | 9 files, all identical on `main` |
| `lint` | 19 errors in 3 files (`ops/oracle/migrate.cjs`, `ops/shaam-callback-catcher.mjs`, `scripts/shaam-sandbox-extended.mjs`), none changed on this branch | same 3 files |
| `build` | ✅ | ✅ |
| `typecheck` | 2 errors, both in the owner's uncommitted files (`apps/web/test/quote-design.unit.test.ts`, `packages/shaam/test/contract.unit.test.ts`) | ✅ 0 errors |
| `test` (unit) | ✅ 294 passed, 1 skipped | ✅ 283 passed, 1 skipped (the owner's untracked tests are absent) |
| `test:regulated` | 1917 passed, **1 failed** (E2E-QUOTE-001: the owner's uncommitted `quotes.tsx`), 3 expected-fail, 3 skipped; boundaries + provenance ✅ | ✅ **1918 passed**, 3 expected-fail, 3 skipped; boundaries + provenance ✅ |
| `shaam:contract` | ✅ | ✅ |
