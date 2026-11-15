# SA2 · תשלום של מסמך שממתין למספר הקצאה נשמר בשרת

תאריך: 2026-11-16 · שלב A, סעיף A2 (בטיחות כסף) · מקור: פרסונה 02 (יוסי החשמלאי), כאב 2.

## הבעיה (אומתה בקוד)

- כשמפיקים מסמך עם תשלום ("קיבלתי תשלום", חשבונית מס/קבלה) והשרת מעביר אותו ל-WAITING_FOR_ALLOCATION, פרטי התשלום נשמרו **רק בטלפון**.
- הם ישבו ב-slot מקומי אחד לכל עסק (`PendingIssue`, המפתח `nd_pending_issue_<business>`).
- הפקה נוספת, התקנה מחדש או טלפון חדש מחקו אותם. התשלום לא נרשם אף פעם.

## מה השתנה

### שרת (invoiceproject, ענף `stageA/pending-payment`)

- **מיגרציה 0096 `document_pending_payments`:** תשלום מיועד שמחובר למסמך. הסטטוסים: PENDING, RECORDED, CANCELLED.
  - שורה אחת לכל (עסק, מפתח אידמפוטנטיות), עם RLS.
  - שורה שנרשמה או בוטלה לא משתנה ולא נמחקת (trigger).
- **זה לא תשלום:** כל עוד המסמך ממתין, אין שורה ב-`payments`, אין הקצאה, `paid_total_minor` נשאר 0, ולכן הדוחות, הספר ולוח הבקרה לא סופרים אותו.
- **רישום אוטומטי ואטומי:** `completeAllocation` רושם את כל התשלומים הממתינים באותה טרנזקציה שבה המסמך הופך ל-FINALIZED (תשלום והקצאה).
  - כל דרכי ההשלמה עוברות שם: מספר משע"ם, מספר שהוזן ידנית, המשך בלי מספר והתאמה.
  - המפתח `pending-payment:<id>` מבטיח שניסיון חוזר לא ירשום פעמיים.
- **ביטול בקשת ההקצאה** (`allocation/cancel`, המסמך חוזר לטיוטה) מבטל גם את מה שהמתין.
- **פרטי מסמך:** `GET /documents/:id` מחזיר `document.pendingPayments`, רק את הממתינים.

### אפליקציה (ענף `stageA/pending-payment`)

- **הכסף נשלח עם ההפקה:** `runIssue` שולח את התשלום בקריאת finalize (`pendingPayments`).
  - אם המסמך ממתין והשרת החזיר את התשלום, הטלפון לא שומר עותק (`payment = null`, `paymentViaServer = true`).
  - בלי הד מהשרת, התשלום מועלה מיד ל-`POST /documents/:id/pending-payments` עם המפתח `<finalizeKey>:pending:0`. זה המפתח שהשרת נותן בעצמו, ולכן גם ניסיון חוזר לא יוצר כפילות.
- **גיבוי מקומי לזמן קצר, רק בתקלת רשת:** אם אין רשת, העותק נשאר בטלפון. הוא מועלה בפתיחה הבאה (`uploadLocalPendingPayment`, מ-AppShell, פעם אחת לכל עסק בכל הרצה).
- **מיגרציה של גרסה ישנה:** `PendingIssue` בשלב waitingAllocation עם תשלום מועלה פעם אחת.
  - אם המספר כבר הגיע, השרת רושם את התשלום מיד.
  - אחרי זה ההמשך לא רושם את התשלום שוב.
- **שרת ישן בלי SA2** (404 NOT_FOUND): ההתנהגות הקודמת נשמרת.
- **מסך המסמך (D), מצב WAITING_FOR_ALLOCATION:** כרטיס בעברית פשוטה.
  - מה קורה: "המסמך ממתין למספר הקצאה", ולמה.
  - השורה "תשלום ממתין: ₪X ביט, יירשם כשיתקבל מספר ההקצאה", עם "ערוך" (סכום) ו"בטל תשלום" (אחרי אישור).
  - מה אפשר לעשות: לחכות, להזין מספר ידנית (אם מופעל ויש הרשאה), או לבטל את הבקשה. הביטול מסביר שגם התשלום הממתין יבוטל.
- **הודעת ההפקה:** "ממתין למספר הקצאה. התשלום נשמר ויירשם כשהמספר יגיע".

## שינויי חוזה API

