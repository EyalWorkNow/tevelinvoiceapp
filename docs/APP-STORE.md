# תבל – חשבוניות · App Store Connect

מסמך הגשה ל-App Store (iPhone בלבד, V2). הטקסטים מוכנים להדבקה. מה שמסומן `<…>` צריך השלמה לפני ההגשה.
**הערה:** חלקים להלן נכתבו לפני מעבר מסלולי iOS ל-StoreKit ואינם מקור אמת לתשלום. ראו [תוכנית מוכנות עדכנית](../apple-review/PRODUCTION_READINESS_PLAN-he.md) ו-[הגדרת IAP](../apple-review/APPLE-IAP-SETUP-he.md). אין להעתיק Review Notes או App Privacy מכאן לפני יישורם לקוד Release.
מקור הדרישות: `docs/SPEC-v2-he.md` §16 (AS-1–AS-11), F6 ו-AT-95/AT-96. (V1: `docs/SPEC-he.md` §10–§11.)

---

## 1. זהות האפליקציה

| שדה | ערך |
|---|---|
| Bundle ID | `space.tevel.invoice` |
| SKU | `tevel-invoice-ios` |
| Team | `ARFSXMWT96` (מתוך פרויקט ה-Xcode, לוודא שזה הצוות הנכון) |
| שפה ראשית | עברית |
| שם בבית (CFBundleDisplayName) | תבל |
| קטגוריה ראשית / משנית | Business (עסקים) / Finance (פיננסים) |
| מחיר | הורדת האפליקציה חינם; מסלולי מנוי דיגיטליים ב-iOS דורשים מוצרי StoreKit ו-App Store Connect פעילים לפני הגשה |
| מכשירים | iPhone בלבד (`TARGETED_DEVICE_FAMILY = 1`), לאורך בלבד, iOS 15 ומעלה |
| Capability | Sign in with Apple (`Runner.entitlements`). צריך להפעיל אותו גם ב-App ID בפורטל המפתחים |

## 2. מטא-דאטה (עברית)

**שם (עד 30 תווים)**
```
תבל – חשבוניות
```

**כותרת משנה (עד 30 תווים)**
```
חשבונית וקבלה בשלוש נגיעות
```

**טקסט קידום (עד 170 תווים, אפשר לשנות בלי גרסה חדשה)**
```
בוחרים לקוח, "קיבלתי תשלום" או "בקש תשלום", ושולחים בווטסאפ. חשבונית מס, קבלה או חשבונית מס/קבלה יוצאות תוך שניות, עם מספור רציף ו-PDF מקורי.
```

**תיאור (עד 4,000 תווים)**
```
תבל היא הדרך המהירה להפיק חשבוניות וקבלות לעסק שלך, ישר מהאייפון.

שלוש נגיעות למסמך
בוחרים לקוח, לוחצים "קיבלתי תשלום" או "בקש תשלום", מקלידים סכום ולוחצים "הפק". סוג המסמך נבחר לבד לפי סוג העסק ולפי זה אם כבר קיבלת תשלום: חשבונית מס, חשבונית מס/קבלה, קבלה או חשבון עסקה.

שליחה ללקוח בנגיעה
שולחים ללקוח בווטסאפ קישור מאובטח למסמך, במייל או כקובץ PDF.

בקשת תשלום ב-QR
מציגים ללקוח ברקוד שמוביל לקישור התשלום של העסק, על מסמך פתוח או על סכום חופשי.

תשלומים וביטולים
רושמים תשלום על חשבונית פתוחה והקבלה נוצרת אוטומטית. מבטלים מסמך בעזרת חשבונית זיכוי, בנגיעה ועם אישור.

לקוחות
רשימה עם חיפוש, הוספה מהירה ובחירה מאנשי הקשר בלי לתת לאפליקציה גישה אליהם.

הצעות מחיר
מכינים הצעת מחיר, שולחים ללקוח והופכים אותה לחשבונית בנגיעה.

צילום הוצאות
מצלמים קבלה מספק והיא נשמרת בהוצאות של העסק.

צוות והרשאות
מזמינים עובדים, רואה חשבון או מנהל, וכל אחד רואה ועושה רק את מה שמותר לו. מסמך של עובד יכול לחכות לאישור לפני ההפקה.

דוחות
הכנסות, הוצאות, מע"מ, רווח והפסד, חובות לקוחות וכרטסת לקוח – במסך, ובשליחה למייל.

מתאים לעוסק פטור ולעוסק מורשה
לעוסק פטור לא מופיע מע"מ ולא ניתן להפיק חשבונית מס. המספור, חישוב המע"מ וקובץ ה-PDF המקורי נעשים בשרת של תבל.

מאובטח
פתיחה עם Face ID, אימות דו-שלבי לבעלי עסקים, והסתרת סכומים במסך החלפת האפליקציות.

נדרש חשבון תבל. נכנסים עם Apple או עם אימייל וסיסמה.
```

