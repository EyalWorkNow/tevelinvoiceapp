# Mobile / backend connection audit

Generated from the actual registered server route table and mobile source on 2026-11-09. This is a source-contract inventory, not evidence that a provider or production deployment is configured. Dynamic paths are compared as templates; conditional direct handlers require review.

| Method | Mobile path | Source | Status | Server route |
|---|---|---|---|---|
| GET | /documents/$id | lib/api/actions_api.dart:45 | ROUTE_PRESENT | GET /documents/:id, GET /documents/:id |
| GET | /documents | lib/api/actions_api.dart:62 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /documents/$documentId/pdf | lib/api/actions_api.dart:76 | ROUTE_PRESENT | GET /documents/:id/pdf |
| GET | /documents/$documentId/pdf | lib/api/actions_api.dart:81 | ROUTE_PRESENT | GET /documents/:id/pdf |
| POST | /documents/$documentId/artifact?type=COPY | lib/api/actions_api.dart:87 | ROUTE_PRESENT | POST /documents/:id/artifact |
| POST | /documents/${doc.id}/share-link | lib/api/actions_api.dart:105 | ROUTE_PRESENT | POST /documents/:id/share-link |
| POST | /documents/${doc.id}/share-link | lib/api/actions_api.dart:109 | ROUTE_PRESENT | POST /documents/:id/share-link |
| POST | /documents/$documentId/share-link/revoke | lib/api/actions_api.dart:118 | ROUTE_PRESENT | POST /documents/:id/share-link/revoke |
| POST | /documents/$documentId/send | lib/api/actions_api.dart:128 | ROUTE_PRESENT | POST /documents/:id/send |
| POST | /deliveries/$deliveryId/process | lib/api/actions_api.dart:138 | ROUTE_PRESENT | POST /deliveries/:id/process |
| POST | /customers/$customerId/consent | lib/api/actions_api.dart:144 | ROUTE_PRESENT | POST /customers/:id/consent |
| POST | /documents/${doc.id}/approve | lib/api/actions_api.dart:174 | ROUTE_PRESENT | POST /documents/:id/approve |
| POST | /documents/$documentId/reject | lib/api/actions_api.dart:200 | ROUTE_PRESENT | POST /documents/:id/reject |
| POST | /documents/${doc.id}/credit | lib/api/actions_api.dart:276 | ROUTE_PRESENT | POST /documents/:id/credit |
| POST | /documents/$documentId/void | lib/api/actions_api.dart:329 | ROUTE_PRESENT | POST /documents/:id/void |
| GET | /documents/$documentId/allocation | lib/api/actions_api.dart:383 | ROUTE_PRESENT | GET /documents/:id/allocation |
| POST | /documents/$documentId/allocation/$action | lib/api/actions_api.dart:393 | ROUTE_PRESENT | POST /documents/:id/allocation/cancel, POST /documents/:id/allocation/evaluate, POST /documents/:id/allocation/request, POST /documents/:id/allocation/reconcile, POST /documents/:id/allocation/decision, POST /documents/:id/allocation/manual |
| POST | /documents/$documentId/allocation/manual | lib/api/actions_api.dart:403 | ROUTE_PRESENT | POST /documents/:id/allocation/manual |
| POST | /documents/$documentId/allocation/decision | lib/api/actions_api.dart:409 | ROUTE_PRESENT | POST /documents/:id/allocation/decision |
| POST | /documents/$documentId/allocation/cancel | lib/api/actions_api.dart:418 | ROUTE_PRESENT | POST /documents/:id/allocation/cancel |
| GET | /quotes/$quoteId/pdf | lib/api/actions_api.dart:439 | ROUTE_PRESENT | GET /quotes/:id/pdf |
| POST | /quotes/$quoteId/share-link | lib/api/actions_api.dart:444 | ROUTE_PRESENT | POST /quotes/:id/share-link |
| POST | /quotes/$quoteId/clone | lib/api/actions_api.dart:450 | ROUTE_PRESENT | POST /quotes/:id/clone |
| POST | /documents/${doc.id}/clone | lib/api/actions_api.dart:465 | ROUTE_PRESENT | POST /documents/:id/clone |
| POST | /documents | lib/api/actions_api.dart:471 | ROUTE_PRESENT | POST /documents, POST /documents |
| POST | /documents/$documentId/clone | lib/api/actions_api.dart:497 | ROUTE_PRESENT | POST /documents/:id/clone |
| POST | /auth/login | lib/api/auth_api.dart:34 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/apple | lib/api/auth_api.dart:41 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/google | lib/api/auth_api.dart:52 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/password/forgot | lib/api/auth_api.dart:58 | DIRECT_HANDLER_REVIEW |  |
| GET | /auth/mfa/methods | lib/api/auth_api.dart:86 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/mfa/email/send | lib/api/auth_api.dart:107 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/mfa/email/verify | lib/api/auth_api.dart:112 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/mfa | lib/api/auth_api.dart:122 | DIRECT_HANDLER_REVIEW |  |
| GET | /auth/invite/$token | lib/api/auth_api.dart:131 | DIRECT_HANDLER_REVIEW |  |
| POST | /auth/invite/$token/accept | lib/api/auth_api.dart:140 | DIRECT_HANDLER_REVIEW |  |
| PUT | /business/profile | lib/api/auth_api.dart:158 | ROUTE_PRESENT | PUT /business/profile |
| PUT | /business/onboarding | lib/api/auth_api.dart:168 | ROUTE_PRESENT | PUT /business/onboarding |
| GET | /mobile/businesses | lib/api/auth_api.dart:204 | DIRECT_HANDLER_REVIEW |  |
| POST | /businesses | lib/api/auth_api.dart:225 | ROUTE_PRESENT | POST /businesses |
| GET | /settings/branding | lib/api/branding_api.dart:62 | ROUTE_PRESENT | GET /settings/branding |
| PUT | /settings/branding | lib/api/branding_api.dart:86 | ROUTE_PRESENT | PUT /settings/branding |
| POST | /settings/branding/preview | lib/api/branding_api.dart:112 | ROUTE_PRESENT | POST /settings/branding/preview |
| GET | /billing/plans | lib/api/commerce_api.dart:60 | ROUTE_PRESENT | GET /billing/plans |
| GET | /billing/subscription | lib/api/commerce_api.dart:74 | ROUTE_PRESENT | GET /billing/subscription |
| POST | /billing/checkout | lib/api/commerce_api.dart:80 | ROUTE_PRESENT | POST /billing/checkout |
| POST | /billing/checkouts/$id/verify | lib/api/commerce_api.dart:96 | ROUTE_PRESENT | POST /billing/checkouts/:id/verify |
| POST | /billing/subscription/cancel | lib/api/commerce_api.dart:101 | ROUTE_PRESENT | POST /billing/subscription/cancel |
| GET | /billing/apple/account | lib/api/commerce_api.dart:104 | ROUTE_PRESENT | GET /billing/apple/account |
| POST | /billing/apple/transactions/verify | lib/api/commerce_api.dart:116 | ROUTE_PRESENT | POST /billing/apple/transactions/verify |
| GET | /expenses/overview | lib/api/commerce_api.dart:152 | ROUTE_PRESENT | GET /expenses/overview |
| PATCH | /expenses/$id/recognition | lib/api/commerce_api.dart:164 | ROUTE_PRESENT | PATCH /expenses/:id/recognition |
| POST | /documents/$id/dispatch | lib/api/commerce_api.dart:199 | ROUTE_PRESENT | POST /documents/:id/dispatch |
| GET | /settings/cardcom | lib/api/commerce_api.dart:205 | ROUTE_PRESENT | GET /settings/cardcom |
| PUT | /settings/cardcom | lib/api/commerce_api.dart:207 | ROUTE_PRESENT | PUT /settings/cardcom |
| POST | /settings/cardcom/disconnect | lib/api/commerce_api.dart:213 | ROUTE_PRESENT | POST /settings/cardcom/disconnect |
| GET | /payments/cardcom-checkouts | lib/api/commerce_api.dart:215 | ROUTE_PRESENT | GET /payments/cardcom-checkouts |
| POST | /payments/cardcom-checkouts/$id/verify | lib/api/commerce_api.dart:223 | ROUTE_PRESENT | POST /payments/cardcom-checkouts/:id/verify |
| POST | /documents/$documentId/payment-link | lib/api/commerce_api.dart:231 | ROUTE_PRESENT | POST /documents/:id/payment-link |
| GET | /crm/customers | lib/api/customer_crm_api.dart:45 | ROUTE_PRESENT | GET /crm/customers |
| PUT | /crm/customers/$customerId | lib/api/customer_crm_api.dart:74 | ROUTE_PRESENT | PUT /crm/customers/:id |
| GET | /customers | lib/api/customers_api.dart:73 | ROUTE_PRESENT | GET /customers, GET /customers |
| GET | /customers | lib/api/customers_api.dart:88 | ROUTE_PRESENT | GET /customers, GET /customers |
| GET | /customers/$id | lib/api/customers_api.dart:96 | ROUTE_PRESENT | GET /customers/:id |
| POST | /customers | lib/api/customers_api.dart:123 | ROUTE_PRESENT | POST /customers |
| POST | /customers/$customerId/consent | lib/api/customers_api.dart:145 | ROUTE_PRESENT | POST /customers/:id/consent |
| PATCH | /customers/$id | lib/api/customers_api.dart:150 | ROUTE_PRESENT | PATCH /customers/:id, PATCH /customers/:id |
| POST | /customers/$id/archive | lib/api/customers_api.dart:155 | ROUTE_PRESENT | POST /customers/:id/archive |
| GET | /documents | lib/api/customers_api.dart:160 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /documents | lib/api/customers_api.dart:189 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /documents | lib/api/customers_api.dart:197 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /customers/$customerId/statement | lib/api/customers_api.dart:232 | ROUTE_PRESENT | GET /customers/:id/statement |
| POST | /customers/$customerId/statement/send | lib/api/customers_api.dart:246 | ROUTE_PRESENT | POST /customers/:id/statement/send |
| GET | /customers/$customerId/statement.pdf | lib/api/customers_api.dart:253 | ROUTE_PRESENT | GET /customers/:id/statement.pdf |
| GET | /dashboard | lib/api/documents_api.dart:35 | ROUTE_PRESENT | GET /dashboard, GET /dashboard |
| GET | /documents | lib/api/documents_api.dart:40 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /documents/$id | lib/api/documents_api.dart:57 | ROUTE_PRESENT | GET /documents/:id, GET /documents/:id |
| GET | /customers | lib/api/documents_api.dart:61 | ROUTE_PRESENT | GET /customers, GET /customers |
| GET | /documents/$id/pdf | lib/api/documents_api.dart:73 | ROUTE_PRESENT | GET /documents/:id/pdf |
| POST | /documents/$id/artifact | lib/api/documents_api.dart:76 | ROUTE_PRESENT | POST /documents/:id/artifact |
| GET | /documents/$id/pdf | lib/api/documents_api.dart:78 | ROUTE_PRESENT | GET /documents/:id/pdf |
| DELETE | /documents/$id | lib/api/documents_api.dart:84 | ROUTE_PRESENT | DELETE /documents/:id |
| POST | /expenses/uploads/initiate | lib/api/expenses_api.dart:112 | ROUTE_PRESENT | POST /expenses/uploads/initiate |
| POST | /expenses/uploads/$uploadId/complete | lib/api/expenses_api.dart:131 | ROUTE_PRESENT | POST /expenses/uploads/:id/complete |
| GET | /expenses/uploads/$uploadId | lib/api/expenses_api.dart:139 | ROUTE_PRESENT | GET /expenses/:id/extraction, GET /expenses/uploads/:id, GET /expenses/:id/extraction, GET /expenses/:id/source |
| GET | /expenses/inbox | lib/api/expenses_api.dart:173 | ROUTE_PRESENT | GET /expenses/inbox, GET /expenses/inbox |
| GET | /expense-categories | lib/api/expenses_api.dart:190 | ROUTE_PRESENT | GET /expense-categories |
| POST | /expenses/$id/extract | lib/api/expenses_api.dart:212 | ROUTE_PRESENT | POST /expenses/:id/extract, POST /expenses/:id/extract |
| PATCH | /expenses/$id/draft | lib/api/expenses_api.dart:233 | ROUTE_PRESENT | PATCH /expenses/:id/draft |
| POST | /expenses/$id/approve | lib/api/expenses_api.dart:243 | ROUTE_PRESENT | POST /expenses/:id/approve |
| POST | /expenses/$id/reject | lib/api/expenses_api.dart:247 | ROUTE_PRESENT | POST /expenses/:id/reject |
| POST | /expenses/$id/duplicate | lib/api/expenses_api.dart:251 | ROUTE_PRESENT | POST /expenses/:id/duplicate |
| POST | /expenses/$id/undo-duplicate | lib/api/expenses_api.dart:254 | ROUTE_PRESENT | POST /expenses/:id/undo-duplicate |
| GET | /expenses/$id/source | lib/api/expenses_api.dart:257 | ROUTE_PRESENT | GET /expenses/uploads/:id, GET /expenses/:id/source |
| GET | /expenses | lib/api/expenses_api.dart:285 | ROUTE_PRESENT | GET /expenses |
| PATCH | /expenses/$id | lib/api/expenses_api.dart:302 | ROUTE_PRESENT | PATCH /expenses/:id |
| DELETE | /expenses/$id | lib/api/expenses_api.dart:305 | ROUTE_PRESENT | DELETE /expenses/:id |
| GET | /mobile/inbox | lib/api/inbox_api.dart:60 | ROUTE_PRESENT | GET /mobile/inbox |
| GET | /dashboard | lib/api/inbox_api.dart:137 | ROUTE_PRESENT | GET /dashboard, GET /dashboard |
| GET | /approvals | lib/api/inbox_api.dart:146 | ROUTE_PRESENT | GET /approvals |
| GET | /expenses/inbox | lib/api/inbox_api.dart:149 | ROUTE_PRESENT | GET /expenses/inbox, GET /expenses/inbox |
| GET | /settings/branding | lib/api/inbox_api.dart:177 | ROUTE_PRESENT | GET /settings/branding |
| GET | /documents/$id | lib/api/inbox_api.dart:539 | ROUTE_PRESENT | GET /documents/:id, GET /documents/:id |
| POST | /documents/$id/allocation | lib/api/inbox_api.dart:541 | ROUTE_PRESENT | POST /documents/:id/allocation |
| GET | /customers | lib/api/inbox_api.dart:598 | ROUTE_PRESENT | GET /customers, GET /customers |
| POST | /documents/${d.id}/send | lib/api/inbox_api.dart:618 | ROUTE_PRESENT | POST /documents/:id/send |
| POST | /deliveries/${delivery['deliveryId']}/process | lib/api/inbox_api.dart:622 | ROUTE_PRESENT | POST /deliveries/:id/process |
| POST | /documents/$documentId/share-link | lib/api/inbox_api.dart:651 | ROUTE_PRESENT | POST /documents/:id/share-link |
| POST | /documents/$documentId/artifact | lib/api/inbox_api.dart:654 | ROUTE_PRESENT | POST /documents/:id/artifact |
| POST | /documents/$documentId/share-link | lib/api/inbox_api.dart:655 | ROUTE_PRESENT | POST /documents/:id/share-link |
| GET | /documents | lib/api/inbox_api.dart:686 | ROUTE_PRESENT | GET /documents, GET /documents |
| GET | /customers | lib/api/inbox_api.dart:758 | ROUTE_PRESENT | GET /customers, GET /customers |
| GET | /quotes | lib/api/inbox_api.dart:775 | ROUTE_PRESENT | GET /quotes |
| POST | /documents/preview | lib/api/issue_api.dart:38 | ROUTE_PRESENT | POST /documents/preview |
| GET | /sequences | lib/api/issue_api.dart:80 | ROUTE_PRESENT | GET /sequences |
| POST | /documents/$id/sign | lib/api/issue_api.dart:93 | ROUTE_PRESENT | POST /documents/:id/sign |
| POST | /documents/$id/allocation/evaluate | lib/api/issue_api.dart:101 | ROUTE_PRESENT | POST /documents/:id/allocation/evaluate |
| POST | /documents/$id/share-link | lib/api/issue_api.dart:107 | ROUTE_PRESENT | POST /documents/:id/share-link |
| POST | /documents/$id/share-link | lib/api/issue_api.dart:111 | ROUTE_PRESENT | POST /documents/:id/share-link |
| POST | /documents/$id/finalize | lib/api/issue_api.dart:180 | ROUTE_PRESENT | POST /documents/:id/finalize |
| POST | /documents/$id/payments | lib/api/issue_api.dart:218 | ROUTE_PRESENT | POST /documents/:id/payments |
| POST | /receipts | lib/api/issue_api.dart:247 | ROUTE_PRESENT | POST /receipts |
| GET | /documents/$id/allocation | lib/api/issue_api.dart:288 | ROUTE_PRESENT | GET /documents/:id/allocation |
| POST | /documents/$id/allocation/request | lib/api/issue_api.dart:290 | ROUTE_PRESENT | POST /documents/:id/allocation/request |
| POST | /documents/$id/artifact | lib/api/issue_api.dart:332 | ROUTE_PRESENT | POST /documents/:id/artifact |
| POST | /payments | lib/api/issue_api.dart:346 | ROUTE_PRESENT | POST /payments, POST /payments |
| PATCH | /customers/$customerId | lib/api/issue_api.dart:367 | ROUTE_PRESENT | PATCH /customers/:id, PATCH /customers/:id |
| POST | /documents/${p.draftId}/submit | lib/api/issue_api.dart:389 | ROUTE_PRESENT | POST /documents/:id/submit |
| DELETE | /documents/${p.draftId} | lib/api/issue_api.dart:407 | ROUTE_PRESENT | DELETE /documents/:id |
| POST | /documents | lib/api/issue_api.dart:452 | ROUTE_PRESENT | POST /documents, POST /documents |
| PUT | /documents/${p.draftId} | lib/api/issue_api.dart:461 | ROUTE_PRESENT | PUT /documents/:id, PUT /documents/:id |
| POST | /documents/${p.cloneFrom}/clone | lib/api/issue_api.dart:479 | ROUTE_PRESENT | POST /documents/:id/clone |
| GET | /documents | lib/api/issue_api.dart:498 | ROUTE_PRESENT | GET /documents, GET /documents |
| DELETE | /documents/$draftId | lib/api/issue_api.dart:521 | ROUTE_PRESENT | DELETE /documents/:id |
| GET | /items | lib/api/items_api.dart:32 | ROUTE_PRESENT | GET /items, GET /items |
| POST | /items | lib/api/items_api.dart:53 | ROUTE_PRESENT | POST /items |
| PATCH | /items/$id | lib/api/items_api.dart:80 | ROUTE_PRESENT | PATCH /items/:id |
| POST | /items/$id/archive | lib/api/items_api.dart:84 | ROUTE_PRESENT | POST /items/:id/archive |
| POST | /items/$id/restore | lib/api/items_api.dart:87 | ROUTE_PRESENT | POST /items/:id/restore |
| POST | /payments | lib/api/payments_api.dart:128 | ROUTE_PRESENT | POST /payments, POST /payments |
| POST | /payments | lib/api/payments_api.dart:135 | ROUTE_PRESENT | POST /payments, POST /payments |
| POST | /documents/${doc.id}/payments | lib/api/payments_api.dart:156 | ROUTE_PRESENT | POST /documents/:id/payments |
| POST | /receipts | lib/api/payments_api.dart:175 | ROUTE_PRESENT | POST /receipts |
| GET | /payments | lib/api/payments_api.dart:231 | ROUTE_PRESENT | GET /payments |
| POST | /payments/$paymentId/void | lib/api/payments_api.dart:256 | ROUTE_PRESENT | POST /payments/:id/void |
| GET | /quotes | lib/api/quotes_api.dart:21 | ROUTE_PRESENT | GET /quotes |
| GET | /quotes/$id | lib/api/quotes_api.dart:31 | ROUTE_PRESENT | GET /quotes/:id |
| POST | /quotes | lib/api/quotes_api.dart:48 | ROUTE_PRESENT | POST /quotes, POST /quotes |
| PUT | /quotes/$id | lib/api/quotes_api.dart:68 | ROUTE_PRESENT | PUT /quotes/:id |
| POST | /quotes/$id/clone | lib/api/quotes_api.dart:81 | ROUTE_PRESENT | POST /quotes/:id/clone |
| POST | /quotes/$id/share-link | lib/api/quotes_api.dart:90 | ROUTE_PRESENT | POST /quotes/:id/share-link |
| GET | /quotes/$id/pdf | lib/api/quotes_api.dart:98 | ROUTE_PRESENT | GET /quotes/:id/pdf |
| POST | /quotes/$id/status | lib/api/quotes_api.dart:104 | ROUTE_PRESENT | POST /quotes/:id/status |
| POST | /quotes/$id/convert | lib/api/quotes_api.dart:120 | ROUTE_PRESENT | POST /quotes/:id/convert, POST /quotes/:id/convert |
| GET | /dashboard | lib/api/reports_api.dart:22 | ROUTE_PRESENT | GET /dashboard, GET /dashboard |
| GET | /reports/income | lib/api/reports_api.dart:32 | ROUTE_PRESENT | GET /reports/:kind |
| GET | /reports/$kind | lib/api/reports_api.dart:44 | ROUTE_PRESENT | GET /reports/:kind |
| GET | /reports/$kind | lib/api/reports_api.dart:58 | ROUTE_PRESENT | GET /reports/:kind |
| POST | /exports/$kind | lib/api/reports_api.dart:67 | ROUTE_PRESENT | POST /exports/excel, POST /exports/accountant, POST /exports/uniform-format |
| GET | /exports/download | lib/api/reports_api.dart:69 | ROUTE_PRESENT | GET /exports/download |
| POST | /reports/$kind/send?from=${period.fromIso}&to=${period.toIso} | lib/api/reports_api.dart:107 | ROUTE_PRESENT | POST /reports/:kind/send |
| GET | /payments | lib/api/reports_api.dart:130 | ROUTE_PRESENT | GET /payments |
| GET | /mobile/inbox | lib/api/reports_api.dart:210 | ROUTE_PRESENT | GET /mobile/inbox |
| PUT | /business/profile | lib/api/settings_api.dart:26 | ROUTE_PRESENT | PUT /business/profile |
| PUT | /settings/approval | lib/api/settings_api.dart:63 | ROUTE_PRESENT | PUT /settings/approval |
| GET | /sequences | lib/api/settings_api.dart:76 | ROUTE_PRESENT | GET /sequences |
| PUT | /sequences/${row['numbering_scope_key']}/start | lib/api/settings_api.dart:81 | ROUTE_PRESENT | PUT /sequences/:scopeKey/start |
| POST | /mobile/web-handoff | lib/api/settings_api.dart:93 | ROUTE_PRESENT | POST /mobile/web-handoff |
| POST | /mobile/logout-all | lib/api/settings_api.dart:136 | DIRECT_HANDLER_REVIEW |  |
| POST | /mobile/account/delete | lib/api/settings_api.dart:166 | DIRECT_HANDLER_REVIEW |  |
| PUT | /settings/document-email | lib/api/settings_api.dart:248 | ROUTE_PRESENT | PUT /settings/document-email |
| PUT | /settings/reminders | lib/api/settings_api.dart:260 | ROUTE_PRESENT | PUT /settings/reminders |
| PUT | /settings/accountant-automation | lib/api/settings_api.dart:272 | ROUTE_PRESENT | PUT /settings/accountant-automation |
| POST | /business/type-change | lib/api/settings_api.dart:303 | ROUTE_PRESENT | POST /business/type-change |
| GET | /shaam/status | lib/api/shaam_api.dart:11 | ROUTE_PRESENT | GET /shaam/status |
| GET | /settings/signing | lib/api/shaam_api.dart:34 | ROUTE_PRESENT | GET /settings/signing |
| POST | /settings/signing/unlock | lib/api/signing_api.dart:70 | ROUTE_PRESENT | POST /settings/signing/unlock |
| POST | /documents/$documentId/artifact | lib/api/signing_api.dart:112 | ROUTE_PRESENT | POST /documents/:id/artifact |
| POST | /documents/$documentId/sign | lib/api/signing_api.dart:120 | ROUTE_PRESENT | POST /documents/:id/sign |
| GET | /suppliers | lib/api/suppliers_api.dart:33 | ROUTE_PRESENT | GET /suppliers, GET /suppliers |
| GET | /suppliers/$id | lib/api/suppliers_api.dart:51 | ROUTE_PRESENT | GET /suppliers/:id |
| PATCH | /suppliers/$id | lib/api/suppliers_api.dart:68 | ROUTE_PRESENT | PATCH /suppliers/:id |
| POST | /suppliers/$id/archive | lib/api/suppliers_api.dart:73 | ROUTE_PRESENT | POST /suppliers/:id/archive |
| POST | /suppliers | lib/api/suppliers_api.dart:78 | ROUTE_PRESENT | POST /suppliers |
| GET | /business/members | lib/api/team_api.dart:23 | ROUTE_PRESENT | GET /business/members |
| POST | /business/members/invite | lib/api/team_api.dart:51 | ROUTE_PRESENT | POST /business/members/invite, POST /business/members/invite |
| PUT | /business/members/${m.userId}/permissions | lib/api/team_api.dart:105 | ROUTE_PRESENT | PUT /business/members/:userId/permissions |
| PUT | /business/members/${member.userId}/role | lib/api/team_api.dart:144 | ROUTE_PRESENT | PUT /business/members/:userId/role |
| PUT | /business/members/${member.userId}/permissions | lib/api/team_api.dart:145 | ROUTE_PRESENT | PUT /business/members/:userId/permissions |
| POST | /business/invitations/$invitationId/resend | lib/api/team_api.dart:150 | ROUTE_PRESENT | POST /business/invitations/:id/resend |
| POST | /business/invitations/$invitationId/revoke | lib/api/team_api.dart:153 | ROUTE_PRESENT | POST /business/invitations/:id/revoke |
| POST | /business/ownership/transfer | lib/api/team_api.dart:203 | ROUTE_PRESENT | POST /business/ownership/transfer |
| POST | /business/ownership/transfer | lib/api/team_api.dart:210 | ROUTE_PRESENT | POST /business/ownership/transfer |
| POST | /business/members/$userId/revoke | lib/api/team_api.dart:216 | ROUTE_PRESENT | POST /business/members/:userId/revoke |
| GET | /integrations/status | lib/screens/business/integrations_screen.dart:28 | ROUTE_PRESENT | GET /integrations/status |
| GET | /tax-rates | lib/screens/compose/compose_memory.dart:34 | ROUTE_PRESENT | GET /tax-rates |
| GET | /customers | lib/screens/compose/compose_memory.dart:62 | ROUTE_PRESENT | GET /customers, GET /customers |
| PATCH | /customers/${customer.id} | lib/screens/compose/compose_submit.dart:269 | ROUTE_PRESENT | PATCH /customers/:id, PATCH /customers/:id |
| GET | /mobile/push-status | lib/state/system_notices.dart:106 | ROUTE_PRESENT | GET /mobile/push-status |
| DELETE | /mobile/push-tokens | lib/state/system_notices.dart:133 | ROUTE_PRESENT | DELETE /mobile/push-tokens |
| POST | /mobile/push-tokens | lib/state/system_notices.dart:236 | ROUTE_PRESENT | POST /mobile/push-tokens |

