// Labels owned by squad D – people & expenses (SPEC-v2 §6.P, §6.P2, §6.E, S2).
// F11: imperative verbs only; every visible string of P, P2, S2 and E is here.
library;

abstract final class PeopleHe {
  // P · לקוחות
  static const title = 'לקוחות';
  static const addCustomer = '+ לקוח';
  static const addSupplier = '+ ספק';
  static const search = 'חיפוש';
  static const chipAll = 'הכל';
  static const chipDebtors = 'חייבים';
  static const chipSuppliers = 'ספקים';
  static const owesYou = 'חייב לך';
  static const archivedBadge = 'בארכיון';
  static const supplierBadge = 'ספק';
  static const emptyCustomers = 'עוד אין לקוחות. הוסף מאנשי הקשר →';
  static const emptyCustomersAction = 'הוסף מאנשי הקשר';
  static const emptySuppliers = 'עוד אין ספקים. ספק נוצר גם מצילום הוצאה.';
  static const emptyDebtors = 'אף לקוח לא חייב לך כרגע ✓';
  static const noMatches = 'לא נמצא. אפשר להוסיף לקוח חדש.';
  static const capped500 = 'מוצגים 500 הלקוחות האחרונים · לחיפוש מלא: המשך במחשב';

  // P2 · כרטיס
  static const call = 'חייג';
  static const whatsapp = 'ווטסאפ';
  static const mail = 'מייל';
  static String newDocFor(String name) => 'מסמך חדש ל-$name';
  static String newExpenseFrom(String name) => 'הוצאה חדשה מ-$name';
  static const detailsAndEdit = 'פרטים ועריכה';
  static const archive = 'ארכב';
  static String archiveWithBalance(String amount) => 'ללקוח יש $amount פתוח. לארכב בכל זאת?';
  static const archiveConfirm = 'לארכב את הלקוח?';
  static const archived = 'הלקוח הועבר לארכיון';
  static const documents = 'מסמכים';
  static const noDocuments = 'עוד אין מסמכים ללקוח הזה';
  static const notIssuedYet = 'עוד לא הופק';
  static const notFound = 'הלקוח לא נמצא';
  static const sendStatement = 'שלח כרטסת';
  static const statementPeriod = 'מתחילת השנה עד היום';
  static String statementFileName(String name) => 'כרטסת $name.pdf';
  static String statementSent(String email) => 'הכרטסת נשלחה ל-$email';
  static const supplierArchiveConfirm = 'לארכב את הספק?';
  static const supplierArchived = 'הספק הועבר לארכיון';

  // S2 · לקוח
  static const pickTitle = 'לקוח';
  static const pickQuestion = 'ממי?';
  static const searchContacts = 'חיפוש באנשי קשר';
  static const existingCustomer = 'לקוח קיים';
  static const mostActive = 'הכי פעילים אצלך';
  static const yourContacts = 'אנשי הקשר שלך';
  static const pickSupplierTitle = 'ספק';
  static const walkIn = 'לקוח מזדמן';
  static const walkInHint = 'לקוח עסקי שצריך לקזז מע״מ? בחר אותו בשם';
  static const newCustomer = '+ לקוח חדש';
  static const newSupplier = '+ ספק חדש';
  static const newCustomerTitle = 'לקוח חדש';
  static const newSupplierTitle = 'ספק חדש';
  static const editTitle = 'פרטים ועריכה';
  static const name = 'שם';
  static const phone = 'טלפון';
  static const email = 'אימייל';
  static const taxId = 'ע.מ. / ח.פ. (לא חובה)';
  static const contactPerson = 'איש קשר';
  static const notes = 'הערות';
  static const paymentTerms = 'תנאי תשלום';
  static const address = 'כתובת';
  static const street = 'רחוב';
  static const houseNumber = 'מספר';
  static const city = 'עיר';
  static const postalCode = 'מיקוד';
  static const cityRequired = 'צריך עיר';
  static const accountKey = 'מפתח חשבון';
  static const consentSwitch = 'לשלוח לו מסמכים בווטסאפ ובמייל';
  static const consentHint = 'דולק = הלקוח הסכים לקבל מסמכים דיגיטליים';
  static const nameRequired = 'צריך שם';
  static const phoneInvalid = 'מספר הטלפון לא נראה תקין';
  static const emailInvalid = 'כתובת האימייל לא תקינה';
  static const taxIdInvalid = 'המספר לא תקין — בדוק את הספרות';
  static String alreadyExists(String name) => 'כבר קיים: $name';
  static const useExisting = 'השתמש בו';
  static const contactsFailed = 'לא הצלחנו לפתוח את אנשי הקשר';
  static const saving = 'שומר…';
  static const editNote = 'השינוי לא משנה מסמכים שכבר הופקו';

  /// BE-09 payment terms codes → words (§10).
  static const Map<String, String> paymentTermsLabels = {
    'IMMEDIATE': 'מיידי',
    'EOM': 'שוטף',
    'EOM_30': 'שוטף+30',
    'EOM_45': 'שוטף+45',
    'EOM_60': 'שוטף+60',
    'EOM_90': 'שוטף+90',
  };
}