> לא לכתוב "מחובר לביט", "מספר הקצאה אוטומטי" או כל דבר שלא קיים בפועל בפרוד (הנחיה 2.3; ראו B9 בספק: SHAAM כבוי בפרוד).

**מילות מפתח (עד 100 תווים, בלי רווחים אחרי פסיק)**
```
חשבונית,קבלה,חשבונית מס,עוסק פטור,עוסק מורשה,הוצאות,QR,ווטסאפ,הנהלת חשבונות,עסק
```

**כתובות**

| שדה | כתובת |
|---|---|
| Support URL | `https://www.tevel.space/contact` (חי; `tevel.space/support` מחזיר 404) |
| Marketing URL (רשות) | `https://tevel.space` |
| Privacy Policy URL | `https://www.tevel.space/legal/privacy` (חי; `tevel.space/privacy` מחזיר 404). תנאי שימוש: `https://www.tevel.space/legal/tevel-invoice` — מסומן באתר "טיוטה", להשלים לפני ההגשה |
| מייל תמיכה (באפליקציה) | `support@tevel.space` |
| Copyright | `2026 תבל` |

**צילומי מסך:** iPhone 6.9" (1320×2868), נלקחים מהסימולטור iPhone 17 Pro Max עם נתוני הדגמה בלבד. סדר מומלץ: בית (כפתורי "קיבלתי תשלום" / "בקש תשלום"), בחירת לקוח, סכום, הצלחה ושיתוף לווטסאפ, פרטי מסמך, צוות והרשאות. בלי מסגרות שמבטיחות פיצ'רים שלא קיימים.

## 3. תווית פרטיות (App Privacy)

**האם אתם או שותפים אוספים נתונים מהאפליקציה?** כן.
**Tracking:** לא. אין SDK של פרסום או אנליטיקה ואין ATT. `NSPrivacyTracking = false`.

| סוג נתון (App Store Connect) | נאסף | מקושר למשתמש | Tracking | מטרה |
|---|---|---|---|---|
| Contact Info → Name | כן | כן | לא | App Functionality |
| Contact Info → Email Address | כן | כן | לא | App Functionality |
| Contact Info → Phone Number | כן | כן | לא | App Functionality |
| Financial Info → Other Financial Info | כן | כן | לא | App Functionality |
| User Content → Photos or Videos | כן | כן | לא | App Functionality |
| Identifiers → User ID | כן | כן | לא | App Functionality |

כל שאר הסוגים: **לא נאסף**. זה כולל מיקום, אנשי קשר (בורר המערכת מעביר רק את הרשומה שנבחרה, שנשמרת כשם וטלפון של לקוח), היסטוריית גלישה, Device ID, נתוני שימוש, אבחון וקריסות (אין דיווח קריסות ב-V2).

הערות:
- שם, אימייל וטלפון כוללים גם את פרטי הלקוחות שהעסק מזין.
- Financial Info = סכומים, מסמכים ותשלומים. אין באפליקציה כרטיסי אשראי ואין חשבונות בנק.
- Photos = צילומי קבלות הוצאה שהמשתמש בוחר לשלוח.
- User ID = מזהה המשתמש בשרת, מזהי Apple/Google (subject) לכניסה, וטוקן המכשיר שמקושר למשתמש.
- אותן קטגוריות מוצהרות ב-`ios/Runner/PrivacyInfo.xcprivacy`. אם יתווסף בעתיד Crashlytics או אנליטיקה, צריך לעדכן את שני המקומות.

