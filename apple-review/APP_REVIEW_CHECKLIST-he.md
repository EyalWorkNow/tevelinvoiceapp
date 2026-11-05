# רשימת מוכנות ל־Apple Review

עודכן: 5 בנובמבר 2026.

| נושא | מצב | מה נדרש |
|---|---|---|
| פרויקט iOS ב־Xcode | מוכן מקומית | `ios/Runner.xcworkspace`, scheme `Runner`. לפתוח את ה־workspace. |
| Bundle ID וחתימה | **מוכן; IPA חתום נבנה** | `space.tevel.invoice`, Team `ARFSXMWT96`. ב־5.11 ה־IPA נבנה בהצלחה ונחתם בתעודת Apple Distribution של הצוות. ה־entitlement של Sign in with Apple נכלל בחתימה. |
| Build version | קיים | `1.0.0+1`; להעלות build number בכל העלאה, ולבחור גרסת מוצר ב־App Store Connect. |
| App icon | קיים | לבדוק את התצוגה בגודל 1024×1024 וב־Organizer/Archive. |
| Privacy Manifest | קיים | `ios/Runner/PrivacyInfo.xcprivacy` נכלל במשאבי Runner; להשוות את ההצהרות לתלויות ולמעקב בפועל. |
| הרשאות iOS | קיימות | מצלמה, תמונות ו־Face ID כוללות הסברים בעברית; לבדוק כל הרשאה בזרימת אמת לפני שליחה. |
| Sign in with Apple | בקוד וב־IPA החתום | כפתור Apple וזרימת auth קיימים. נבדק כי ה־IPA החתום כולל entitlement `com.apple.developer.applesignin = Default`. נותר לבדוק את הכניסה מול Production/Test account. |
| הרשמה/פתיחת עסק | חלקית בלבד | יש Sign in with Apple, כניסה באימייל/סיסמה וקבלת הזמנה. אין כפתור הרשמה עצמית; משתמש חדש ללא עסק מופנה לפתיחת העסק במחשב. סרטון לא יכול להציג פתיחת עסק בתוך האפליקציה כפי שהיא כעת. |
| מחיקת חשבון | קוד ו־API קיימים; UI עבר בדיקה ממוקדת | המסך מבקש אימות חוזר ואישור. API מבטל tokens/sessions, מסיר שיוכי משתמש, מאנונם אותו ושומר רשומות חשבונאיות; עסק שבו אין בעלים נוסף נסגר ולא נמחק. בדיקת Flutter המקומית עברה; נדרשת בדיקה מלאה בשרת production עם חשבון מחיקה נפרד. |
| פרטיות/תנאים/תמיכה | תנאים ותמיכה נגישים; פרטיות האפליקציה חסרה | שלושת הקישורים החזירו HTTP 200 ב־5.11.2026, אך תוכן מדיניות הפרטיות הקיים מכסה בעיקר לידים/CRM ואינו מתאר מספיק את אפליקציית החשבוניות. נדרשת מדיניות ייעודית לפני קישור/פרסום. |
| גישה לבודק | חסום | חשבון הבדיקה המקומי אינו זמין ל־Apple. נדרשים חשבון production פעיל, עסק הדגמה עם נתונים בטוחים, ואישורי כניסה פעילים. |
| תשלום מסלול | שלושה מוצרים נשמרו; חיבור production חסר | קבוצת `Tevel Monthly Plans` (ID ‏`22549611`) מכילה שלושה מוצרים חודשיים ולוקליזציות עבריות. מחירי Apple בישראל הם ₪7.90, ₪9.90 ו־₪14.90 (נקודות המחיר הקרובות ל־₪8/10/15). שלושת המוצרים במצב `Prepare for Submission`; הסדר הנוכחי מתחילים→צמיחה→ללא הגבלה ויש להפוך לפי מדרג השירות. ניסיון עריכה דרך הדפדפן לא פעל. יש לוודא זמינות ישראל לכל מוצר, להגדיר Server Notifications, `APPLE_APP_ID`, מיגרציה ובדיקות Sandbox. Cardcom לתשלום חשבוניות לקוחות לא שונה. |
| מחיקת חשבון בודק | חסום | ליצור חשבון בדיקה שני שאפשר למחוק בלי להסיר את חשבון ההדגמה הראשי. |
| צילומי מסך | חסרים ב־ASC | מסך App Store Connect מציג 0/10. יש להפיק צילומי מסך נקיים מתוך Release בגודל נתמך (למשל 1206×2622) ולוודא שאין פרטי לקוח אמיתיים. |
| סרטון הדגמה | תסריט קיים, צילום חסר | תסריט ב־`DEMO_VIDEO_SCRIPT-he.md`. לצלם עם חשבון ה־production demo לאחר יצירתו; לא להציג יצירת עסק באפליקציה. סרטון לא מחליף חשבון בודק ואינו נדרש אוטומטית. |
| App Store Connect | הרשומה אומתה; מטא־דאטה ראשונית נשמרה | ברשומה `6831079441` מאומתים `תבל עסקים`, Bundle ID ‏`space.tevel.invoice`, SKU ‏`tevel-invoice-ios`, שפה עברית, קטגוריית Business ודירוג 4+. נשמרו כותרת משנה, תיאור, טקסט קידום, מילות מפתח, Support URL, Marketing URL וזכויות יוצרים `2026 Tevel`. ההתחברות פעילה; לא הועלה build ולא נשלחה גרסה לבדיקה. |
| קבוצת מינויים | נוצרה; מוצרים נשמרו | נוצרה הקבוצה `Tevel Monthly Plans`, מזהה `22549611`, ושלושה מוצרים עם תמחור ולוקליזציה בעברית. Apple מציינת שהקבוצה הראשונה מוגשת יחד עם גרסת האפליקציה. |
| App Privacy | חסום לתיקון הצהרה | App Store Connect עדיין מציג `Data Not Collected`, שאינו נכון לאפליקציה שמקבלת ושומרת חשבונות, פרטי לקוחות, מסמכים והוצאות בשרת. מדיניות הפרטיות הקיימת ב־`/legal/privacy` מתארת בעיקר פניות לאתר/CRM ולא את האפליקציה; יש לפרסם מדיניות ייעודית ומדויקת ולהצהיר על סוגי המידע לפי הזרימות וה־SDKs לפני Publish. |
| Content Rights ו־DSA | ממתין לפרטים אמיתיים | הצהרת זכויות לתוכן של לקוחות לא נבחרה. רשומת DSA מציגה כרגע Non-Trader; אם המפתח מציע שירות מסחרי באזורי האיחוד, יש לעדכן פרטי סוחר/איש קשר אמיתיים דרך בעל החשבון. אין להצהיר בשם העסק ללא אימות הנתונים. |
| בדיקות לפני שליחה | נדרש | בדיקת התקנה נקייה על מכשיר פיזי, כניסה/יציאה, רכישה/שחזור, מחיקת חשבון, הרשאות, קישורים, שגיאות רשת, ו־VoiceOver. |