## Local/fallback/unsupported markers

Every marker requires interpretation: cache fallbacks and deliberate desktop handoffs are not automatically defects.

- `lib/api/actions_api.dart:19` — import 'customers_api.dart' show fetchCustomerDetail, isMissingRoute;
- `lib/api/actions_api.dart:53` — if (e.isNetwork || (e.status != 404 && !isMissingRoute(e))) rethrow;
- `lib/api/actions_api.dart:367` — /// ADR-SHAAM-DEGRADATION: calm notice while the Tax Authority is unavailable (or the
- `lib/api/actions_api.dart:386` — /// While the Tax Authority is down the server fails fast (SHAAM_SERVICE_UNAVAILABLE) without
- `lib/api/actions_api.dart:395` — if (e.code != 'SHAAM_SERVICE_UNAVAILABLE') rethrow;
- `lib/api/actions_api.dart:427` — /// own rate; [vatRateBasisPoints] is the fallback for lines without one.
- `lib/api/actions_api.dart:469` — if (!isMissingRoute(e)) rethrow; // the route itself is missing (before BE-08)
- `lib/api/client.dart:331` — code = 'SERVICE_UNAVAILABLE';
- `lib/api/client.dart:357` — '/mobile/web-handoff',
- `lib/api/customers_api.dart:29` — bool isMissingRoute(Object e) => e is ApiException && e.status == 404 && e.code == 'NOT_FOUND';
- `lib/api/customers_api.dart:98` — if (!isMissingRoute(e)) rethrow;
- `lib/api/customers_api.dart:236` — return _statementSupport[bid] = !isMissingRoute(e);
- `lib/api/expenses_api.dart:208` — /// (503 EXTRACTION_UNAVAILABLE) or the expense is not reviewable: the card
- `lib/api/expenses_api.dart:307` — /// Local search for the inbox fallback: supplier name, document number,
- `lib/api/inbox_api.dart:5` — // * P0 fallback (route missing → 404 NOT_FOUND): compose the cards on the
- `lib/api/models/member.dart:29` — Me(userId: '', role: role, permissions: {...?rolePermissionsFallback[role], ...grants}.toList()),
- `lib/api/models/member.dart:34` — final base = (rolePermissionsFallback[role] ?? const <String>[]).toSet();
- `lib/api/models/member.dart:85` — Set<String> get effective => {...?rolePermissionsFallback[role], ...grants};
- `lib/api/models/member.dart:178` — /// V1 web link (fallback).
- `lib/api/quotes_api.dart:8` — // (per-line rates win; the body rate is a fallback), POST /quotes/:id/clone,
- `lib/api/settings_api.dart:89` — /// BE-35: POST /mobile/web-handoff {topic} → e-mail with the link. A server
- `lib/api/settings_api.dart:91` — Future<void> sendWebHandoff(String topic, String topicLabel) async {
- `lib/api/settings_api.dart:93` — await _api.post('/mobile/web-handoff', {'topic': topic});
- `lib/api/settings_api.dart:195` — // router's fallback; domain 404s carry their own code). Rows/fields of such a
- `lib/api/settings_api.dart:204` — bool isMissingRoute(Object e) => e is ApiException && e.status == 404 && e.code == 'NOT_FOUND';
- `lib/api/settings_api.dart:214` — /// these routes: the empty POST meets the 404 fallback) is still probed.
- `lib/api/settings_api.dart:225` — return _probes[key] = !isMissingRoute(e);
- `lib/api/settings_api.dart:234` — if (isMissingRoute(e)) return null;
- `lib/api/signing_api.dart:93` — // Keychain unavailable: the dialog comes back next time.
- `lib/api/suppliers_api.dart:9` — import 'customers_api.dart' show isMissingRoute;
- `lib/api/suppliers_api.dart:55` — if (!isMissingRoute(e)) rethrow;
- `lib/api/team_api.dart:10` — // P0 fallback (server without BE-41 ignores `permissions` on invite): the
- `lib/api/team_api.dart:57` — final (json, asRep) = await _withRepFallback(
- `lib/api/team_api.dart:124` — final (_, asRep) = await _withRepFallback(
- `lib/api/team_api.dart:160` — await _withRepFallback(
- `lib/api/team_api.dart:181` — Future<(T, bool)> _withRepFallback<T>(
- `lib/screens/auth/invite_screen.dart:121` — (invite?.inviterName ?? '').isEmpty ? AuthHe.inviterFallback : invite!.inviterName,
- `lib/screens/business/shaam_page.dart:115` — ? BusinessHe.signingNotConfigured
- `lib/screens/business/sheets/editor_configs.dart:614` — return sendWebHandoff(t, desktopTopics[t] ?? t);
- `lib/screens/compose/compose_screen.dart:65` — bool _unavailable = false;
- `lib/screens/compose/compose_screen.dart:84` — _unavailable = false;
- `lib/screens/compose/compose_screen.dart:95` — if (load == null) return setState(() => _unavailable = true);
- `lib/screens/compose/compose_screen.dart:193` — child: _unavailable
- `lib/screens/document/document_screen.dart:762` — label: bytes != null ? DocumentHe.pdfOpen : DocumentHe.pdfUnavailable,
- `lib/screens/document/sheets/s6_share.dart:368` — if (result == 'UNAVAILABLE') {
- `lib/screens/document/sheets/s6_share.dart:371` — 'SMS_UNAVAILABLE',
- `lib/screens/expense/expense_capture_screen.dart:96` — ? ExpenseHe.cameraUnavailable
- `lib/screens/home/doc_rows.dart:69` — /// "בתוקף עד 12.10.2026" (else "נוצרה …") — never the title's fallback word.
- `lib/screens/home/inbox_cards.dart:12` — import '../../api/settings_api.dart' show sendWebHandoff;
- `lib/screens/home/inbox_cards.dart:270` — await sendWebHandoff('TAX_AUTHORITY', InboxHe.handoffShaam);
- `lib/screens/people/person_screen.dart:130` — if (!opened) throw StateError('External app unavailable');
- `lib/screens/reports/reports_screen.dart:21` — import '../../api/settings_api.dart' show sendWebHandoff;
- `lib/screens/reports/reports_screen.dart:222` — await sendWebHandoff('UNIFORM_FORMAT', ReportsHe.uniformFormat);
- `lib/state/caps.dart:90` — const Map<String, List<String>> rolePermissionsFallback = {
- `lib/state/caps.dart:113` — Caps._(this._caps, this.preset, this.approvalPolicy, this.fromFallback);
- `lib/state/caps.dart:120` — final perms = (me.permissions ?? rolePermissionsFallback[role] ?? const <String>[]).toSet();
- `lib/state/caps.dart:179` — final bool fromFallback;
- `lib/state/customer_crm_store.dart:405` — if (kReleaseMode) throw StateError('Preview mode unavailable');
- `lib/state/system_notices.dart:112` — if (!deliveryConfigured) throw StateError('PUSH_SERVICE_NOT_CONFIGURED');
- `lib/state/system_notices.dart:245` — throw StateError('PUSH_SERVICE_NOT_CONFIGURED');
- `lib/ui/theme.dart:198` — static const List<String> _hebrewFallback = [
- `lib/ui/theme.dart:206` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:216` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:226` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:235` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:243` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:251` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:259` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:267` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:274` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:280` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/theme.dart:287` — fontFamilyFallback: _hebrewFallback,
- `lib/ui/widgets/notch_notice.dart:36` — /// Keeps the existing snackbar content/action and the native fallback.
- `lib/util/biometric.dart:13` — unavailable,
- `lib/util/biometric.dart:73` — LocalAuthExceptionCode.noCredentialsSet => UnlockResult.unavailable,
- `lib/util/errors_he.dart:7` — /// used only for VALIDATION). [status] drives the fallback for unknown codes.
- `lib/util/errors_he.dart:14` — return _mobileMessages['SERVICE_UNAVAILABLE']!;
- `lib/util/errors_he.dart:44` — 'SMS_UNAVAILABLE':
- `lib/util/errors_he.dart:50` — 'MERCHANT_VAULT_UNAVAILABLE':
- `lib/util/errors_he.dart:80` — 'SERVICE_UNAVAILABLE': 'השירות לא זמין זמנית — נסו שוב בעוד רגע',
- `lib/util/errors_he.dart:138` — 'WEB_HANDOFF_THROTTLED':
- `lib/util/errors_he.dart:141` — 'EMAIL_UNAVAILABLE': 'לא הצלחנו לשלוח את המייל. נסה שוב.',
- `lib/util/errors_he.dart:158` — 'BUSINESS_TYPE_CHANGE_NOT_SUPPORTED':
- `lib/util/errors_he.dart:186` — 'MFA_EMAIL_UNAVAILABLE': 'שליחת קודים במייל אינה זמינה בשרת זה',
- `lib/util/errors_he.dart:239` — 'SHAAM_TEMPORARILY_UNAVAILABLE':
- `lib/util/errors_he.dart:274` — 'EXTRACTION_UNAVAILABLE':
- `lib/util/errors_he.dart:276` — 'DB_UNAVAILABLE': 'השרת אינו זמין כרגע — נסה שוב בעוד רגע',
- `lib/util/errors_he.dart:280` — 'GOOGLE_CERTS_UNAVAILABLE': 'אימות Google אינו זמין כרגע — נסה שוב בעוד רגע',
- `lib/util/errors_he.dart:293` — 'SIGNING_UNAVAILABLE': 'שירות החתימה אינו זמין כרגע — נסו שוב בעוד רגע',
- `lib/util/errors_he.dart:295` — 'PADES_BRIDGE_UNAVAILABLE': 'רכיב החתימה (PAdES) אינו זמין בשרת',
- `lib/util/errors_he.dart:312` — 'SCANNER_UNAVAILABLE': 'סורק הקבצים אינו זמין כרגע — נסו שוב בעוד רגע',
- `lib/util/labels/business_he.dart:23` — /// V1 server role names (display only, e.g. S14 role tag fallback).
- `lib/util/labels/business_he.dart:112` — static const signingNotConfigured = 'לא הוגדרה חתימה – המשך במחשב';
- `lib/util/labels/business_he.dart:370` — static const inviterFallback = 'המזמין';
- `lib/util/labels/document_he.dart:108` — static const pdfUnavailable = 'ה-PDF עוד לא מוכן';
- `lib/util/labels/people_he.dart:150` — static const cameraUnavailable = 'המצלמה לא זמינה — אפשר לבחור תמונה מהגלריה';
