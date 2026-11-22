# מצב הכנה להגשה — 19.11.2026

- בילד 1.0.0 (23) נבנה, נחתם, נמסר ל־Apple, עובד, זמין ב־TestFlight ונבחר לגרסה 1.0. בעל האפליקציה אישר שבדיקת המכשיר עברה.
- שרת 1184103 פעיל: PAID_FEATURES_ENABLED=0, BILLING_ENFORCE=0. אכיפת מינוי כבויה, רכישות Apple ו־Cardcom אינן זמינות. לא נמצאו מינויים של Apple/Cardcom; רק מינויים ללא חיוב (COMP).
- הבילד מסתיר כפתור מסלול ומדלג על מסכי המינוי בכניסה ובפתיחת האפליקציה. תיקון מחיקת החשבון כלול.
- שני הסרטונים צורפו ל־App Review כ־TEVEL-APP-REVIEW-EVIDENCE.zip. המקור נשמר בהורדות.
- נוצר חשבון סקירה חדש בכתובת הבדיקה הקיימת, עם עסק ולקוח פיקטיביים בלבד. פרטי הכניסה נשמרו ב־App Store Connect. כניסה ראשית, כניסת API, הנפקת אסימון, פרופיל ולקוחות נבדקו בהצלחה; אסימוני הבדיקה הזמניים בוטלו. ההחרגה הקיימת של חשבון הסקירה לא שונתה ולא הורחבה.
- שש פסקאות תשובה ל־2.1 נשמרו ב־Notes; הוצהר במפורש שאין מצורפת תעודת רישום תוכנה ולא נטען לאישור ממשלתי. בעל האפליקציה הבהיר שרשום בשע״ם בלבד.
- שאלות דירוג הגיל החדשות הושלמו: ללא שיתוף מיקום וללא היכרויות.

## שינויים וקבצים

קוד האפליקציה והשרת מוזג:
- https://github.com/EyalWorkNow/tevelinvoiceapp/pull/40
- https://github.com/EyalWorkNow/invoice/pull/73

פרטי הבילד והחתימה ב־FREE-RELEASE-CANDIDATE.json. חומרי הסקירה ב־RESUBMISSION-2.1-FREE-RELEASE-en.md וב־review-evidence/.

## אימות

- Flutter analyze: עבר; 20 בדיקות ממוקדות עברו, ובדיקת מצב חינמי נפרדת עברה.
- בדיקות שרת מלאות מקומית: פורמט, lint, build, typecheck, 732 בדיקות יחידה ו־4047 בדיקות אינטגרציה, בדיקות גבולות רגולטוריים ומקורות, חוזה SHAAM — עברו. בדיקות עם skip/expected-fail נותרו במצבן המקורי.
- GitHub Actions לא התחיל בגלל מגבלת חיוב בחשבון; זו אינה תוצאת בדיקות הקוד. הבדיקות הורצו מקומית.
- פריסה: גיבוי מוצפן ושחזור בדיקה, בדיקות preflight/postflight, ready/version ו־smoke עברו. worker הופעל מחדש לאחר שאומת שהתור ריק.

## נותר

ההגשה נשלחה מחדש ב־19.11.2026 בשעה 21:12 (ישראל), לאחר אישור מפורש להגיש עם שחרור ידני. נצפה ב־App Store Connect סטטוס Waiting for Review עבור 1.0.0 (23). שחרור ידני נשמר לפני ההגשה, ולכן אישור הסקירה לא יפרסם לציבור באופן אוטומטי.

מגבלות ידועות: אין תעודת רישום תוכנה מאומתת; רישום בשע״ם אינו מוכיח רישום במרשם התוכנות. המכשיר והסרטונים על iOS 26.7.3, בעוד Apple מפרסמת iOS 27.2.1 כגרסה העדכנית ובבקשתה ביקשה הקלטה על מערכת עדכנית. הפער נמסר למשתמש לפני השליחה; לא נטען בהגשה שנבדקה מערכת 27.2.1. ייתכן שתידרש השלמת סרטון או מסמך. אין להסיק מאישור Apple אישור רגולטורי בישראל.

מקורות: https://support.apple.com/en-us/100100 ; https://www.gov.il/en/service/registration-software-designed-managing-computerized-accounting-system

קישור להגשה: https://appstoreconnect.apple.com/apps/6831079441/distribution/reviewsubmissions/details/8c89d24a-0874-4720-8712-6eec115627f1

## קובצי קוד ששונו

אפליקציה (worktree: /Users/eyalatiya/Projects/tim-wt/delete-account-fix):
- lib/screens/business/delete_account_screen.dart
- test/business/delete_account_test.dart
- lib/api/environment.dart
- lib/app_shell.dart
- lib/screens/auth/auth_flow.dart
- lib/screens/billing/billing_screen.dart
- lib/screens/billing/plan_gate.dart
- lib/screens/profile/profile_settings_screen.dart
- test/billing/free_release_test.dart
- tool/build_release.dart
- pubspec.yaml

שרת (worktree: /Users/eyalatiya/Projects/inv-wt/free-release):
- .env.example
- apps/api/src/commerce/apple-iap.ts
- apps/api/src/commerce/cardcom.ts
- packages/postgres/src/subscription-quota.ts
- apps/api/test/apple-iap.unit.test.ts
- apps/api/test/commerce.unit.test.ts
- apps/api/test/commerce.int.test.ts

לא נוספו תלויות ולא שונה מבנה מסד הנתונים.
