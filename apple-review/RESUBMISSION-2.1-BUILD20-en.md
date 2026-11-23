# Guideline 2.1 response - version 1.0.0 (20)

DRAFT - NOT READY TO SUBMIT. Replace all bracketed fields and complete the release gates in RESUBMISSION-2.1-CHECKLIST-he.md. This file contains no credentials. Put credentials in App Store Connect's protected Sign-In Information fields; provide additional role/deletion accounts securely in Review Notes if needed.

## 1. Physical-device recording and QA

Recording: [ATTACHMENT_FILENAME_OR_ACCESSIBLE_VIDEO_URL]
Device: [PHYSICAL_DEVICE_MODEL]; OS: [VERSION_AND_BUILD]; app: 1.0.0 (20).
Recording date: [DATE]. Physical-device QA: [SUPPORTED_PLATFORMS_TESTED_AND_RESULTS].

The recording begins by launching the installed app and demonstrates sign-in, business selection, the home dashboard, a sample customer, document creation/viewing and reports. Account deletion is demonstrated in [DELETION_RECORDING_ATTACHMENT] using a separate disposable account. [ADD_TIMESTAMPS_MATCHING_THE_ACTUAL_RECORDING].

## 2. Purpose and audience

Tevel Businesses is a Hebrew business-management app for Israeli business owners and their authorized staff. It brings customer records, income documents, expense attachments and reports into one mobile workspace, reducing repeated entry and helping users follow their business activity. Access to business data is role-based. The app is an administrative software tool; it does not itself provide banking, investment or lending services.

[CONFIRM_PUBLIC_CUSTOMER_ELIGIBILITY: explain whether any eligible business can become a customer, or whether access is restricted to named organizations. Do not describe an organization-only app as a general-public service.]

## 3. Setup and main features

Use the email and password provided in Sign-In Information. [VERIFIED_DEMO_BUSINESS_AND_ROLE]. [EXACT_MFA_INSTRUCTIONS_OR_VERIFIED_NO_CHALLENGE]. [ADDITIONAL_ROLE_ACCOUNTS_IF_REQUIRED].

Build 20 has email/password sign-in. There is no self-service account registration or Apple/Google sign-in button. The "No account? Contact us" action opens contact options for the Tevel team, which provisions accounts. The recording demonstrates that actual entry path; business-profile onboarding is not presented as public account registration.

After sign-in, choose the supplied demo business if a business picker appears. Review Home, Customers, income documents, Expenses and Reports. Use [EXACT_SAMPLE_CUSTOMER_NAME], [EXACT_SAMPLE_DOCUMENT] and [EXACT_SAMPLE_EXPENSE_FILE]; all must contain synthetic data. [ADD_EXACT_NAVIGATION_LABELS_VERIFIED_ON_DEVICE].

Account deletion is available from the profile/settings area under "מחיקת חשבון" (Delete Account). A sole owner first receives a business-impact warning. The deletion screen explains deletion/retention, requests fresh authentication and the Hebrew confirmation word "מחק", then deletes the account and signs out. Use [SEPARATE_DISPOSABLE_DELETION_ACCOUNT] for destructive testing, preserving the main review account.

Business records and files are created by users and shared with selected recipients; [VERIFY_AND_DESCRIBE_ALL_PUBLIC_OR_INTERACTIVE_SURFACES, including any public booking/signature/document pages]. [DESCRIBE_REPORTING/BLOCKING_IF_APPLICABLE; do not assert that all UGC requirements are inapplicable without checking those surfaces].

## Paid access

The current version has no paid features. No payment or subscription is currently required to access the app's features. Consequently, there is no paid-content access flow to demonstrate in the recording. Payments recorded on business documents represent transactions between the business and its customers, not purchases of app features.

[INTERNAL_VERIFICATION_BEFORE_SUBMISSION: the owner confirmed on 2026-11-19 that there are currently no paid features. Verify this applies to all eligible accounts, not only the review account or a trial. Build 20 still contains a plans screen, StoreKit code and server-driven plan gates; confirm none requires payment or offers a working purchase in this release. Existing draft IAP products do not by themselves establish that paid features are live. Remove this internal paragraph only after resolving that check.]

## 4. External services

- Tevel API at https://invoice.crm.tevel.space: business permissions, records, document/expense workflows and reports.
- Supabase Auth: primary email/password authentication when enabled in the submitted build. Tevel applies the business session and permissions.
- Apple Push Notification service: notifications and supported Live Activity updates. StoreKit support exists in the codebase, but payment is not currently required for access, as stated above; [VERIFY_ANY_PURCHASE_UI_REACHABLE_IN_THE_SUBMITTED_BUILD].
- iOS Photos/Camera/Contacts/Calendar and the system share sheet: optional, user-initiated device integrations. External sharing may open WhatsApp or email.
- [CONFIRM_PRODUCTION_STORAGE_AND_DATABASE_PROVIDERS].
- [CONFIRM_EMAIL/SMS_DELIVERY_PROVIDERS].
- [CONFIRM_OCR/AI_PROVIDER_AND_WHAT_IS_SENT, or accurately state the feature is unavailable in the submitted release].
- [CONFIRM_CARDCOM_AND_TAX_AUTHORITY_INTEGRATION_STATUS; distinguish configured production services from source-code support or previews].

## 5. Regions

The current UI is Hebrew (he-IL), and the product is designed for Israeli businesses and Israeli business-document workflows. [CONFIRM_ENABLED_STOREFRONTS, reviewer access from outside Israel, currency/tax behavior and any country-dependent service restrictions]. We do not claim support for other countries' tax regimes. [VERIFY_BEFORE_STATING_THAT_FEATURES_ARE_IDENTICAL_IN_ALL_REGIONS].

## 6. Authorization and third-party material

[ATTACH_VERIFIABLE_SOFTWARE_REGISTRATION/TAX_AUTHORITY_AUTHORIZATION_RELEVANT_TO_THE_ENABLED_FUNCTIONS, with document name, issuer and reference number; explain scope]. Do not replace missing authorization with a claim that registration is unnecessary, and do not describe a pending application, sandbox approval or unrelated software version as a production authorization.

[IDENTIFY_ANY_PROTECTED_THIRD_PARTY_MATERIAL_AND_LICENSE/CONSENT, or confirm after an asset audit that no such licensed content is distributed]. Demo records and attachments must be synthetic, with rights cleared for every displayed image.
