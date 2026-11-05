# תבל – חשבוניות · סטטוס (2026-10-30)

> נכתב בבדיקת השחרור האחרונה. כל המספרים בטבלאות למטה הם מריצות אמיתיות מהיום, בלי הערכות.
> מקור האמת למוצר: `docs/SPEC-he.md`. חוזה ה-API: `docs/API-MOBILE.md`. ארכיטקטורה: `docs/ARCHITECTURE.md`. הגשה לחנות: `docs/APP-STORE.md`.

## 1. בשורה אחת

אפליקציית האייפון (Flutter, עברית ו-RTL מלאים) עובדת מקצה לקצה בסימולטור מול שרת פיתוח **מקומי**: כניסה (אימייל+סיסמה, קוד אימות במייל, Face ID), בית, הפקת מסמך ב-3 שלבים, שיתוף בווטסאפ, QR לתשלום, מייל, רישום תשלום, ביטול בזיכוי, לקוחות, צילום הוצאה, הגדרות ומחיקת חשבון.
**שום דבר לא נפרס לפרוד** ושום build לא הועלה ל-TestFlight או לחנות.

## 2. מה נבנה

### 2.1 מסכים באפליקציה (`lib/screens/`)

| מסך בספק | קובץ | מה יש |
|---|---|---|
| S0 פתיחה | `auth/splash_screen.dart`, `auth/app_lock.dart` | שחזור סשן מה-Keychain, Face ID / קוד מכשיר, נעילה אחרי 5 דק' ברקע, הסתרת תוכן ב-app switcher |
| S1 כניסה | `auth/login_screen.dart` | Apple (ראשון), אימייל+סיסמה, שכחתי סיסמה, קישורי פרטיות ותנאים. Google מוסתר עד שיוגדר client id |
| G1 קוד אימות | `auth/mfa_sheet.dart` | 6 ספרות, הדבקה אוטומטית, שליחה חוזרת, הרשמה ראשונה ל-MFA במייל |
| G2 בחירת עסק | `auth/business_picker_sheet.dart` | |
| S2 הקמת עסק | `auth/onboarding_screen.dart` | 2 שלבים, בדיקת ספרת ביקורת |
| S3 בית | `home/home_screen.dart` | כרטיס הכנסות, ממתינים לתשלום, צלם הוצאה / בקש תשלום, באנרים, פעילות + "הצג הכל" עם סינון וחיפוש, מטמון |
| S4 מסמך חדש | `new_document/*` | מקלדת סכום, כולל/לא כולל מע"מ (חישוב ברוטו→נטו מדויק), לקוח, "שולם כבר?", בחירת סוג מסמך אוטומטית, תצוגה מקדימה, idempotency והמשך מסמך שלא הושלם |
| S5 הצלחה | `new_document/issue_success_screen.dart` | ווטסאפ, QR, עוד (מייל / PDF / קישור) |
| S6 פרטי מסמך | `document/*` | סטטוס, שורות, סכומים, PDF, פעולות |
| G3 / G4 / S7 | `actions/*` | רישום תשלום → קבלה, ביטול → חשבונית זיכוי, QR (ממסמך או סכום חופשי), גיליון שיתוף |
| S8 לקוחות | `customers/*` | רשימה עם אינדקס א-ב, חיפוש, פרטי לקוח ויתרה, הוספה/עריכה, בורר אנשי קשר בלי הרשאה |
| S9 הגדרות | `settings/*` | פרטי עסק, קישור תשלום, תבנית ווטסאפ, Face ID, התנתקות / מכל המכשירים, מחיקת חשבון, פרטיות/תנאים/תמיכה |
| S10 צילום הוצאה | `expense/expense_capture_screen.dart` | מצלמה / גלריה / PDF → JPEG → SHA-256 → העלאה → המתנה לקליטה |

### 2.2 שינויים בשרת (`~/Projects/invoiceproject⁩`, ענף `feat/mobile-api`, 8 commits, **לא נדחף ולא נפרס**)

| commit | מה |
|---|---|
| `19031e6` | worker ששולח מיילים של מסמכים מה-outbox (B6) |
| `a3b5879` | `POST /auth/apple` (B1), `POST /auth/device-token` (B4), `GET /mobile/session`, `POST /mobile/logout`, `POST /mobile/account/delete` (B2) |
| `a33aabc` | `POST /documents/:id/share-link` + דף ציבורי `GET /d/:token`, `/d/:token/pdf` (B3); `paymentLinkUrl` בפרופיל העסק (B5); `PATCH /customers/:id`, `POST /customers/:id/archive` (B7); אכיפת עוסק פטור (B8) |
| `8f3de61` | שרת פיתוח מקומי על 3031 (`ops/run-mobile-dev.sh`) + חשבונות בדיקה (`scripts/seed-mobile-dev.ts`) |
| `69f6a15` | אבטחה: הורדת קישור שיתוף נרשמת פעם אחת, בדיקת MFA חוזרת לטוקן מכשיר, אימות מחדש למחיקת חשבון |
| `2ff0ace` | `POST /mobile/logout-all` |
| `cae6864` | ביטול ההרשאה ב-Apple כשמוחקים חשבון |
| `15a904b` | `GET /customers` מחזיר `customer_type` |

