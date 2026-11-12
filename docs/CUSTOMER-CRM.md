# Customer CRM and job planning

## Server persistence — 2026-11-09

Authenticated application sessions now use the existing backend: GET /crm/customers and PUT /crm/customers/:id. PostgreSQL migration 0092 adds business-scoped records, revisions, mutation idempotency and scheduled notice occurrences with forced RLS. The in-memory simulator preview explicitly opts into device-local storage.

Legacy local data imports by stable item IDs without overwriting matching server items. A durable device queue retries offline changes using the same mutation ID. Initial server loading must succeed before editing; once initialized, offline edits remain visible as pending. Concurrent edits require an explicit server/device choice and preserve a local conflict backup. Caches and pending writes are isolated by account and business; session expiry preserves pending work, while explicit logout uses the existing unsaved-work confirmation.

Financial CRM data is hidden from users without money:read. Editing other job fields cannot overwrite a hidden budget. Wire timestamps use UTC; collection dates retain calendar-day semantics in Israel. Reminder, visit and collection events are scheduled transactionally, then rechecked before dispatch by the outbox worker.

The UI shows synchronization, retry and conflict states. Missing/forbidden APIs are errors; no silent device-only fallback pretends to be server persistence. Manual CRM receipts remain planning data and do not issue accounting documents.

Source changes: lib/api/customer_crm_api.dart, lib/state/customer_crm_store.dart, lib/state/cache.dart, lib/screens/people/customer_crm_sync_status.dart and the CRM views. Backend changes: customer-crm-model.ts, customer-crm.ts, migration 0092 and apps/api/src/routes/v2/customer-crm.ts. Full feature inventory and unresolved blockers: docs/backend-audit/FEATURE-MAP-he.md.

The customer record supports notes, follow-ups, visits, work status, per-visit checklists and an optional repeat cadence (7, 14, 30 or 90 days). Creating another visit is an explicit action: it opens a new job for review. No background jobs are generated automatically. The new visit retains the agreed price and preparation list, while actual cost, time, money received and completed checkboxes reset.

Each job can hold an agreed price, direct costs, working minutes, a manually tracked received amount and a collection deadline. Enter prices and costs on the same VAT basis. Blank price/cost/time means unknown, rather than zero. A known zero direct cost is supported. Manual money received cannot exceed the agreed price.

The business board provides day/week filters, a month selector and a collection queue. Monthly figures use the scheduled visit date, not payment transaction dates. Tracked money received includes deposits on open jobs as well as completed jobs in the selected month. The collection queue includes all completed, non-cancelled jobs with known positive remaining balances, regardless of the selected month. A collection deadline becomes late on the next calendar day.

Contribution is agreed price minus known direct costs. Hourly contribution uses the combined contribution and time of completed jobs with known price, cost and time. It is not net profit, cash flow, bank balance or a tax calculation. These planning figures are kept separate from invoice and receipt totals. They are shown only under the existing money-view capability; operations retain customer-management capability checks.

Device storage is a cache and durable pending queue for the server integration described above. Existing notes, reminders and jobs remain readable. Writes persist before UI success; pending cloud acknowledgement remains visible and failed saves retain editor drafts.

## Production integration still required

Authenticated endpoints, durable storage, scoped authorization, revisions, idempotent writes, legacy import and offline retry are implemented. Production still requires the new migrations and API/worker deployment, backups and provider configuration.

Background reminders and approval/payment events are wired through server scheduling and APNs. Delivery to a registered iPhone still needs end-to-end verification, and the current signing key is Sandbox only. Reconcile job collections with issued documents and recorded payments before replacing manual tracking.

Useful later additions: link expenses and documents to jobs, recurring maintenance contracts, customer approval of estimates, deposit/payment requests, fixed monthly expense planning and business goals. Those should use actual server records rather than duplicated manual totals.

## Local verification and preview

Run `flutter test --no-pub test/customer_crm_store_test.dart test/customer_crm_test.dart test/customer_crm_planning_test.dart`.

The isolated simulator entrypoint is `tool/notch_preview.dart`. Its loopback-only preview endpoint accepts `?crm=seed&to=/person/c1` to insert disposable sample jobs into its temporary storage. The main application does not import those fixtures.

## Files in this change

- `lib/state/customer_crm_store.dart`, `customer_crm_job_budget.dart`, `customer_crm_insights.dart`: persisted job details, validation, atomic checklists and planning calculations.
- `lib/screens/people/customer_crm_editors.dart`, `customer_crm_job_fields.dart`, `customer_crm_jobs.dart`, `customer_crm_finance_card.dart`, `customer_crm_panel.dart`, `customer_crm_agenda_screen.dart`, `person_screen.dart`: editors, job cards, customer/business overview and existing capability wiring.
- `lib/util/labels/customer_crm_he.dart`: Hebrew product text.
- `test/customer_crm_store_test.dart`, `customer_crm_test.dart`, `customer_crm_planning_test.dart`: storage, calculations, form validation and complete UI workflow.
- `tool/notch_preview.dart`, `tool/crm_preview_data.dart`: disposable simulator fixtures.

## Field-work interface

Customer work is split into visits, notes/follow-ups and money. The closest open visit expands by default; other visits keep only time, work, address and status visible. Money uses collection rows and a monthly ledger rather than repeated metric cards. The duplicated customer heading is removed in dark mode.

A new visit starts with title, optional address, date and time. Preparation, recurrence and money are optional details. Service and garden presets fill only empty fields and retain anything already entered. Presets do not invent a price.

A note can be pinned above visits for access instructions or customer preferences. Pinning is persisted without changing its text. A one-tap follow-up creates a call reminder for tomorrow at 09:00. An open visit can move to tomorrow or a week later without rewriting its budget or checklist. Payment deadlines stay as entered.

The visit's map action opens only a fixed Apple Maps address search. Its WhatsApp action prepares a customer-facing appointment draft; the user reviews and sends it in WhatsApp. Private notes, instructions and job costs are excluded from that draft. Neither action sends a message automatically.

The business board separates visits, collection and follow-ups. Visits/follow-ups can be searched by customer or work text. Daily and seven-day date filters remain available. Collection totals are unaffected by visit search.

Additional changed files for this interface: `lib/util/crm_visit.dart`, `lib/util/allowed_urls.dart`, `test/customer_crm_actions_test.dart`; the existing CRM screens, store, labels and workflow tests listed above were updated.

## Verification — 2026-11-08

- CRM suite: 26 tests passed across store, planning, complete customer workflow and visit actions. Includes 375px layout with 1.3x text, pinned-note persistence, concurrent rescheduling/checklist updates, private-data exclusion from appointment drafts, restricted map URLs and failed-save retry.
- Scoped Flutter analysis: 15 source/test files, no issues.
- iPhone 17 Pro simulator: reviewed the customer tabs and financial ledger; saved a service preset from the short form, moved a visit to tomorrow, pinned an access note and filtered the business board by work title. External WhatsApp/Maps opening was tested through the fake launcher rather than sending a real customer message.
- Broader existing `people_screens_test.dart`: 23 passed, 6 failed. Failures concern contact import/prefill, retry visibility, lazy document/statement rows and duplicate-phone UI. A focused rerun of four non-CRM cases passed one and still failed three (contact import, new-contact prefill, duplicate phone). Those broader failures remain unresolved; no clean pre-change baseline was established, so this is not a claim that the entire application test suite is green.
