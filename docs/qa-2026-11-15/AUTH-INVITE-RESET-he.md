# הזמנת עובד ו"שכחתי סיסמה" באפליקציה – 15.11.2026

שתי זרימות כניסה היו שבורות ב-production (שרת `001882c`, TestFlight build 10). המסמך מתאר את המצב שהיה, מה תוקן ואיך, מה צריך להגדיר ב-Supabase וב-Apple, באיזה סדר לפרוס, ומה הבעלים צריך לבדוק.

| | ענף | ראש הענף |
|---|---|---|
| שרת (`invoiceproject`) | `fix/auth-invite-reset` | `f3ea420` (מעל `001882c`) |
| אפליקציה (`tevel-invoice-mobile`) | `fix/auth-invite-reset` | ה-commit שמוסיף את המסמך הזה (מעל `24d23a7`) |

לא בוצעו push, פריסה, ssh ל-production או שינוי כלשהו ב-Supabase.

---

## 1. איך זה עבד עד היום

**התאמת זהות Supabase למשתמש תבל.** ההתאמה **לא** נעשתה לפי אימייל, ולא הייתה טבלת קישור. השרת (`POST /auth/supabase`, `apps/api/src/supabase-auth.ts`) מאמת את ה-access token מול `https://lyfojepvxzskyoesbmqx.supabase.co/auth/v1/user`. הוא דורש משתמש מאושר (`email_confirmed_at`) שאינו אנונימי, ושדה `app_metadata.tevel_user_id` עם UUID של משתמש תבל. את `app_metadata` אפשר לכתוב רק עם מפתח service-role, כלומר מפעיל ידני. לשרת ב-production אין מפתח כזה.

**אימייל לא מוכר בהחלפה.** משתמש Supabase בלי `tevel_user_id` מקבל `403 NO_LINKED_ACCOUNT`, גם אם האימייל שלו זהה לאימייל של משתמש תבל. משתמש שלא קיים ב-Supabase בכלל נכשל עוד קודם, בשלב הסיסמה מול Supabase, ומקבל "האימייל או הסיסמה שגויים".

**קבלת הזמנה בשרת.**
- `POST /business/members/invite` יוצר טוקן אקראי. במסד נשמר רק ה-hash שלו (SHA-256), וההזמנה תקפה 7 ימים. "שלח שוב" מנפיק טוקן חדש.
- המייל כולל שני קישורים: `https://invoice.crm.tevel.space/m/invite/:token` ו-`.../app/#/invite?token=`.
- `GET /auth/invite/:token` הוא תצוגה ציבורית: עסק, תפקיד, מזמין, והאם כבר קיים חשבון. הזמנה שפגה, בוטלה או נוצלה מחזירה 410.
- `POST /auth/invite/:token/accept` מקבל אחת משתי הוכחות:
  - `{password}`: יוצר חשבון חדש עם סיסמת תבל, או בודק את הסיסמה של חשבון קיים;
  - `{idToken}` של Google (Firebase).
- בסוף נוצר סשן cookie. הפונקציה ב-SQL `accept_invitation` מוסיפה את החברות.
- `/m/invite/:token` הפנה ב-302 לדף ההזמנה **באתר**.

**איפוס סיסמה של תבל.** `POST /auth/password/forgot` מחזיר תמיד `202`. אם החשבון קיים, נשלח מייל בעברית עם קישור `/app/#/reset?token=` שתקף שעה, ופותח את האתר. `POST /auth/password/reset` משלים את האיפוס. זו סיסמת תבל, לא סיסמת Supabase.

**גישה ל-Supabase מהמחשב.** הרצתי `which supabase` והתוצאה הייתה `supabase not found`. ה-CLI לא מותקן ואין גישת ניהול, ולכן לא נגעתי בשום הגדרה מרחוק. כל הגדרות ה-dashboard מופיעות כרשימת צעדים בסעיף 4.

## 2. מה היה שבור ולמה