## Build חתום — 5 בנובמבר 2026

- `xcodebuild -list -workspace ios/Runner.xcworkspace`: הצליח; scheme ‏`Runner`, Bundle ID ‏`space.tevel.invoice`, Team ‏`ARFSXMWT96`, יעד iOS ‏15.0.
- `security find-identity -v -p codesigning`: נמצאו תעודות Apple Development ו־Apple Distribution תקינות.
- אחרי פתיחת `ios/Runner.xcworkspace` הנכון, `flutter build ipa --release --export-options-plist=apple-review/ExportOptions.plist --build-name=1.0 --build-number=1` הצליח.
- נוצר `build/ios/ipa/תבל.ipa` (24.9MB), גרסה `1.0.0`, build ‏`1`, Bundle ID ‏`space.tevel.invoice`.
- `codesign -dv --verbose=2` אימת חתימה `Apple Distribution: Eyal Atiya (ARFSXMWT96)`; בדיקת entitlements אישרה `com.apple.developer.applesignin = Default` ו־`get-task-allow = false`.
- לא בוצעה העלאה ל־App Store Connect. להעלאה נוספת יש להעלות את Build Number.

## בדיקות תשלום קריטיות

בקוד קיימים שלושה מסלולים שנרכשים ב־iOS דרך StoreKit. חריג Enterprise Services 3.1.3(c) אינו מתאים למכירה לבעל עסק יחיד; רכישת המינוי הדיגיטלי מחויבת דרך IAP כברירת מחדל. השרת מאמת עסקאות והודעות שרת V2. מינויי Cardcom אינם זמינים לרכישה מתוך iOS; סליקת חשבוניות של לקוחות העסק נשארת מוצר נפרד. נדרשת הקמת מוצרי IAP ובדיקת Sandbox לפני שימוש אמיתי. אלה מסקנות מהנחיות Apple ומהמודל שנמצא בקוד, לא ייעוץ משפטי.

הנחיות Apple הרלוונטיות: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (2.1, 3.1.1, 3.1.3(c), 5.1.1(v)); [Payment options in the EU](https://developer.apple.com/support/payment-options-on-the-app-store-in-the-eu/); [External Purchase regions and entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.storekit.custom-purchase-link.allowed-regions); [Sign in with Apple capability](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/); [Complete Review Information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/).
