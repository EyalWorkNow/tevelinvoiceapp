# רשימת מוכנות ל־Apple Review

עודכן: 5 בנובמבר 2026.

| נושא | מצב | מה נדרש |
|---|---|---|
| פרויקט iOS ב־Xcode | מוכן מקומית | `ios/Runner.xcworkspace`, scheme `Runner`. לפתוח את ה־workspace. |
| Bundle ID וחתימה | **חסום לחתימה** | `space.tevel.invoice`, Team `ARFSXMWT96`. תעודות Distribution ו־Development מקומיות תקינות; Xcode לא מחובר לחשבון, והפרופיל שנבחר אינו כולל Sign in with Apple. `-allowProvisioningUpdates` נכשל עם `No Accounts`. |
| Build version | קיים | `1.0.0+1`; להעלות build number בכל העלאה, ולבחור גרסת מוצר ב־App Store Connect. |
| App icon | קיים | לבדוק את התצוגה בגודל 1024×1024 וב־Organizer/Archive. |
| Privacy Manifest | קיים | `ios/Runner/PrivacyInfo.xcprivacy` נכלל במשאבי Runner; להשוות את ההצהרות לתלויות ולמעקב בפועל. |
| הרשאות iOS | קיימות | מצלמה, תמונות ו־Face ID כוללות הסברים בעברית; לבדוק כל הרשאה בזרימת אמת לפני שליחה. |
| Sign in with Apple | בקוד; חתימה חסומה | כפתור Apple וזרימת auth קיימים, וגם entitlement מקומי. נדרש לחבר את Xcode לחשבון, לבדוק יכולת App ID, ולחדש provisioning profile. |
| הרשמה/פתיחת עסק | חלקית בלבד | יש Sign in with Apple, כניסה באימייל/סיסמה וקבלת הזמנה. אין כפתור הרשמה עצמית; משתמש חדש ללא עסק מופנה לפתיחת העסק במחשב. סרטון לא יכול להציג פתיחת עסק בתוך האפליקציה כפי שהיא כעת. |
| מחיקת חשבון | קוד ו־API קיימים; UI עבר בדיקה ממוקדת | המסך מבקש אימות חוזר ואישור. API מבטל tokens/sessions, מסיר שיוכי משתמש, מאנונם אותו ושומר רשומות חשבונאיות; עסק שבו אין בעלים נוסף נסגר ולא נמחק. בדיקת Flutter המקומית עברה; נדרשת בדיקה מלאה בשרת production עם חשבון מחיקה נפרד. |
| פרטיות/תנאים/תמיכה | קישורים קיימים ונגישים | `https://www.tevel.space/legal/privacy`, `https://www.tevel.space/legal/tevel-invoice`, `https://www.tevel.space/contact` החזירו HTTP 200 ב־5.11.2026. לבדוק שהתוכן מעודכן, מלא ומתאים לאיסוף המידע בפועל. |
| גישה לבודק | חסום | חשבון הבדיקה המקומי אינו זמין ל־Apple. נדרשים חשבון production פעיל, עסק הדגמה עם נתונים בטוחים, ואישורי כניסה פעילים. |
| תשלום מסלול | קוד מוכן; הגדרת App Store Connect חסרה | iOS משתמש ב־StoreKit למינויי חודש. השרת מאמת JWS חתום של Apple, מקשר את המינוי לעסק, מטפל בהודעות V2 ובמניעת הפעלת מסלול על סמך בקשת לקוח בלבד. נדרשים שלושה מוצרים וקבוצת מינוי ב־App Store Connect, נקודות מחיר, App Apple ID, URL להודעות שרת, בדיקות Sandbox והפעלת מיגרציה ב־Production. Cardcom לתשלום חשבוניות לקוחות לא שונה. |
| מחיקת חשבון בודק | חסום | ליצור חשבון בדיקה שני שאפשר למחוק בלי להסיר את חשבון ההדגמה הראשי. |
| צילומי מסך | נוצרו צילומי Preview; לא סופיים לחנות | `capture-preview-screenshots.sh` מצלם את ה־UI עם Backend מדומה ובנתוני דמה. לבדוק אותם מול ה־Release המועמד ולהשלים סטים/גדלים ושפות שנדרשים ב־App Store Connect לפני העלאה. |
| סרטון הדגמה | תסריט קיים, צילום חסר | תסריט ב־`DEMO_VIDEO_SCRIPT-he.md`. לצלם עם חשבון ה־production demo לאחר יצירתו; לא להציג יצירת עסק באפליקציה. סרטון לא מחליף חשבון בודק ואינו נדרש אוטומטית. |
| App Store Connect | החשבון המחובר נבדק | Apps מציג רק “Al Jamal” ו־“Rently”; Tevel Invoice לא רשומה. Apple דורשת מבעל החשבון לקבל הסכם Developer Program מעודכן לפני חזרת גישה ל־Certificates/Identifiers/Profiles. לאחר קבלת ההסכם: ליצור/לאמת רשומת `space.tevel.invoice`, תנאי תשלום, App Privacy ומטא־דאטה. |
| בדיקות לפני שליחה | נדרש | בדיקת התקנה נקייה על מכשיר פיזי, כניסה/יציאה, רכישה/שחזור, מחיקת חשבון, הרשאות, קישורים, שגיאות רשת, ו־VoiceOver. |

## בדיקות תשלום קריטיות

בקוד קיימים שלושה מסלולים שנרכשים ב־iOS דרך StoreKit. חריג Enterprise Services 3.1.3(c) אינו מתאים למכירה לבעל עסק יחיד; רכישת המינוי הדיגיטלי מחויבת דרך IAP כברירת מחדל. השרת מאמת עסקאות והודעות שרת V2. מינויי Cardcom אינם זמינים לרכישה מתוך iOS; סליקת חשבוניות של לקוחות העסק נשארת מוצר נפרד. נדרשת הקמת מוצרי IAP ובדיקת Sandbox לפני שימוש אמיתי. אלה מסקנות מהנחיות Apple ומהמודל שנמצא בקוד, לא ייעוץ משפטי.

הנחיות Apple הרלוונטיות: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (2.1, 3.1.1, 3.1.3(c), 5.1.1(v)); [Payment options in the EU](https://developer.apple.com/support/payment-options-on-the-app-store-in-the-eu/); [External Purchase regions and entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.storekit.custom-purchase-link.allowed-regions); [Sign in with Apple capability](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/); [Complete Review Information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/).
