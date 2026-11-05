# דוח מוכנות ל־App Store — Tevel Invoice

נבדק: 5 בנובמבר 2026. לא בוצעה העלאה או הגשה ל־Apple.

| נושא | סטטוס | ממצא / פעולה שנותרה |
|---|---|---|
| App Store Connect | נבדק בחשבון המחובר | בעל החשבון מחובר. ברשימת Apps מופיעות “Al Jamal” ו־“Rently”; Tevel Invoice אינה רשומה. Apple מציגה הסכם Apple Developer Program מעודכן הממתין לקבלת בעל החשבון, וחוסמת עד אז גישה ל־Certificates, Identifiers & Profiles. לא נוצרה רשומה חדשה ולא אושר ההסכם בשמו. |
| Bundle ID ו־Team ID | מוגדרים בפרויקט | `space.tevel.invoice` / `ARFSXMWT96`; יעד iOS 15.0; גרסה `1.0.0 (1)`. תעודות Apple Development ו־Distribution נמצאו מקומית. |
| Sign in with Apple | בשימוש; חתימה חסומה | כפתור וזרימת Apple קיימים בקוד. Entitlement קיים. Archive חתום נכשל כי Xcode אינו מחובר לחשבון והפרופיל המקומי אינו כולל entitlement. להתחבר ב־Xcode ולחדש profile עם capability. |
| מינוי iOS ומדיניות תשלום | קוד IAP ושרת מוכנים; App Store Connect נדרש | מסלולי Tevel באפליקציית iOS משתמשים ב־StoreKit, עם מחיר מהחנות, אימות JWS בשרת, שיוך לעסק, שחזור רכישה והודעות שרת V2 לחידוש/ביטול/החזר. נקבעו שלושה מזהי מוצר לפי המסלולים שקיימים בקוד. נדרשים יצירת המוצרים, קבוצת המינויים, נקודות המחיר ו־App Apple ID ב־App Store Connect. חיבור Cardcom לא בוצע; תשלום לקוח עבור חשבונית העסק נשאר זרימה נפרדת. |
| חשבונות בדיקה | חסומים לסביבת production | קובצי login הקיימים מיועדים לשרת פיתוח מקומי. נדרשים חשבון הדגמה קבוע וחשבון מחיקה נפרד ב־production. אין גישה מאושרת ליצור משתמשים בסביבת הייצור. |
| הרשמה/פתיחת חשבון | חלקית | Apple sign-in, אימייל/סיסמה וקבלת הזמנה קיימים. אין כפתור הרשמה עצמית; חשבון חדש ללא עסק מתבקש להמשיך במחשב כדי לפתוח עסק. |
| מחיקת חשבון | קוד קיים; בדיקת UI ממוקדת עברה | ההגדרה נגישה בפרופיל/הגדרות. API דורש אימות חוזר ואישור, מבטל sessions/tokens, מסיר אמצעי אימות ומאנונם את המשתמש. מסמכים חשבונאיים נשמרים; עסק ללא בעלים נוסף נסגר, לא נמחק. צריך לאמת מול חשבון מחיקה ייעודי ב־production ולוודא נוסח/תקופת שמירת מידע עם הייעוץ המקצועי שלכם. |
| סרטון הדגמה | תסריט קיים; צילום production חסר | יש לצלם אחרי יצירת demo account. אל תציגו פתיחת עסק בתוך האפליקציה; מסלול זה מופנה למחשב. |
| מטא־דאטה עברית/אנגלית | טיוטות מוכנות | `APP_STORE_METADATA-he.md`, `APP_STORE_METADATA-en.md`. נדרשים אישור מוצר, דירוג גיל, App Privacy, זכויות תוכן, ופרטי קשר/תמיכה מאומתים ב־Connect. |
| צילומי מסך | 10 צילומי Preview אמיתיים מסימולטור | PNG נשמרו תחת `screenshots/`, iPhone 17 Pro Max ‏1320×2868, Hebrew, backend מדומה ונתוני דמה. לא הוכנו צילומי Release באנגלית. יש לאמת זכויות לתמונות פרופיל ולבצע בדיקה מול Release סופי לפני העלאה. |
| Archive | Release לא חתום עבר | `xcodebuild archive` עבר אחרי הוספת StoreKit; `apple-review/build/Tevel.xcarchive` כולל את הקוד העדכני, אך נבנה עם `CODE_SIGNING_ALLOWED=NO` ולכן אינו מתאים להתקנה/הפצה. Archive חתום עדיין חסום: Xcode `No Accounts` וה־profile המקומי חסר Sign in with Apple. |
| IPA | לא נוצר | נדרש Archive חתום ו־Provisioning Profile עדכני. לא בוצעה העלאה. |

## אימותים שבוצעו

- Xcode `Runner.xcworkspace` נפתח מהנתיב של הפרויקט הנוכחי.
- `xcodebuild archive` ללא חתימה: `ARCHIVE SUCCEEDED`.
- `xcodebuild archive -allowProvisioningUpdates`: נכשל עם `No Accounts` וגם profile חסר Sign in with Apple.
- `flutter test test/business/delete_account_test.dart`: כל הבדיקות עברו.
- `flutter analyze --no-pub`: נקי לאחר חיבור StoreKit; בדיקות Commerce ומחיקת חשבון ממוקדות: 14/14 עברו.
- בדיקות API ממוקדות למינוי Apple, Commerce והגדרות Production: 52/52 עברו; TypeScript API עבר `tsc --noEmit`.
- מיגרציה `0090_apple_iap.sql` וכל 90 המיגרציות הוחלו בהצלחה על מסד זמני נקי. המסד הזמני נמחק לאחר הבדיקה.
- `flutter build ios --release --no-codesign`: עבר; Xcode כלל את `in_app_purchase_storekit`.
- `xcodebuild archive ... CODE_SIGNING_ALLOWED=NO`: `ARCHIVE SUCCEEDED`; זה Archive בלתי חתום.
- `flutter test -d <iPhone 17 Pro Max> integration_test/design_preview_test.dart`: עבר; צילם מסכי home, customer, compose, people, management, reports, desktop handoff ו־request.
- בדיקת API `apps/api/test/mobile-auth.int.test.ts`: ‏16/16 עברו במסד זמני חדש לאחר החלת 87 migrations; מסד הבדיקה הזמני נמחק בסיום.
- ניסיון מקדים מול `invoice_test_phase1` נכשל בגלל סכימה מקומית ישנה (`membership_grants_for_user` חסרה ועמודת `i.permissions` חסרה). המסד הקיים לא אופס; בדיקת אינטגרציה יכולה להשאיר בו נתוני fixture זמניים.
- `git diff --check`: עבר.
- `plutil -lint`: עבר ל־Info.plist, PrivacyInfo.xcprivacy, entitlements ו־ExportOptions.
- כתובות privacy, terms ותמיכה החזירו HTTP 200 בבדיקת 5.11.2026.

## מקורות Apple

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 2.1, 3.1.1, 3.1.3(c), 5.1.1(v).
- [Payment options on the App Store in the EU](https://developer.apple.com/support/payment-options-on-the-app-store-in-the-eu/) — אפשרויות תשלום חיצוני לפי אזור ו־entitlement.
- [External purchase entitlement regions](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.storekit.custom-purchase-link.allowed-regions) — רשימת אזורים מותרים.
- [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/) — נדרש Account Holder או Admin כדי לשנות App ID capabilities.
- [Complete Review Information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) — חשבון הדגמה פעיל ופרטי גישה לבודקים.
