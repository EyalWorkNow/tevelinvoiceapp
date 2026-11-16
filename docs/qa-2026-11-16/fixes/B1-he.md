# B1 · תפקיד קופאי/ת, ורישום תשלום בנפרד מהפקת חשבוניות

תאריך: 2026-11-16 · שלב B, סעיף B.3 (הרשאות צוות) · מקור: פרסונה 04 (סיגל, סלון), כאב 3, ופרסונה 05 (אורי, סוכנות), כאב 4.

## הבעיה (אומתה בקוד)

1. **עובדת בסלון לא יכולה להפיק קבלה על תשלום שקיבלה עכשיו בלי אישור.**
   - עובד בלי `document:finalize` שולח **כל** מסמך לאישור (`caps.dart` `approvalNeeded`, `submitForApproval` `makerCannotFinalize`).
   - המתג "מפיק בעצמו" נותן `document:finalize` ו-`payment:record` לכל סוגי המסמכים ובלי תקרה, ולכן מחייב אימות דו-שלבי (`membershipRequiresMfa`).
   - אין דרך לתת "קבלה על כסף שהתקבל, בלי לראות הכנסות".
2. **רישום תשלום דרש הרשאת הפקה.**
   - באפליקציה: `paymentRecord = payment:record && document:finalize`.
   - בשרת: `POST /receipts` דרש `payment:record` **וגם** `document:finalize`.
   - לכן מנהלת משרד שרושמת העברות יכלה גם להפיק חשבוניות מס.

## ההחלטה

- **תפקיד חדש `CASHIER` ("קופאי/ת")** עם הרשאה צרה חדשה: `document:finalize_with_payment`.
  - ההרשאה הזאת **אינה** `document:finalize`. הכלל "MFA לכל מי שמחזיק `document:finalize` או `payment:record`" נשאר כמו שהוא.
  - היא לא ניתנת כהרשאה נוספת (NON_GRANTABLE). היא מגיעה רק עם התפקיד. גם הבעלים והשותף לא מחזיקים אותה, כי יש להם `document:finalize`.
  - הרשאות התפקיד: `document:read`, `document:draft:write`, `document:send`, `document:finalize_with_payment`.
  - אין לקופאי/ת `money:read`, `report:read`, `payment:record`, `document:cancel` או `approval:decide`.
- **בלי אימות דו-שלבי לקופאי/ת. הסיבה מבוססת סיכון, ומתועדת ליד `membershipRequiresMfa` ב-`rbac.ts`:**
  - כל מה שסשן של קופאי/ת יכול לעשות הוא להפיק קבלה קטנה (עד התקרה) על כסף שהוא טוען שקיבל.
  - הוא לא רואה סכומים (חוץ ממסמכים שלו), דוחות או ספר תשלומים.
  - הוא לא רושם תשלום על מסמך קיים, לא מבטל תשלום, לא מזכה, לא מבטל מסמך, לא מאשר ולא משנה הגדרות או צוות.
  - כל פעולה נרשמת ב-audit.
  - זו אותה חשיפה כמו קופאית עם קופה. אימות דו-שלבי בדלפק של סלון (מכשיר משותף, עשרות פעמים ביום) הוא בדיוק החסם שסיגל תיארה.
  - קופאי/ת שקיבל/ה גם `document:finalize` או `payment:record` כהרשאה נוספת נתפס/ת בכלל הרגיל ומתבקש/ת MFA.
- **`payment:record` לבד = רישום תשלום על מסמך קיים.** זה ה-preset החדש "מנהל/ת משרד" (EMPLOYEE + `payment:record` + `money:read`, כדי לראות את היתרה שעליה רושמים).
  - מה מותר: לרשום תשלום (`POST /payments`), לשייך אותו למסמך (`POST /documents/:id/payments`) ולהפיק את הקבלה על התשלום הזה (`POST /receipts` עם `forDocumentId`).
  - מה אסור: להפיק 305, 320 או 300, או קבלה עצמאית בלי מסמך.
  - `payment:record` עדיין מחייב MFA, כי הוא מאפשר גם לבטל תשלום (`POST /payments/:id/void`).

## מה השתנה

### שרת (invoiceproject, ענף `stageB/cashier-role`, מיגרציה **0100**)

- **מיגרציה 0100 `cashier_role`:** הערך `CASHIER` ב-enum `membership_role`. ההרשאות עצמן נמצאות ב-`@invoice/security`.
- **התקרה:** `business_settings.document_settings.approval.cashierCapMinor`.
  - ברירת המחדל היא 200000 (₪2,000).
  - הסכום **כולל מע"מ**, "עד" (מעל התקרה, כלומר `>`, הולך לאישור).
  - גם הסף של מדיניות האישור של העסק (THRESHOLD, `>=`) חל על הקופאי/ת, כך שהקופאי/ת אף פעם לא מפיק/ה יותר ממה שכל עובד אחר יכול בלי אישור.
  - `PUT /settings/approval` מקבל `cashierCapMinor`. בלי השדה, הערך השמור נשאר (מיזוג JSON). `/me.approvalPolicy.cashierCapMinor` מחזיר אותו.
