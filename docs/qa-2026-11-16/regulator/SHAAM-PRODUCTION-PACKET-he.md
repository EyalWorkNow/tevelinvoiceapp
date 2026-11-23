# חבילת הגשה: מעבר של "חשבוניות ישראל" (שע"ם) לייצור

> הוכן ב-2026-11-16 (Stage B). **מסמך בלבד: לא שונה קוד, לא נשלח מייל ולא נגעו בפורטל.**
> המקור הוא ריפו השרת `~/Projects/invoiceproject⁩` ב-`origin/main` = `ae9a672` (2026-11-16 04:17). הקבצים שנקראו: `docs/shaam/*`, `docs/operations/PATH-TO-PRODUCTION-2026-11-he.md`, `ops/oracle/*`, `packages/shaam/src/config.ts` ו-`SHAAM-ONBOARDING-CHECKLIST.md`.
> המקרא: ✅ אומת היום · 📁 לפי הריפו (לא אומת מול הרשות היום) · ⚠️ לא מאומת או סותר · ⛔ חוסם.

---

## 0. השורה התחתונה

1. הקוד מוכן. הבדיקות מול ה-sandbox עברו ב-26.10 ("ALL GATES PASS": אושרה הקצאה של 9 ספרות, וקוד 432 הוחזר ל-VAT שגוי). מאז 1.11 ה-sandbox מחזיר `401 invalid_token` לכל קריאה, והריפו לא מתעד שום פתרון. **השאלה עדיין רלוונטית** (§4).
2. כדי לעבור לייצור, בעל בית התוכנה (את/ה) צריך/ה לבצע את **נוהל חיבור בית תוכנה**: רישום תאגיד והרשאה, חתימה על כתב התחייבות ועל נספח אבטחת מידע, בקשה דיגיטלית, ארגון ואפליקציה בפורטל הייצור והרשמה למוצר Invoices. שום דבר מזה לא מתועד בריפו כאילו בוצע.
3. ⛔ **חוסם הנדסי שנמצא היום.** ה-redirect URI שצריך לרשום בפורטל הוא `https://invoice.crm.tevel.space/shaam/callback`, ובייצור הוא מחזיר **HTTP 404**. גם `/app/` מחזיר 404, כלומר השרת ב-Oracle לא מגיש את ה-SPA. לפני ש-OAuth בייצור יעבוד צריך תיקון: כלל Caddy או הגשת `WEB_DIST`. ראו §2.3.
4. ⚠️ ב-`docs/shaam/SHAAM-PRODUCTION-ONBOARDING.md` עדיין רשומה כתובת ה-Vercel הישנה (`invoice-web-rose-rho.vercel.app`). היום היא מחזירה **HTTP 500**. **אסור לרשום אותה.**

---

## 1. רשימת פעולות לבעלים, לפי הסדר

