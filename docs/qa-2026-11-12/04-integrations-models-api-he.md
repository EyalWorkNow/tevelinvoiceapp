# 04 · אינטגרציות, מודלים וחוזה API — תבל חשבוניות iOS

> בדיקה לקריאה בלבד, 2026-11-12. אפליקציה: `~/Projects/tevel-invoice-mobile`. שרת: `~/Projects/invoiceproject⁩` (ענף `feat/mobile-api-v2`, `70d49f3`). נשלחו רק בקשות GET מקומיות (`/ready`, `/version`). לא בוצעה אף קריאה לספק בתשלום.
> לא מדווח שוב כאן (כבר ידוע): אין רענון טוקן, כל 401 מנתק, טוקני push לא נמחקים ביציאה, אין allow-list ל-API_BASE, Supabase "פעיל" עם define אחד, אין מפתח idempotency ב-POST /documents.

## 1. מטריצת אינטגרציות

| אינטגרציה | איפה מחובר | Timeout / ניסיונות חוזרים | מה המשתמש רואה בכשל | סודות | עלות | מצב ב-:3031 |
|---|---|---|---|---|---|---|
| שע"ם (מספרי הקצאה) | `packages/shaam/src/client.ts`, `apps/api/src/shaam-deps.ts`; באפליקציה `lib/api/actions_api.dart:383-418` | 20 ש' (`client.ts:96`). כשל לפני שליחה מסווג "בטוח לנסות שוב", כשל אחרי שליחה מסווג "לא ידוע", ואז מבצעים התאמה. ה-worker מנסה שוב כש-`SHAAM_AUTO_RETRY` | כ-25 קודים בעברית (`errors_he.dart:237-261`) | OAuth, הטוקן מוצפן (`SHAAM_TOKEN_ENC_KEY`) | אין | **כבוי** (`SHAAM_ENABLED=0`). השירות המדומה ב-:3022 וה-sandbox ב-:3021 פועלים |
| Cardcom, תשלום לקוח וקישור תשלום | `apps/api/src/commerce/cardcom.ts`, `customer-payments.ts`, `routes/v2/merchant-payments.ts`; באפליקציה `allowed_urls.dart:62` | 20 ש' (`cardcom.ts:79`), בלי ניסיון חוזר. קישור ממתין נעשה בו שימוש חוזר (`customer-payments.ts:112`) | 503/502, עם הודעה גנרית "השירות לא זמין" | שם ה-API נשמר חתום (`sealMerchant`). המסוף מוגדר לכל עסק | עמלות סליקה | לא מוגדר |
| מנוי | iOS: IAP (`billing_screen.dart:786`). מחוץ ל-iOS: Cardcom | — | הודעות מקומיות | — | עמלת Apple | IAP זמין רק כשמוגדר |
| WhatsApp | (א) קישור `wa.me` מהאפליקציה (`s6_share.dart:95`, `compose_submit.dart:194`). (ב) Cloud API של Meta בשרת (`commerce/whatsapp.ts`, `routes/v2/dispatch.ts`) | 20 ש', בלי ניסיון חוזר. המצב מסומן UNKNOWN לפני השליחה, כדי למנוע שליחה כפולה | ראו ממצא H1 | `WHATSAPP_ACCESS_TOKEN` במשתני סביבה | תבנית utility בתשלום לכל הודעה | (א) אמיתי. (ב) לא מוגדר |
| דוא"ל ו-worker | `notifications/src/index.ts:58` (nodemailer, Gmail SMTP), `worker/src/delivery-consumer.ts` | 3 ניסיונות עם backoff של `60·5^n`. אין timeout מפורש ל-SMTP | סטטוס משלוח במסמך | סיסמת SMTP במשתני סביבה | חינם, אבל בכפוף למכסות Gmail | `EMAIL_MODE=file` (מדומה) |
| Apple Sign-in | `login_screen.dart:82`, `auth-routes.ts:147` (JWKS) | **אין timeout** ב-fetch של JWKS. הקאש מחזיק שעה | 401/503 בעברית | aud = bundle id | — | אמיתי |
| Google Sign-in | `auth_api.dart:63` (קוד מת). השרת מצפה ל-Firebase ID token | **אין timeout** (`auth-routes.ts:122`) | — | — | — | אין כפתור. `google_sign_in` ב-pubspec לא בשימוש |
| Supabase Auth | `lib/api/supabase_auth.dart`, `apps/api/src/supabase-auth.ts` | 30 ש' באפליקציה, 10 ש' בשרת | קודי `SUPABASE_*` בעברית | publishable key | — | ידוע, לא נבדק שוב |
| APNs ו-Live Activities | `ios/Runner/SystemNotices.swift`, `ios/TevelActivity`, `lib/state/system_notices.dart`, `notifications/src/apns.ts`, `worker/src/push-consumer.ts` | 10 ש' לכל שליחה. עד 60 ניסיונות. טוקן שמחזיר 410 או BadDeviceToken נמחק | "שגיאת חיבור" גנרית (ממצא M2) | מפתח P8 נשמר כקובץ במצב 600 | חינם | `APNS_ENABLED` מוגדר (sandbox). המסירה למכשיר לא אומתה |
| OCR להוצאות (Claude vision) | `packages/ocr/src/claude-vision.ts`, `app.ts:159-166`, `routes/v2/expenses.ts:418`; באפליקציה `expenses_screen.dart:229-266` | באפליקציה 20 ש'. בשרת ברירות המחדל של ה-SDK: **10 דק' timeout ו-2 ניסיונות חוזרים** | 503 `EXTRACTION_UNAVAILABLE`, ואז מעבר להזנה ידנית בלי הודעה | `ANTHROPIC_API_KEY` | ראו §4 | **כבוי** (אין מפתח, ולכן 503) |
| LLM נוסף | נבדק grep ל-openai/gemini/deepseek/anthropic/vision/ocr בשני הריפו | — | — | — | — | **אין**. Claude vision הוא המודל היחיד |

