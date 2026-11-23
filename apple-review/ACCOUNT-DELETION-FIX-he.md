# תיקון מחיקת חשבון - 19.11.2026

## התקלה ששוחזרה

חשבון המקושר דרך app_metadata.tevel_user_id ב-Supabase יכול להתחבר בלי ערך users.supabase_subject. מסלול המחיקה הישן דרש את הערך הזה, ולכן דחה גם סיסמה תקינה עם REAUTH_FAILED. מסך iOS גם המשיך להציע או לדרוש Apple לפי סימון ישן ב-Keychain, למרות ש-build 20 משתמש בכניסה עם סיסמה.

## התיקון

- שרת: אימות סיסמה דרך Supabase והכרעת הבעלות לפי אותו סדר קישורים המשמש בכניסה: קישור מפעיל מאומת, ובהיעדרו קישור subject שנשמר בשרת. אין קישור לפי אימייל או user_metadata. סיסמה מקומית ישנה אינה מתקבלת בחשבון שמסומן כמנוהל על ידי Supabase. חיבור האימות הזמני נסגר.
- אפליקציה: מחיקה עם סיסמת הכניסה ואישור "מחק", ללא Apple וללא תלות בסימון מהתקנה ישנה. נוסף כפתור הצגה/הסתרה של סיסמה ונעילה בזמן הבקשה. אזהרת הבעלים ושמירת המסמכים נשארו.
- חוזה REST לא השתנה. בשרת נשמרה תאימות לבקשות מגרסאות ישנות.

## קוד לביקורת

- שרת: https://github.com/EyalWorkNow/invoice/pull/69 ; worktree: /Users/eyalatiya/Projects/inv-wt/delete-account-fix ; commit: 8e59112.
- אפליקציה: https://github.com/EyalWorkNow/tevelinvoiceapp/pull/40 ; worktree: /Users/eyalatiya/Projects/tim-wt/delete-account-fix ; commit: d88f0ec, על בסיס release 1.0.0 (20).

## אימות שבוצע

- לפני התיקון: בדיקת חשבון מקושר מפעיל עם סיסמה תקינה קיבלה 403 במקום 200.
- לאחר התיקון: 10 תרחישי מחיקה במסד מקומי מבודד invoice_test_delete_20261119 עברו, כולל קישור מפעיל ללא סימון provider מקומי, קישור subject, דחיית זהות אחרת/לא מאושרת/metadata בשליטת משתמש, סיסמה ישנה, תקלת ספק וביטול bearer אחרי מחיקה.
- 21 בדיקות אינטגרציה קיימות של mobile-auth ו-Supabase-auth ו-22 בדיקות יחידה של Supabase עברו; 25 בדיקות אפליקציה ממוקדות עברו.
- ניתוח Flutter מלא, בדיקות TypeScript ל-API ולבדיקות, build של API, ESLint ועיצוב הקבצים עברו. הבדיקות הרחבות ויצירת מועמד build חדש מתועדות בנפרד כשיסתיימו.

## לפני צילום מחיקה והגשה

נכון להכנת מסמך זה, התיקון לא מוזג ולא נפרס, ו-build חדש לא הועלה ל-TestFlight. השרת הציבורי /version נבדק ועדיין דיווח 6a80fd6. אין להסיק מבדיקות מקומיות שהחשבון בטלפון כבר ניתן למחיקה. לא נמחק חשבון לקוח אמיתי. אחרי הפריסה יש לבדוק על חומרה פיזית עם חשבון חד-פעמי המיועד למחיקה, ולהשתמש בגרסת האפליקציה המעודכנת כדי לצלם מסך ללא Apple.

## סיום בדיקות ואריזת מועמד

- סבב Flutter מלא: 1415 עברו, 2 דולגו, כשל יחיד בכלל תוויות הכפתורים (AT-92). תוקן לשימוש ב-AuthHe.showPassword / hidePassword. בהרצה חוזרת של spec_lint, מחיקה, settings ו-auth עברו כל 32 הבדיקות. ניתוח Flutter מלא לאחר התיקון עבר.
- נבנה IPA חתום לגרסה 1.0.0 (21), תוך שימור הגדרות API/Auth של build 20. מספר הגרסה, Bundle ID וחתימת קובץ ה-IPA המיוצא אומתו.
- קובץ: /Users/eyalatiya/Projects/tim-wt/delete-account-fix/build/ios/ipa/תבל.ipa
- SHA-256: ce65cdf5998449835cdd00b2a06dbb3d29f3373a262fdd80fa40ce8906c875d4
- מניפסט: /Users/eyalatiya/Projects/tim-wt/delete-account-fix/apple-review/ACCOUNT-DELETION-CANDIDATE.json
- CI של PR השרת עדיין רץ בעת כתיבת העדכון; בדיקות security ו-preview עברו. יש להמתין להצלחת שער ה-CI לפני מיזוג/פריסה.