| # | פעולה | איפה | מה כבר מוכן או ידוע | סטטוס |
|---|---|---|---|---|
| 1 | רישום אישי לאזור האישי ברשות המסים (ת"ז + OTP) | `https://secapp.taxes.gov.il/srRishum/main/openPage` 📁 | — | פתוח, אלא אם כבר נעשה. כניסה ל-sandbox הצליחה ב-10.2026, ולכן כנראה קיים |
| 2 | הרשאה דיגיטלית ("מתן הרשאה לרישום בית התוכנה"). בית התוכנה הוא **עוסק יחיד** (325128361). אם את/ה גם מגיש/ה את הבקשה וגם יוצר/ת את ה-ORGANIZATION בפורטל, **לא צריך הרשאה נפרדת ולא צריך רישום תאגיד**. ההרשאה נדרשת רק אם מישהו אחר פועל מטעמך | האזור האישי ברשות המסים | נוהל 11.1.24 §1 ✅: "אם בעל בית התוכנה … הוא המשתמש עצמו אין צורך במתן הרשאה נפרדת" | כנראה לא נדרש |
| 3 | חשבון בפורטל המפתחים ב-**SANDBOX** וב-**PRODUCTION** | `https://openapi-portal.taxes.gov.il/sandbox` ו-`https://openapi-portal.taxes.gov.il/shaam/production` | ארגון ואפליקציה ב-sandbox קיימים (הריצה של 26.10). לפי מדריך הרשות, רק מי שרשום ב-sandbox מאושר לייצור | sandbox ✅ (לפי הריפו); ייצור פתוח |
| 4 | למלא ולחתום על **כתב התחייבות לשימוש בשירותי API** ועל **נספח אבטחת מידע לבתי תוכנה**: חתימה במקומות הנדרשים **וראשי תיבות בכל עמוד** | הטפסים בדף "קישור לשע"ם" ב-gov.il, וגם בפורטל | נוהל 11.1.24 §3 ✅. ה-ADMIN שנקוב במסמכים חייב להיות **אותו אדם** שייצור את ה-ORGANIZATION בפורטל | פתוח |
| 5 | **הגשת בקשה דיגיטלית** לרישום בית תוכנה לשירותי API, עם המסמכים הסרוקים מ-4 | `https://secapp.taxes.gov.il/mm-rishum-tochna/confirm-api/init-id-av` ✅ | ראו טבלת הערכים ב-§2.1 | פתוח |
| 6 | המתנה למייל אישור, בנוסח "בקשה מס' N לרישום בית תוכנה <ח.פ> אושרה; מנהל פיתוח … הוגדר לפורטל המפתחים" | — | דוגמה במצגת הרשות ✅ | ממתין לרשות |
| 7 | בפורטל הייצור: Create New Organization (שם "קבוצת הפיתוח"), ואחר כך Create New App | פורטל הייצור | שם האפליקציה: `Tevel Invoice`. ה-Redirect מופיע ב-§2.2 | פתוח |
| 8 | רישום האפליקציה למוצר **Invoices** (Approval v2, Invoice-decision v1, invoice-information v2, general-information v2) | פורטל הייצור → Taxes API Product → Subscribe | בלי זה מתקבל 403 | פתוח |
| 9 | העתקה **מדף האפליקציה בפורטל**: Client ID, Client Secret (מוצג פעם אחת בלבד), כתובות authorize/token/API base, ו-scope | פורטל הייצור | **לא לוקחים מה-PDF של 2024** (RTAC-3) | פתוח |
| 10 | העברת הערכים אלינו בערוץ מאובטח (§5) | — | — | פתוח |
| 11 | מספר רישום תוכנה (שדה 1006): **מסלול נפרד**, ראו `BKMV-REGISTRATION-PACKET-he.md`. בייצור הקוד מסרב ל-`99999999` | — | — | ⛔ תלוי במסלול 2 ⚠️ (ראו הערה) |
| 12 | לכל עסק פיילוט: בעל העסק נותן הרשאה ומתחבר ב-OAuth עם זהות שמורשית למספר העוסק (אחרת 406) | האזור האישי של בעל העסק | — | פתוח |

> ⚠️ **הערה לשורה 11.** לפי המסמך הרשמי S7 (טבלה 2.1, כפי שמצוטט בריפו), אפשר להשתמש בח.פ של המנפיק עד שמוקצה מספר רישום. הקוד בייצור (`config.ts`) מסרב רק לערך `99999999`. האפשרות להפעיל ייצור לפני שמספר הרישום מגיע תלויה לכן בפרשנות הזו. **שאלה זו כלולה במייל ב-§4.**

---

## 2. ערכים מוכנים מהריפו ומהשרת

### 2.1 זהות התוכנה ובית התוכנה (לבקשה הדיגיטלית)

| שדה | ערך | מקור |
|---|---|---|
| שם התוכנה | **תבל** (באנגלית: Tevel) | `scripts/build-registration-evidence.ts` ב-origin/main (rc6, ערכים שאושרו ע"י הבעלים 21.10). ⚠️ קורפוס rc4 הישן נושא `Tevel` |
| גרסה | **מהדורה 1** (Edition 1). גרסת השרת `0.1.0`, ובייצור רץ commit `86bd84e` (`/version`, נבדק היום ✅) | `package.json`, `/version` |
| שם בית התוכנה | **עטייה אייל - תבל** | שדה 1010 ב-rc6 (`build-registration-evidence.ts`). ☐ לאשר שזה בדיוק השם הרשום ברשות המסים |
| מספר עוסק של בית התוכנה | **325128361** (עוסק יחיד, לא תאגיד) | שדות 1003 ו-1009 ב-rc6. ⚠️ ב-rc4 הישן מופיע `111111118` הסינתטי |
| אנשי קשר: ADMIN, טכני ואבטחה | ☐ את/ה. האדם שנקוב כ-ADMIN חייב להיות זה שיוצר את ה-ORGANIZATION | נוהל + מצגת ✅ |
| מספר רישום תוכנה (1006) | עוד לא הוקצה. היום `SHAAM_ACCOUNTING_SOFTWARE_NUMBER=99999999` ב-`shaam.env` המקומי (sandbox) | `~/invoiceproject-storage/shaam.env` |

### 2.2 הגדרות האפליקציה בפורטל הייצור

| הגדרה | ערך | הערה |
|---|---|---|
| App name | `Tevel Invoice` | כמו ב-sandbox |
| **OAuth Redirect URI (ייצור)** | `https://invoice.crm.tevel.space/shaam/callback` | זה `${APP_ORIGIN}/shaam/callback`. בייצור `APP_ORIGIN=https://invoice.crm.tevel.space` (`oracle-invoice.env`). הקוד מסרב ל-redirect שה-origin שלו שונה מ-`APP_ORIGIN`. ⛔ היום מחזיר 404 (§2.3) |
| Redirect נוסף (רק אם מתבקש, ל-sandbox או לפיתוח) | `http://localhost:3001/shaam/callback` | הערך הרשום היום ב-sandbox (`SHAAM_SANDBOX_REDIRECT_URI`). ⚠️ פורטל הייצור כנראה לא יקבל http. לא רושמים אותו בייצור |
| Grant | Authorization Code. אימות הלקוח ב-HTTP Basic מול ה-token endpoint, **בלי PKCE**. ה-refresh token חד-פעמי ומתחלף | `packages/shaam/src/oauth.ts` |
| Scope | ב-sandbox: `scope`. הפורטל מציג גם `invoices_scope`. בייצור **אין ברירת מחדל**, ולכן מעתיקים את הערך מהפורטל | RTAC-4 |
| מוצרים | Invoices/v2/Approval · Invoice-decision/v1 (Cancel/Continue/FurtherObjection) · invoice-information/v2/confirmationNumber · general-information/v2/MinimumAmount | `client.ts` |
| כתובות IP | שרת הייצור: Oracle VM, ירושלים, `84.13.76.47` (DNS של `invoice.crm.tevel.space`, נבדק היום ✅) | ⚠️ בנוהל, במצגת ובמדריך **לא מצאנו דרישה** ל-whitelist של IP. ממלאים רק אם הטופס מבקש. לא אומת שזו כתובת היציאה (egress) של השרת |
| Callback / Webhook | אין. השירות סינכרוני, ואין callback מהרשות מלבד ה-OAuth redirect | `SHAAM-PRODUCTION-ONBOARDING.md` §4 |

### 2.3 ⛔ תיקון שנדרש לפני רישום ה-redirect (משימה הנדסית, לא בוצעה כאן)

- נבדק ב-2026-11-16: `curl -sI https://invoice.crm.tevel.space/shaam/callback?state=x` מחזיר **HTTP/2 404**. גם `/app/` ו-`/` מחזירים 404.
- הקוד (`apps/api/src/static.ts`) עונה על `/shaam/callback` ב-302 ל-`/app/#/shaam/callback?...` **רק כש-`WEB_DIST` מוגדר וה-SPA מוגש**. בייצור ב-Oracle זה לא קורה.
- מה הבעלים מחליט: איפה יושב ה-SPA של הדפדפן בייצור (Caddy, ‏`WEB_DIST` בקונטיינר, או דומיין web נפרד). את/ה צריך/ה ללחוץ על "התחבר לרשות המסים" מדפדפן עם session על אותו origin.
- הבדיקה אחרי התיקון: הפקודה למעלה צריכה להחזיר `location: /app/#/shaam/callback?state=x`.
- עוד דבר שחוסם בצד שלנו: `ops/oracle/rollout-v2.sh` (שורה 195) **מכשיל** פריסה אם `SHAAM_ENABLED≠0`. צריך לשנות את השער הזה כשמפעילים את SHAAM.

---

## 3. איך מגישים

לפי נוהל 11.1.24 ✅, **אין מייל הגשה**. ההגשה היא הטופס הדיגיטלי בשלב 5 עם המסמכים הסרוקים. המייל ב-§4 נועד **לשאלות** (401 ופרשנויות) ולמעקב.

- שאלות על תהליך הרישום: **lakohot-bt@taxes.gov.il** ✅
- שאלות תפעוליות או טכניות: **APIsupport@taxes.gov.il**, טלפון **02-5688444**, ימים א'–ה', 8:00–17:00 ✅
- זהות, token ופורטל: OPENAPI@TAXES.GOV.IL ו-ITAOpenApiSupport@taxes.gov.il 📁 (מתועד בריפו, לא אומת היום)

---

## 4. טיוטות מייל מוכנות לשליחה

### 4א. ל-APIsupport@taxes.gov.il, עותק ל-openapi@taxes.gov.il: תקלת 401 ב-sandbox

> **השאלה עדיין רלוונטית.** בריפו אין שום תיעוד שה-401 נפתר: אין commit ל-`packages/shaam` או ל-`docs/shaam` שעוסק בזה אחרי 2.11. לפני השליחה מומלץ להריץ שוב את בדיקת `Invoices/v2/health` (§"Probes" ב-`SANDBOX-401-2026-11-01.md`). אם התקלה כבר נעלמה, מוחקים את חלק א'.

```
נושא: Sandbox חשבוניות ישראל – 401 invalid_token מאז 1.11.2026 + שאלות לקראת מעבר לייצור (Tevel)

שלום רב,

אנו בית התוכנה "עטייה אייל - תבל", עוסק מס' 325128361, מפתחים את התוכנה "תבל" (Tevel, מהדורה 1) המחוברת לשירותי
"חשבוניות ישראל". אפליקציית ה-sandbox שלנו "Tevel Invoice" (Client ID יימסר לפי בקשה) עברה בהצלחה
ב-26.10.2026 את כל תרחישי הבדיקה (Approval v2 מאושר עם מספר הקצאה, 432 על מע"מ שגוי וכו').

א. תקלה ב-sandbox
מאז 31.10.2026 (הצלחה אחרונה 17:50 UTC), כל קריאה ל-https://ita-api.taxes.gov.il/shaam/tsandbox/
(Invoices/v2/Approval, Invoices/v2/health, invoice-information/v2/confirmationNumber) מחזירה
401  www-authenticate: Bearer error='invalid_token' – "Cannot pass the security checks…".
הטוקנים מתקבלים מ-https://openapi.taxes.gov.il/shaam/tsandbox/longtimetoken/oauth2/token
(גם refresh וגם authorization-code חדש מחזירים 200, scope=scope, expires_in=14400).
ה-gateway מחיל על הטוקן את מגבלת הקצב של התוכנית שלנו (x-ratelimit-limit), כלומר האפליקציה מזוהה.
מזהי טרנזקציה: 12dec73f6ae73c1a00741d07, eadb37026ae73c1a005d22c7, 12dec73f6ae72e8200d6c323.
1. האם השתנה משהו ב-31.10–1.11 בספק ה-OAuth של ה-sandbox או בהגדרת האבטחה של Invoices?
   (פורמט ה-access token השתנה: קידומת AAM… במקום AAI…)
2. מאיזה token endpoint ובאיזה scope יש להנפיק כיום טוקנים ל-Invoices v2
   (scope / invoices_scope / invoices_approval_scope)?
3. האם תוכלו לזהות לפי מזהי הטרנזקציה איזו בדיקת אבטחה נכשלת?

ב. שאלות לקראת ייצור
4. כתובות הייצור: האם authorize/token/API base לייצור הם אלו המוצגים בדף האפליקציה בפורטל
   https://openapi-portal.taxes.gov.il/shaam/production (ita-api.taxes.gov.il/shaam/production
   או openapi.taxes.gov.il/shaam/production), ומהו ה-scope בייצור?
5. האם נדרשות בדיקות קבלה/הצהרה כלשהן מעבר ל-sandbox לפני אישור האפליקציה בייצור?
6. שדה 1006 (מספר רישום תוכנה) ב-Approval: עד להקצאת מספר הרישום במרשם התוכנות –
   האם ניתן לשלוח את מספר העוסק של בית התוכנה (325128361), כפי שמופיע בטבלה 2.1 במסמך ה-API (גרסה 2.0, 7.2024)?
7. האם ניתן להזין ידנית בתוכנה מחוברת מספר הקצאה שהתקבל באפליקציית רשות המסים
   עבור חשבונית שכבר ננעלה (למשל בעת תקלה)?
8. האם מזהה משתמש פנימי פסאודונימי (u-<hash>) קביל בשדה user_name?
9. ב-sandbox אושר vat_number של מנפיק שהזהות המחוברת אינה מורשית לו – האם 406/431 נאכפים
   רק בייצור? ואיזה קלט מפיק 460/461 ב-sandbox?

תודה,
[שם], [תפקיד], [טלפון]
```

### 4ב. ל-lakohot-bt@taxes.gov.il: מעקב אחרי בקשת הרישום (שולחים **אחרי** הגשת שלב 5)

```
נושא: בקשה לרישום בית תוכנה לשירותי API – עטייה אייל - תבל, עוסק 325128361, בקשה מס' [___]

שלום רב,
הגשנו ביום [__] בקשה דיגיטלית לרישום בית תוכנה לשירותי API (מס' בקשה [___]) בצירוף כתב
התחייבות ונספח אבטחת מידע חתומים. ה-ADMIN שהוגדר: [שם, ת"ז אחרונות 4]. ארגון ה-sandbox שלנו
פעיל ועבר בדיקות מלאות מול Invoices v2.
נשמח לדעת את סטטוס הבקשה ואם חסר מסמך כלשהו, כדי שנוכל להשלים את הגדרת ה-ORGANIZATION
והאפליקציה בפורטל הייצור.
תודה, [שם, טלפון]
```

---

## 5. מה מחזירים לנו אחרי האישור, ואיך

### 5.1 הערכים ושמות משתני הסביבה (מ-`packages/shaam/src/config.ts`)

| ערך מהפורטל | משתנה סביבה | סודי? |
|---|---|---|
| — (מצב) | `SHAAM_ENV=production` | לא |
| Client ID | `SHAAM_PRODUCTION_CLIENT_ID` | לא, אבל לא מפרסמים |
| Client Secret | `SHAAM_PRODUCTION_CLIENT_SECRET` | **כן** |
| Authorize URL | `SHAAM_PRODUCTION_AUTHORIZE_URL` (https בלבד, כתובת sandbox נדחית) | לא |
| Token URL | `SHAAM_PRODUCTION_TOKEN_URL` | לא |
| API base URL | `SHAAM_PRODUCTION_API_BASE_URL` | לא |
| Scope | `SHAAM_PRODUCTION_SCOPE` (חובה בייצור) | לא |
| Redirect | `SHAAM_PRODUCTION_REDIRECT_URI=https://invoice.crm.tevel.space/shaam/callback` (אפשר להשמיט, ואז הוא נגזר מ-`APP_ORIGIN`) | לא |
| מספר רישום תוכנה | `SHAAM_ACCOUNTING_SOFTWARE_NUMBER` (1..999999999, ‏`99999999` נדחה בייצור) | לא |
| נוצר אצלנו | `SHAAM_TOKEN_ENC_KEY` (`openssl rand -base64 32`, שונה מ-`IDENTITY_ENC_KEY`) | **כן** |
| ברירות מחדל | `SHAAM_KILL_SWITCH=1` בהתחלה, ‏`SHAAM_MANUAL_ENTRY_ENABLED=0`, ואחר כך `SHAAM_ENABLED=1` | לא |
| אופציונלי | `SHAAM_CLIENT_SOFTWARE_KEY`, ‏`SHAAM_REQUEST_TIMEOUT_MS=20000` | — |

**איפה הם נשמרים:** בייצור הנוכחי (Oracle) כל המשתנים יושבים ב-`/opt/tevel-invoice/secrets/invoice.env` (הרשאות 600, ‏`env_file` ב-`ops/oracle/docker-compose.yml`). עותק נשמר ב-`~/invoiceproject-storage/oracle-invoice.env` (600). המסלול של GCP Secret Manager שמתואר ב-`SHAAM-PRODUCTION-ONBOARDING.md` §8 שייך ל-Cloud Run הישן.

### 5.2 העברה מאובטחת

- **לא שולחים** את ה-Client Secret בצ'אט, במייל, בווטסאפ, בטיקט או בצילום מסך.
- הדרך המועדפת: את/ה מעתיק/ה את הערכים בעצמך מהפורטל ישירות לקובץ (`chmod 600`) ב-`~/invoiceproject-storage/` או ב-`invoice.env` על השרת (ssh). לנו מודיעים רק "הוזן".
- אם חייבים להעביר: דרך מנהל סיסמאות משותף (פריט Secure Note), או קובץ מוצפן (`age`/`gpg`) כשהסיסמה עוברת בערוץ אחר. מוחקים אחרי ההזנה.
- סוד שנחשף (הודבק או צולם) מחליפים: Regenerate בפורטל (שער G13).
- את כתובות ה-URL וה-scope אפשר לשלוח כטקסט רגיל.

### 5.3 מה עושים אצלנו אחרי קבלת הערכים (לא מכאן)

`production:check` → פריסה עם `SHAAM_KILL_SWITCH=1` → חיבור OAuth של עסק פיילוט → dry-run D1–D8 (`SHAAM-PRODUCTION-ONBOARDING.md` §6.3) → הסרת ה-kill switch.

---

## 6. זמני תגובה צפויים

| שלב | זמן | ודאות |
|---|---|---|
| אישור ארגון או בקשת בית תוכנה | **לא מפורסם.** המדריך הרשמי אומר רק שהאישור מגיע במייל, ושעד אז אי אפשר להמשיך | ⚠️ לא מאומת. אין SLA רשמי שמצאנו |
| מענה של מרכז התמיכה ב-API | לא מפורסם. שעות פעילות: א'–ה', 8:00–17:00 | ✅ שעות בלבד |
| מהצד שלנו, אחרי קבלת הערכים ותיקון §2.3 | בערך 1–2 ימי עבודה עד dry-run | הערכה פנימית |
| כלל אצבע לתכנון | 2–3 שבועות, כמו "שלב B" ב-`00-PRODUCTION-READINESS-he.md` | הערכה, לא מקור רשמי |

---

## 7. מקורות (נבדקו ב-2026-11-16)

- ✅ נוהל חיבור בית תוכנה, נכון ל-11.1.24: עותק מוצמד בריפו `compliance/regulations/shaam/SHAAM_software-house-connection-procedure-110124.pdf` (sha256 `2647488c…`), והטקסט נקרא היום.
- ✅ מצגת "Tax Authority Open API – שע"ם" (נובמבר 2023), הורדה היום מ-https://www.gov.il/BlobFolder/service/connect-to-shaam/he/Service_Pages_shaam_connection-work-process-software-houses.pdf (sha256 `c2a2ebfe…`). ממנה: כתובת mm-rishum-tochna, ה-ADMIN תואם ליוצר ה-ORGANIZATION, אנשי הקשר ושעות התמיכה.
- ⚠️ דף השירות https://www.gov.il/he/service/connect-to-shaam: **לא נפתח היום (HTTP 403 לכלים אוטומטיים)**. התוכן מצוטט דרך ה-PDF ותוצאות החיפוש. **צריך לבדוק ידנית בדפדפן** שאין טופס או גרסה חדשה של כתב ההתחייבות.
- 📁 OpenApiUserGuide 1.0/5.2023 (S15, בריפו). מתוצאות חיפוש: "only users who signed up to the sandbox portal get approved to production"; עותק חיצוני: https://developer-guide.sovos.com/wp-content/uploads/2023/10/ENG-official-OpenApiUserGuide.pdf.
- 📁 מסמך ה-API לבתי תוכנה v2.0/7.2024: https://www.gov.il/BlobFolder/generalpage/israel-invoice-160723/he/vat_software-houses-180724-en.pdf
- דוח ה-401: `docs/shaam/SANDBOX-401-2026-11-01.md`. שאלות פתוחות: `docs/shaam/RTAC-STATUS.md` (10 פתוחות).
