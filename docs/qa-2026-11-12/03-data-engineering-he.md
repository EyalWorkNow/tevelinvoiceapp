# QA 2026-11-12 · 03 · ביקורת שכבת הנתונים (Data Engineering)

היקף: אפליקציית iOS ‏`tevel-invoice-mobile` והשרת `invoiceproject` (Postgres ‏`invoice_local`). הבדיקה הייתה לקריאה בלבד: לא שונו קבצים ולא נכתב דבר למסד הנתונים.
ארבעה ממצאים ידועים לא נכללו כאן: רענון ב-resume שמאבד עריכה, תור שנחסם לתמיד, hard casts ב-fromJson, ו-`migratedToUser` שאינו נכתב.

## 1. הארכיטקטורה הנוכחית

```
 iPhone (Flutter)                                   Server (Node + Postgres, RLS tenant+business)
 ─────────────────                                  ─────────────────────────────────────────────
 Library/Caches/cache/*.json  ── read-through ──►   GET /customers (≤500) /documents /items ...
   (customer list, home, items, local draft)        customers / documents / catalog_items
 AppSupport/pending/*.json  ── Idempotency-Key ──►  issue / payment (idempotent)
 AppSupport/user_data/customer_crm_<uid>_<bid>.json
   {customers:{id:Entry}, revisions, pending[]}     customer_crm_records (jsonb blob per customer, revision)
        │  PUT whole record + expectedRevision ──►  customer_crm_mutations (idempotency, request_hash)
        │◄─ GET /crm/customers?offset&limit=100 ──  customer_crm_notice_occurrences → outbox → push
        └─ conflict → *_conflict_backup.json         audit_events (one row per CRM write)
```

מקור האמת לנתוני חשבונאות הוא השרת. ה-CRM הוא מסמך JSON אחד לכל לקוח, ובו השלב, ההערות, התזכורות והעבודות. המסמך נשמר במכשיר ומסונכרן בשיטת CAS: השרת מקבל כתיבה רק אם מספר הגרסה שנשלח תואם לגרסה השמורה.

## 2. ממצאים לפי חומרה

### גבוה

