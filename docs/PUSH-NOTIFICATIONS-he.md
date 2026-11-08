# התראות פוש — קטלוג, הגדרות והפעלה (PUSH-001)

> מקור האמת בקוד: `packages/shared/src/push-catalogue.ts` בריפו השרת (invoiceproject, ענף `feat/push-notifications`).
> הטבלה למטה נוצרה אוטומטית מהקובץ הזה. שינוי נוסח / קישור / עדיפות נעשה שם בלבד, והאפליקציה מציגה את מסך ההגדרות לפי `GET /mobile/push/catalogue` — בלי עדכון גרסה.

## עקרונות
- **APNs ישיר, בלי Firebase.** השרת חותם JWT ‏ES256 עם מפתח ‎.p8‎ ושולח ב-HTTP/2 ל-`api.push.apple.com` / `api.sandbox.push.apple.com`.
- **לא מבקשים הרשאה בהפעלה הראשונה.** אחרי הפקת המסמך הראשון (או כשמסמך ממתין לרשות המסים) מופיע הסבר קצר ("לקבל התראות?"), ורק אז הדיאלוג של iOS. פעם אחת להתקנה. אפשר גם מהגדרות › חשבון › התראות.
- **לחיצה על התראה פותחת את הקישור** (מסלול §5) — גם מאפליקציה סגורה, גם אחרי נעילת Face ID, ובעסק הנכון (מחליפה עסק אם צריך).
- **בחזית** — ההתראה מוצגת כבאנר רגיל. **התג (badge)** מתאפס בכל חזרה לאפליקציה.
- **שעות שקט:** ‏22:00–08:00 שעון ישראל, וכל השבת והחג — ההתראה נדחית ל-08:00 ביום העבודה הבא. התראות אבטחה עוקפות. המשתמש יכול לכבות שעות שקט.
- **קטגוריית אבטחה לא ניתנת לכיבוי.**
- **ללא היסטוריה:** בהפעלה הראשונה של השרת לא נשלחות התראות על אירועי עבר.
- **התנתקות / "צא מכל המכשירים" / מחיקת חשבון** — מכבות את המכשיר בשרת מיד.

