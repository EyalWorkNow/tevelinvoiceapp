# App Review Notes — Tevel

**Draft only. Replace every bracketed value before submission. Do not submit local-development credentials.**

## Demo access

- Email: `[PRODUCTION_REVIEW_EMAIL]`
- Password: `[PRODUCTION_REVIEW_PASSWORD]`
- MFA: `[DISABLED FOR THIS REVIEW ACCOUNT / EXACT TEST CODE DELIVERY INSTRUCTIONS]`
- Business: `[DEMO BUSINESS NAME]`
- Role: `[OWNER / REVIEW ROLE WITH ALL FEATURES ENABLED]`

The demo account must be active for the full review period and must not require a personal Apple ID, invitation, email inbox, real phone number, or geographic restriction. Keep this account separate from real customers and give it safe sample records only.

### How accounts work (paste into the Review Notes)

Tevel opens every account itself after a short onboarding conversation with the business owner. The app therefore has no self sign-up and no third-party login (no Sign in with Apple, no Google): users sign in only with the e-mail and password the Tevel team created for them in our admin console. People without an account see "אין לך חשבון? דברו איתנו" on the sign-in screen, which opens WhatsApp or e-mail to our team. Please use the demo account above.

### Owner checklist: creating the review account (not done by the app)

1. In the admin console (www.tevel.space/invoiceadmin → "משתמש חדש") create a dedicated review user, e.g. `test@test.com`, with a strong password, a demo business (name, type, tax id) and a plan, so the reviewer lands on the home screen with no setup wizard and no paywall.
2. Leave MFA off for this user (or give the exact code delivery steps above); the reviewer has no access to its inbox.
3. Add safe sample data (customers, a few documents, an expense).
4. Create a second, separate user for the deletion test.
5. Put both e-mails and passwords ONLY in App Store Connect → the version → App Review Information → **Sign-In Information** ("Sign-in required" checked). Never in Git.
6. Before each submission, sign in once on a device with the review account to confirm it still works.

## Main review paths

1. Sign in using the email and password above.
2. Review the home screen, management, customer records, income documents, expense management, and reports using the demo data.
3. Account deletion: Profile → Settings → Account → Delete Account. The flow explains what is deleted and legally retained, asks the user to reauthenticate, then requires typing the confirmation word. Use the separate deletion account below if you need to complete deletion.

Deletion test account: `[SEPARATE_PRODUCTION_DELETE_TEST_EMAIL]` / `[PASSWORD]`.

## Billing and purchase review

Tevel's three monthly plans are purchased through Apple In-App Purchase in the iOS app. The app verifies signed transactions with our API before enabling a plan and supports restoring purchases. Customers paying a business-issued invoice use a separate payment flow; that flow does not purchase or unlock the Tevel subscription.

## Backend availability

Production API: `https://invoice.crm.tevel.space`. Keep the demo business and review accounts available throughout review. Support page: `https://www.tevel.space/contact`.
