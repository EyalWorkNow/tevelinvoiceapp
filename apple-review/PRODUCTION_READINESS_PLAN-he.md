# הכנת Tevel Invoice ל־Apple App Review

נבדק: 5 בנובמבר 2026. זהו מחקר ותוכנית עבודה לפי קוד הפרויקט, מצב חשבון Apple המחובר ותיעוד Apple העדכני. לא בוצעה קבלת הסכם, יצירת רשומה, העלאה או הגשה ל־Apple.

## מצב קצר

- נבדק החשבון המחובר כבעל החשבון ב־App Store Connect: ברשימת Apps מופיעות “Al Jamal” ו־“Rently”; Tevel Invoice אינה מופיעה. לכן אין עדיין App Record ל־Bundle ID המבוקש בחשבון הזה.
- Apple מציגה הודעה שה־Apple Developer Program License Agreement עודכן. בדף Developer כתוב שקבלת ההסכם נחוצה כדי להחזיר גישה ל־Certificates, Identifiers & Profiles, ל־App Store Connect ול־API. לא קיבלתי את ההסכם בשמך.
- חשבון המפתח הוא Individual וה־Team ID המוצג הוא `ARFSXMWT96`, תואם למזהה בפרויקט. הפרופילים/Capabilities אינם ניתנים כרגע לבדיקה בגלל הסכם הממתין.
- הפרויקט מזהה את `space.tevel.invoice`, Team `ARFSXMWT96`, iOS 15 ומעלה. Archive Release לא חתום ו־IPA חתום עדיין אין.
- מסכי StoreKit ואימות העסקאות בשרת קיימים בקוד, אך מוצרים, מחיר, App Apple ID, התראת שרת ובדיקת Sandbox ב־App Store Connect עדיין לא הוגדרו/אומתו.
- במסמך ההחלטות המקורי נכתב חמישה מסלולים ו־Cardcom בלבד; בקוד המינויים הנוכחי יש שלושה מסלולים: START ‏₪8/21 מסמכים, GROW ‏₪10/30, UNLIMITED ‏₪15 ללא הגבלה. צריך לאשר שהקטלוג הנוכחי הוא ההחלטה העסקית הסופית לפני יצירת מוצרים בחנות. הקוד לא תואם למסמך הישן בנושא הזה.
- קובץ הדרישות המקורי אוסר העלאה והגשה ללא אישור נפרד; ההגבלה נשמרת. בקשת "להתחיל את התהליך" אינה משמשת להעלאה או לשליחה לבדיקה.

## ממצאי מדיניות Apple

1. Guideline 3.1.1 דורש IAP לפתיחת תכונות או שירות דיגיטלי שנרכש מתוך האפליקציה. סעיף 3.1.3(c) חל רק אם האפליקציה נמכרת ישירות לארגונים/קבוצות עבור עובדיהם/תלמידיהם. אותו סעיף מחריג במפורש מכירות לצרכן יחיד/משפחה ודורש להן IAP. כיוון שהמוצר מאפשר לבעל עסק יחיד לבחור מסלול מתוך האפליקציה, אי אפשר להסתמך על החריג הארגוני עבור הרכישה העצמית הזו. לכן מסלול StoreKit ב־iOS הוא ברירת המחדל הבטוחה לפי המודל המתועד. תשלומי הלקוחות עבור סחורה/שירותים ממשיים מחוץ לאפליקציה הם מסלול נפרד ואינם רכישת מנוי Tevel.
2. Apple דורשת שהאפליקציה תהיה שלמה, נבדקת על מכשיר, שכל הקישורים והשרתים יעבדו, ושפרטי החשבון/ההסבר לבודק יספקו גישה מלאה. כשיש מינוי מתחדש נדרש להציג שם, משך, מחיר חידוש ברור, תנאי שירות ופרטיות, וכן שחזור רכישות.
3. אפליקציה עם יצירת חשבון חייבת לאפשר התחלת מחיקה מתוך האפליקציה. יש למחוק נתונים אישיים שאינם חייבים בשימור, ולהסביר למשתמש אילו רשומות נשמרות מכוח חובה חוקית.
4. נדרשים Privacy Policy URL, App Privacy הצהרות שתואמות לקוד/SDK/שרת, גיל ודירוג תואמים, צילומי מסך בגודל הנדרש, פרטי תמיכה, שם/תיאור/מילות מפתח, ולכלול ב־Review Notes הסבר על שימוש עסקי, תהליכי תשלום, שירותים חיצוניים וגישה לחשבונות.
5. עבור כניסה באמצעות Apple, נדרש לוודא capability ב־App ID, entitlement/Provisioning Profile תואמים, ובדיקת כניסה אמיתית במכשיר. אם משתמשים ב־Sign in with Apple ליצירת משתמש, ביטול ההרשאה בזמן מחיקת חשבון חייב להיבדק מול שרת Apple.