**Required-reason APIs** (ב-`PrivacyInfo.xcprivacy` של האפליקציה): UserDefaults `CA92.1`, File timestamp `C617.1`. קוד Dart לא משתמש ב-system boot time או ב-disk space, ולכן אין הצהרה עליהם. לפלאגינים יש manifest משלהם (local_auth, flutter_secure_storage, google_sign_in, image_picker, share_plus, url_launcher, contact picker).

## 4. דירוג גיל

כל התשובות בשאלון הן "None" או "No": אין אלימות, תוכן מיני, עירום, גסות, סמים, אלכוהול, טבק, הימורים, אימה, נושאים רפואיים, תחרויות, תוכן גולשים בלתי מסונן, צ'אט, דפדפן חופשי או פרסום.
- **Unrestricted Web Access:** לא. אין דפדפן באפליקציה. רק שלושה דפים קבועים נפתחים ב-`SFSafariViewController` מרשימה לבנה (`lib/util/allowed_urls.dart`): פרטיות, תנאים ותמיכה (F6, AS-6). שאר הקישורים החיצוניים הם `wa.me`, `mailto:`, `tel:` והגדרות iOS (`app-settings:`, אחרי סירוב הרשאת מצלמה).
- **Parental controls / age assurance:** לא.
- **תוצאה צפויה:** 4+.

## 5. Export compliance (הצפנה)

- `ITSAppUsesNonExemptEncryption = NO` ב-`Info.plist`, כך שהשאלה לא תופיע בכל build.
- **נימוק:** האפליקציה משתמשת רק בהצפנה של מערכת ההפעלה: HTTPS/TLS, Keychain ו-Face ID. SHA-256 משמש לבדיקת שלמות של קבצים בלבד. אין אלגוריתם הצפנה קנייני ואין הצפנה שאינה פטורה. התשובה בשאלון היא "None of the algorithms mentioned above", ולא נדרש מסמך ERN או CCATS.

## 6. הערות לבודק (App Review Information)

**הקמת חשבון הסוקר (AS-10):** בשרת (ריפו invoiceproject) `scripts/seed-app-review.ts` יוצר OWNER בעסק "עוסק פטור – הדגמה" (OSEK_PATUR), שני לקוחות ו-5 מסמכים שמופקים דרך ה-API (300 שולם + קבלה 400, 300 פתוח, 300 שולם + קבלה 400). ה-MFA שלו הוא **אפליקציית אימות בלבד** (TOTP, בלי שיטת מייל), ולכן מסך ה-MFA באפליקציה נפתח ישר במצב "הקלד את הקוד מאפליקציית האימות". אין צורך בפטור MFA בשרת. הסקריפט מדפיס את האימייל, הסיסמה ו-TOTP seed, ואותם מעתיקים לבלוק למטה. בפרוד מריצים אותו רק ע"י בעל העסק בזמן ההגשה, עם `APP_REVIEW_ALLOW_PRODUCTION=yes`, `APP_REVIEW_PASSWORD` ו-`APP_REVIEW_TOTP_SECRET` מפורשים, ומול ה-API ומפתח `IDENTITY_ENC_KEY` של פרוד (`MOBILE_DEV_API`, `DATABASE_URL`). ה-seed וה-password **לא** נשמרים בריפו, רק ב-App Store Connect.


