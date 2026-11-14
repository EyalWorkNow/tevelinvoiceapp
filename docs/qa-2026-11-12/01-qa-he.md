# דוח QA – tevel-invoice-mobile (12.11.2026)

מצב הקוד שנבדק: `main` (cad0a43) **כולל** working tree גדול שלא נעשה לו commit (Supabase auth, CRM לקוחות, התראות notch, ~70 קבצים ששונו). שום קובץ פרויקט לא שונה בבדיקה.
הקוד אונדקס ב-codebase-memory (פרויקט `Users-eyalatiya-Projects-tevel-invoice-mobile`, 4,244 צמתים).

## 1. בדיקות אוטומטיות

| בדיקה | תוצאה |
|---|---|
| `flutter analyze` | ✅ ללא שגיאות |
| `flutter test` (יחידה + widget) | ❌ 786 עברו, 2 דולגו, **6 נכשלו** |
| `dart format --set-exit-if-changed` | ❌ 135 מתוך 244 קבצים לא מפורמטים |
| אינטגרציה בסימולטור (iPhone 17 Pro, API :3031) | ❌ **gate 0/12, compose 0/8**; שאר הסוויטות נעצרו כי הכשל זהה |

### כשלי יחידה
1. **4 golden – `intent_button_*`** (`test/golden/ds_golden_test.dart`): גודל התמונה השתנה (155→149px). או שזה שינוי עיצוב מכוון וצריך `--update-goldens`, או שזה באג פריסה.
2. **AT-92 – 7 מחרוזות עברית בכפתורים מחוץ ל-`lib/util/labels/`**: `contacts_permission.dart:28,32`, `doc_rows.dart:78,102,106`, `cardcom_merchant_screen.dart:548`, `billing_screen.dart:388`.
3. **J8 הזמנת עובד** (`test/business/team_test.dart:73`): לא נמצאת השורה `brow-team`. כנראה הפעולות המהירות החדשות במסך העסק דחפו אותה מחוץ לחלק הנראה של הרשימה, והבדיקה צריכה `scrollUntilVisible`.

### כשל אינטגרציה – חוסם
כל בדיקה שמפעילה את האפליקציה (`app.main()`) נתקעת לפני מסך הבית או מסך הכניסה, והסימולטור מציג מסך שגיאה אדום:
`framework.dart: Failed assertion line 2168 '_elements.contains(element)'`.
בלוג מופיעות גם השגיאות `Duplicate GlobalKey [LabeledGlobalKey<ScaffoldMessengerState>]` ו-`Looking up a deactivated widget's ancestor` (TickerMode ב-dispose), כולן מ-`lib/main.dart:99` (MaterialApp).
החשוד העיקרי הוא `NotchNoticeHost(key: notchNoticeKey)` ו-`systemNotices.install()` / `CustomerCrmStore.instance.install()`, שנוספו ל-`main.dart` ב-working tree. בגרסת v2 שעברה commit הסוויטות האלה עברו 120/120.
**צריך לברר אם המשתמש האמיתי נפגע.** ייתכן שהבעיה רק ב-harness שקורא ל-`main()` כמה פעמים, אבל עד שזה יתברר אין כרגע בדיקת E2E שעוברת.

## 2. באגים שאומתו בקוד (מסקירת קוד)

### גבוה
- **H1 – שורות נוספות בגיליון "עוד" מקושרות לאינדקס** (`s3_more.dart:267,276,287,333`, `removeAt` ב-297). אחרי מחיקת שורה, השדות מציגים ערכים של שורה אחרת. מה שהמשתמש רואה ≠ מה שנשלח בחשבונית.
- **H2 – מספר טלפון מזויף `052-0000111`** מוצג לכל לקוח בלי טלפון, כי `themeMode: ThemeMode.dark` קבוע (`main.dart:110`), והקוד מציג את המספר כש-`context.isDark` (`customer_chip.dart:32`, `s2_customer.dart:494,539`, `people_screen.dart:385`). זו שארית ממוקאפ, והמשתמש רואה נתון כוזב.