## פערים לפי תחום ופעולה

| תחום | מצב שנמצא | עבודה נדרשת | חסם |
|---|---|---|---|
| App Store Connect | החשבון המחובר הוא בעל החשבון; נראות Apps נקראה | ברשימה קיימות שתי אפליקציות אחרות; Tevel Invoice אינה קיימת. אחרי חידוש הגישה: ליצור App Record עם `space.tevel.invoice`, לבדוק הסכמי תשלום, שפות, אזורים, גיל, privacy ו־metadata | בעל החשבון צריך לקרוא ולקבל את הסכם Apple Developer Program המעודכן. לא קיבלתי אותו בשמו |
| זהות וחתימה | Team ID תואם; Bundle ID לא נמצא ברשימת Apps; archive לא חתום נבנה | לאחר הסכם: לאמת/לרשום Bundle ID, capability, profile ו־build number; ליצור archive חתום ו־IPA ולוודא עם `codesign`/Organizer | הסכם Apple מעודכן ממתין לאישור; Xcode דיווח בעבר `No Accounts` וה־profile המקומי חסר Sign in with Apple |
| מודל מסלולים | שלושה מוצרים בקוד, מסמך ישן אומר חמישה | ליישב קטלוג ומחירים; ליצור Subscription Group ו־3 מוצרים חודשיים אם יאושר הקטלוג; להגדיר localization, review screenshot, points/pricing, tax category והסכמים | תלוי בחשבון ASC וקטלוג סופי; לא ליצור מוצרים בתשלום במחיר לא מאושר |
| StoreKit backend | קוד אימות JWS/Notifications v2 קיים; בדיקות unit עוברות | להחיל migration `0090_apple_iap.sql` בפרוד; להגדיר `APPLE_APP_ID`, `APPLE_BUNDLE_ID`, `APPLE_ALLOWED_ENVIRONMENT=Production`; לרשום Notification V2 URL; בדיקת Sandbox/TestFlight: רכישה, restore, חידוש, billing retry, ביטול והחזר | נדרש App Apple ID ו־ASC; נדרש deployment מתואם, שלא בוצע |
| Review accounts | תיעוד כולל סקריפט seed; לא הוכח שנוצר חשבון פרוד | ליצור חשבון דמו קבוע עם נתונים סינתטיים; בנוסף חשבון מחיקה נפרד; לבדוק כניסה, MFA, הרשאות, נעילות ויציבות API. למינוי: לספק לבודק גם משתמש במצב ללא מינוי/מינוי שפג לפי הנחיות Apple | נדרשת הרשאה ליצירה בסביבת פרוד ואחסון סודות ב־ASC, לא בצ׳אט |
| מחיקת חשבון | UI/API ובדיקות ממוקדות קיימים; אין אימות פרוד בדוח | תרחיש מלא בחשבון המחיקה בלבד; לוודא סגירת עסק לפי בעלים/חברים, שמירת מסמכים, ביטול sessions וטוקנים והרשאת Apple; לבדוק מדיניות שמירה משפטית ותשובת הצלחה/כשל | בדיקת פרוד דורשת חשבון בדיקה וסביבת פרוד |
| Sign in with Apple | UI, token flow ו־entitlement בפרויקט; חתימה חסומה | לבדוק capability ב־Apple Developer; profile מעודכן; מכשיר פיזי; יצירה/כניסה עם Hide My Email; revoke בזמן delete | אין התחברות ל־Developer Account כרגע |
| App Privacy/Manifest | manifest קיים והצהרות מתועדות | להשוות בפועל לכל plugin, API, logs ונתוני לקוחות; לוודא תוויות privacy ב־ASC; privacy URL ותהליך זכויות/מחיקה. להפיק Xcode Privacy Report ולבדוק warnings | תוויות ASC לא אומתו בחשבון |
| תנאים/פרטיות/תמיכה | Privacy ותמיכה חיו בבדיקה קודמת; תנאים תועדו כטיוטה באתר | לוודא נוסח סופי, בעלות משפטית, מחירי מנוי וחידוש/ביטול, retention ומדיניות שירות; לא להגיש תנאים שמסומנים טיוטה | בעל העסק/ייעוץ משפטי צריך לאשר נוסח סופי |
| מטא־דאטה | טיוטות עברית/אנגלית קיימות | לוודא מגבלות תווים, התאמת תיאור לגרסה ויכולות פרוד, screenshots לכל localization, keywords, copyright, support contact ו־age rating | נכסי release ומגע תמיכה עדיין לא אומתו |
| צילומי מסך/וידאו | צילומי Preview עם backend מדומה קיימים; תסריט וידאו קיים | לצלם מגרסת Release עם נתוני דמה מאושרים, בלי placeholders/הבטחות; לוודא iPhone Dynamic Island; iPad אם נתמך; לבדוק זכויות לתמונות. סרטון אינו דרישה כללית, אלא אם דרוש חומר ייעודי (כגון חומרה) או שהבודק צריך אותו | נדרשים build חתום/חשבונות בדיקה; אין להשתמש במידע אמיתי |
| בדיקות קבלה | analyze, tests, build ו־archive לא חתום עברו; אין עדיין ריצת device+ASC | ריצה נקייה על מכשיר: onboarding, Apple/email login, MFA, לקוחות, מסמכים, PDF, הוצאה/OCR, QR/share, offline/errors, permissions, Dynamic Type, VoiceOver, delete, subscription/restore; לוודא שכל השירותים נגישים | נדרש מכשיר/חשבון/פרוד. ציון Apple דורש מכשירים בפועל |
| הפצה | אין העלאה או הגשה | אחרי אישור נפרד בלבד: upload build, לחבר build, לוודא IAP items, review notes, submission metadata ואז Add for Review/Submit for Review | לא מורשה במסגרת המשימה הנוכחית לפי ההנחיה הקודמת |