מיגרציות חדשות: `0054_account_deletion`, `0055_share_links`, `0056_business_payment_link`, `0057_mobile_security_hardening`.

## 3. תוצאות בדיקות (2026-10-30, 08:30–08:45)

### 3.1 שרת

`pnpm run ci` בתיקיית העבודה **נכשל בשלב הראשון** (`format:check`), ולכן הרצתי כל שלב בנפרד. הרצתי פעמיים: בתיקיית העבודה שלך, ובעותק נקי של הענף (git worktree זמני של `15a904b`, בלי השינויים שלך שלא נשמרו ב-commit).

| שלב | עותק נקי של הענף | תיקיית העבודה (כולל השינויים שלך) |
|---|---|---|
| `format:check` | ✗ 10 קבצים | ✗ 19 קבצים |
| `lint` | ✗ 19 שגיאות ב-3 קבצים | ✗ אותן 19 |
| `build` | ✓ | ✓ |
| `typecheck` | ✓ | ✗ 2 שגיאות |
| `test` (unit) | ✓ 283 עברו, 1 דולג (38 קבצים) | ✓ 294 עברו, 1 דולג (39 קבצים) |
| `test:regulated` (integration + גבולות + provenance) | ✓ 478 עברו, 3 expected-fail, 3 דולגו (55 קבצים) | ✗ 1 נכשל: `E2E-QUOTE-001` (יצירת הצעת מחיר בדפדפן, timeout) |
| `shaam:contract` | ✓ | ✓ |

**מאיפה הכישלונות (נבדק קובץ-קובץ):**
- `format:check` ו-`lint`: **אף קובץ לא שייך לענף** `feat/mobile-api`. הקבצים כבר נמצאים ב-`main` כך (`apps/web/src/pages/documents.tsx`, `ops/oracle/*`, `ops/shaam-callback-catcher.mjs`, `scripts/shaam-*.{ts,mjs}`, `packages/postgres/src/delivery.ts` ועוד), ובתיקיית העבודה מתווספים גם הקבצים שלך שלא נשמרו ב-commit. כל הקבצים שהענף שינה עוברים prettier.
- `typecheck`: שתי השגיאות נמצאות בקבצים שלך שלא נשמרו ב-commit: `apps/web/test/quote-design.unit.test.ts` (חסר `--jsx`) ו-`packages/shaam/test/contract.unit.test.ts` (`import.meta`).
- `E2E-QUOTE-001`: בעותק הנקי הבדיקה עוברת. הכישלון מופיע רק עם העבודה שלך על הצעות מחיר (`quotes.tsx`, `quote-design.tsx`), שלא נשמרה ב-commit.
- ⇒ כדי ש-`pnpm run ci` יעבור עד הסוף צריך `prettier --write` ותיקון eslint לקבצי `main`, וגם לסיים את עבודת הצעות המחיר. לא נגעתי בזה, כי אלה לא קבצים של הענף ובחלקם אלה השינויים שלך.

### 3.2 אפליקציה

| בדיקה | תוצאה |
|---|---|
| `flutter analyze` | ✓ No issues found |
| `flutter test` (unit + widget, 19 קבצים) | ✓ 190 עברו |

### 3.3 בדיקות אינטגרציה בסימולטור iPhone 17 (iOS 26.4) מול `http://127.0.0.1:3031`, כל קובץ בנפרד

| קובץ | בדיקות | תוצאה | זמן |
|---|---|---|---|
| `login_smoke_test.dart` | 1: כניסת עובד → בית | ✓ 1/1 | 1:07 |
| `auth_flow_test.dart` | 5: סיסמה שגויה, כניסה + טוקן ב-Keychain, הפעלה מחדש, התנתקות + ביטול טוקן, בעלים עם קוד MFA במייל | ✓ 5/5 | 0:49 |
| `issue_flow_test.dart` | 4: §12.2, §12.3, §12.6 (מסמך אחד בלבד אחרי ניתוק), §12.7 (עוסק פטור) | ✓ 4/4 | 1:19 |
| `actions_flow_test.dart` | 1: ווטסאפ (wa.me + קישור שיתוף חי), QR = קישור התשלום, מייל → SENT, ביטול → זיכוי + חסימת זיכוי כפול | ✓ 1/1 | 0:50 |
| `misc_flow_test.dart` | 2: בעלים: בית, RTL ו-overflow בגודל טקסט 1.0/2.0, לקוחות, קישור תשלום; מחיקת חשבון → אי אפשר להיכנס שוב | ✓ 2/2 | 1:55 |
| `screenshots_test.dart` | 1: מעבר על כל המסכים הראשיים + צילומים | ✓ 1/1 | 1:13 |
| **סה"כ** | **14** | **✓ 14/14** | |