### בינוני
- `document_screen.dart:497`: `_vatRate() => 1800` קבוע בהמרת הצעת מחיר לחשבונית, במקום לקחת את השיעור מ-`/tax-rates`.
- `compose_submit.dart:181-198, 243-247`: כשל בשיתוף **אחרי** שהמסמך כבר הופק מוצג כשגיאת הפקה, והמסמך לא נפתח.
- `compose_submit.dart:354-366`: הצעת מחיר מוצגת "נשלחה" גם כשהשליחה נכשלה או שהמשתמש ביטל את גיליון השיתוף.
- הנחה לא מאומתת: הנחה גדולה מסכום השורה הראשית יוצרת שורה שלילית (`compose_state.dart:133-144`).
- `document_screen.dart:362-384`: יש `setState` אחרי `await` של דיאלוג, בלי בדיקת `mounted`.
- `router.dart:264-283`: קישור `tevel://gate` פותח מסך כניסה מעל session פעיל. `?businessId=` מחליף עסק בשקט מקישור חיצוני, וזה עלול לגרום להפקת מסמך בעסק הלא נכון.
- CRM (`customer_crm_store.dart`):
  - רענון ב-resume עלול לבטל עריכה שממתינה בתור.
  - mutation שנכשלת חוסמת את התור לתמיד.
  - hard-cast ב-`fromJson` הופך קובץ פגום לחסימה קבועה.
  - `migratedToUser` לא נכתב אף פעם, ולכן CRM מקומי ישן עלול לעבור לחשבון אחר באותו מכשיר.
- `session.dart:80-125`: 401 מ-`refreshBusiness` בזמן restore נבלע. חריגות שאינן `ApiException` עלולות להשאיר את ה-Splash תקוע.
- טוקן push לא נמחק ב-sign-out (צריך לאמת אם השרת מנקה אותו בעצמו).

### נמוך
- `TevelActivity.swift:73,79`: `case "reminder"` כפול, ולכן אייקון הטלפון לא יוצג לעולם.
- `customer_crm_jobs.dart:343,348`: שני פריטי תפריט עם `value: 'edit'`.
- חסרים busy-guards: `team_page` (שליחה חוזרת / ביטול), `s3_more._saveItem` (יוצר פריטים כפולים בקטלוג).
- `billing_screen.dart:134,766` קורא ל-`launchUrl` ישירות, בלי המעבר דרך ה-allow-list.
- אימייל בתוך טקסט עברי בלי `ltrIsolate` (`team_page.dart:240,252`). סכומים מעוצבים ידנית ב-`cardcom_merchant_screen.dart:352`.
- `supabase_auth.dart:55-60`: כל 400/422 מוצג כ"סיסמה שגויה".

## 3. נבדק ותקין
- סביבת release ננעלת ל-HTTPS ציבורי, ושרת ה-debug על 9999 מוגבל ל-loopback ול-debug.
- Supabase: מאמת דומיין ומפתח publishable, ולא שומר טוקן.
- טוקן המכשיר נשמר ב-Keychain. טוקן מהתקנה קודמת מבוטל.
- כסף ומע״מ מחושבים כ-BigInt באגורות, עם עיגול נכון.
- APNs: development/production תואמים ל-Debug/Release. ל-Info.plist יש את כל מחרוזות הפרטיות.
- כפתורי הפקה ותשלום מוגנים מפני לחיצה כפולה.

## 4. סדר תיקון מומלץ
1. לאבחן את כשל האינטגרציה (`main.dart` / `NotchNoticeHost`) ולהחזיר את ה-E2E לירוק.
2. H2 (מספר טלפון מזויף) ו-H1 (שורות לפי אינדקס): תיקונים קטנים, השפעה ישירה על נכונות החשבונית.
3. `_vatRate`, הודעות השיתוף וההצעה, ובדיקת deep-link לפני החלפת עסק.
4. תור ה-CRM: poison queue, parse סלחני, כתיבת `migratedToUser`.
5. golden, AT-92, J8 ו-`dart format`.
