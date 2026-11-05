# חבילת App Store ו־Apple Review

התיקייה מרכזת את חומרי ההפצה של אפליקציית תבל ל־iOS: פרטי build, הנחיות Xcode, טיוטות לחנות, הוראות לבודק ותסריט וידאו. קובץ האפליקציה נוצר כ־`.xcarchive` תחת `build/` ואינו מיועד ל־Git.

## מצב נוכחי

- פרויקט Xcode: `../ios/Runner.xcworkspace` — יש לפתוח את ה־workspace, לא את קובץ ה־project.
- Bundle ID: `space.tevel.invoice`.
- גרסה נוכחית: `1.0.0 (1)` מתוך `pubspec.yaml`.
- Team שמוגדר בפרויקט: `ARFSXMWT96`; Xcode מחובר לחשבון Apple Developer. IPA חתום נבנה בהצלחה.
- יעד iOS מינימלי: 15.0.
- קובץ Privacy Manifest קיים ומחובר ל־Runner.
- מחיקת חשבון זמינה בפרופיל ← הגדרות ← חשבון ← מחיקת חשבון. המסך מבקש אימות חוזר ומציג מה נמחק ומה נשמר לפי חובת שמירה.
- קישורי תנאים ותמיכה פעילים. דף הפרטיות באתר אינו ייעודי לאפליקציה ודורש השלמה לפני הגשה.

## מצב App Store Connect

רשומת `תבל עסקים` נבדקה בפועל: Apple ID ‏`6831079441`, Bundle ID ‏`space.tevel.invoice`, SKU ‏`tevel-invoice-ios`. נשמרו פרטי חנות ראשוניים בעברית; הקטגוריה Business ודירוג הגיל 4+ מוגדרים. נוצרה קבוצת המינויים `Tevel Monthly Plans` עם ID ‏`22549611`, ובה שלושה מוצרים חודשיים עם לוקליזציות בעברית. שלושתם במצב `Prepare for Submission`; סדר הרמות עדיין מתחילים, צמיחה, ללא הגבלה. טיוטת App Privacy עם 10 סוגי מידע נשמרה ולא פורסמה. ה־IPA הועלה ב־5.11.2026 דרך Transporter; לא הצלחתי לאמת עיבוד כי דפי האפליקציה לא נטענו בבדיקה האחרונה. לא נלחץ Add for Review.

## חסימות לפני שליחה

1. **מינוי iOS:** שלושת המוצרים קיימים בקבוצה `22549611`, עם מחירי ישראל ₪7.90/₪9.90/₪14.90. יש לסדר את רמות השירות, לאמת זמינות בכל מוצר, להגדיר Server Notifications ו־`APPLE_APP_ID`, להחיל מיגרציה `0090_apple_iap.sql` בשרת ולהשלים בדיקות Sandbox. חיבור Cardcom לא נעשה; זרימת תשלום של לקוח העסק עבור חשבונית היא נפרדת.
2. **חתימה:** הושלמה. נוצר IPA חתום תחת `build/ios/ipa/תבל.ipa`; נבדקו החותם וה־entitlements. הקובץ הועלה ל־App Store Connect; לפני העלאה חוזרת יש להעלות את Build Number.
3. **חשבונות בודק:** החשבון שב־`docs/TEST-LOGIN-he.md` עובד רק בסביבת פיתוח מקומית. יש ליצור Production Demo account וחשבון מחיקה נפרד עם נתוני דמה בלבד; אין גישה או הרשאה ליצור אותם בשרת ייצור במסגרת העבודה המקומית. את פרטי ההתחברות יש לשמור ישירות בשדות המאובטחים של App Store Connect, לא בקובצי Git.
4. **פרטיות וזכויות:** טיוטת App Privacy נשמרה עם 10 סוגי מידע כ־Data Linked to You ולצורכי App Functionality, אך לא פורסמה. יש לאמת מול זרימות הייצור וספקי צד שלישי ולפרסם מדיניות פרטיות ספציפית. הצהרת Content Rights עדיין דורשת אימות.
5. **פרטי בודק ו־DSA:** חשבון Production demo, חשבון מחיקה נפרד, צילומי מסך (המשתמש יעלה), ופרטי סוחר DSA עדיין חסרים. פרטי קשר לבודק הוזנו ב־ASC, אך חסרים פרטי גישה לחשבון הדגמה. יש להשתמש בפרטי עסק אמיתיים ולשמור סיסמאות רק בשדות App Store Connect.