לוגים: `/tmp/tevel-it-<name>.log`, `/tmp/tevel-it-screenshots.log`.

**סעיפי §12 שלא נבדקו אוטומטית:** §12.1 (זמן כניסה < 2 ש' לא נמדד), §12.4 בסימולטור נבדק ה-URL של wa.me, לא פתיחה אמיתית של ווטסאפ, §12.8 צילום הוצאה (יש בדיקות unit בלבד; ההעלאה לא נבדקה מול השרת בסימולטור), §12.10 VoiceOver (בדיקה ידנית; Dynamic Type 200% נבדק), §12.11 מצב כהה (נבדק ב-widget test, לא בסימולטור).

## 4. צילומי מסך (`docs/screenshots/`, צולמו מחדש היום מהסימולטור, חשבון העובד)

| קובץ | מסך |
|---|---|
| `01-login.png` | S1 כניסה |
| `02-home.png` | S3 בית |
| `03-new-document-amount.png` | S4 שלב 1: סכום |
| `04-new-document-customer.png` | S4 שלב 2: לקוח |
| `05-new-document-summary.png` | S4 שלב 3: סיכום |
| `06-success.png` | S5 הצלחה |
| `07-payment-qr.png` | S7 QR לתשלום |
| `08-document-detail.png` | S6 פרטי מסמך |
| `09-customers.png` | S8 לקוחות |
| `10-settings.png` | S9 הגדרות |

(`home.png` ו-`login.png` הישנים נמחקו. אותם מסכים נמצאים ב-01 וב-02.)

## 5. איך מריצים

```bash
# 1) שרת פיתוח מקומי (DB מקומי invoice_local, פורט 3031 — אף פעם לא 3001/3011/3021, אף פעם לא הפרוד)
cd ~/Projects/invoiceproject* && git checkout feat/mobile-api
ops/run-mobile-dev.sh            # build + migrate + start   (SKIP_BUILD=1 לדלג על build; "stop" לעצירה)
curl http://127.0.0.1:3031/ready
DATABASE_URL=postgresql://localhost:5432/invoice_local pnpm exec tsx scripts/seed-mobile-dev.ts   # חשבונות בדיקה (idempotent)

# 2) אפליקציה בסימולטור
cd ~/Projects/tevel-invoice-mobile
~/flutter/bin/flutter run -d "iPhone 17" --dart-define=API_BASE=http://127.0.0.1:3031

# 3) בדיקות
~/flutter/bin/flutter analyze && ~/flutter/bin/flutter test
~/flutter/bin/flutter test integration_test/<name>_test.dart -d "iPhone 17" --dart-define=API_BASE=http://127.0.0.1:3031
# צילומי מסך: הפקודה המלאה בראש integration_test/screenshots_test.dart
```

**חשבונות פיתוח** (בשרת המקומי בלבד), סיסמה לכולם: `Mobile12345678`

| אימייל | תפקיד | עסק | קוד אימות |
|---|---|---|---|
| `mobile-owner@tevel.test` | OWNER | סטודיו תבל לדוגמה (עוסק מורשה) | קוד במייל |
| `mobile-employee@tevel.test` | EMPLOYEE (הפקה + רישום תשלום) | אותו עסק | אין |
| `mobile-patur@tevel.test` | OWNER | דנה כהן – עיצוב (עוסק פטור) | קוד במייל |

קוד האימות בפיתוח: `jq -r .subject "$(ls -t ~/invoiceproject-mobile-dev-storage/outgoing-emails/*.json | head -1)" | grep -oE '^[0-9]{6}'`

**מצב כרגע:** האפליקציה רצה בסימולטור iPhone 17 ומחוברת כ-`mobile-owner@tevel.test` (אורי, סטודיו תבל לדוגמה, עוסק מורשה), על מסך הבית. היא הופעלה ברקע עם `nohup flutter run`, והלוג נכתב ל-`/tmp/tevel-mobile-run.log`. כדי לעצור: `pkill -f "flutter_tools.snapshot run"`.
בסימולטור הופעל Face ID מדומה (Features → Face ID → Enrolled). בפתיחה הבאה של האפליקציה יופיע Face ID. לאישור: Features → Face ID → Matching Face. בלי Face ID רשום, iOS מבקש את קוד המכשיר.

## 6. מה לא נעשה ומחכה לך

| # | מה | למה זה אצלך |
|---|---|---|
| 1 | **פריסת `feat/mobile-api` לפרוד** (כולל מיגרציות 0054–0057), הגדרת `APPLE_AUDIENCE=space.tevel.invoice`, וניתוב `/d/*` ב-proxy ל-API | פריסה לפרוד רק באישורך. הענף גם לא נדחף ל-GitHub |
| 2 | **Apple Developer**: הפעלת Sign in with Apple ב-App ID `space.tevel.invoice`, ויצירת רשומת אפליקציה ב-App Store Connect | דורש את החשבון שלך. צריך גם לוודא שה-Team `ARFSXMWT96` נכון |
| 3 | **Google**: מזהה לקוח iOS (`GOOGLE_IOS_CLIENT_ID`) + reversed client id ב-Info.plist | בלי זה הכפתור מוסתר. דורש Firebase/Google Cloud |
| 4 | **דפי פרטיות ותנאים** ב-tevel.space: פרטיות חי ב-`/legal/privacy`; תנאי השימוש (`/legal/tevel-invoice`) מסומנים "טיוטה". `tevel.space/privacy` ו-`/support` מחזירים 404 | תוכן משפטי ופריסת האתר |
| 5 | **חשבון הדגמה לבודקי אפל בפרוד** (D4): משתמש ועסק "חשבון הדגמה – App Review", עם נתוני דוגמה ו-MFA קבוע או כבוי | נוצר בפרוד |
| 6 | **הפעלת SHAAM בפרוד** (`SHAAM_ENABLED=0` כרגע). עד אז אין מספרי הקצאה בפרוד | onboarding ייצור מול רשות המסים |
| 7 | **קישורי PayMe דינמיים** (V1.1): היום ה-QR הוא קישור התשלום הקבוע של העסק | seller id של PayMe עוד פתוח |
| 8 | בדיקה **במכשיר אמיתי**: כניסה עם Apple ID אמיתי, Face ID, פתיחה אמיתית של ווטסאפ, מצלמה | נבדק רק בסימולטור ובבדיקות unit (Apple: JWKS מדומה) |
| 9 | build להפצה (TestFlight/App Store) | לא מעלים בלי אישורך המפורש |

## 7. בעיות פתוחות ידועות (בכנות)

1. **`pnpm run ci` לא ירוק** בגלל `format:check`/`lint` על קבצים שכבר נמצאים ב-`main`, ובגלל העבודה שלך על הצעות מחיר שלא נשמרה ב-commit (פירוט ב-§3.1). כל שאר השלבים ירוקים בענף נקי.
2. **כרטיס "הכנסות החודש" סופר גם קבלות וחשבוניות זיכוי** (חישוב `/dashboard` בשרת; `API-MOBILE.md` §10.2). המספר בבית לא מדויק חשבונאית.
3. **אין endpoint לביטול קישור שיתוף**. הקישור פג אחרי 30 יום.
4. **נושא המייל של מסמך באנגלית** (`"TAX_INVOICE 3"`).
5. **Apple Sign-In** אומת רק בבדיקות unit עם JWKS מדומה, לא מול Apple אמיתי.
6. **שרת הפיתוח על 3031 נבנה מתיקיית העבודה**, כלומר כולל גם את השינויים שלך שלא נשמרו ב-commit (`packages/shaam/src/*`, `quotes.ts`). זה לא משפיע על זרימות המובייל, אבל זה לא build נקי של הענף.
7. **התקנה מחדש מוחקת את הסשן** (בכוונה: טוקן מהתקנה קודמת מבוטל). לכן `flutter test` על המכשיר, שמסיר את האפליקציה בסוף, מנתק את המשתמש.
8. **צילום הוצאה מול השרת לא נבדק בסימולטור** (רק בבדיקות unit), והשרת המקומי לא סורק וירוסים.
9. ב-`API-MOBILE.md` §5/§10 עדיין כתוב "אין logout-all ל-bearer". זה כבר לא נכון: `POST /mobile/logout-all` נוסף ב-`2ff0ace`.
10. כפתור ה-"+" הצף מכסה חלקית את השורה השנייה ברשימת הפעילות במסך הבית (נראה ב-`02-home.png`). השורה עדיין לחיצה, אבל השורה המשנית שלה (סוג ומספר המסמך) מוסתרת בחלקה עד שגוללים.
11. תיקון קטן ב-`customers_screen.dart` (בדיקת "החלפת עסק באמצע טעינה" אחרי await) נמצא בעץ בלי commit. כל הבדיקות עברו איתו, ולכן נשמר ב-commit נפרד.