## הקטלוג
| # | סוג (kind) | מתי נשלחת (טריגר) | למי | כותרת | גוף | קישור | עדיפות | collapse | קטגוריה בהגדרות | ברירת מחדל | שעות שקט |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `ITA_ALLOCATION_APPROVED` | audit tax_authority.allocation_received (via ≠ submission: a retry/reconciliation finished) | מי שביצע את הפעולה | רשות המסים אישרה את המסמך | {docType} {docNumber} קיבל מספר הקצאה ומוכן לשליחה ללקוח | `/doc/{documentId}` | גבוהה (10) | `ita-{documentId}` | מסמכים ורשות המסים | פעילה | נדחית ל-08:00 |
| 2 | `ITA_ALLOCATION_REJECTED` | audit tax_authority.allocation_rejected (via ≠ submission) | מי שביצע את הפעולה | רשות המסים דחתה את המסמך | {docType} {docNumber} לא קיבל מספר הקצאה. כדאי לבדוק את הפרטים ולנסות שוב | `/doc/{documentId}` | גבוהה (10) | `ita-{documentId}` | מסמכים ורשות המסים | פעילה | נדחית ל-08:00 |
| 3 | `DOCUMENT_SEND_FAILED` | audit document.send_failed / document.send_expired (the e-mail worker gave up) | מי שביצע את הפעולה | המסמך לא נשלח ללקוח | שליחת {docType} {docNumber} נכשלה. אפשר לשלוח שוב מהמסמך | `/doc/{documentId}` | רגילה (5) | `send-{documentId}` | מסמכים ורשות המסים | פעילה | נדחית ל-08:00 |
| 4 | `PAYMENT_RECEIVED` | audit payment.recorded by SYSTEM/INTEGRATION or by another member (online payment, team) | בעלים + מנהלים | התקבל תשלום | {customerName} שילם/ה. הקבלה מחכה במסמך | `/doc/{documentId}` | גבוהה (10) | `pay-{paymentId}` | תשלומים | פעילה | נדחית ל-08:00 |
| 5 | `PAYMENTS_OVERDUE` | daily sweep 09:00 Israel (never Shabbat/holidays): documents that became overdue | בעלים + מנהלים | חשבוניות שעבר מועד התשלום שלהן | {count} חשבוניות עברו היום את מועד התשלום. אפשר לשלוח תזכורת ללקוחות | `/activity?chip=unpaid` | רגילה (5) | `overdue-{businessId}` | תשלומים | פעילה | נדחית ל-08:00 |
| 6 | `QUOTE_SIGNED` | audit quote.accepted_by_customer (the customer signed on the public page) | בעלים + מנהלים | הלקוח אישר את הצעת המחיר | {customerName} חתם/ה על הצעת המחיר. אפשר להפיק חשבונית | `/quote/{quoteId}` | גבוהה (10) | `quote-{quoteId}` | לקוחות | פעילה | נדחית ל-08:00 |
| 7 | `QUOTE_VIEWED` | audit quote.share_viewed (first view of a shared quote) | בעלים + מנהלים | הלקוח צפה בהצעת המחיר | {customerName} פתח/ה את הצעת המחיר | `/quote/{quoteId}` | רגילה (5) | `quote-view-{quoteId}` | לקוחות | כבויה (opt-in) | נדחית ל-08:00 |
| 8 | `TEAM_MEMBER_JOINED` | auth auth.invite_accepted (acceptInvitation) | בעלים + מנהלים | חבר צוות הצטרף | {memberName} הצטרף/ה לעסק | `/business/team` | רגילה (5) | `—` | צוות | פעילה | נדחית ל-08:00 |
| 9 | `SUBSCRIPTION_RENEWS_SOON` | App Store: subscription renewal in 3 days (enqueueAccountPush from the IAP code) | המשתמש עצמו | המנוי מתחדש בקרוב | המנוי לתבל חשבוניות יתחדש בעוד 3 ימים | `/business/account` | רגילה (5) | `sub-renew` | מנוי | פעילה | נדחית ל-08:00 |
| 10 | `SUBSCRIPTION_PAYMENT_FAILED` | App Store Server Notification DID_FAIL_TO_RENEW | המשתמש עצמו | חידוש המנוי נכשל | Apple לא הצליחה לחייב את אמצעי התשלום. כדאי לעדכן אותו כדי שהמנוי לא ייעצר | `/business/account` | גבוהה (10) | `sub-state` | מנוי | פעילה | נדחית ל-08:00 |
| 11 | `SUBSCRIPTION_EXPIRED` | App Store Server Notification EXPIRED | המשתמש עצמו | המנוי הסתיים | המנוי לתבל חשבוניות הסתיים. אפשר לחדש אותו מהאפליקציה | `/business/account` | גבוהה (10) | `sub-state` | מנוי | פעילה | נדחית ל-08:00 |
| 12 | `EXPORT_READY` | audit export.generated / export.uniform_format_generated | מי שביצע את הפעולה | הקובץ מוכן | הדוח שביקשת מוכן להורדה | `/reports` | רגילה (5) | `export-{exportId}` | דוחות וייצוא | פעילה | נדחית ל-08:00 |
| 13 | `EXPORT_FAILED` | audit export.failed | מי שביצע את הפעולה | הפקת הדוח נכשלה | לא הצלחנו להפיק את הקובץ. אפשר לנסות שוב מדוחות | `/reports` | רגילה (5) | `export-{exportId}` | דוחות וייצוא | פעילה | נדחית ל-08:00 |
| 14 | `NEW_DEVICE_LOGIN` | mobile sign-in issued a device token (issueDeviceToken) — sent to the OTHER devices | המשתמש עצמו | כניסה מטלפון חדש | נכנסו לחשבון שלך מ-{deviceName}. לא את/ה? אפשר לנתק את כל המכשירים | `/business/account` | גבוהה (10) | `—` | אבטחה | פעילה | עוקפת |
| 15 | `UPLOAD_BLOCKED` | audit expense.upload_rejected_malware (the virus scan blocked a file) | מי שביצע את הפעולה | קובץ נחסם | הקובץ "{fileName}" נחסם בסריקת האבטחה ולא נשמר | `/expenses` | רגילה (5) | `—` | אבטחה | פעילה | נדחית ל-08:00 |

**שדות:** ‏`{...}` ממולאים בשרת. "collapse" = ‏`apns-collapse-id` — התראה חדשה מאותו מפתח מחליפה את הקודמת במסך. עדיפות 10 = מיידית; 5 = רגילה (מוגבלת ל-20 בשעה למשתמש).

## מנויים (צריך חיבור מצד הבעלים)
‏`SUBSCRIPTION_RENEWS_SOON`, ‏`SUBSCRIPTION_PAYMENT_FAILED`, ‏`SUBSCRIPTION_EXPIRED` מוכנים בקטלוג ובשרת, אבל הקוד של In-App Purchase / Cardcom עדיין לא מחויב בריפו — לכן אין טריגר אוטומטי. בקוד ה-IAP קוראים ל:
```ts
await enqueueAccountPush(pool, userId, 'SUBSCRIPTION_PAYMENT_FAILED', `iap:${notificationUUID}`, { /* vars */ });
```
‏DID_FAIL_TO_RENEW → ‏`SUBSCRIPTION_PAYMENT_FAILED`; ‏EXPIRED → ‏`SUBSCRIPTION_EXPIRED`; 3 ימים לפני החידוש → ‏`SUBSCRIPTION_RENEWS_SOON`.
תשלום אונליין (Cardcom) יפעיל `PAYMENT_RECEIVED` אוטומטית אם הוא כותב אירוע ביקורת `payment.recorded`.