```
Sign-in (email + password):
  Email:    <APP_REVIEW_EMAIL>
  Password: <APP_REVIEW_PASSWORD>

Two-step verification: after the password the app asks for a 6-digit code.
Add this key to any authenticator app (Google Authenticator, 1Password, Apple
Passwords → "Set up verification code" → enter setup key), then enter the
6-digit code it shows:
  Setup key (TOTP, SHA1, 6 digits, 30 s): <APP_REVIEW_TOTP_SECRET>
No e-mail code is used for this account.

The account is the owner of the exempt-dealer business "עוסק פטור – הדגמה"
(Osek Patur) with two sample customers and 5 documents (3 transaction invoices,
2 receipts). All amounts are small; nothing is sent to the Israel Tax Authority.

What to try:
1. Home → "קיבלתי תשלום" (Got paid) or "בקש תשלום" (Request payment) → pick a
   customer → type an amount → "הפק" (Issue).
2. On the success screen tap WhatsApp (opens wa.me with a secure document link),
   or "QR" to show a payment request.
3. Open a document → record a payment, or cancel it (creates a credit note).
4. Tab "עסק" (Business) → "החשבון שלי" (My account) → "מחיקת חשבון" (Delete account)
   deletes the account in-app (Guideline 5.1.1(v)): re-enter the password (or confirm
   with Apple), type "מחק" and confirm. The sole owner of a business first sees a
   warning that the business will be closed. Accounting documents are retained for
   7 years as required by Israeli tax law; the user's personal login data is
   anonymized, and a Sign in with Apple grant is revoked.

Notes:
- Sign in with Apple is offered on the login screen (4.8). [Only if the build defines
  GOOGLE_IOS_CLIENT_ID and shows the Google button, add: "with the same prominence as Google".]
- Tevel subscription plans are sold through Apple In-App Purchase in iOS. The QR / "pay" link is the merchant's own
  payment page for real-world goods and services between the business and its
  customer; it does not purchase or unlock the Tevel subscription.
- Camera / photo access is only used to capture expense receipts.
- The app is in Hebrew (right-to-left).
Contact: <name>, <phone>, support@tevel.space
```

## 7. רשימת בדיקה לפני הגשה (לפי SPEC-v2 §16)