1. **עובד מוזמן (A7).**
   - לקישור באפליקציה לא היו associated domains, ולשרת לא היה קובץ AASA, ולכן הקישור נפתח באתר.
   - `InviteScreen` לא היה נגיש משום מקום.
   - הסיסמה שהעובד קבע באתר נשמרה כסיסמת תבל, בעוד שהאפליקציה (build 9 ואילך) שולחת את הסיסמה ל-Supabase, שלא מכיר אותו. התוצאה: "האימייל או הסיסמה שגויים".
   - גם אם היה נוצר לו משתמש ב-Supabase, השרת היה דוחה אותו (`NO_LINKED_ACCOUNT`), כי אין `tevel_user_id`.
   - Apple עבד רק כשהאימייל ב-Apple זהה לאימייל שבהזמנה, ורק אחרי שההזמנה התקבלה באתר.
2. **"שכחתי סיסמה" (A3).** בבילד עם Supabase הקוד הציג בכוונה רק "פנו לתמיכה", כדי לא לאפס סיסמת תבל שהאפליקציה לא משתמשת בה. לא היה מימוש של שחזור סיסמה ב-Supabase.

## 3. מה שיניתי

### שרת (`fix/auth-invite-reset`)

- **קישור שהשרת כותב** (migration `0095_supabase_identity_link.sql`): `users.supabase_subject` (ייחודי) ו-`supabase_linked_at`, באותה צורה כמו `apple_subject` ו-`google_subject`. בהחלפת הטוקן בכניסה השרת מחפש קודם את הקישור של המפעיל (`app_metadata`), ואחר כך את `supabase_subject`. **הוא אף פעם לא מקשר לפי אימייל בזמן כניסה.**
- **קבלת הזמנה עם Supabase:** `POST /auth/invite/:token/accept {supabaseAccessToken, password?, displayName?}`.
  - השרת מאמת את הטוקן מול Supabase. אם האימייל לא אושר, הוא מחזיר `403 SUPABASE_EMAIL_NOT_CONFIRMED`.
  - האימייל המאושר חייב להיות האימייל שאליו נשלחה ההזמנה. אחרת מוחזר `403 INVITATION_EMAIL_MISMATCH` עם `signedInEmail`.
  - **חשבון חדש:** נוצר כשהוא כבר מקושר, באותה טרנזקציה שבה נוצרת החברות. ה-`password` נשמר גם כסיסמת תבל, כך שאותה סיסמה פותחת גם את האתר.
  - **חשבון קיים:** מקושר רק אם הוא כבר מקושר לזהות הזו, או אם `password` הוא סיסמת תבל הנוכחית שלו. הקישור עצמו אף פעם לא מוסיף שיטת כניסה לחשבון קיים, כי מי ששלח את ההזמנה מחזיק את הקישור (C1). חשבון בלי סיסמת תבל מקבל `409 INVITATION_USE_EXISTING_SIGN_IN` ("המשך עם Apple").
  - אם הזהות כבר מקושרת לחשבון אחר, מוחזר `409 SUPABASE_IDENTITY_MISMATCH`.
- **קבלת הזמנה עם Apple** (`{appleIdentityToken}`): אימייל Apple המאומת חייב להיות האימייל שבהזמנה. כתובת relay מקבלת הודעה שמציינת את הכתובת. חשבון חדש נוצר עם `apple_subject`.
- **חבר קיים:** `accept_invitation` מחזיר עכשיו `409 MEMBER_EXISTS` ולא דורס את התפקיד. ההזמנה נשארת פתוחה.
- **AASA:** `GET /.well-known/apple-app-site-association` וגם `/apple-app-site-association`. הם מוגשים כ-`application/json`, בלי הפניה, ולא תלויים ב-build של האתר:
  ```json
  {"applinks":{"apps":[],"details":[{"appID":"ARFSXMWT96.space.tevel.invoice","appIDs":["ARFSXMWT96.space.tevel.invoice"],"paths":["/m/invite/*"],"components":[{"/":"/m/invite/*"}]}]}}
  ```
  הנתיב שנתבע הוא `/m/invite/*` ולא `/invite/*`, כי זה הנתיב שבמייל.