| קריאה | שינוי |
|---|---|
| `POST /documents/:id/finalize` | שדה גוף אופציונלי `pendingPayments: [{method, amountMinor?, paymentDate?, currency?, reference?, bankNumber?, branchNumber?, accountNumber?}]` (עד 10). נשמר רק כשהתוצאה WAITING_FOR_ALLOCATION. אז התשובה כוללת `pendingPayments` (הממתינים). אם יש תשלומים בגוף, נדרשת ההרשאה payment:record. |
| `GET /documents/:id/pending-payments` | חדש: `{pendingPayments:[…]}`, כולל RECORDED ו-CANCELLED. |
| `POST /documents/:id/pending-payments` | חדש. Idempotency-Key חובה. ממתין: 201 PENDING. מסמך שכבר הופק: נרשם מיד (RECORDED). אותו מפתח: 200 עם `reused:true`. מצב אחר: 409 DOCUMENT_NOT_WAITING. |
| `PATCH /documents/:id/pending-payments/:paymentId` | חדש: עריכה בזמן ההמתנה. 409 PENDING_PAYMENT_NOT_PENDING. סכום מעל היתרה: 422 PENDING_PAYMENT_EXCEEDS_TOTAL. |
| `DELETE /documents/:id/pending-payments/:paymentId` | חדש: ביטול, אידמפוטנטי. תשלום שכבר נרשם: 409 PENDING_PAYMENT_ALREADY_RECORDED. |
| `GET /documents/:id` | `document.pendingPayments` (PENDING בלבד). |

- בלי `amountMinor`, הסכום הוא מה שפתוח במסמך (סך הכול פחות מה ששולם ופחות ממתינים אחרים). הסכום נקבע לפי הסכום שהשרת חישב, לא לפי החישוב בטלפון.
- אמצעי תשלום מורחבים (BIT וכו') עדיין דורשים `PAYMENT_METHODS_EXTENDED=1`, כמו ב-`/payments`.

## בדיקות

- **שרת, `packages/postgres/test/pending-payments.int.test.ts`:**
  - נשמר עם מסמך ממתין ונרשם בהשלמה.
  - לא נספר כהכנסה לפני כן (ספר, יתרה, פרטים).
  - אין כפילות בניסיון חוזר (השלמה, הוספה, העלאה מאוחרת), ומפתח זהה עם תוכן אחר נדחה כ-conflict.
  - פיצול לצ'ק וביט, ביטול ועריכה בזמן ההמתנה.
  - ביטול בקשת ההקצאה, אי-שינוי (trigger) ו-RLS.
  - מסלול עם מספר שמור (חשבונית ישראל, 320).
- **שרת, `apps/api/test/pending-payments-http.int.test.ts`:**
  - finalize עם pendingPayments, ניסיון חוזר באותו מפתח והשלמה.
  - העלאה אחרי finalize, עריכה וביטול.
  - הרשאה (403 לעובד), ולידציה, ומסמך שלא ממתין.
- **שרת, הסוויטה המלאה:**
  - `pnpm test:integration`: ‏94 קבצים, 2418 בדיקות ירוקות.
  - build, typecheck, lint ו-prettier ירוקים.
- **אפליקציה, `test/pending_payment_issue_test.dart`:**
  - finalize נושא את התשלום, והטלפון לא שומר עותק.
  - ההמשך לא רושם בעצמו.
  - העלאה בלי הד, ובלי רשת עם העלאה בפתיחה.
  - מיגרציה מגרסה ישנה, ושרת ישן.
- **אפליקציה, `test/document/document_screen_test.dart`:** הכרטיס, השורה "תשלום ממתין", ביטול, עריכה, וצופה בלי הרשאה.
- **אפליקציה, סה"כ:** `flutter analyze` נקי ו-`flutter test` ירוק.

## מה עוד פתוח

- **פיצול תשלום ישירות מההפקה** (סעיף 3 בפרסונה): השרת כבר מקבל עד 10 תשלומים. במסך ההפקה עדיין יש אמצעי תשלום אחד (compose_state, באחריות סוכן אחר).
- **עריכה במסך D:** אפשר לערוך רק את הסכום. כדי להחליף אמצעי תשלום, מבטלים ורושמים מחדש אחרי ההפקה.
- **נגיעות קטנות מחוץ לתחום** (לתיאום):
  - `lib/app_shell.dart`: שורת listener אחת להעלאה בפתיחה.
  - `lib/util/labels/labels.dart`: שורת export אחת.
  - `test/compose_screen_test.dart`: בדיקת גוף ה-finalize הוגמשה.
