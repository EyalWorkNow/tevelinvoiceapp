// Labels · ייבוא לקוחות (customer import / export from the לקוחות tab).
// F11: imperative verbs only; every visible string of the import flow is here.
library;

abstract final class ImportHe {
  // Entry points (P header ⋯ and the empty state).
  static const menuImport = 'ייבוא לקוחות';
  static const menuExport = 'ייצוא לקוחות לאקסל';
  static const emptyImportAction = 'ייבא לקוחות';
  static const exportReady = 'קובץ הלקוחות מוכן לשיתוף';
  static const exportFailed = 'הייצוא נכשל. נסו שוב.';

  // Step 1 · source
  static const title = 'ייבוא לקוחות';
  static const sourceIntro =
      'עוברים ממערכת אחרת? מביאים את כל הלקוחות בבת אחת — בלי להקליד מחדש.';
  static const sourceContacts = 'מאנשי הקשר בטלפון';
  static const sourceContactsSub = 'בוחרים כמה אנשי קשר שרוצים';
  static const sourceFile = 'מקובץ Excel או CSV';
  static const sourceFileSub =
      'חשבונית ירוקה, iCount, רווחית, EZcount, חשבשבת או כל קובץ לקוחות';
  static const whatsappHint =
      'הקובץ בוואטסאפ או במייל? פתחו אותו ← שיתוף ← "שמירה בקבצים", ואז בחרו אותו כאן.';
  static const readingFile = 'קורא את הקובץ…';
  static const loadingContacts = 'טוען אנשי קשר…';
  static const contactsDenied =
      'כדי לייבא מאנשי הקשר, יש לאפשר גישה לאנשי הקשר בהגדרות האייפון.';
  static const openSettings = 'פתח הגדרות';
  static const noContacts = 'לא נמצאו אנשי קשר עם שם';

  // Step 2a · contacts
  static const contactsTitle = 'בחירת אנשי קשר';
  static const contactsSearch = 'חיפוש איש קשר';
  static const selectAll = 'בחר הכל';
  static const clearAll = 'נקה בחירה';
  static const alreadyCustomer = 'כבר לקוח';
  static String selectedCount(int n) => n == 1 ? 'נבחר 1' : 'נבחרו $n';
  static String continueWith(int n) => 'המשך עם $n';

  // Step 2b · column mapping
  static const mappingTitle = 'התאמת עמודות';
  static String detected(String source, int rows) =>
      'זיהינו: $source · $rows שורות';
  static const mappingIntro =
      'בדקו שכל שדה מקבל את העמודה הנכונה. אפשר לשנות בלחיצה.';
  static const noHeaderNote =
      'לא מצאנו שורת כותרות בקובץ — בחרו לכל שדה את העמודה שלו.';
  static const notMapped = '— לא לייבא —';
  static const nameRequired = 'צריך לבחור עמודה לשם הלקוח';
  static const sample = 'לדוגמה';
  static const previewTable = 'תצוגה מקדימה';
  static const checkRows = 'בדוק את השורות';

  static const fieldLabels = <String, String>{
    'name': 'שם לקוח *',
    'taxId': 'ח.פ. / ת.ז.',
    'phone': 'טלפון',
    'mobile': 'נייד',
    'email': 'אימייל',
    'address': 'כתובת מלאה',
    'street': 'רחוב',
    'houseNumber': 'מספר בית',
    'city': 'עיר',
    'postalCode': 'מיקוד',
    'contactPerson': 'איש קשר',
    'notes': 'הערות',
    'paymentTerms': 'תנאי תשלום',
    'country': 'מדינה',
  };

  // Step 3 · review
  static const reviewTitle = 'בדיקה לפני ייבוא';
  static const checking = 'בודק את השורות…';
  static const tabNew = 'חדשים';
  static const tabDuplicates = 'כפולים';
  static const tabErrors = 'שגיאות';
  static String newCount(int n) => '$n חדשים';
  static String dupCount(int n) => '$n כבר קיימים';
  static String errCount(int n) => '$n עם שגיאות';
  static const duplicatesQuestion = 'מה לעשות עם לקוחות שכבר קיימים?';
  static const policySkip = 'דלג';
  static const policyMerge = 'השלם פרטים חסרים';
  static const policyCreate = 'צור בכל זאת';
  static const policySkipHelp = 'הלקוח הקיים נשאר כמו שהוא';
  static const policyMergeHelp =
      'רק שדות ריקים אצל הלקוח הקיים יתמלאו. שום פרט קיים לא נמחק.';
  static const policyCreateHelp = 'ייווצר לקוח נוסף (למשל סניף)';
  static String existing(String name, String by) => 'קיים: $name · $by';
  static const byTaxId = 'אותו ח.פ.';
  static const byPhone = 'אותו טלפון';
  static const byEmail = 'אותו מייל';
  static String sameAsRow(int row) => 'כפול לשורה $row בקובץ';
  static String rowLabel(int row) => 'שורה $row';
  static const fixRow = 'תקן שורה';
  static const fixHint = 'שורות עם שגיאה לא ייובאו. אפשר לתקן בלחיצה.';
  static const save = 'שמור';
  static const nothingToImport = 'אין שורות תקינות לייבוא';
  static String importN(int n) => n == 1 ? 'ייבא לקוח אחד' : 'ייבא $n לקוחות';
  static const rowPolicyTitle = 'ללקוח הזה';
  static const useDefault = 'כמו כולם';

  // Step 4 · progress / summary
  static String importing(int done, int total) => 'מייבא… $done מתוך $total';
  static const retrying = 'החיבור נקטע — מנסה שוב…';
  static const failedMidway =
      'הייבוא נעצר באמצע. מה שכבר נשמר נשאר; לחיצה על "נסה שוב" תמשיך מאותה נקודה בלי כפילויות.';
  static const tryAgain = 'נסה שוב';
  static const summaryTitle = 'הייבוא הסתיים';
  static String added(int n) => 'נוספו $n';
  static String updated(int n) => 'עודכנו $n';
  static String skipped(int n) => 'דולגו $n';
  static String errors(int n) => 'שגיאות $n';
  static const shareErrors = 'שתף רשימת שגיאות';
  static const done = 'סיום';
  static const errorsFileName = 'שגיאות-ייבוא-לקוחות.csv';
  static const errorsCsvHeader = 'שורה,שם,שדה,שגיאה';
}