- **דף נחיתה** ל-`/m/invite/:token` (במקום הפניה): "פתח באפליקציה" מוביל ל-`tevel://invite/:token`, ו"אין לי את האפליקציה — המשך באתר" לדף ההזמנה באתר. בדף אין JavaScript, ה-CSP הוא `default-src 'none'`, ומוגדר `Referrer-Policy: no-referrer`.
- **טקסט המייל:** מוסבר שבטלפון הקישור נפתח באפליקציה.
- **לוגים:** טוקן ההזמנה כבר לא נכתב בלוג הבקשות (`/auth/invite/:token`, `/m/invite/:token`).
- **מחיקת חשבון:** מאפסת גם את `supabase_subject`. המשתמש ב-Supabase עצמו לא נמחק, כי אין לשרת מפתח service-role.
- **תיעוד:** `docs/auth/ACCOUNT-LINKING-POLICY.md`, בסעיף Supabase.

### אפליקציה (`fix/auth-invite-reset`)

- **קישורים:** `tevel://invite/:token` ו-`https://<host>/m/invite/:token` (כ-URL מלא או כנתיב בלבד) פותחים את `InviteScreen`, גם בהפעלה קרה. ההזמנה נשמרת עד שה-splash מסיים לנתב.
- **מסך ההזמנה:** מציג עסק, תפקיד, מזמין ואת האימייל שבהזמנה (קבוע, לא ניתן לעריכה).
  - **אין חשבון:** שם וסיסמה. הסיסמה נבדקת מקומית לפי אותה מדיניות כמו בשרת: 12 תווים לפחות ו-4 תווים שונים לפחות. האפליקציה מבצעת Supabase `signUp` עם האימייל שבהזמנה.
    - אם "Confirm email" כבוי: מתקבל סשן מיד, ואז `accept`.
    - אם "Confirm email" פעיל: מוצג מסך "אישור כתובת האימייל" עם קוד בן 6 ספרות (`verify type=signup`) ו"שלח קוד חדש" (`resend`), ואז `accept`.
    - אם כבר קיים חשבון Supabase עם אותה סיסמה (ניסיון קודם), נעשה בו שימוש. אם הוא קיים עם סיסמה אחרת, מוצגת ההודעה "לכתובת הזו כבר יש סיסמה באפליקציה…".
  - **יש חשבון:** סיסמה. אם זו סיסמת האפליקציה (Supabase), נשלחים גם הטוקן וגם הסיסמה. אחרת נשלחת רק הסיסמה, והשרת בודק אותה כסיסמת תבל. יש גם קישור "שכחתי סיסמה".
  - **"המשך עם Apple":** שולח `appleIdentityToken` ל-`/accept`.
  - **אחרי קבלת ההזמנה:** `finishSignIn` מבצע MFA אם צריך, מנפיק device token ומנווט כרגיל.
  - **שגיאות בעברית:**
    - הזמנה שפגה או בוטלה: "ההזמנה כבר לא בתוקף. בקש מ-{מזמין} לשלוח שוב".
    - אימייל לא תואם: "ההזמנה נשלחה ל-x, התחברת כ-y. …".
    - חבר קיים: "אתה כבר חבר ב-{עסק}".
- **"שכחתי סיסמה" עם Supabase** (`lib/screens/auth/password_recovery.dart`), בלי deep link:
  1. אימייל, ואז `POST /auth/v1/recover`. התשובה זהה לכל כתובת: "אם הכתובת … רשומה, נשלח אליה קוד".
  2. קוד מהמייל, ואז `POST /auth/v1/verify` עם `type=recovery`. מתקבל סשן שחזור שנשמר בזיכרון בלבד: לא ב-Keychain ולא בלוג.
  3. "סיסמה חדשה", ואז `PUT /auth/v1/user`.
  4. החלפה ב-`/auth/supabase` עם אותו סשן, וכניסה רגילה.
  - אם הסיסמה עודכנה אבל אין חשבון תבל מקושר, מוצג "הסיסמה עודכנה" יחד עם ההסבר, ולא כישלון שקט.
  - בתוך הזמנה רק הסיסמה משתנה, ואז ממשיכים להצטרף.
  - בבילד בלי Supabase נשאר קישור האיפוס של תבל.
