# App Review Notes — Tevel

**Draft only. Replace every bracketed value before submission. Do not submit local-development credentials.**

## Demo access

- Email: `[PRODUCTION_REVIEW_EMAIL]`
- Password: `[PRODUCTION_REVIEW_PASSWORD]`
- MFA: `[DISABLED FOR THIS REVIEW ACCOUNT / EXACT TEST CODE DELIVERY INSTRUCTIONS]`
- Business: `[DEMO BUSINESS NAME]`
- Role: `[OWNER / REVIEW ROLE WITH ALL FEATURES ENABLED]`

The demo account must be active for the full review period and must not require a personal Apple ID, invitation, email inbox, real phone number, or geographic restriction. Keep this account separate from real customers and give it safe sample records only.

## Main review paths

1. Sign in using the email and password above.
2. Review the home screen, management, customer records, income documents, expense management, and reports using the demo data.
3. Account deletion: Profile → Settings → Account → Delete Account. The flow explains what is deleted and legally retained, asks the user to reauthenticate, then requires typing the confirmation word. Use the separate deletion account below if you need to complete deletion.

Deletion test account: `[SEPARATE_PRODUCTION_DELETE_TEST_EMAIL]` / `[PASSWORD]`.

## Billing and purchase review

Tevel's three monthly plans are purchased through Apple In-App Purchase in the iOS app. The app verifies signed transactions with our API before enabling a plan and supports restoring purchases. Customers paying a business-issued invoice use a separate payment flow; that flow does not purchase or unlock the Tevel subscription.

## Backend availability

Production API: `https://invoice.crm.tevel.space`. Keep the demo business and review accounts available throughout review. Support page: `https://www.tevel.space/contact`.