- **אכיפה בשרת, לא רק הסתרה בממשק:**
  - `finalizeDocument`: לקופאי/ת מותר רק RECEIPT או TAX_INVOICE_RECEIPT, ורק כשהקורא רושם את התשלום באותה טרנזקציה (`withPayment`).
    - התשלום חייב לכסות את כל הסכום. אחרת: `CASHIER_PAYMENT_MUST_COVER_TOTAL`.
    - מעל התקרה: `APPROVAL_REQUIRED`.
  - `POST /documents/:id/finalize`: קופאי/ת חייב/ת לשלוח בדיוק תשלום אחד ב-`pendingPayments`. אחרת 403.
    - כשהמסמך הופק, התשלום נרשם ומשויך מיד, והתשובה כוללת `paymentRecorded: true`.
    - כשהמסמך ממתין למספר הקצאה, התשלום נשמר כממתין (SA2).
  - `POST /receipts`: שדה חדש `payment` (תשלום שהתקבל עכשיו, inline). השרת רושם את התשלום ואת הקבלה בטרנזקציה אחת. לקופאי/ת זו הדרך היחידה. `paymentIds` אסור לקופאי/ת.
  - **מעל התקרה, לאישור הבעלים (maker-checker הקיים), והכסף לא הולך לאיבוד:**
    - קבלה 400: השרת יוצר טיוטת קבלה, שולח אותה לאישור ומצמיד אליה את התשלום כממתין. התשובה: `outcome.status = 'PENDING_APPROVAL'`.
    - 320: `POST /documents/:id/submit` מקבל עכשיו `pendingPayments`, למי שמחזיק `payment:record` או לקופאי/ת. הכסף ממתין עם המסמך.
    - אישור (`approveDocument`) שמסתיים ב-FINALIZED רושם את התשלום באותה טרנזקציה. בקבלה 400 נוצר קישור `payment_receipts` במקום הקצאה.
    - דחייה (`rejectApproval`) מבטלת את הממתין, עם סיבה, ונרשמת ב-audit.
  - **מקור (ORIGINAL) וחתימה:** בלי `document:finalize`, רק על 400 או 320 שהקורא יצר בעצמו (`assertMayIssueOriginal`). פתיחת נעילת החתימה עדיין דורשת `document:finalize`.
  - **סכומים:** אותו מנגנון של `money:read` שמסתיר סכומים מ-EMPLOYEE.
    - `/dashboard` ו-`GET /payments` מוחזרים בלי סכומים.
    - ברשימות ובפרטים, סכומים של מסמכים של אחרים הם null, ושל המסמכים של הקופאי/ת עצמו/ה נשארים.
    - PDF או שליחה של מסמך של אחר: 403.
    - "לטיפול" והרשימה מסוננים למסמכים של הקופאי/ת בלבד, כמו אצל EMPLOYEE.
  - `GET /reports/*`: 403 (`report:read`).
- **טבלת הגישה (`access.ts`):**
  - `finalize`: anyOf finalize או finalize_with_payment.
  - `receipts`: anyOf payment:record או finalize_with_payment.
  - `artifact` (ORIGINAL) ו-`sign`: anyOf finalize, finalize_with_payment או payment:record. הבדיקה לפי בעלות נעשית בדומיין.
  - שדה חדש `anyOfByQuery`.

### אפליקציה (ענף `stageB/cashier-role`)

- **`lib/state/caps.dart`:**
  - preset חדש `cashier` (התפקיד CASHIER) ו-`officeManager` (EMPLOYEE + `payment:record` + `money:read`, בלי finalize).
  - `Cap.paymentRecord` הוא עכשיו `payment:record` בלבד: רישום תשלום על מסמך קיים (S5).
  - `Cap.paymentIssue` חדש, "קיבלתי תשלום" למסמך חדש: (`document:finalize` וגם `payment:record`) או `document:finalize_with_payment`.
  - `approvalNeeded(total, paid:)`: לקופאי/ת, מסמך משולם הולך לאישור רק מעל התקרה או מעל הסף של העסק. כל מסמך אחר הולך תמיד לאישור.
  - `ApprovalPolicy.cashierCapMinor` נקרא מ-`/me`.
- **הזמנה ועריכת חבר צוות:**
  - "קופאי/ת": "מפיק/ה קבלה על תשלום שהתקבל עכשיו, עד ₪2,000 בלי אישור. לא רואה הכנסות ולא מבטל/ת."
  - "מנהל/ת משרד": "רואה יתרות, רושם/ת תשלומים על מסמכים קיימים ומצלם/ת הוצאות. לא מפיק/ה חשבוניות. יתבקש אימות דו-שלבי."
  - שני ה-presets מוצגים בגיליון ההזמנה ובעריכת חבר צוות.
- **הבית של הקופאי/ת:** כפתור ראשי גדול "קיבלתי תשלום" עם שורה "קבלה על תשלום שקיבלת עכשיו · עד ₪X בלי אישור".
  - אין כרטיס כסף (השרת לא מחזיר סכומים) ואין "בקש תשלום".
  - הכפתור פותח את ה-Composer ישירות על 320 (עוסק מורשה) או על 400 (פטור או עמותה).