abstract final class ExpenseHe {
  static const title = 'הוצאות';
  static String progress(int i, int n) => '$i מתוך $n';
  static const approve = 'אשר';
  static const save = 'שמור';
  static const approving = 'מאשר…';
  static const skip = 'דלג';
  static const reject = 'דחה';
  static const rejectTitle = 'למה?';
  static const rejectHint = 'סיבת הדחייה';
  static const rejectRequired = 'צריך סיבה';
  static const supplier = 'ספק';
  static const chooseSupplier = 'בחר ספק';
  static const amount = 'סכום כולל מע״מ';
  static const date = 'תאריך';
  static const chooseDate = 'בחר תאריך';
  static const category = 'קטגוריה';
  static const more = 'עוד';
  static const docNumber = 'מספר מסמך';
  static const vat = 'מע״מ';
  static const required = 'חובה';
  static String missing(String fields) => 'חסר: $fields';
  static const reading = 'קורא את הקבלה…';
  static const scanning = 'בודק את הקובץ…';
  static const readFailed = 'לא הצלחנו לקרוא את הקבלה. מלא ידנית.';
  static const errorCard = 'לא הצלחנו לעבד את הקובץ. צלם שוב.';
  static String duplicateOf(String date) => 'נראה כמו הוצאה מ-$date · אותה הוצאה?';
  static const duplicateUnknown = 'נראה כמו הוצאה שכבר הועלתה · אותה הוצאה?';
  static const duplicateYes = 'כן, אותה הוצאה';
  static const duplicateNo = 'לא';
  static const approved = 'ההוצאה אושרה ✓';
  static const saved = 'נשמר לבדיקה ✓';
  static const rejected = 'ההוצאה נדחתה';
  static const allDone = 'אין הוצאות לבדיקה ✓';
  static const capture = 'צלם הוצאה';
  static const allExpenses = 'כל ההוצאות';
  static const review = 'לבדיקה';
  static const chipAll = 'הכל';
  static const chipMine = 'שלי';
  static const emptyList = 'עוד אין הוצאות';
  static const image = 'תמונת הקבלה';
  static const pdf = 'קובץ PDF';
  static const searchHint = 'חיפוש לפי ספק, מספר או סכום';
  static const delete = 'מחק';
  static const deleteConfirm = 'למחוק את ההוצאה? היא לא תיכלל בדוחות.';
  static const deleted = 'ההוצאה נמחקה';
  static const updated = 'ההוצאה עודכנה ✓';
  static const editTitle = 'עריכת הוצאה';

  // Capture (＋ → הוצאה)
  static const noCameraAccess = 'אין גישה למצלמה. אפשר לאשר בהגדרות של האייפון.';
  static const noPhotosAccess = 'אין גישה לתמונות. אפשר לאשר בהגדרות של האייפון.';
  static const cameraUnavailable = 'המצלמה לא זמינה — אפשר לבחור תמונה מהגלריה';
  static const galleryFailed = 'לא הצלחנו לפתוח את הגלריה';
  static const imageUnreadable = 'לא הצלחנו לקרוא את התמונה. צלם שוב או בחר תמונה אחרת.';
  static const filesFailed = 'לא הצלחנו לפתוח את הקבצים';
  static const fileTooBig = 'הקובץ גדול מדי — עד 20MB';
  static const pdfInvalid = 'הקובץ אינו PDF תקין. בחר קובץ אחר או צלם את הקבלה.';
  static const captureTitle = 'צילום הוצאה';
  static const captureHeadline = 'צלם את הקבלה מהספק';
  static const captureSub = 'היא תגיע לתיבת ההוצאות לבדיקה';
  static const openSettings = 'פתח הגדרות';
  static const offlineCapture = 'אין חיבור — אפשר לשלוח הוצאה רק כשיש רשת';
  static const shoot = 'צלם';
  static const fromGallery = 'בחר מהגלריה';
  static const pickPdf = 'בחר PDF';
  static const preparing = 'מכין את התמונה…';
  static const uploading = 'מעלה את הקבלה…';
  static const received = 'הקבלה התקבלה';
  static const captured = 'ההוצאה נקלטה ✓';
  static const stillScanning = 'הבדיקה נמשכת ברקע — היא תופיע בתיבת ההוצאות בעוד רגע';
  static const willAppear = 'תופיע בהוצאות לבדיקה';
  static const uploadedBefore = 'נראה שהקבלה הזו כבר הועלתה בעבר';
  static const finish = 'סיום';
  static const captureAnother = 'צלם עוד הוצאה';
  static const blocked = 'הקובץ נחסם מטעמי אבטחה';
  static const sendFailed = 'השליחה לא הצליחה';
  static const blockedHint = 'צלם את הקבלה מחדש. אם זה חוזר — פנה לתמיכה.';
  static const reshoot = 'צלם שוב';

  /// Server expense status → list word.
  static const Map<String, String> statusLabels = {
    'UPLOADED': 'בקליטה',
    'SCANNING': 'בבדיקה',
    'NORMALIZING': 'בקליטה',
    'EXTRACTING': 'בקריאה',
    'NEEDS_REVIEW': 'לבדיקה',
    'READY_TO_APPROVE': 'לבדיקה',
    'APPROVED': 'אושרה',
    'REJECTED': 'נדחתה',
    'DUPLICATE': 'כפולה',
    'ERROR': 'שגיאה',
  };
}