**H1. CRM ברמת מסמך שלם: התנגשויות שווא ודריסת עבודה של משתמש אחר.**
כל שינוי קטן, כמו סימון פריט ב-checklist, שולח את כל רשומת הלקוח עם `expectedRevision` (`lib/state/customer_crm_store.dart:935-948`, ‏`packages/postgres/src/customer-crm.ts:130-132`). כששני עובדים עורכים את אותו לקוח, למשל אחד מוסיף הערה ואחר מסמן עבודה, נוצר `CRM_CONFLICT`. ההתנגשות נוצרת גם כשהשינויים לא נוגעים זה בזה. אם בוחרים ב-"שמור את גרסת המכשיר", כל הרשומה המקומית נשלחת על גבי גרסת השרת (`customer_crm_store.dart:658-670`), וכך נמחקות בשקט ההערות והעבודות שהמשתמש השני הוסיף. השרת לא שומר היסטוריית גרסאות של הרשומה: ה-audit שומר רק metadata (`customer-crm.ts:168-176`). לכן אין דרך לשחזר את מה שנמחק.
**מה לעשות:** לעבור לפעולות ברמת פריט (`addNote`, `patchJob` וכו') או למיזוג תלת-כיווני לפי id של כל פריט. כבר יש פונקציה כזו בשרת, `mergeCrmImport` (`customer-crm-model.ts:181`), אבל היא מופעלת רק בייבוא. בנוסף כדאי לשמור טבלת `customer_crm_record_versions`.

**H2. אין מחיקה ואין מדיניות שמירה לנתוני CRM ולנתוני לקוחות (תיקון 13 / תקנות אבטחת מידע).**
`delete_user_account` סוגר את העסק ומאנונם רק את המשתמש. לקוחות, `customer_crm_records`, ההערות החופשיות והכתובות נשארים לתמיד. לקוח בודד אפשר רק לארכב (`lib/api/customers_api.dart:176-178`), ואין route למחיקה או לאנונימיזציה. חובת השמירה של 7 שנים חלה על רשומות חשבונאיות, לא על הערות CRM, כך שאין סיבה חוקית לשמור אותן. בנוסף, הטבלאות `customer_crm_mutations` ו-`customer_crm_notice_occurrences` גדלות בלי גבול (`migrations/0092_customer_crm.sql:13-34`). זה פער מול עקרון צמצום המידע ומול זכות התיקון והמחיקה.
**מה לעשות:** להוסיף `DELETE /crm/customers/:id` ו-`POST /customers/:id/erase`. המחיקה צריכה לנקות את ה-CRM, את ה-PII שאינו חשבונאי ואת ה-notices, ולהשאיר את שם הלקוח ומספר המזהה רק במסמכים שהוצאו. בעסק שנסגר צריך לנקות את ה-CRM אחרי N ימים, ולהוסיף job ניקוי ל-mutations שגילן מעל 30 יום.

**H3. אין אימות ואין מניעת כפילויות לקוחות בצד השרת.**
`POST /customers` (`apps/api/src/routes.ts:396-425`) מקבל `taxId`, `email` ו-`phone` כמחרוזות חופשיות דרך `vOptionalString`. אין בדיקת ספרת ביקורת, למרות ש-`isValidIsraeliId` קיימת ב-`packages/shared/src/israel.ts:34`. אין גם נרמול טלפון, ואימות דוא"ל קיים רק ב-PATCH. הבקשה נשלחת בלי Idempotency-Key (`customers_api.dart:144`), ולכן retry אחרי timeout יוצר לקוח כפול. זיהוי הכפילויות קיים רק בלקוח, מול רשימה מקומית של עד 500 לקוחות (`sheets/s2_customer.dart:550-557`, ‏`customers_api.dart:18`). אין אינדקס ייחודי על `(business_id, tax_id)`. ב-`invoice_local` מצאתי 3 קבוצות של ח.פ. כפול, 5 קבוצות של שם כפול ו-ח.פ. אחד בפורמט לא תקין.
**מה לעשות:** לאמת בשרת ספרת ביקורת וטלפון ישראלי (בפורמט E.164), לבדוק כפילות לפי tax_id ולהחזיר `409 CUSTOMER_DUPLICATE` עם ה-id הקיים, להוסיף Idempotency-Key ל-POST, ולבנות כלי מיזוג לקוחות שמעביר מסמכים ו-CRM ללקוח שנשאר.

### בינוני

**M1. התראות CRM נשלחות למשתמש הלא נכון.**
`recipientUserId` נקבע לפי מי שכתב לאחרונה, לא לפי מי שיצר את התזכורת או מי שאחראי עליה (`customer-crm.ts:264`). מכיוון ש-`due_at` הוא חלק מהמפתח הייחודי (`0092:32`), כל דחייה של מועד יוצרת occurrence חדש עבור מי שערך. אין במודל שדה `assigneeId`.

**M2. טיוטה מקומית נשמרת בתיקיית Caches.**
`nd_local_draft_*` נשמרת דרך `AppCache.write` לתיקייה `Library/Caches` (`lib/screens/compose/compose_memory.dart:109-117`, ‏`lib/state/cache.dart:66-71`). iOS רשאית למחוק את התיקייה הזו, והיא גם נמחקת כשתוקף ה-session פג (`cache.dart:167-176`, ‏`session.dart:232`), למרות שהקוד מתעד שנתוני משתמש צריכים לשרוד מצב כזה. כדאי להעביר את הטיוטה ל-`user_data`.

**M3. נתוני ה-cache משותפים לכל המשתמשים באותו עסק.**
מפתחות כמו `people_customers_$bid`, ‏`home_$bid` ו-`items_*` לא כוללים את מזהה המשתמש (`customers_api.dart:24-27`). במכשיר משותף, כשה-session פג, משתמש עם תפקיד מוגבל עלול לראות נתונים, למשל יתרות, שנשמרו בזמן שבעל העסק היה מחובר. זה שונה מהבאג הידוע של ה-CRM.

**M4. עימוד ה-CRM ב-offset בין בקשות נפרדות.**
`listCustomerCrm` מבצע `count(*)` ואחר כך `order by customer_id offset` (`customer-crm.ts:71-77`), וכל עמוד נשלף בטרנזקציה נפרדת. רשומה שנוצרת באמצע הטעינה מזיזה את ה-offset. הלולאה בצד הלקוח (`lib/api/customer_crm_api.dart:44-62`) נעצרת כש-`length >= total`, ולכן היא עלולה להחזיר רשומה כפולה ולהשמיט רשומה אחרת. ההמלצה היא keyset (`customer_id > $cursor`) או `updatedSince`, שיאפשר גם סנכרון דלתא במקום משיכה מלאה בכל resume.

**M5. כתיבה מוגברת.**
כל קליק כותב מחדש blob של עד 900KB (`customer-crm.ts:149-155`), רושם audit event, ומפעיל `scheduleCrmNotices` שעובר על כל ה-occurrences. ככל שעסק צובר יותר עבודות, ה-TOAST וטבלת `audit_events` גדלים מהר.

**M6. שני מקורות אמת לגבייה.**
`paidMinor` מוזן ידנית בעבודת CRM (`customer_crm_job_budget.dart:3-17`) ולא קשור לקבלות. `CustomerCrmInsights` מציג "נגבה" ו"נותר לגבות" (`customer_crm_insights.dart:31-72`), ואלה יכולים להיות שונים מהיתרה האמיתית ב-`documents.balance_minor`. צריך לסמן בממשק בבירור שאלו נתוני תכנון, או לקשר עבודה למסמך (`documentId`).

**M7. אינדקסים לשאילתות שהאפליקציה מריצה בפועל.**
- ה-lateral של "מסמך אחרון" (`packages/postgres/src/customers.ts:230-233`) ממיין לפי `created_at`, אבל `documents_customer_idx` כולל רק את `(business_id, customer_id)`. מומלץ ‎`(business_id, customer_id, created_at desc)`.
- החיפוש לפי טלפון משתמש ב-`regexp_replace` על כל השורות, ו-`tax_id like '%x%'` לא נשען על אף אינדקס (`customers.ts:235-237`). מומלץ לשמור עמודה מנורמלת `phone_digits` עם אינדקס trigram.
- `GET /customers` ב-V1 מוגבל ל-500 בלי עימוד (`routes.ts:433`). האפליקציה מבקשת `limit=500` (`customers_api.dart:85`), ועסק עם יותר לקוחות מקבל רשימה חלקית, וזיהוי הכפילויות עובד רק על החלק הזה.

### נמוך

- **L1.** מזהי הערות, תזכורות ועבודות נוצרים מ-`microsecondsSinceEpoch` (`customer_crm_store.dart:45,110,217`). הם לא UUID, הם חושפים את זמן היצירה, ובייבוא ממספר מכשירים עלולה להיות התנגשות. כדאי לעבור ל-UUIDv7.
- **L2.** `customerName` נשמר בעותק בתוך כל תזכורת ועבודה. השרת מעדכן אותו רק כשהרשומה נכתבת (`customer-crm-model.ts:135,157`), ולכן אחרי שינוי שם הלקוח ביומן יוצג השם הישן.
- **L3.** `paymentDueAt` לא עובר את `instantFields` ונשלח כזמן מקומי בלי offset (`customer_crm_api.dart:104-107`). השרת חותך אותו ל-10 תווים, כך שהתוצאה תקינה, אבל זה שביר.
- **L4.** `*_conflict_backup.json` (`customer_crm_store.dart:673-676`) לא נמחק אף פעם, ונשאר עותק PII ישן במכשיר.
- **L5.** בתיקיית `user_data` אין `NSFileProtectionComplete`, ולכן חלה ברירת המחדל: הקבצים פתוחים אחרי ביטול הנעילה הראשון (`ios/Runner/AppDelegate.swift:42-52`). הקבצים כן מוחרגים מגיבוי, וזה טוב. החיסרון הוא שאם המכשיר אבד, אין ל-CRM גיבוי בצד הלקוח, ונשאר רק מה שבשרת.
- **L6.** ל-`catalog_items` יש גם `is_active` וגם `archived_at`, כלומר שני דגלים לאותו מצב. `POST /items` לא שולח Idempotency-Key.
- **L7.** אין ייצוא CRM (CSV/JSON) לבעל העסק, וזו דרישה של זכות העיון.

### מה עובד טוב

RLS מאולץ (forced) על כל הטבלאות. מניעת replay לפי `request_hash`. בקשה חוזרת עם אותו `mutationId` מחזירה את התוצאה הקיימת ולא נספרת כהתנגשות. כתיבה אטומית למכשיר בשיטת tmp ואז rename. קבצי pending מוחרגים מגיבוי. הסתרת `budget` ממשתמשים בלי הרשאת `money:read`, גם בקריאה וגם בכתיבה. העלאת הוצאות עם sha256 שמונע כפילויות. סכומים נשמרים ביחידות minor.

## 3. מוכנות לדוחות ולאנליטיקה

נתוני ה-CRM נשמרים כ-JSONB לא מנורמל, ולכן אי אפשר להריץ עליהם SQL סביר: משפך לפי שלב, הכנסה מעבודות או זמני תגובה. אין היסטוריה של מעברי שלבים, כי השדה `stage` נדרס בכל שינוי, ולכן אי אפשר למדוד המרה. בנוסף אין חותמת זמן לשינוי סטטוס של עבודה. ההמלצה: טבלאות `crm_jobs` ו-`crm_stage_events` (מנורמלות, או view שמחולץ מה-JSONB), ואירועי outbox ‏`crm.stage_changed` שיזינו מחסן נתונים.

## 4. מפת דרכים לפי עדיפות

| # | פעולה | גודל | סוגר |
|---|-------|------|------|
| 1 | אימות ת.ז./ח.פ., טלפון ודוא"ל בשרת + Idempotency-Key ל-POST /customers + `409 CUSTOMER_DUPLICATE` | S | H3 |
| 2 | מחיקה/אנונימיזציה של לקוח ושל CRM, ניקוי CRM בסגירת עסק, job retention ל-mutations ול-occurrences | M | H2, L4 |
| 3 | מיזוג ברמת פריט בשרת (הרחבת `mergeCrmImport` לכל כתיבה) + טבלת גרסאות | M | H1 |
| 4 | טיוטה מקומית ל-`user_data`; מפתחות cache לפי משתמש ועסק | S | M2, M3 |
| 5 | `assigneeId` לתזכורות ולעבודות; ההתראה נשלחת לאחראי | S | M1 |
| 6 | עימוד keyset ו-`updatedSince` ל-CRM; עימוד אמיתי ל-/customers | M | M4, M7 |
| 7 | אינדקסים: ‎`documents(business_id, customer_id, created_at desc)`, ‏`phone_digits` + trgm | S | M7 |
| 8 | קישור עבודה למסמך, וסימון "תכנון" על נתוני הגבייה ב-CRM | S | M6 |
| 9 | `crm_stage_events` / view אנליטי; ייצוא CRM | M | §3, L7 |
| 10 | UUIDv7 למזהים מקומיים, `NSFileProtectionComplete`, ניקוי conflict backup | S | L1, L4, L5 |