- **Associated Domains:** `applinks:invoice.crm.tevel.space` ב-`ios/Runner/Runner.entitlements`, ב-commit נפרד. **יש לעשות צעד מקדים ב-Apple לפני הבילד הבא** (סעיף 5).

### בדיקות

| | מה נבדק | תוצאה |
|---|---|---|
| שרת – אינטגרציה | `apps/api/test/supabase-invite.int.test.ts` (מסד `invoice_test_f`): <br>• קבלה עם זהות Supabase תואמת → קישור, device token, כניסה חוזרת ב-`/auth/supabase` וכניסה באתר <br>• אימייל לא תואם, ו-`signedInEmail` בתשובה <br>• אימייל לא מאושר <br>• הזמנה שפגה או בוטלה (410) <br>• חבר קיים (409, התפקיד לא השתנה) <br>• חשבון קיים: סיסמת תבל, קישור מפעיל, זהות שמקושרת למשתמש אחר <br>• אין קישור לפי אימייל בכניסה <br>• Apple: relay ותואם <br>• מבנה ה-JSON של AASA | ✅ |
| שרת – דף הנחיתה | `v2-team.int.test.ts` | ✅ |
| שרת – unit | `supabase-auth.unit.test.ts` | ✅ |
| שרת – כל החבילה | build, typecheck, lint, prettier, `pnpm test` (425) ו-`pnpm test:integration` מלא (2376) | ✅ |
| אפליקציה | `test/auth_invite_reset_test.dart`: <br>• פירוש קישורים <br>• קודי השגיאה של Supabase <br>• signUp: סשן, ממתין לקוד, חשבון קיים <br>• recover, verify ו-update password <br>• מצבי מסך ההזמנה: חשבון חדש, קוד אישור (קוד שגוי, שליחה חוזרת, קוד נכון), חשבון קיים, אי-התאמה דרך Apple, חבר קיים, פג ובוטל <br>• שכחתי סיסמה: בקשה, קוד, סיסמה חדשה, הצלחה, וגם קוד שגוי, סיסמה זהה לקודמת, אין חשבון מקושר, ובתוך הזמנה | ✅ |
| אפליקציה – כל החבילה | `flutter analyze` נקי; `flutter test --concurrency=1` (956) | ✅ |

את Supabase מדמה MockClient, כמו בבדיקות `supabase_auth` הקיימות. **לא בוצעה כניסה אמיתית מול Supabase, לא נשלח מייל אמיתי, ולא נבדק universal link על מכשיר.** את זה צריך לבדוק הבעלים (סעיף 6).

## 4. רשימת צעדים ב-dashboard של Supabase

הפרויקט: `tevel-invoice-eu` (`lyfojepvxzskyoesbmqx`), https://supabase.com/dashboard/project/lyfojepvxzskyoesbmqx

1. **SMTP משלכם (חובה).** Authentication → Emails → SMTP Settings → Enable Custom SMTP. בלי זה, השרת המובנה של Supabase שולח רק לחברי הצוות של הפרויקט, ובמכסה של בערך 2 מיילים בשעה, כך שעובדים לא יקבלו קוד.
   - Sender email: אותה כתובת שממנה השרת שולח היום (Gmail, `EMAIL_MODE=provider`)
   - Sender name: `תבל`
   - Host: `smtp.gmail.com`
   - Port: `465`
   - Username: אותה כתובת Gmail
   - Password: אותו App Password של Gmail שמשמש את השרת. לא להכניס אותו לצ'אט או ל-Git.
   - אין כאן שירות חדש בתשלום.