## API (מובייל, Bearer)
| מסלול | מה |
|---|---|
| `GET /mobile/push/catalogue` | קטגוריות + סוגים (לבניית מסך ההגדרות) |
| `POST /mobile/push/devices` | ‏`{deviceId, token, environment: sandbox\|production, locale, appVersion?}` |
| `POST /mobile/push/devices/unregister` | ‏`{deviceId}` |
| `GET` / `PUT /mobile/push/preferences` | ‏`{disabledCategories[], enabledKinds[], quietHours}` |

## שרת — איך זה עובד
1. **fan-out** קורא את `audit_events` (פונקציית definer `push_audit_feed`, עם השהיה של 2 דקות ו-cursor) ומתרגם אירועים להתראות. אירועים ישירים (כניסה ממכשיר חדש, חבר צוות הצטרף) נכנסים בתוך הטרנזקציה של הפעולה עצמה, ולא מפילים אותה אם נכשלים.
2. **outbox** — טבלת `push_notifications`, ‏idempotency לפי ‏(מפתח, מכשיר), ‏`not_before` לשעות שקט, ‏`expires_at` לפי TTL.
3. **dispatch** — נעילה ב-`SKIP LOCKED`, שליחה, ‏retry עם backoff (‏1ד׳ → 5ד׳ → 30ד׳ → 2ש׳ → 6ש׳), טוקן מת (410 / BadDeviceToken / Unregistered) → המכשיר מושבת והתור שלו נמחק.
4. **סיכום חשבוניות באיחור** — פעם ביום ב-09:00, לא בשבת/חג.

## פריסה
1. מיגרציה `0091_push_notifications.sql` (‏`pnpm db:migrate`).
2. משתני סביבה ל-container של ה-API:
```
PUSH_LOOP=1                       # ה-worker כבוי ב-compose של הייצור, לכן הלולאה רצה ב-API
APNS_TEAM_ID=ARFSXMWT96
APNS_TOPIC=space.tevel.invoice
# עכשיו (מפתח sandbox בלבד):
APNS_SANDBOX_KEY_ID=XF679C98KP
APNS_SANDBOX_KEY_PATH=/opt/tevel-invoice/secrets/apple/AuthKey_XF679C98KP.p8
# כשיהיה מפתח "Sandbox & Production" — מחליף את השניים למעלה:
# APNS_KEY_ID=<10 תווים>
# APNS_KEY_PATH=/opt/tevel-invoice/secrets/apple/AuthKey_<id>.p8
# אופציונלי: APNS_PRODUCTION_KEY_ID / APNS_PRODUCTION_KEY_PATH, APNS_ENV=sandbox,production, PUSH_INTERVAL_MS=15000
```
3. ב-compose: ‏`- /opt/tevel-invoice/secrets/apple:/opt/tevel-invoice/secrets/apple:ro` לשירות api. הקבצים: ‏root, הרשאות 600 (או קריא ל-uid של ה-container בלבד). **המפתח לעולם לא נכנס לאפליקציה או ל-git.**
4. בלי מפתח תקין — השרת רושם שגיאה בלוג וההתראות נשארות בתור (שום דבר לא נופל).

**חשוב:** בניית TestFlight/App Store מקבלת טוקן **production**. עם מפתח sandbox בלבד ההתראות יגיעו רק לבניות Xcode/סימולטור. כדי ש-TestFlight יקבל — צריך מפתח APNs מסוג "Sandbox & Production" (Apple Developer › Keys).

## אפליקציה
- תוסף מקומי `packages/tevel_push` (ערוץ `tevel/push`, ‏Swift, ‏SPM) — בלי לגעת ב-AppDelegate.
- ‏`lib/push/push_service.dart` — רישום, הרשאה, פתיחת קישור (כולל המתנה לסיום הנעילה בהפעלה קרה).
- ‏`lib/screens/profile/notification_settings_screen.dart` — מסך ההגדרות.
- ‏`ios/Runner/Runner.entitlements` — ‏`aps-environment = development`; ב-Archive ל-App Store, ‏Xcode מחליף ל-production אוטומטית.

## בדיקה בסימולטור
```
xcrun simctl push <udid> space.tevel.invoice payload.apns
```
עם `{"aps":{"alert":{"title":"…","body":"…"},"badge":1},"link":"/doc/<id>","kind":"…","businessId":"…"}`.
