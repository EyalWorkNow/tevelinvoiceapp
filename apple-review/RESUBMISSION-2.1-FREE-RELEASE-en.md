# Review notes for the free release (build 23)

Status: draft. Server free mode deployed as 1184103. New isolated review account provisioned and credentials saved to App Store Connect; primary authentication, app login, device token, profile and customers returned success. Evidence ZIP uploaded. Build 23 delivered. Developer confirmed physical-device QA of build 23 passed. Developer clarified that only SHAAM registration exists; no software-registration certificate was supplied. The truthful six-part notes and build 23 were saved in App Store Connect. The user authorized submission with manual release. Resubmitted at 21:12 Israel time; App Store Connect shows Waiting for Review for build 23. The iOS 26.7.3 versus latest 27.2.1 recording gap was disclosed before submission. Exact submitted notes: APP_REVIEW_NOTES-FREE-BUILD23-en.txt.

---

Response to Guideline 2.1:

1. Physical-device demonstration
Attached tevel-main-flow.mp4 begins on the iPhone Home Screen, launches Tevel, signs in, navigates the main screens, creates an invoice, views its PDF, and opens customer/report/profile features. Attached tevel-account-deletion.mp4 launches the app, signs in, and demonstrates account deletion through the account settings, ending at the sign-in screen. Recordings supplied by the developer on an iPhone 16 Pro; device OS verified as iOS 26.7.3. The videos predate build 23; build 23 additionally removes subscription and purchase prompts.

2. Purpose, audience and business model
Tevel is a Hebrew business administration app for Israeli business owners and their authorized staff. It centralizes customer records, business documents, expense records and reports. Businesses are provisioned by the Tevel team; the app does not have a self-service registration wizard for new customers. New customers can contact Tevel from the sign-in screen. Access and available actions depend on the user's business role. In this release, downloading the app and all its features are free for all users. No subscription, external payment or in-app purchase is required for access.

3. Review access and feature instructions
Use the dedicated demo credentials in the Sign-In Information fields. Internet access is required. No accessory or sample file is needed for the main document/customer flow. From Home (בית), tap + to create a document: choose its type, enter an amount, choose/add a customer, review the summary and issue it; open the resulting document/PDF. Customers (לקוחות) manages customers. Management (ניהול) opens business tools including expenses and reports. Profile (פרופיל) contains account/business settings. Account deletion: Profile > account settings > Delete account (מחיקת חשבון), enter the account password and type מחק, then confirm. This removes the user's access and signs them out; legally retained business records may remain. Do deletion last because the credentials cease to work afterward. No Apple account authentication is required for deletion.

Private business records are shared only through user-selected document links or sharing actions. The app has no public community feed or random-user chat.

4. External services
Tevel's production API uses an Oracle-hosted PostgreSQL database and file storage; Supabase Auth provides primary email/password authentication; Gmail SMTP sends requested business email; Apple APNs delivers enabled push notifications; ClamAV scans uploaded files. User-initiated sharing can open Mail/WhatsApp and native iOS sharing. Camera/photos/contacts/calendar permissions are requested for the related user action. No AI provider is active in this release. Automatic Israel Tax Authority submission is disabled. Apple/Cardcom purchases are unavailable in this release.

5. Regional behavior
The same feature set is offered across storefronts. The interface is Hebrew and the business workflows target Israeli businesses, including ILS amounts. The app does not adapt documents to other countries' tax systems.

6. Authorization/documentation
The developer reports registration with SHAAM only. No software-registration certificate is supplied and no government approval is claimed. Automatic Israel Tax Authority submission is disabled. The app provides invoicing and business record keeping, without banking, lending, investment or payment processing in this release. No licensed third-party media is distributed.