## סדר עבודה מומלץ

1. בעל החשבון קורא ומקבל את הסכם Apple Developer Program המעודכן מתוך חשבון המפתח. אחרי כן לבדוק שוב שהגישה ל־Certificates, Identifiers & Profiles חזרה.
2. לאמת רשומת אפליקציה ו־Bundle ID (כרגע Tevel Invoice לא מופיעה ברשימת Apps), Team, agreements ו־capabilities. ליצור App Record רק אחרי שחרור החסימה ואימות שאין app identifier תפוס/קיים בחשבון אחר.
3. לסגור מקור אמת למספר מסלולים ולמחיר. לתעד את החלטת העסק; לא להסתמך על טקסט ישן מול קוד חדש.
4. להשלים קוד/שרת בהתאם למדיניות ולתוכנית IAP, לבדוק migration/deployment ותצורת Sandbox, ורק אחר כך לבנות Release.
5. לסדר חתימה ולבנות archive/IPA חתום; לוודא את ה־entitlements, privacy report ו־bundle metadata.
6. ליצור חשבונות בדיקה דרך מנגנון מוגן, להכניס credentials ל־Review Information רק מתוך ממשק Apple (לא לשמור בריפו), ולבצע את כל תרחישי קבלה על מכשיר.
7. להשלים תנאים ומדיניות, App Privacy, גיל, מטא־דאטה ושני סטים של screenshots (עברית/אנגלית), ולתעד Review Notes.
8. בדיקת מוכנות סופית ו־diff. העלאה, Add for Review, Submit for Review ופרסום יבוצעו רק אחרי אישור נפרד.

## מקורות Apple שנבדקו

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — 2.1, 3.1.1, 3.1.3(c), 4.8, 5.1.1(v).
- [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/) — פרטי מוצר, credentials לחשבון demo, כולל מצב subscription שפג.
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app) — דרישות metadata/build ושלבי submission.
- [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/) — app record ותפקידים נדרשים.
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) — privacy URL והצהרות.
- [Account deletion guideline](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion/) — מחיקה מתוך האפליקציה.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) — גדלי וצורות screenshots.
- [Auto-renewable Subscriptions](https://developer.apple.com/app-store/subscriptions/) — מחיר, משך, הצגת תנאים, restore, privacy/terms.