## פתיחה ובנייה

1. פתחו Xcode:

   ```sh
   open ios/Runner.xcworkspace
   ```

2. בחרו `Runner` ואת `Any iOS Device (arm64)`.
3. לפני Archive, ודאו ששרת production פועל, שחשבון ההדגמה פעיל, שהתשלום הוסדר, ושגרסת `pubspec.yaml` הוגדלה.
4. בחרו **Product → Archive**. Xcode מציג את התוצאה ב־Organizer.
5. ייצאו IPA. העלאה ל־App Store Connect בוצעה; אין לשלוח את הגרסה ל־App Review לפני השלמת הרשימה ואישור מפורש.

ה־IPA החתום שנבנה נמצא ב־`build/ios/ipa/תבל.ipa`. הוא נחתם עם Apple Distribution של צוות `ARFSXMWT96` והועלה ל־App Store Connect. טרם אומת ב־App Store Connect לאחר עיבוד וטרם נשלח לבדיקה. פרטי הגדרת מוצרי המינוי והשרת נמצאים ב־`APPLE-IAP-SETUP-he.md`.

אחרי התחברות לחשבון Xcode ויצירת Archive חתום, אפשר לייצא IPA מקומי (הפקודה אינה מעלה אותו) עם:

```sh
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath apple-review/build/Tevel-Signed.xcarchive \
  -exportPath apple-review/build/export \
  -exportOptionsPlist apple-review/ExportOptions.plist \
  -exportArchive
```

ה־Archive המקומי הוא חבילת Xcode; הוא אינו אומר שהבנייה הועלתה ל־App Store Connect או אושרה. אם חתימה אוטומטית מבקשת פרופיל, התחברו ב־Xcode לחשבון Apple Developer המתאים ובחרו Team `ARFSXMWT96`.

## חומרי התיקייה

- `APP_REVIEW_CHECKLIST-he.md` — רשימת מוכנות ומצב פריטים.
- `APP_REVIEW_NOTES-en.md` — טיוטת הערות באנגלית לבודק.
- `DEMO_VIDEO_SCRIPT-he.md` — תסריט צילום מסך עבור סרטון הדגמה פנימי/חומרי App Store.
- `APP_STORE_METADATA-he.md` — טיוטת טקסט לעמוד החנות.
- `APP_STORE_METADATA-en.md` — טיוטת טקסט אנגלית.
- `capture-preview-screenshots.sh` — צילום מסכי Preview עם backend מדומה.
- `READINESS_REPORT-he.md` — דוח מצב, ראיות והפעולות שנותרו.
- `ExportOptions.plist` — הגדרות ייצוא Xcode ל־App Store Connect.
- `screenshots/README.md`, `video/README.md` — הנחיות והכנה לחומרי מדיה.

## אימות מחיקת חשבון

לבדיקה בלי לפגוע בחשבון הדגמה ראשי, התחברו עם חשבון מחיקה ייעודי. בפרופיל, העבירו את הבורר ל״הגדרות״, גללו ל״מחק חשבון״, בצעו אימות והקלידו ״מחק״. בדקו שהחשבון וכל ה־sessions נמחקים/מבוטלים, שהאפליקציה חוזרת למסך כניסה, ושמידע שנשמר לפי דין מוסבר למשתמש. אין להריץ בדיקת מחיקה עם חשבון בעל נתונים אמיתיים.