2. **Email provider.** Authentication → Sign In / Providers → Email:
   - Enable Email provider: **ON**
   - Allow new users to sign up: **ON** (בלי זה ההרשמה מתוך ההזמנה נכשלת עם `SUPABASE_SIGNUP_DISABLED`)
   - Confirm email: **ON** (מומלץ; האפליקציה תציג מסך קוד)
   - Secure password change: להשאיר כברירת המחדל (**OFF**). השחזור מאמת ממילא עם קוד.
   - Minimum password length: `12`
   - Email OTP length: `6`
   - Email OTP expiration: `3600` שניות
3. **Allow anonymous sign-ins:** OFF (השרת דוחה משתמשים אנונימיים בכל מקרה).
4. **URL Configuration.** Site URL: `https://invoice.crm.tevel.space/app/`. העיצוב החדש לא תלוי ב-redirect URL, כי הוא עובד עם קודים. ה-Site URL נועד רק לכך שקישור ברירת מחדל לא יוביל ל-localhost. אין צורך ב-Redirect URLs.
5. **Email templates** (Authentication → Emails → Templates). חובה שיופיע `{{ .Token }}`.
   - **Confirm signup:** Subject: `קוד האישור שלך לתבל`
     ```html
     <div dir="rtl" style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6">
       <h2>ברוכים הבאים לתבל</h2>
       <p>כדי לסיים ליצור את החשבון, הזינו באפליקציה את הקוד:</p>
       <p style="font-size:28px;font-weight:bold;letter-spacing:6px" dir="ltr">{{ .Token }}</p>
       <p>הקוד תקף לשעה. אם לא ביקשתם להצטרף לתבל, אפשר להתעלם מהודעה זו.</p>
     </div>
     ```
   - **Reset Password:** Subject: `קוד לאיפוס הסיסמה בתבל`
     ```html
     <div dir="rtl" style="font-family:Arial,sans-serif;font-size:16px;line-height:1.6">
       <h2>איפוס סיסמה</h2>
       <p>הזינו באפליקציית תבל את הקוד:</p>
       <p style="font-size:28px;font-weight:bold;letter-spacing:6px" dir="ltr">{{ .Token }}</p>
       <p>הקוד תקף לשעה. אם לא ביקשתם איפוס, אפשר להתעלם מהודעה זו. הסיסמה שלכם לא השתנתה.</p>
     </div>
     ```
6. **Rate limits.** Authentication → Rate Limits → Rate limit for sending emails: `30` לשעה. זו ברירת המחדל עם SMTP משלכם, ומספיקה בשלב הזה.
7. **לא לעשות:** לא ליצור מפתח service-role עבור השרת או האפליקציה. לא לכתוב `tevel_user_id` לעובדים חדשים. הקישור נעשה עכשיו אוטומטית בקבלת ההזמנה.

## 5. סדר פריסה (שרת קודם)

1. **שרת:** לפרוס את `fix/auth-invite-reset` דרך ה-rollout המוגן הרגיל. Migration `0095` רץ אוטומטית. השינוי תואם לאחור:
   - build 10 ממשיך לעבוד: קבלת הזמנה עם סיסמה, ו-`/auth/supabase` לחשבונות שהמפעיל קישר.
   - באתר, הקישור הראשון במייל מציג עכשיו דף נחיתה עם "המשך באתר", במקום הפניה אוטומטית. הקישור השני במייל ממשיך לפתוח את האתר ישירות.
2. **אימות השרת:**
   - `curl -sI https://invoice.crm.tevel.space/.well-known/apple-app-site-association` צריך להחזיר `200` ו-`content-type: application/json`, בלי הפניה. אם Caddy מגיש את `/.well-known/` בעצמו, צריך להעביר את הנתיב הזה ל-API.
   - `curl -s https://invoice.crm.tevel.space/m/invite/AAAAAAAAAAAAAAAAAAAAAAAA` צריך להחזיר דף שמכיל "פתח באפליקציה".
