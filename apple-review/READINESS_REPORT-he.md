# דוח מוכנות ל־App Store — Tevel Invoice

נבדק: 5 בנובמבר 2026. IPA הועלה ל־App Store Connect דרך Transporter; גרסה לא הוגשה ל־Review.

| נושא | סטטוס | ממצא / פעולה שנותרה |
|---|---|---|
| App Store Connect | הרשומה אומתה; מטא־דאטה ראשונית נשמרה | ברשומה `6831079441` מאומתים `תבל עסקים`, Bundle ID ‏`space.tevel.invoice`, SKU ‏`tevel-invoice-ios`, עברית, קטגוריית Business ודירוג 4+. נשמרו כותרת משנה, תיאור, טקסט קידום, מילות מפתח, Support URL, Marketing URL וזכויות יוצרים `2026 Tevel`. build ‏1.0.0 (1) הועלה וממתין לעיבוד; לא נשלחה גרסה לבדיקה. |
| Bundle ID ו־Team ID | חתימת IPA הצליחה | `space.tevel.invoice` / `ARFSXMWT96`; יעד iOS 15.0; גרסה `1.0.0 (1)`. ה־IPA נחתם ב־Apple Distribution של הצוות וכולל Sign in with Apple entitlement. |
| Sign in with Apple | חתום ב־IPA | כפתור וזרימת Apple קיימים בקוד. בדיקת IPA אישרה `com.apple.developer.applesignin = Default`; נדרשת בדיקת התחברות מול סביבת Production עם משתמש בדיקה. |
| מינוי iOS ומדיניות תשלום | שלושה מוצרים ומחירים נשמרו ב־ASC; אינטגרציית production חסרה | בקבוצה `Tevel Monthly Plans` (ID ‏`22549611`) נוצרו המוצרים החודשיים עם לוקליזציות בעברית: עד 21 מסמכים ב־₪7.90, עד 30 ב־₪9.90, וללא הגבלה ב־₪14.90. אלו מדרגות Apple הקרובות למחירים 8/10/15 ₪ שנקבעו, מאחר שלא היו נקודות מחיר מדויקות. שלושת המוצרים במצב `Prepare for Submission`; סדר הרמות הנוכחי בסיסי→צמיחה→ללא הגבלה ואינו תואם להמלצת ASC לסדר יורד לפי רמת השירות. פתיחת העריכה דרך חיבור הדפדפן לא פעלה. נותרו אימות זמינות ישראל לכל מוצר, Server Notifications, `APPLE_APP_ID` ובדיקות Sandbox בשרת. חיבור Cardcom לא בוצע. |
| חשבונות בדיקה | חסומים לסביבת production | קובצי login הקיימים מיועדים לשרת פיתוח מקומי. נדרשים חשבון הדגמה קבוע וחשבון מחיקה נפרד ב־production. אין גישה מאושרת ליצור משתמשים בסביבת הייצור. |
| הרשמה/פתיחת חשבון | חלקית | Apple sign-in, אימייל/סיסמה וקבלת הזמנה קיימים. אין כפתור הרשמה עצמית; חשבון חדש ללא עסק מתבקש להמשיך במחשב כדי לפתוח עסק. |
| מחיקת חשבון | קוד קיים; בדיקת UI ממוקדת עברה | ההגדרה נגישה בפרופיל/הגדרות. API דורש אימות חוזר ואישור, מבטל sessions/tokens, מסיר אמצעי אימות ומאנונם את המשתמש. מסמכים חשבונאיים נשמרים; עסק ללא בעלים נוסף נסגר, לא נמחק. צריך לאמת מול חשבון מחיקה ייעודי ב־production ולוודא נוסח/תקופת שמירת מידע עם הייעוץ המקצועי שלכם. |
| סרטון הדגמה | תסריט קיים; צילום production חסר | יש לצלם אחרי יצירת demo account. אל תציגו פתיחת עסק בתוך האפליקציה; מסלול זה מופנה למחשב. |
| App Privacy ומדיניות | חסום להצהרה מדויקת | כרגע App Store Connect מציג `Data Not Collected`, אף שהאפליקציה שולחת ושומרת פרטי חשבון, לקוחות, הוצאות ומסמכים בשרת. דף הפרטיות הקיים מתאר בעיקר לידים/CRM ולא את אפליקציית החשבוניות. יש להכין מדיניות ייעודית, לאמת קטגוריות מול ה־SDKs והשרת, ורק אז לפרסם הצהרה. |
| Content Rights ו־DSA | חסרים אימות/פרטי עסק | שאלת זכויות לתוכן לקוחות לא הושלמה; סטטוס DSA כרגע Non-Trader. נדרש אימות מעמד העסק ופרטי קשר/סוחר אמיתיים לפני שינוי. |
| מטא־דאטה עברית/אנגלית | עברית הוזנה; צילומי מסך חסרים | העברית נשמרה ונבדקה בעמוד הגרסה. אין צילומי מסך ב־App Store Connect (0/10 ל־iPhone), ואין קובצי Preview בתיקיית `apple-review/screenshots/` מעבר להנחיות. יש לצלם מתוך Release עדכני. |
| צילומי מסך | חסרים להעלאה | ASC מציג 0/10 צילומי מסך למכשיר iPhone עם Dynamic Island. דורש רזולוציה נתמכת כגון 1206×2622 או 1179×2556. |
| Archive | נוצר בחתימה אוטומטית | `build/ios/archive/Runner.xcarchive` נוצר ב־5.11 מה־workspace הנכון כחלק מבניית IPA חתום. |
| IPA | **נוצר ונבדק מקומית** | `build/ios/ipa/תבל.ipa`, ‏24.9MB, גרסה `1.0.0 (1)`. `codesign` אימת Apple Distribution של `ARFSXMWT96`, Bundle ID נכון ו־Sign in with Apple entitlement. הועלה ב־Transporter; המצב שנצפה הוא Processing. טרם אומת עיבוד מלא ב־App Store Connect. |
| גישת App Store Connect | פעילה | הרשומה וקבוצת המינויים נפתחו בחשבון המחובר; copyright נשמר כ־`2026 Tevel`. |

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
- `xcodebuild -list -workspace ios/Runner.xcworkspace`: עבר; זוהו scheme ‏`Runner` ו־Bundle ID ‏`space.tevel.invoice`.
- `security find-identity -v -p codesigning`: נמצאו תעודות Apple Development ו־Apple Distribution תקינות.
- `flutter build ipa --release --export-options-plist=apple-review/ExportOptions.plist --build-name=1.0 --build-number=1`: עבר; נוצר IPA חתום.
- `codesign -dv --verbose=2` ו־`codesign -d --entitlements :-`: אומתו זהות החותם, Bundle ID וה־entitlements של ההפצה ושל Sign in with Apple.
- `plutil -lint`: עבר ל־Info.plist, PrivacyInfo.xcprivacy, entitlements ו־ExportOptions.
- כתובות privacy, terms ותמיכה החזירו HTTP 200 בבדיקת 5.11.2026.

## מקורות Apple

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 2.1, 3.1.1, 3.1.3(c), 5.1.1(v).
- [Payment options on the App Store in the EU](https://developer.apple.com/support/payment-options-on-the-app-store-in-the-eu/) — אפשרויות תשלום חיצוני לפי אזור ו־entitlement.
- [External purchase entitlement regions](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.storekit.custom-purchase-link.allowed-regions) — רשימת אזורים מותרים.
- [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/) — נדרש Account Holder או Admin כדי לשנות App ID capabilities.
- [Complete Review Information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) — חשבון הדגמה פעיל ופרטי גישה לבודקים.