## 2. ממצאים לפי חומרה

### גבוה

**H1. WhatsApp אוטומטי ננעל לתמיד במצב UNKNOWN, גם כשברור שההודעה לא נשלחה.**
`dispatch.ts:93` מסמן את המצב UNKNOWN לפני הקריאה לרשת. אם `sendWhatsAppInvoice` זורק `HttpError` שמעיד על כשל ודאי, למשל `CUSTOMER_PHONE_INVALID` (422, נזרק עוד לפני שליחה, `whatsapp.ts:30`) או תשובה שאינה OK (`WHATSAPP_SEND_FAILED`), השגיאה נזרקת הלאה (`dispatch.ts:187-188`) והשורה נשארת UNKNOWN. כל קריאה הבאה מחזירה `claimed:false` (`dispatch.ts:87`), ולכן ההודעה לא תישלח לעולם. אין worker או נתיב שמבצעים התאמה ל-`document_dispatches`: חיפוש grep ב-`apps/worker` ובשכבת postgres לא מצא כלום. בנוסף, האפליקציה מדלגת על חלופת `wa.me` כשהשליחה האוטומטית נכשלה (`compose_submit.dart:176-183`). התוצאה: הלקוח לא מקבל את המסמך, ובעל העסק חושב שהוא "בבדיקה".
**המלצה:** כשל ודאי (שגיאה לפני השליחה, או 4xx מ-Meta) צריך לעבור ל-FAILED ולאפשר ניסיון חוזר. ל-UNKNOWN צריך התאמה לפי webhook הסטטוס של Meta או כפתור "שלח שוב" מפורש. באפליקציה, כשהשליחה נכשלה ונבחר "הפק ושלח בווטסאפ", לפתוח `wa.me`.

