# תוכנית צוות – 10 סוכנים מתקנים את ממצאי ה-QA (12.11.2026)

מקור הממצאים: `00-ACTION-PLAN-he.md` ודוחות 01–07 בתיקייה הזו. המזהים (0.x, 1.x, 2.x, 3.x) מתייחסים לתוכנית הפעולה.

**מחוץ לתחום (לא נוגעים):**
- **סליקה**, שתיכנס בהמשך: Cardcom, קישור תשלום / QR לתשלום, checkout של לקוחות, `cardcom_merchant_screen`, `commerce`/`merchant-payments` בשרת, R2.
- **שלב 4**, כלומר פיצ'רים חדשים מדוח 05.
- רכישת מנוי (IAP) נשארת כמו שהיא, חוץ ממעבר `launchUrl` דרך ה-allow-list.

## בסיס
- **אפליקציה:** branch `qa/base-2026-11-12` (commit 156f4f8 + התוכנית הזו). זה snapshot של כל ה-WIP שלא עבר commit.
- **שרת:** `origin/main` = b6c6fe3 במאגר `~/Projects/invoiceproject⁩`, ששמו מסתיים בתו הנסתר U+2069 (להשתמש ב-glob `~/Projects/invoiceproject*`).
  - ה-checkout הראשי של המאגר הזה מכיל WIP ישן של המשתמש ומריץ את שרת הפיתוח :3031. **לא נוגעים בו.**

## כללי עבודה לכל סוכן
1. **עבודה ב-worktree משלך בלבד:**
   - אפליקציה: `git -C ~/Projects/tevel-invoice-mobile worktree add ~/Projects/tim-wt/<id> -b qa/<id> qa/base-2026-11-12`, ואחר כך `flutter pub get`.
   - שרת: `git -C <repo> worktree add ~/Projects/inv-wt/<id> -b qa/<id> b6c6fe3`, ואחר כך `pnpm install`.
2. **בעלות על קבצים:** עורכים רק את הקבצים שבאחריותך (ראו הטבלה למטה). אם חייבים לגעת בקובץ של סוכן אחר, השינוי צריך להיות מינימלי, ומדווחים עליו ב-`foreign_files`.
3. **Labels:** כל סוכן מוסיף מחרוזות רק לקובץ ה-labels של התחום שלו. לא עורכים את `common_he.dart`.
4. **בדיקות:**
   - לכל תיקון לוגי צריך בדיקה אחת שנכשלת בלי התיקון: widget test, unit test או int test.
   - לפני commit: `flutter analyze` נקי, ו-`flutter test` לקבצים שנגעת בהם.
   - בשרת: typecheck, ובדיקות היחידה והאינטגרציה הרלוונטיות.
5. **בלי `dart format` גורף.** הסוכן המאחד (A10) מפרמט בסוף. מותר לפרמט רק קבצים שנגעת בהם.
6. **אסור:**
   - push, deploy, או נגיעה ב-production.
   - שינוי ב-DB `invoice_local` או בשרת :3031.
   - שימוש בסימולטור. רק A9 ו-A10 משתמשים בו.
   - בדיקות שרת רצות על DB משלך (`createdb invoice_qa_<id>`).