3. **Supabase:** כל סעיף 4, ובמיוחד SMTP והתבניות, לפני שמפיצים בילד חדש.
4. **Apple Developer:**
   - Identifiers → `space.tevel.invoice` → Capabilities → **Associated Domains: ON**.
   - Profiles → לייצר מחדש את **"Tevel Invoice App Store"** ולהוריד אותו. בדקתי את הפרופילים המקומיים, ואף אחד מהם לא כולל את ה-entitlement.
   - בלי הצעד הזה ה-export של הבילד ייכשל. אם צריך לשחרר בילד לפני כן: `git revert` ל-commit של ה-entitlement (`feat(ios): Associated Domains…`). בינתיים כפתור "פתח באפליקציה" בדף הנחיתה עדיין מביא את ההזמנה לאפליקציה.
5. **אפליקציה:** להעלות את מספר הבילד (11). לבנות עם `tool/build_release.dart` ועם `SUPABASE_AUTH_URL` ו-`SUPABASE_AUTH_PUBLISHABLE_KEY` כמו ב-`docs/SUPABASE-AUTH.md`. להעלות ל-TestFlight.

## 6. מה הבעלים צריך לבדוק (על אייפון עם build 11)

1. **הזמנה חדשה:** להזמין כתובת שאין לה חשבון.
   - במייל בטלפון, הקישור הראשון פותח את האפליקציה ישירות, במסך "הוזמנת ל-… כ…". אם במקום זה נפתח דפדפן, נבדק "פתח באפליקציה".
2. **יצירת חשבון:** שם וסיסמה, ואז "יצירת חשבון והצטרפות".
   - מגיע מייל בעברית עם קוד. מזינים אותו ונכנסים לעסק.
   - עם הרשאה שמחייבת MFA, מופיע קודם שלב הקוד הדו-שלבי.
3. **כניסה חוזרת:** "התנתקות", ואז כניסה עם האימייל והסיסמה. הכניסה צריכה לעבוד, וגם כניסה באתר עם אותה סיסמה.
4. **שכחתי סיסמה:**
   - במסך הכניסה: קוד, ואז סיסמה חדשה, ואז נכנסים.
   - עם כתובת שלא קיימת מופיעה אותה הודעה, ולא נשלח מייל.
5. **Apple עם כתובת אחרת:** מבטלים הזמנה, שולחים חדשה, ונכנסים עם Apple שמשתמש ב"הסתר את האימייל שלי". צריכה להופיע ההודעה "ההזמנה נשלחה ל-…, התחברת כ-…", וההזמנה נשארת פתוחה.
6. **הזמנה שבוטלה:** מבטלים הזמנה במסך הצוות ופותחים את הקישור. צריך להופיע "ההזמנה כבר לא בתוקף…".
7. **הזמנה במחשב:** הקישור הראשון מציג דף נחיתה, ו"המשך באתר" פותח את דף ההזמנה שמוכר מהאתר.

## 7. מה נשאר פתוח

- **משתמשים ותיקים עם סיסמת תבל בלבד (A2):** עדיין לא יכולים להיכנס לאפליקציה עם סיסמה, אלא אם קישרו אותם, או שהם מקבלים הזמנה ומשתמשים בה מתוך האפליקציה עם סיסמת תבל. ההמשך המתבקש הוא "קישור סיסמת אפליקציה": signUp, ואחריו אימות סיסמת תבל, ואז `supabase_subject`. צריך החלטת מוצר.
- **שתי סיסמאות:** איפוס באפליקציה משנה את סיסמת Supabase בלבד, ואיפוס באתר משנה את סיסמת תבל בלבד. אחרי איפוס הן כבר לא זהות.
- **מחיקת חשבון:** לא מוחקת את המשתמש ב-Supabase, כי אין מפתח service-role. הקישור בתבל כן מתאפס.
- **בדיקות על מכשיר:** universal link על מכשיר ומייל אמיתי מ-Supabase לא נבדקו (סעיף 6).