**H2. OCR: עלות לא מוגבלת וחיוב שממשיך אחרי שהמשתמש ויתר.**
- אין דה-דופליקציה: כשל בחילוץ (שורת FAILED) משאיר `extraction_source` ריק (`extraction.ts:217` מעדכן רק בהצלחה). האפליקציה מפעילה חילוץ מחדש בכל פתיחה של המסך, כי הסט `_extracted` נשמר רק בזיכרון של המסך (`expenses_screen.dart:61,246`). כל פתיחה היא קריאת מודל חדשה בתשלום.
- הקריאה למודל סינכרונית בתוך בקשת ה-HTTP. ה-client נבנה בלי `timeout` ובלי `maxRetries` (`claude-vision.ts:148-150`), ולכן במקרה הגרוע היא יכולה להימשך עד כ-30 דקות. האפליקציה מוותרת אחרי 20 ש' (`expenses_screen.dart:257`), אבל השרת ממשיך ומחויב.
- ברירת המחדל של המודל היא `claude-opus-5` (`claude-vision.ts:21`), אף שההערה אומרת "production must set EXPENSE_AI_MODEL". `production-config.ts` לא אוכף את זה (grep ריק).
**המלצה:** להגביל את מספר החילוצים לכל הוצאה (למשל 2) ולשמור את התוצאה לפי `sha256`. לקבוע `timeout: 25_000, maxRetries: 1`. לחסום הפעלה ב-production בלי `EXPENSE_AI_MODEL`. לשקול להעביר את החילוץ ל-worker אחרי הסריקה, והאפליקציה תבצע polling.

### בינוני

**M1. הודעות שגיאה: השרת שולח הודעה בעברית והאפליקציה זורקת אותה.** `errorMessageHe` (`errors_he.dart:10-16`) מחזירה "שגיאה לא צפויה (CODE)" לכל קוד שלא מופיע במפה, גם כשהשרת שלח `message` בעברית. השוואה בין 168 הקודים בשרת ל-225 הקודים באפליקציה מצאה קודים חסרים שהמשתמש יכול לפגוש: `CUSTOMER_PHONE_INVALID`, `WHATSAPP_SEND_FAILED`, `PAYMENT_CREATE_FAILED`, `PAYMENT_PROVIDER_UNAVAILABLE`, `PAYMENT_PROVIDER_INVALID`, `PAYMENT_TOKEN_INVALID`, `CHECKOUT_NOT_FOUND`, `CHECKOUT_NOT_READY`, `BILLING_CONSENT_REQUIRED`, `PLAN_INVALID`, `APPLE_TRANSACTION_ALREADY_LINKED`, `APPLE_ACCOUNT_MISMATCH`, `IDEMPOTENCY_KEY_INVALID`, `ACCOUNT_ALREADY_EXISTS`, `EMAIL_INVALID`, `BUSINESS_NAME_INVALID`, `TAX_RATE_MISSING`, `QUOTE_CHANGED`. כשל של ספק ב-502 מוצג כ"השירות לא זמין" בלי לומר איזה ספק נכשל.
**המלצה:** להוסיף את הקודים החסרים למפה. אם `message` מכיל עברית, להציג אותו כחלופה במקום "שגיאה לא צפויה". להוסיף בדיקת CI שמשווה את קודי השרת לקודי האפליקציה.

**M2. Push לא עובד אצל תפקידים בלי MFA, והמשתמש לא יודע למה.** `mobile-push.ts:33-37` דורש `mfa_verified` על טוקן המכשיר. מי שנכנס כעובד, צופה או רו"ח בתצורה שאין בה MFA יקבל `VALIDATION` "a current device credential is required". המסך מציג "שגיאת חיבור" וכפתור "נסו שוב" שלא יעבוד לעולם (`system_notice_settings.dart:88-94`).
**המלצה:** להחזיר קוד ייעודי, למשל `PUSH_MFA_REQUIRED`, ולהסביר למשתמש. לחלופין, לא להציג את האפשרות כשאין MFA.