| # | הנחיה | בדיקה | סטטוס |
|---|---|---|---|
| 1 | 2.1 אפליקציה שלמה | ריצת קבלה §12 עברה בסימולטור; אין מסכי "בקרוב" | ☐ |
| 2 | 2.1 חשבון הדגמה | משתמש Review ייעודי **בפרוד** (D4, AS-10), עסק "עוסק פטור – הדגמה", 5 מסמכים, MFA אפליקציית אימות בלבד; נוצר ב-`scripts/seed-app-review.ts` (ראה סעיף 6). `demo` חסום בפרוד. **TOTP:** ה-setup key ב-Review Notes, ולפני ההגשה נבדק שקוד מאפליקציית אימות נכנס בפרוד | ☐ |
| 3 | 2.1 / 2.5 build לפרוד | ב-Release (`kReleaseMode`) ברירת המחדל בקוד היא `https://invoice.crm.tevel.space` (`lib/api/client.dart`), ולכן build לחנות לא צריך `--dart-define=API_BASE`. ב-Debug/Profile ברירת המחדל היא `http://127.0.0.1:3031` (שרת פיתוח מקומי). לא להעביר API_BASE אחר ל-build של החנות | ☐ |
| 4 | 2.1 שרת | נקודות הקצה החדשות (A–J) פרוסות בפרוד; ה-proxy מנתב `/d/*` ל-API; `APPLE_AUDIENCE=space.tevel.invoice` | ☐ |
| 5 | 2.3 מטא-דאטה | צילומי מסך אמיתיים מהסימולטור; התיאור לא מבטיח פיצ'רים שלא קיימים (ביט, מספר הקצאה בפרוד) | ☐ |
| 6 | 2.5.1 API ציבוריים | Flutter ופלאגינים רשמיים בלבד | ✔ |
| 7 | 3.1.1 IAP | iOS uses StoreKit for Tevel subscriptions; App Store Connect products, prices, restore, review visibility, Sandbox and server verification must be active and verified before submission | ☐ |
| 8 | 4.0 / 4.2 / F6 | מסכים native; אין כפתור שפותח דפדפן לפעולה עסקית (רק "המשך במחשב" ששולח קישור למייל). `SFSafariViewController` רק לפרטיות/תנאים/תמיכה; `launchUrl` רק `wa.me`/`mailto:`/`tel:`/`app-settings:` (AT-95, `test/fakes_test.dart`) | ☐ |
| 9 | 4.8 Sign in with Apple | entitlement `com.apple.developer.applesignin` ב-`Runner.entitlements` ✔; capability מופעלת ב-App ID ☐; כפתור Apple ראשון ובגודל שווה ✔ (נבדק בסימולטור); התחברות אמיתית עם Apple ID נבדקה במכשיר ☐ | ☐ |
| 10 | 4.8 / Google | אם כפתור Google מוצג: `GIDClientID` ו-URL scheme של ה-reversed client id נוספו ל-Info.plist. בלעדיהם הכפתור מוסתר (`GOOGLE_IOS_CLIENT_ID`) | ☐ |
| 11 | 5.1.1(i) פרטיות | `https://www.tevel.space/legal/privacy` חי; קישור במסך הכניסה ובהגדרות ✔; מוזן ב-App Store Connect | ☐ |
| 12 | 5.1.1(ii) הרשאות | מחרוזות בעברית ב-Info.plist ✔: מצלמה, תמונות, Face ID. **אין** הרשאת אנשי קשר ✔ | ✔ |
| 13 | 5.1.1(v) מחיקת חשבון | לשונית "עסק" → "החשבון שלי" → "מחיקת חשבון": אימות מחדש (סיסמה/Apple), הקלדת "מחק", מסך אזהרה לבעלים יחיד (§13.15, AS-3); נבדק מקצה לקצה מול השרת | ☐ |
| 13א | 5.1.1(v) / 4.8 ביטול Apple | במחיקה האפליקציה שולחת `appleAuthorizationCode` והשרת מבטל את ה-grant ב-`appleid.apple.com/auth/revoke`. בפרוד מוגדרים `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (.p8); בלעדיהם המחיקה עוברת אבל הביטול רק נרשם ביומן | ☐ |
| 14 | 5.1.2 שימוש בנתונים | תווית פרטיות לפי סעיף 3; אין ATT; `NSPrivacyTracking=false` ✔ | ☐ |
| 15 | Privacy Manifest | `ios/Runner/PrivacyInfo.xcprivacy` בשלב Copy Bundle Resources של Runner ✔ (נמצא ב-Runner.app); אחרי Archive: Xcode → Generate Privacy Report ללא אזהרות | ☐ |
| 16 | הצפנה | `ITSAppUsesNonExemptEncryption = NO` ✔ | ✔ |
| 17 | התקנים | `TARGETED_DEVICE_FAMILY = 1`, לאורך בלבד ✔, iOS 15+ ✔ | ✔ |
| 18 | ATS | `NSAllowsLocalNetworking` (localhost ו-127.0.0.1) רק ב-Debug/Profile, לשרת הפיתוח המקומי. שלב הבנייה "Strip Dev ATS (Release)" מוחק את `NSAppTransportSecurity` מה-Info.plist של Release, כך שבגרסת החנות אין חריגת ATS. אין `NSAllowsArbitraryLoads` ✔. כל ה-URLs בפרוד הם HTTPS. אחרי Archive: `plutil -p Runner.app/Info.plist` לא מציג NSAppTransportSecurity | ✔ |
| 19 | נגישות | VoiceOver בעברית על הבית ועל S4; Dynamic Type XXL בלי שבירה; ניגודיות AA | ☐ |
| 20 | יציבות | מצב טיסה בכל מסך, בלי קריסות | ☐ |
| 21 | אבטחה §11 | הטוקן ב-Keychain בלבד; overlay במסך החלפת האפליקציות; נעילת Face ID אחרי 5 דקות | ☐ |
| 22 | נכסים | אייקון 1024 בלי alpha ✔ (כל האייקונים בלי alpha); מסך פתיחה בפחם עם הלוגו ✔ | ✔ |
| 23 | גרסה | `version:` ב-pubspec עודכן (CFBundleShortVersionString / CFBundleVersion) | ☐ |
| 24 | הפצה | **לא** מעלים build ל-TestFlight או ל-App Store בלי אישור מפורש של המשתמש | ☐ |

## 8. נכסי מותג (שחזור)

האייקון, תמונת הפתיחה ו-`assets/brand/tevel_mark.png` נוצרים מהלוגו המקורי:
```
swift ios/tool/make_brand_assets.swift ~/Projects/invoiceproject*/tevelinvoicelogo.png
```
הסקריפט חותך את סמל הכוכבית הירוקה ומניח אותה על פחם `#1D1D20`. האייקונים נשמרים בלי alpha.