7. **Commit:** commits קטנים על `qa/<id>`, עם שורת `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
   - בסיום כותבים `docs/qa-2026-11-12/fixes/<id>.md` בעברית, עם רשימה של מה תוקן, מה לא תוקן ולמה, ואילו בדיקות נוספו.

## חלוקה

### A1 – Composer (הפקת מסמך)
- **בעלות:** `lib/screens/compose/**` (כולל `fields/customer_chip.dart`), `lib/ui/widgets/keypad.dart`, `lib/util/labels/compose_he.dart`, `lib/api/compose_memory.dart` (או המקום שבו נמצא `/tax-rates`), ו-tests של compose.
- **משימות:**
  - 0.2: X קבוע, ו"לשמור טיוטה?" אם יש סכום. בלי הלולאה שבין "ממי?" למסך הסכום.
  - 0.3: פריסה קבועה במסך הסכום, וחסימת ההפקה 400ms אחרי שינוי layout.
  - 0.4: מפתחות יציבים לשורות ב-`s3_more`.
  - 0.5: שורת מע״מ בסדר נכון, עם `ltrIsolate`.
  - 0.1 בקבצים שלך: נקודה עשרונית ב-keypad, ובלי `052-0000111` ב-customer_chip.
  - 1.3: כשל שיתוף אחרי הפקה יוצג כ"הופק, השיתוף נכשל" וייפתח המסמך. ההצעה תסומן "נשלחה" רק אם נשלחה. לתפוס `Object`.
  - ולידציית הנחה: הנחה גדולה מהשורה הראשית חסומה.
  - busy-guard ל-`_saveItem`.
  - 2.3: `/tax-rates` מה-cache.
  - כרטיסי בית שפותחים composer: UNFINISHED בלי `draftId` לא יפתח composer ריק. QUOTE_ACCEPTED לא ימיר בשרת לפני אישור המשתמש. רק הצד של ה-composer.
  - טיוטה מקומית: להציג "המשך טיוטה" במקום שחזור שקט.
- **לא שלך:** `openIssuedDocument`, כלומר המסך שמוצג אחרי ההפקה, שייך ל-A2. תמשיך לקרוא לו כמו היום.

### A2 – מסך מסמך ושיתוף
- **בעלות:** `lib/screens/document/**`, `lib/util/labels/document_he.dart`, `status_he.dart`, ו-tests של document.
- **משימות:**
  - 1.1: כפתור ראשי לפי סטטוס: טיוטה → הפק. הופק → שלח. נשלח וממתין → "קיבלתי תשלום" + "תזכורת".
  - 1.2:
    - כשהמסמך נפתח מיד אחרי הפקה, מציגים מצב הצלחה ("חשבונית 710 הופקה") עם WhatsApp, העתק קישור ו"עוד".
    - גיליון השיתוף: 3 פעולות ראשיות + "עוד", בלי למחוק אפשרויות.
    - פריט Cardcom נשאר כמו שהוא, בלי שינוי בלוגיקת סליקה.
  - 0.6: `_vatRate` מהשרת.
  - `mounted` לפני `_guard`.
  - `s8_cancel`: לתפוס `Object`.
  - "עבור ללקוח" מהמסמך.
  - document cache-first, מדוח 02.
- **הערה:** מסך "תשלום מאובטח" שנדחף אחרי הפקה ב-debug הוא דמו של סליקה. לא נוגעים בו, אבל מוודאים שהוא לא מופיע ב-release.

### A3 – בית, מעטפת וניווט
- **בעלות:** `lib/screens/home/**`, `lib/app_shell.dart`, `lib/router.dart`, `lib/ui/widgets/**` (חוץ מ-keypad), `lib/util/labels/inbox_he.dart`.
- **משימות:**
  - 0.1 בבית: סכום באיחור, ו-`isDark` שמשנה תוכן ב-`home_screen`.
  - 0.8: "באיחור" יפתח רשימה עם תצוגה מקדימה ואישור לפני שליחה. בלי מייל המוני.
  - 1.4: להסיר את בקשת אנשי הקשר מכניסה לבית.
  - 1.5: שם אחד, "מסמכים", בכפתור הבית ובכותרת. FAB "+ חשבונית" בכל הלשוניות.
  - 1.6: padding תחתון בגובה סרגל הניווט בכל רשימה, דרך widget משותף.
  - 1.7: שורת מסמך עם מספר, סוג מלא, סטטוס אחד, וראשי תיבות במקום תמונת stock.
  - 1.8: שם העסק והתפקיד גלויים בבית.
  - 1.11: deep link או התראה למסך לא מורשה מציגים הודעה. `go()` סוגר composer או dialog פתוח לפני ניווט. התראה כשהאפליקציה פתוחה ניתנת ללחיצה.
  - 1.12: `/gate` רק כשלא מחוברים. החלפת עסק מקישור חיצוני דורשת אישור.
  - AT-92 ב-`doc_rows.dart`.
- **ממשק:** כותרת מסך "פעילות" מוחלפת ל"מסמכים" על ידי A4 (מסך ה-activity). אתה רק בבית ובסרגל.

### A4 – ניהול, פרופיל, הגדרות, רשימת מסמכים
- **בעלות:** `lib/screens/business/**` (ב-`cardcom_merchant_screen.dart` רק העברת label של AT-92), `lib/screens/profile/**`, `lib/screens/activity/**`, `lib/screens/billing/**` (רק AT-92 ו-launchUrl), `lib/screens/reports/**`, `lib/util/labels/business_he.dart`, `payment_he.dart`.
- **משימות:**
  - 0.7: לשונית "פרופיל" מציגה טופס פרטי עסק רק ל-`settingsBusiness`. לאחרים: פרופיל אישי, וכפתור "מסלול" רק למי שמורשה.
  - 1.5: מסך ניהול בלי כפילויות בין הפעולות המהירות לרשימה. "עיצוב מסמכים" ו"מיתוג" מאוחדים.
  - `business_template` `isDark`.
  - 1.10: "לצאת בלי לשמור?" ב-S13 ובמיתוג.
  - `team_page`: busy guards, ו-`ltrIsolate` לאימייל.
  - 2.5: `ListView.builder` + paging + decode ב-isolate ב-activity. כותרת "מסמכים". סינון לפי סוג ותאריך.
  - billing: `launchUrl` דרך `launchAllowed`.
  - AT-92: billing ו-cardcom (label בלבד).
  - דוחות: לא נוגעים בלוגיקה.

### A5 – אנשים ו-CRM (UI)
- **בעלות:** `lib/screens/people/**`, `lib/state/contacts_permission.dart`, `lib/util/labels/people_he.dart`, `customer_crm_he.dart`.
- **משימות:**
  - 0.1: בלי `052-0000111` ב-`people_screen` וב-`s2_customer`. `person_screen` בלי `isDark` שמשנה תוכן.
  - 1.4: בקשת הרשאה לאנשי קשר רק בלחיצה על "ייבוא". AT-92 ב-`contacts_permission`.
  - 1.9: כרטיס לקוח:
    - "חשבונית חדשה ללקוח" (דרך `openCompose` הקיים) ו"קיבלתי תשלום".
    - לשונית "כסף" מציגה יתרה מהמסמכים, ושדה ידני מסומן כהערכה.
    - בלי "רענון" ובלי חיווי שמירה כפול.
    - סטטוס ברירת מחדל הגיוני ללקוח עם מסמכים.
  - `customer_crm_jobs`: `'edit'` כפול.
  - `finance_card`: חיצים נכונים ב-RTL.
  - `agenda`: עבודות שעבר זמנן ולא נסגרו מוצגות גם בסינון היום/השבוע.
  - `person_screen`: `catchError` / try.
  - 1.10 ב-S2 ובדיאלוגים של CRM.

### A6 – שכבת נתונים באפליקציה (state/api/auth)
- **בעלות:** `lib/state/**` (חוץ מ-`contacts_permission`), `lib/api/**` (חוץ מ-`compose_memory` / tax-rates אם שייכים ל-A1), `lib/util/errors_he.dart`, `lib/util/allowed_urls.dart`, `lib/screens/auth/**`, `lib/main.dart` (חוץ מהשורות ש-A9 צריך ל-harness; לתאם דרך הדיווח).
- **משימות:**
  - CRM store:
    - רענון ב-resume בלי איפוס state.
    - poison queue: 4xx (חוץ מ-409 ו-429) עובר לקובץ backup, עם הודעה למשתמש.
    - parse סלחני: פריט פגום עובר להסגר.
    - כתיבת `migratedToUser`.
  - session:
    - 401 ב-`refreshBusiness` בזמן restore.
    - `on Object` ב-restore.
    - מחיקת טוקן push לפני logout.
  - 3.8: טיוטות ב-Application Support. מפתח cache לפי user+business, עם מיגרציה שקטה.
  - 3.6: `errors_he` מציג את הודעת השרת העברית כשאין מיפוי, ומוסיף את 18 הקודים החסרים מדוח 04.
  - `supabase_auth`: מיפוי מדויק של 400/422.
  - 2.1: פתיחה מה-cache, כלומר בית מיד ורענון ברקע.
  - 2.2: שרשרת ההפקה ב-`issue_api`: cache ל-`/sequences` והסרת GET כפולים, בלי לשנות את הסמנטיקה של ההפקה ובלי לגעת ב-idempotency.
  - `client.dart`: `FormatException` של `API_BASE` עוטפים ב-`ApiException`.
  - 0.1 ב-`main.dart`: לא משנים את `ThemeMode`, רק מוודאים שאין תלות בתוכן.
  - push ל-role בלי MFA: הודעה ברורה ב-`system_notices`.

### A7 – שרת: לקוחות ונתונים
- **בעלות:** בשרת, `packages/postgres/src/customers*`, `customer-crm*`, migrations חדשות (מספור מהבא הפנוי ב-b6c6fe3), `apps/api/src/routes/v2/customers.ts`, `customer-crm.ts`, והמחיקה ב-`delete_user_account`.
- **משימות:**
  - 3.1:
    - ולידציית ח.פ./ת.ז. (ספרת ביקורת) וטלפון.
    - Idempotency-Key ב-`POST /customers`.
    - `409 CUSTOMER_DUPLICATE` לח.פ. קיים באותו עסק.
    - unique index חלקי רק אם לא שובר נתונים קיימים. אחרת דוח כפילויות + script.
  - 2.4: `GET /customers` עם JOIN מצטבר במקום 5 subqueries לכל שורה, ו-paging.
  - 3.9: אינדקסים: `documents(customer_id, created_at)`, וחיפוש לפי טלפון וח.פ.
  - 3.2:
    - merge לפי פריט ב-CRM, כדי ששני משתמשים שעורכים חלקים שונים לא יקבלו CONFLICT.
    - שמירת גרסה קודמת בטבלת היסטוריה.
  - 3.3:
    - API למחיקת לקוח, כולל CRM ו-PII שאינו חשבונאי.
    - retention ל-`customer_crm_mutations` ול-notice_occurrences.
    - `delete_user_account` מנקה PII שאינו חשבונאי.
  - M1: push של CRM לאחראי, אם זה זול.
- **תאימות:** אם משנים חוזה API, זה חייב להיות תואם לאחור לאפליקציה הקיימת. תעד כל שינוי חוזה ב-`fixes/A7.md`.

### A8 – שרת: אינטגרציות וביצועים + מסך הוצאות
- **בעלות:** בשרת, `apps/api/src/routes/v2/dispatch.ts`, קוד OCR/claude-vision, notifications/SMTP, `auth-routes.ts` (timeouts בלבד), APNs, gzip/ETag ב-`app.ts`/`http.ts`, ותבנית ה-PDF (ז'רגון `renderer`). באפליקציה, `lib/screens/expense/**` ב-worktree אפליקציה נפרד בשם `A8-app`.
- **משימות:**
  - 3.4: כשל ודאי ב-WhatsApp → FAILED ולא UNKNOWN, עם בדיקה.
  - 3.5:
    - OCR עם timeout של 30s ו-retries=1.
    - כשל לא גורם לקריאה חוזרת בכל פתיחה. בשרת וגם באפליקציה (`expenses_screen.dart:61,246`).
    - חובת `EXPENSE_AI_MODEL` ב-production-config, או ברירת מחדל זולה.
    - הודעת הסכמה לפני שליחת תמונה.
  - SMTP ו-JWKS: timeouts מפורשים.
  - APNs: שימוש חוזר ב-connection.
  - 2.4: gzip + ETag לתגובות JSON.
  - ה-PDF ללקוח בלי `template ... renderer r4.2`.
  - שיתוף אחד במקום שניים ב-issue+WhatsApp, אם זה בצד השרת.
- **לא:** Cardcom, checkout, קישור תשלום.

### A9 – בדיקות, E2E ו-native
- **בעלות:** `integration_test/**`, `test/golden/**`, `test/business/team_test.dart`, `test/spec_lint_test.dart` (רק אם צריך), `ios/TevelActivity/**`, `docs/TEST-LOGIN-he.md`. ב-`lib/main.dart` רק מה שה-harness מחייב, מינימלי ומדווח.
- **משימות:**
  - 0.9: להחזיר את 6 סוויטות `v2_qa-*` לירוק בסימולטור (iPhone 17 Pro, `EF82558D-7B24-4BDD-8B96-DA66170CF700`) מול :3031.
    - השורש: `app.main()` נקרא פעמיים, עם GlobalKeys כפולים ו-`NotchNoticeHost`.
    - עדיף לתקן ב-harness. אם האפליקציה צריכה תיקון אמיתי (למשל dispose לא תקין ב-`NotchNoticeHost`), לתקן אותו.
  - J8: `scrollUntilVisible`.
  - goldens של intent_button: רק אחרי שמוודאים שזה שינוי עיצוב מכוון.
  - Swift: `case "reminder"` כפול.
  - לעדכן את `TEST-LOGIN-he.md`, כי test@test.com הוא OWNER.
- **הערה:** הבדיקות שלך רצות על קוד ה-base. אחרי האיחוד, A10 מריץ אותן שוב.

### A10 – מאחד, QA ראשי ובודק סופי
מתחיל אחרי שכל A1–A9 סיימו.

**אפליקציה:**
- יוצר `qa/integration-2026-11-12` מ-base וממזג את `qa/A1`…`qa/A9` ו-`qa/A8-app`, עם פתרון קונפליקטים.
- מריץ `dart format lib test integration_test`, ואחר כך `flutter analyze` ו-`flutter test` (כולם ירוקים).
- מריץ את 6 סוויטות ה-E2E בסימולטור.
- עושה מעבר חי בסימולטור על המסלולים מדוח 07: הפקה עם אגורות, יציאה מה-composer, מסמך לפי סטטוס, כרטיס לקוח, ניהול ופרופיל לפי תפקיד.

**שרת:**
- יוצר `qa/integration-2026-11-12` מ-b6c6fe3 וממזג את A7 ו-A8.
- מריץ typecheck ו-unit, ו-int על DB משלו.

**סיכום:**
- מתקן שבירות אינטגרציה בעצמו.
- כותב `docs/qa-2026-11-12/09-FINAL-REPORT-he.md`: מה תוקן, מה לא ולמה, תוצאות בדיקות, ומה נדרש מהמשתמש.
- לא עושה push.