**M3. אין גרסת API ואין גרסת אפליקציה בבקשות.** אף כותרת לא מזהה את הגרסה (`client.dart:264` מוסיף רק Accept, Authorization ו-X-Business-Id), ובשרת אין בדיקת גרסה מינימלית. התאימות נשענת על שדות nullable ועל probes כמו `serverHasPost`, ששולח POST ריק לנתיב משנה-מצב כשמדובר בשרת ישן (`settings_api.dart:215-226`).
**המלצה:** לשלוח כותרות `X-App-Version` ו-`X-App-Build`. בשרת להחזיר `426 APP_UPGRADE_REQUIRED` ולהוסיף מסך עדכון. לבטל את ה-probe ב-POST לטובת `features[]` ב-`/me`.

**M4. אמינות הדוא"ל.** שליחה דרך Gmail SMTP (`index.ts:66-72`) בלי timeouts מפורשים: ב-nodemailer ברירת המחדל לחיבור היא 2 דק' ול-socket היא 10 דק'. גם קודי MFA עוברים בערוץ הזה. מכסות Gmail ויישור SPF/DMARC ל-`from` יגבילו את השליחה ב-production.
**המלצה:** לעבור לספק טרנזקציוני עם דומיין מאומת, ולהגדיר `connectionTimeout` ו-`socketTimeout`.

### נמוך

- **L1.** fetch של JWKS של Apple ו-Google רץ בלי `AbortSignal.timeout` (`auth-routes.ts:122,147`). כשהשירות החיצוני איטי, הכניסה נתקעת.
- **L2.** Sign in with Apple נשלח בלי `nonce` (`login_screen.dart:82`), ולכן אין הגנה מפני replay של identity token שדלף.
- **L3.** החבילה `google_sign_in` מופיעה ב-pubspec (`pubspec.yaml:38`) אבל לא בשימוש, וגם `signInWithGoogle` הוא קוד מת.
- **L4.** APNs פותח חיבור HTTP/2 חדש לכל הודעה (`apns.ts:154`). Apple ממליצה לשמור חיבור פתוח. בעומס זה עלול להיחשב התנהגות פוגענית.
- **L5.** ב-OCR בדיקת ה-hash נעשית על בייטים שנקראו פעם אחת, והספק קורא אותם שוב מהאחסון (`extraction.ts:302` לעומת `app.ts:163`). זה TOCTOU תיאורטי.
- **L6.** בכל הפקה עם WhatsApp נוצרים שני קישורי שיתוף: אחד ב-dispatch ואחד ב-`createIssueShareLink` (`compose_submit.dart:171,185`).

### נקודות חזקות (נבדקו)

- idempotency בתשלומים טובה מאוד: מפתח לכל slot נשמר בקאש לפני השליחה, ויש שחזור של `IDEMPOTENCY_CONFLICT` ושל הקצאה שהתשובה עליה אבדה (`payments_api.dart:97-180`).
- קישור תשלום Cardcom ממוחזר כשהוא עדיין ממתין. כתובת ה-URL מאומתת גם בשרת וגם באפליקציה.
- שע"ם מבחין בין כשל לפני שליחה לכשל אחרי שליחה, ויש kill-switch.
- ב-iOS המנוי עובר רק דרך IAP.
- כיסוי החוזה (הרצת עותק של `audit_backend_coverage.py` שכותב ל-`/tmp` בלבד, כי הכלי המקורי כותב ל-`docs/backend-audit`): 202 קריאות באפליקציה מול 192 נתיבים בשרת. 188 תואמים לנתיב, 14 מטופלים ישירות (`/auth/*`, `/mobile/*`, ואומתו ידנית ב-`auth-routes.ts`), **0 לא תואמים**.

## 3. חוזה API: סיכום

- **נתיבים חסרים:** אין. אין קריאה מהאפליקציה לנתיב שלא קיים בשרת.
- **נתיבים בשרת שהאפליקציה לא משתמשת בהם:** `/auth/google` בפועל, BE-42 (ITA OAuth במובייל), וחלק מ-`/deliveries/:id/process`. אלה לא תקלות.
- **Idempotency:** `/payments`, `/receipts`, `finalize` ו-`credit` עם מפתח. `POST /businesses` עם מפתח אופציונלי. `dispatch` ללא מפתח, אבל השרת עושה dedup לפי מסמך וערוץ (זה הגורם ל-H1). `allocation/*` ללא מפתח, ונשען על מכונת המצבים.
- **מיפוי שגיאות:** ראו M1.