- **עסק → אישורים (§13.6):** שדה חדש "קופאי/ת מפיק/ה בלי אישור עד" (סכום כולל מע"מ). נשמר ב-`cashierCapMinor`.
- **S5 (רישום תשלום על מסמך קיים):** מי שאין לו `document:finalize` (מנהל/ת משרד) לא מתבקש/ת סיסמת חתימה. הקבלה ממתינה לחתימה של הבעלים, במקום להיתקל ב-403.
- **זרימת ההפקה (`issue_api.dart`):**
  - 320 עד התקרה: finalize עם התשלום. כשהתשובה `paymentRecorded` מגיעה, אין קריאה נוספת ל-`/payments`.
  - 320 מעל התקרה: "שלח לאישור", והתשלום נשלח עם ה-submit.
  - 400: `POST /receipts {payment}` בלי `POST /payments`. מעל התקרה התשובה PENDING_APPROVAL, והמסמך מוצג כ"נשלח לאישור".

## שינויי חוזה API

| קריאה | שינוי |
|---|---|
| `GET /me` | `role` יכול להיות `CASHIER`. `permissions` כולל `document:finalize_with_payment`. `approvalPolicy.cashierCapMinor`. |
| `PUT /settings/approval` | `cashierCapMinor` אופציונלי (מחרוזת, אגורות). בלי השדה, הערך השמור נשאר. |
| `POST /business/members/invite`, `PUT .../role` | `role: "CASHIER"` מותר. |
| `POST /documents/:id/finalize` | קופאי/ת: בדיוק תשלום אחד ב-`pendingPayments` שמכסה את כל הסכום, ורק ל-400 או 320. התשובה כוללת `paymentRecorded: true` כשהתשלום נרשם. |
| `POST /documents/:id/submit` | גוף אופציונלי `pendingPayments` (payment:record או קופאי/ת). הכסף ממתין עם המסמך, נרשם באישור ומבוטל בדחייה. |
| `POST /receipts` | `payment: {method, amountMinor, paymentDate?, reference?, …}` במקום `paymentIds`. תוצאה חדשה אפשרית: `outcome.status = 'PENDING_APPROVAL'`. `payment:record` בלי finalize: רק עם `forDocumentId`. |
| שגיאה חדשה | `CASHIER_PAYMENT_MUST_COVER_TOTAL` (422). |

## בדיקות

- **שרת, `apps/api/test/b1-cashier-role.int.test.ts` (11 בדיקות):**
  - `/me` של קופאי/ת.
  - 400 של ₪120: FINALIZED, תשלום וקישור קבלה.
  - 320 של ₪118 עם תשלום: FINALIZED ושולם במלואו, וניסיון חוזר לא רושם פעמיים.
  - 320 בלי תשלום: 403. תשלום חלקי: נדחה.
  - 305: 403. גם `/payments` ו-`credit`: 403.
  - `GET /reports`: 403. לוח הבקרה, הרשימה והספר בלי סכומים. PDF של אחר: 403.
  - מעל התקרה: APPROVAL_REQUIRED. אחרי submit הכסף ממתין, והאישור רושם אותו.
  - קבלה מעל התקרה: אישור מפיק אותה ורושם את הכסף, ודחייה מבטלת אותו.
  - הבעלים משנה את התקרה, וקליינט שלא שולח אותה לא מאפס אותה.
  - מנהלת משרד רושמת תשלום וקבלה על 305 קיים, אבל finalize ל-305 שלה מחזיר 403 וקבלה עצמאית מחזירה 403.
- **שרת, `v2-rbac-matrix.int.test.ts`:** שני presets חדשים (CASHIER ו-OFFICE_MANAGER) בכל המטריצה, ובדיקות שה-MFA לא חל על קופאי/ת אבל חל על קופאי/ת עם grant.
- **אפליקציה:** `test/b1_cashier_test.dart`.
  - מיפוי caps לקופאי/ת ולמנהלת משרד.
  - `approvalNeeded` לפי התקרה.
  - ה-presets בעורך ההזמנה ובעורך החבר.
  - הבית של הקופאי/ת: "קיבלתי תשלום", בלי כרטיס כסף ובלי "בקש תשלום".
  - `presetToServer` ו-`presetOf`.
- **אפליקציה:** `test/issue_api_test.dart`: כשה-finalize מחזיר `paymentRecorded`, אין `POST /payments` נוסף. `test/caps_test.dart`: מטריצת ה-caps כוללת את שני ה-presets החדשים.

## מה לא נעשה

- **"מפיק בעצמו" נשאר כמו שהוא** (finalize ו-payment:record, עם MFA), לעובד שבאמת מפיק חשבוניות.
- **אין תקרה לכל עובד.** התקרה היא לעסק כולו.
- **קופאי/ת לא יכול/ה לפתוח נעילת חתימה** (הסיסמה של הבעלים). אם החתימה נעולה, המסמך מחכה לחתימה של הבעלים.