## 4. שימוש במודלים (Claude vision ל-OCR)

**איכות ה-prompt והתכנון: טובה.** יש הגנה מפורשת מפני prompt injection, הוראה "לא להמציא ולא לחשב", structured output לפי JSON schema, אימות נוסף ב-`parseExtraction`, טיפול ב-`refusal`, ציון ביטחון לכל שדה, ו-benchmark עם קורפוס injection (`packages/ocr/benchmark`).

**חסרים:**
- (א) `max_tokens: 4096` כולל thinking, שב-Opus 5 פועל כברירת מחדל. קבלה ארוכה תיחתך, ו-`stop_reason: max_tokens` לא מטופל בנפרד, כך שהכשל נרשם כ"פלט פגום".
- (ב) אין הנחיה מפורשת להמיר תאריך ישראלי `DD/MM/YYYY`, ואין הנחיה לעוסק פטור ללא מע"מ.
- (ג) אין הגבלה על אורך `lineItems`.
- (ד) לא נקבע `effort`. לחילוץ מספיק `low`.

**PII:** תמונת הקבלה המלאה נשלחת לספק בארה"ב. היא כוללת שם ספק, ח.פ, לעיתים שם הלקוח ו-4 ספרות אחרונות של כרטיס. אין הסכמה או גילוי באפליקציה, ולא נמצאה הגדרת zero-retention.
**המלצה:** לציין זאת במדיניות הפרטיות, להציג הודעה חד-פעמית לפני "קרא אוטומטית", ולבדוק DPA.

**עלות לקריאה (הערכה):** בערך 2.5K טוקני קלט (תמונה ו-prompt) ו-1–2K טוקני פלט כולל thinking.

| מודל | מחיר קלט / פלט (למיליון טוקנים) | עלות לקבלה |
|---|---|---|
| Opus 5 | $5 / $25 | כ-$0.04–0.06 (כ-₪0.15–0.22) |
| Sonnet 5.5 | $2 / $10 | כ-$0.02 |
| Haiku 5.5 | $0.10 / $0.50 | פחות מ-$0.002 |

PDF מרובה עמודים מכפיל את העלות. מסלול "מתחילים" עולה ₪8 לחודש, כך שמשתמש שמעלה בערך 50 קבלות, או נתקל בלולאת ה-retry של H2, עולה יותר ממה שהוא משלם.
**המלצה:** להריץ את ה-benchmark הקיים על Haiku 5.5 ועל Sonnet 5.5 ולבחור את הזול ביותר שעובר את הסף. Opus 5 מוגזם למשימה הזאת.

**איפה מודל יעזור:**
- (1) הצעת קטגוריה להוצאה כבר יוצאת מה-OCR. כדאי לחבר אותה לכללים לכל ספק, כדי שלא יידרש מודל בפעם השנייה.
- (2) זיהוי כפילויות לפי hash ושדות. אין צורך במודל.
- (3) ניסוח הודעות ווטסאפ ותזכורות: עדיף טקסט קבוע (קיים) ולא LLM.

**שימוש מוגזם:** רק בחירת Opus ל-OCR.

## 5. המלצות לפי סדר

1. H1: לתקן את מצבי ה-dispatch ואת חלופת `wa.me`.
2. H2: הגבלה ודה-דופליקציה ל-OCR, timeout ו-retries מפורשים, אכיפה של `EXPENSE_AI_MODEL` ומעבר למודל זול.
3. M1: להשלים את קודי השגיאה ולהציג את הודעת השרת בעברית כחלופה, עם בדיקת CI.
4. M2: הודעת push ייעודית למשתמשים בלי MFA.
5. M3: כותרות גרסה ותגובת 426.
6. M4: ספק דוא"ל טרנזקציוני ו-timeouts.
7. L1–L6.
