// Hebrew messages by server error code.
// _webMessages and _validationMessages are a verbatim port of
// invoiceproject apps/web/src/api.ts (ERROR_MESSAGES_HE / VALIDATION_MESSAGES_HE).
// Mobile-only and new-contract codes live in _mobileMessages.

/// Hebrew message for a server error [code] (+ the raw server `message`,
/// used only for VALIDATION). [status] drives the fallback for unknown codes.
String errorMessageHe(String code, {String? serverMessage, int status = 0}) {
  if (code == 'VALIDATION') return validationMessageHe(serverMessage);
  final known = _mobileMessages[code] ?? _webMessages[code];
  if (known != null) return known;
  // The server already wrote a Hebrew sentence for codes the app does not know.
  final server = serverMessage?.trim();
  if (server != null && server.length <= 300 && _hebrew.hasMatch(server)) {
    return server;
  }
  if (status == 429) return _webMessages['RATE_LIMITED']!;
  if (status == 503 || status == 502 || status == 504) {
    return _mobileMessages['SERVICE_UNAVAILABLE']!;
  }
  return 'שגיאה לא צפויה ($code)';
}

final RegExp _hebrew = RegExp(r'[\u05D0-\u05EA]');

/// CRM changes the server refused for good (kept in a backup file on the device).
String crmRejectedNoticeHe(int count) => count == 1
    ? 'שינוי אחד בתיק הלקוח נדחה על ידי השרת ולא נשמר. עותק נשמר במכשיר.'
    : '$count שינויים בתיקי לקוחות נדחו על ידי השרת ולא נשמרו. עותק נשמר במכשיר.';

/// VALIDATION carries a meaningful English server message; the common ones in Hebrew.
String validationMessageHe(String? raw) {
  final text = (raw ?? '').replaceFirst(RegExp(r'^VALIDATION:\s*'), '').trim();
  if (text.isEmpty) return _webMessages['VALIDATION']!;
  final exact = _validationMessages[text];
  if (exact != null) return exact;
  if (text.startsWith('logo image is too large')) {
    return 'קובץ הלוגו גדול מדי (עד ~512KB)';
  }
  var m = RegExp(r'^(.+) must be at most (\d+) characters$').firstMatch(text);
  if (m != null) return 'השדה "${m[1]}" ארוך מדי (עד ${m[2]} תווים)';
  m = RegExp(r'^(.+) must be text$').firstMatch(text);
  if (m != null) return 'השדה "${m[1]}" חייב להיות טקסט';
  m = RegExp(r'^(.+) must be one of: (.+)$').firstMatch(text);
  if (m != null) return 'השדה "${m[1]}" חייב להיות אחד מ: ${m[2]}';
  m = RegExp(r'^unknown permission: (.+)$').firstMatch(text);
  if (m != null) return 'הרשאה לא מוכרת: ${m[1]}';
  return 'הנתונים לא תקינים: $text';
}

const Map<String, String> _mobileMessages = {
  'SUPABASE_AUTH_DISABLED': 'שירות ההתחברות עדיין לא הוגדר. פנו לתמיכה.',
  'SUPABASE_AUTH_UNAVAILABLE':
      'שירות ההתחברות לא זמין זמנית. נסו שוב בעוד רגע.',
  'SUPABASE_TOKEN_INVALID': 'לא ניתן לאמת את ההתחברות. נסו להתחבר שוב.',
  'SUPABASE_EMAIL_NOT_CONFIRMED':
      'כתובת האימייל עדיין לא אושרה. פתחו את הקישור שנשלח אליכם ואז התחברו.',
  'SUPABASE_USER_BANNED': 'החשבון הזה חסום להתחברות. פנו לתמיכה.',
  'SUPABASE_LOGIN_INVALID_INPUT': 'יש להזין כתובת אימייל וסיסמה תקינות.',
  'SUPABASE_RECOVERY_SUPPORT_REQUIRED': 'לאיפוס הסיסמה בחשבון זה פנו לתמיכה.',
  'CRM_CONFLICT': 'המידע עודכן במכשיר אחר. השינויים שלך שמורים עד לבחירת גרסה.',
  'CRM_MUTATION_REUSED': 'לא ניתן לאשר את הסנכרון הזה. יש לרענן את תיק הלקוח.',
  'PAYMENT_METHOD_NOT_AVAILABLE':
      'ביט אינו פעיל במסוף הזה. אפשר לבחור כרטיס או להפעיל את השירות בקארדקום.',
  'SMS_UNAVAILABLE':
      'שליחת SMS אינה זמינה במכשיר הזה. אפשר לקבל את המסמך בסריקה או במייל.',
  'SMS_FAILED': 'ההודעה לא נשלחה. ניתן לנסות שוב.',

  'BUSINESS_MERCHANT_NOT_CONFIGURED':
      'יש לחבר את מסוף קארדקום של העסק דרך חיבורים ושליחה.',
  'MERCHANT_VAULT_UNAVAILABLE':
      'שמירת פרטי הסליקה אינה זמינה כרגע. יש לפנות לתמיכה.',
  'PAYMENT_LINK_BALANCE_CHANGED':
      'היתרה או המסוף השתנו. יש לבדוק את דף התשלום הקיים בקארדקום לפני קישור חדש.',
  'DOCUMENT_NOT_PAYABLE':
      'המסמך אינו פתוח לתשלום. בדוק אם כבר שולם, בוטל או הומר.',

  'EXPENSE_VAT_NOT_RECOVERABLE':
      'לעוסק פטור אין קיזוז מע״מ תשומות. יש לבחור 0%.',
  'SUBSCRIPTION_REQUIRED':
      'להפקת מסמכים נדרש מסלול פעיל. ניתן לבחור מסלול בניהול העסק.',
  'INVOICE_QUOTA_EXCEEDED':
      'מכסת מסמכי ההכנסה החודשית נוצלה. ניתן לשדרג מסלול בניהול העסק.',
  'PAYMENT_NOT_CONFIGURED': 'התשלום ייפתח לאחר השלמת חיבור הסליקה לעסק.',
  'PAYMENT_NOT_COMPLETE': 'ממתינים לאישור התשלום. ניתן לבדוק שוב בעוד רגע.',
  'PAYMENT_DECLINED': 'התשלום לא אושר. ניתן לבדוק את אמצעי התשלום ולנסות שוב.',
  'PAYMENT_MISMATCH':
      'פרטי התשלום עדיין לא אומתו. יש לפנות לתמיכה לפני ניסיון נוסף.',
  'CHECKOUT_PENDING':
      'יש לעסק דף תשלום פתוח. יש להשלים אותו או להמתין לפקיעתו.',
  'CUSTOMER_CONTACT_MISSING':
      'יש להוסיף ללקוח כתובת מייל או מספר טלפון למשלוח.',
  'WHATSAPP_NOT_CONFIGURED':
      'משלוח WhatsApp אוטומטי ייפתח לאחר חיבור החשבון העסקי.',
  'WHATSAPP_DELIVERY_UNKNOWN':
      'מצב המשלוח עדיין בבדיקה אצל הספק. אין צורך לשלוח שוב.',
  // QA 2026-11-12 (report 04 · M1): server codes the app did not map.
  'CUSTOMER_PHONE_INVALID':
      'מספר הטלפון של הלקוח אינו תקין. יש לתקן אותו בכרטיס הלקוח.',
  'WHATSAPP_SEND_FAILED':
      'הודעת ה-WhatsApp לא נשלחה אצל הספק. אפשר לשלוח שוב או לשתף בקישור.',
  'BILLING_CONSENT_REQUIRED': 'יש לאשר את פרטי המסלול לפני ההמשך.',
  'PLAN_INVALID': 'יש לבחור מסלול תקין.',
  'APPLE_TRANSACTION_ALREADY_LINKED':
      'הרכישה הזו כבר משויכת לעסק אחר. פנו לתמיכה לשיוך מחדש.',
  'APPLE_ACCOUNT_MISMATCH':
      'הרכישה שייכת לחשבון Apple אחר. היכנסו עם החשבון שביצע את הרכישה.',
  'IDEMPOTENCY_KEY_INVALID': 'הבקשה לא תקינה — נסו שוב',
  'ACCOUNT_ALREADY_EXISTS': 'כבר קיים חשבון עם הכתובת הזו. אפשר להתחבר אליו.',
  'EMAIL_INVALID': 'כתובת האימייל אינה תקינה',
  'BUSINESS_NAME_INVALID': 'שם העסק אינו תקין',
  'TAX_RATE_MISSING': 'לא מוגדר שיעור מע״מ לתאריך הזה. פנו לתמיכה.',
  'QUOTE_CHANGED': 'הצעת המחיר עודכנה בינתיים. פתחו אותה שוב ובדקו לפני ההמשך.',
  'PUSH_MFA_REQUIRED':
      'התראות למכשיר זמינות רק אחרי אימות דו-שלבי. התנתקו והתחברו שוב עם קוד אימות.',
  'API_CONFIG_INVALID': 'כתובת השרת בגרסה הזו אינה תקינה. פנו לתמיכה.',
  // Client-side (no HTTP response).
  'NETWORK': 'אין חיבור לשרת — בדקו את החיבור לאינטרנט ונסו שוב',
  'TIMEOUT': 'השרת לא הגיב בזמן — נסו שוב',
  'BAD_RESPONSE': 'התקבלה תשובה לא תקינה מהשרת — נסו שוב',
  'SERVICE_UNAVAILABLE': 'השירות לא זמין זמנית — נסו שוב בעוד רגע',
  // Mobile wording overrides (no "refresh the page" on a phone).
  'UNAUTHENTICATED': 'פג תוקף ההתחברות — התחברו מחדש',
  'SESSION_INVALID': 'פג תוקף ההתחברות — התחברו מחדש',
  'CSRF_INVALID': 'פג תוקף ההתחברות — התחברו מחדש',
  'RATE_LIMITED': 'יותר מדי ניסיונות — נסו שוב בעוד דקה',
  'IDEMPOTENCY_CONFLICT': 'הפעולה כבר בוצעה — רעננו את המסך',
  'CONFLICT': 'הנתונים השתנו בינתיים — רעננו את המסך ונסו שוב',
  'UNSUPPORTED_MEDIA_TYPE': 'בקשה לא תקינה — נסו שוב',
  'NO_LINKED_ACCOUNT':
      'לא מצאנו חשבון לכתובת הזו. בקשו מבעל העסק להזמין אתכם, או היכנסו עם Apple.',
  'INVALID_ID': 'הקישור אינו תקין',
  // New mobile contract (CONTRACT A–I).
  'APPLE_TOKEN_INVALID': 'אימות Apple נכשל — נסו שוב',
  'APPLE_SIGNIN_DISABLED': 'התחברות עם Apple אינה מופעלת בשרת',
  'APPLE_IDENTITY_MISMATCH': 'החשבון מקושר לזהות Apple אחרת — פנו למנהל העסק',
  'CUSTOMER_NOT_FOUND': 'הלקוח לא נמצא',
  'EXEMPT_BUSINESS_VAT_FORBIDDEN':
      'עוסק פטור אינו רשאי לגבות מע״מ — הסכום יופק ללא מע״מ',
  'DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS':
      'סוג המסמך הזה אינו מותר לסוג העסק שלך',
  'SHARE_LINK_NOT_FOUND': 'הקישור למסמך לא נמצא או שפג תוקפו',
  // V2 (SPEC-v2-he.md §4, §8.3, §12, §14). 403s also refresh capabilities (§4.6).
  'FORBIDDEN': 'ההרשאות שלך עודכנו',
  'DOCUMENT_ACTION_FORBIDDEN': 'ההרשאות שלך עודכנו',
  'CREDIT_SOURCE_TYPE_INVALID':
      'אפשר להפיק זיכוי רק לחשבונית מס או לחשבונית מס-קבלה',
  'BACKDATING_OWNER_ONLY': 'רק בעל העסק יכול להפיק מסמך בתאריך עבר',
  'FUTURE_ISSUE_DATE':
      'אי אפשר להפיק מסמך בתאריך עתידי. שנה את תאריך המסמך להיום או לתאריך קודם',
  'APPROVAL_NO_OTHER_APPROVER':
      'אין בעסק מאשר נוסף — אי אפשר לחייב אישור של מישהו אחר',
  'PAYMENT_LOCKED_IN_DOCUMENT':
      'התשלום כבר כלול במסמך שהופק. לחשבונית מס-קבלה הפק זיכוי; ביטול קבלה — המשך במחשב',
  'SECTION46_APPROVAL_REQUIRED':
      'קבלה על תרומה דורשת מספר אישור סעיף 46 בפרטי העסק',
  'INVITATION_EXPIRED': 'ההזמנה כבר לא בתוקף. בקש מהמזמין לשלוח שוב',
  'INVITATION_REVOKED': 'ההזמנה כבר לא בתוקף. בקש מהמזמין לשלוח שוב',
  'CUSTOMER_VAT_STATUS_UNKNOWN': 'צריך לדעת אם הלקוח עוסק מורשה לפני ההפקה',
  'CUSTOMER_VAT_NUMBER_MISSING': 'חסר מספר עוסק מורשה של הלקוח',
  // V2 server codes (docs/API-MOBILE.md "All V2 error codes → Hebrew" = apps/web/src/api.ts).
  'MEMBER_NOT_FOUND': 'החבר לא נמצא בעסק או שאינו פעיל',
  'ALREADY_OWNER': 'החבר הזה כבר בעלים של העסק',
  'OWNERSHIP_CODE_THROTTLED': 'נשלח קוד לפני רגע — נסה שוב בעוד דקה',
  'OWNERSHIP_CODE_INVALID': 'הקוד שגוי',
  'OWNERSHIP_CODE_EXPIRED': 'הקוד פג או נוצל — בקש קוד חדש',
  'PAYMENT_VOIDED': 'התשלום בוטל ולא ניתן להשתמש בו.',
  'PAYMENT_NOT_FOUND': 'התשלום לא נמצא.',
  'PAYMENT_METHOD_NOT_ENABLED':
      'אמצעי התשלום עדיין לא זמין. רשום אותו כהעברה בנקאית.',
  'DOCUMENT_VOID_NOT_ALLOWED':
      'אפשר לבטל כך רק חשבון עסקה, הזמנה או הזמנת רכש שהופקו.',
  'DOCUMENT_ALREADY_VOIDED': 'המסמך כבר בוטל.',
  'DOCUMENT_HAS_PAYMENTS': 'יש תשלום על המסמך. בטל קודם את הקבלה במחשב.',
  'CLONE_TYPE_NOT_ALLOWED': 'אי אפשר לשכפל לסוג המסמך הזה.',
  'ALLOCATION_NUMBER_RESERVED':
      'המספר כבר שמור ברשות המסים – אי אפשר לבטל את הבקשה. בחר "המשך בלי מספר" או נסה שוב.',
  'ITEM_NOT_FOUND': 'הפריט לא נמצא',
  'WEB_HANDOFF_THROTTLED':
      'נשלחו יותר מדי קישורים בשעה האחרונה. נסה שוב מאוחר יותר.',
  'EMAIL_MISSING': 'לחשבון אין כתובת אימייל',
  'EMAIL_UNAVAILABLE': 'לא הצלחנו לשלוח את המייל. נסה שוב.',
  'DONATION_REPORTING_DISABLED': 'דיווח תרומות לרשות המסים עדיין לא מחובר',
  'DONATION_REPORTING_TRANSIENT': 'מערכת דיווח התרומות לא זמינה כרגע. נסה שוב.',
  'DONATION_REPORT_NOT_APPLICABLE': 'רק קבלה על תרומה מדווחת למערכת התרומות',
  'DONATION_NOT_REPORTED': 'הקבלה עוד לא דווחה, ולכן אין מה לבטל',
  'FINALIZATION_EVIDENCE_MISSING': 'המסמך עוד לא הופק',
  'SUPPLIER_NOT_FOUND': 'הספק לא נמצא',
  'EXPENSE_BUSY': 'ההוצאה עדיין בעיבוד. נסה שוב בעוד רגע.',
  'EXPENSE_DUPLICATE': 'כבר קיימת הוצאה מאושרת מאותו ספק עם אותו מספר מסמך',
  'EXPENSE_DELETED': 'ההוצאה נמחקה',
  'REPORT_NOT_FOUND': 'הדוח לא נמצא',
  'REPORT_NOT_APPLICABLE':
      'הדוח אינו רלוונטי לסוג העסק (לעוסק פטור אין דוח מע"מ)',
  'ACCOUNTANT_EMAIL_MISSING': 'חסר מייל של רואה החשבון בפרטי העסק',
  'CUSTOMER_EMAIL_MISSING': 'ללקוח אין כתובת אימייל',
  'QUOTE_EXPIRED': 'תוקף הצעת המחיר פג',
  'QUOTE_NOT_ACCEPTABLE': 'הצעת המחיר אינה זמינה לאישור',
  'BUSINESS_TYPE_CHANGE_NOT_SUPPORTED':
      'באפליקציה אפשר לעבור רק מעוסק פטור לעוסק מורשה. לשינוי אחר – המשך במחשב.',
  'BUSINESS_TYPE_CHANGE_CONFLICT':
      'כבר הופקו מסמכים כעוסק פטור מתאריך התחולה ואילך. בחר תאריך מאוחר יותר.',
  'BUSINESS_TYPE_CHANGE_PENDING':
      'כבר נקבע שינוי סוג עסק. אפשר לבטל אותו ולקבוע מחדש.',
  'BUSINESS_TYPE_CHANGE_NOT_FOUND': 'אין שינוי סוג עסק מתוזמן',
  'CREDIT_LIMIT_EXCEEDED': 'הסכום גבוה מהיתרה שאפשר לזכות',
  'APPROVAL_REQUIRED':
      'הסכום מעל סף האישור. שנה את המדיניות בעסק → אישורים או הקטן את הסכום',
  'SHAAM_AUTHORIZATION_REQUIRED':
      'נדרש חיבור לרשות המסים (עסק → רשות המסים וחתימה)',
  'SIGNING_LOCKED': 'החתימה נעולה — היא תשוחרר ב-Face ID בהפקה הבאה',
};

const Map<String, String> _webMessages = {
  'INVITATION_INVALID': 'ההזמנה פגה, בוטלה או כבר נוצלה — בקש הזמנה חדשה',
  'INVITATION_EMAIL_MISMATCH':
      'יש להיכנס עם חשבון Google של הכתובת שאליה נשלחה ההזמנה',
  'MEMBER_EXISTS': 'הכתובת הזו כבר משתמש בעסק',
  'INVITATION_USE_GOOGLE':
      'החשבון הזה נכנס עם Google — קבלו את ההזמנה בלחיצה על «המשך עם Google»',
  'MFA_LOCKED': 'יותר מדי ניסיונות שגויים. נסו שוב בעוד 15 דקות',
  'UNSUPPORTED_MEDIA_TYPE': 'בקשה לא תקינה — רעננו את הדף ונסו שוב',
  'USER_EXISTS': 'לכתובת זו כבר יש חשבון — שלחו הזמנה במקום',
  'PASSKEY_INVALID': 'האימות במכשיר לא הצליח — נסה שוב',
  'MFA_LAST_METHOD': 'זו שיטת האימות היחידה — הוסף שיטה אחרת לפני ההסרה',
  'MFA_EMAIL_THROTTLED': 'נשלח קוד לפני רגע — המתינו מעט לפני שליחה חוזרת',
  'MFA_EMAIL_UNAVAILABLE': 'שליחת קודים במייל אינה זמינה בשרת זה',
  'VALIDATION': 'קלט לא תקין — בדקו את השדות ונסו שוב',
  'INVALID_JSON': 'הבקשה לא תקינה',
  'BUSINESS_REQUIRED': 'יש לבחור עסק לפני הפעולה',
  'INVALID_CREDENTIALS': 'האימייל או הסיסמה שגויים',
  'INTERNAL': 'תקלה בשרת',
  'UNAUTHENTICATED': 'נדרשת התחברות מחדש',
  'SESSION_INVALID': 'פג תוקף החיבור — התחבר מחדש',
  'CSRF_INVALID': 'פג תוקף הטופס — רעננו את הדף ונסו שוב',
  'MFA_REQUIRED': 'נדרש קוד אימות דו-שלבי',
  'MFA_CODE_INVALID': 'קוד האימות שגוי',
  'MFA_NOT_ENROLLED': 'אימות דו-שלבי לא הוגדר לחשבון זה',
  'MFA_NOT_PENDING': 'אין תהליך אימות פתוח — התחבר מחדש',
  'RESET_TOKEN_INVALID': 'אסימון האיפוס שגוי או שפג תוקפו',
  'GOOGLE_TOKEN_INVALID': 'אימות Google נכשל — נסה שוב',
  'NO_LINKED_ACCOUNT':
      'אין חשבון פעיל המשויך לכתובת Google זו. פנה למנהל המערכת.',
  'GOOGLE_SIGNIN_DISABLED': 'התחברות Google אינה מופעלת בשרת',
  'NOT_FOUND': 'הפריט המבוקש לא נמצא (ייתכן שנמחק או שאין לכם גישה אליו)',
  'DOCUMENT_NOT_FOUND': 'המסמך לא נמצא',
  'EXPENSE_NOT_FOUND': 'ההוצאה לא נמצאה',
  'QUOTE_NOT_FOUND': 'הצעת המחיר לא נמצאה',
  'EXPORT_NOT_FOUND': 'הייצוא לא נמצא',
  'PAYLOAD_TOO_LARGE': 'הקובץ או הבקשה גדולים מדי',
  'RATE_LIMITED': 'יותר מדי בקשות — המתינו רגע ונסו שוב',
  'DOCUMENT_ACTION_FORBIDDEN': 'אין לתפקיד שלך הרשאה לפעולה זו. פנו לבעל העסק.',
  'DOCUMENT_INVALID_TRANSITION': 'לא ניתן לבצע מעבר סטטוס זה למסמך',
  'QUOTE_INVALID_TRANSITION': 'לא ניתן לבצע מעבר סטטוס זה להצעת המחיר',
  'DOCUMENT_SEQUENCE_ERROR': 'שגיאה ברצף מספרי המסמכים — פנה לתמיכה',
  'ORIGINAL_ARTIFACT_REGENERATION_FORBIDDEN': 'למסמך כבר יש קובץ מקור',
  'APPROVAL_REQUIRED': 'המסמך דורש אישור לפני הפקה',
  'APPROVAL_SELF_FORBIDDEN': 'לא ניתן לאשר מסמך שיצרת בעצמך (הפרדת תפקידים)',
  'PAYMENT_AMOUNT_INVALID': 'סכום התשלום אינו תקין',
  'PAYMENT_CURRENCY_MISMATCH': 'מטבע התשלום אינו תואם את מטבע המסמך',
  'PAYMENT_ALLOCATION_INVALID': 'שיוך התשלום אינו תקין',
  'PAYMENT_OVERALLOCATED': 'סכום התשלום עולה על היתרה לתשלום',
  'MONEY_CURRENCY_MISMATCH': 'אי-התאמה בין מטבעות',
  'INVALID_TAX_CALCULATION': 'חישוב המס אינו תקין',
  'TAX_RULE_NOT_FOUND': 'לא נמצא כלל מס מתאים',
  'INSUFFICIENT_STOCK': 'אין מספיק מלאי לביצוע הפעולה',
  'WAREHOUSE_REQUIRED': 'יש לבחור מחסן',
  'INVENTORY_ITEM_REQUIRED': 'יש לבחור פריט מלאי',
  'PARTY_REQUIRED': 'יש לבחור לקוח או ספק',
  'ARTIFACT_REQUIRED': 'חסר קובץ מקור לפעולה זו',
  'CONSENT_REQUIRED': 'נדרשת הסכמה לפני ביצוע הפעולה',
  'IDEMPOTENCY_CONFLICT': 'הפעולה כבר בוצעה — רעננו את המסך',
  'IDEMPOTENCY_KEY_REQUIRED': 'שגיאה טכנית בבקשה — נסה שוב',
  'ALLOCATION_REJECTED': 'רשות המסים דחתה את בקשת ההקצאה',
  'ALLOCATION_NOT_ELIGIBLE': 'מספר הקצאה אינו חל על מסמך זה',
  'ALLOCATION_NOT_REQUIRED':
      'מספר הקצאה אינו נדרש למסמך זה (ניתן לבקש וולונטרית)',
  'SHAAM_DISABLED': 'השילוב עם רשות המסים אינו מופעל בשרת',
  'SHAAM_KILL_SWITCH': 'בקשות אוטומטיות לרשות המסים מושבתות זמנית — מצב ידני',
  'SHAAM_TEMPORARILY_UNAVAILABLE':
      'רשות המסים אינה זמינה כרגע — נסה שוב בעוד רגע',
  'SHAAM_AUTHORIZATION_REQUIRED':
      'נדרש חיבור לרשות המסים (הגדרות → חשבוניות ישראל)',
  'SHAAM_STATE_INVALID': 'החזרה מרשות המסים אינה תקפה — התחל את החיבור מחדש',
  'SHAAM_OAUTH_FAILED': 'ההרשאה מול רשות המסים נכשלה',
  'SHAAM_LOCAL_VALIDATION': 'נתוני החשבונית אינם עומדים בדרישות רשות המסים',
  'SHAAM_SCHEMA': 'הבקשה אינה תואמת את הסכמה של רשות המסים',
  'SHAAM_MANUAL_ENTRY_DISABLED': 'הזנה ידנית של מספר הקצאה אינה מופעלת',
  'ALLOCATION_PENDING': 'בקשת ההקצאה ממתינה לרשות המסים',
  'ALLOCATION_OUTCOME_UNKNOWN': 'תוצאת ההקצאה טרם ידועה — נסה לבצע התאמה',
  'ALLOCATION_RECONCILE_DEFERRED':
      'ההתאמה מול רשות המסים תושלם בעוד רגע — מסמך זהה עדיין ממתין לתשובה',
  'ALLOCATION_IDENTICAL_FACTS_PENDING':
      'מסמך אחר עם נתונים זהים ממתין לתשובת רשות המסים — הבקשה תישלח אחרי שתוצאתו תתברר',
  'ALLOCATION_NUMBER_HELD':
      'מספר ההקצאה כבר רשום על מסמך אחר של העסק — בדוק את המספר שהוזן',
  'ALLOCATION_ALREADY_RESOLVED': 'בקשת ההקצאה כבר הוכרעה',
  'ALLOCATION_RULE_NOT_CONFIGURED': 'כללי הקצאת מספרים אינם מוגדרים',
  'EXPENSE_NOT_EDITABLE':
      'הוצאה זו אינה ניתנת לעריכה במצבה הנוכחי (כפולה / מאושרת / נדחתה)',
  'EXPENSE_NOT_REVIEWABLE': 'זיהוי אוטומטי אפשרי רק להוצאה בבדיקה',
  'EXPENSE_DUPLICATE_SELF': 'לא ניתן לסמן הוצאה ככפולה של עצמה',
  'EXPENSE_DUPLICATE_TARGET': 'ההוצאה שנבחרה כמקור היא בעצמה כפולה או נדחתה',
  'EXPENSE_INVALID_TRANSITION': 'הפעולה אינה מותרת במצב הנוכחי של ההוצאה',
  'GOOGLE_IDENTITY_MISMATCH': 'החשבון מקושר לזהות Google אחרת — פנו למנהל העסק',
  'GOOGLE_PROVIDER_UNTRUSTED': 'התחברות Google לא אומתה — נסו שוב',
  'DOCUMENT_NOT_FINAL': 'הפעולה דורשת מסמך סופי',
  'PASSWORD_POLICY': 'סיסמה חלשה: לפחות 12 תווים, לא תו חוזר, לא סיסמה נפוצה',
  'PAYMENT_CHECK_DETAILS_REQUIRED':
      'תשלום בהמחאה מחייב מספר בנק, סניף, חשבון ומספר המחאה',
  'VAT_RATE_NOT_STATUTORY':
      'שיעור המע״מ בשורה אינו השיעור הסטטוטורי לתאריך המסמך',
  'UNIFORM_FORMAT_IDENTITY_UNSET':
      'זהות התוכנה לייצוא מבנה אחיד טרם הוגדרה בשרת',
  'EXTRACTION_UNAVAILABLE':
      'שירות הזיהוי האוטומטי אינו זמין כרגע — ניתן להזין את הנתונים ידנית ולשמור',
  'DB_UNAVAILABLE': 'השרת אינו זמין כרגע — נסה שוב בעוד רגע',
  'CONSTRAINT_VIOLATION':
      'הנתונים אינם עומדים בכללי המערכת — בדקו את השדות ונסו שוב',
  'SESSION_AUTH_DISABLED': 'התחברות אינה מופעלת בשרת — פנה למנהל המערכת',
  'GOOGLE_CERTS_UNAVAILABLE': 'אימות Google אינו זמין כרגע — נסה שוב בעוד רגע',
  'TAX_AUTHORITY_DISABLED': 'חיבור לרשות המסים טרם הופעל (ממתין לאישור והרשמה)',
  'SIGNING_DISABLED': 'חתימה דיגיטלית טרם הופעלה (ממתינה לאישור מקצועי)',
  'UNIFORM_FORMAT_DISABLED': 'ייצוא במבנה אחיד אינו מופעל',
  'SIGNING_ACTIVATION_INVALID': 'סיסמת ההפעלה שגויה',
  'SIGNING_LOCKED': 'החתימה נעולה — פתחו אותה בהגדרות עם סיסמת ההפעלה',
  'SIGNING_NOT_ENABLED': 'חתימה דיגיטלית לא הופעלה לעסק זה (הגדרות → חתימה)',
  'SIGNING_IDENTITY_MISSING':
      'לא הוגדרה זהות חתימה לעסק — הגדירו תעודה בהגדרות',
  'SIGNING_IDENTITY_EXISTS': 'כבר קיימת זהות חתימה לעסק זה',
  'SIGNING_CERTIFICATE_EXPIRED': 'תעודת החתימה פגה — יש לחדש אותה לפני חתימה',
  'SIGNING_CERTIFICATE_SELF_SIGNED':
      'תעודת החתימה אינה מאושרת על ידי גורם מוסמך',
  'SIGNING_UNAVAILABLE': 'שירות החתימה אינו זמין כרגע — נסו שוב בעוד רגע',
  'SIGNATURE_FAILED': 'החתימה נכשלה — נסו שוב או פנו לתמיכה',
  'PADES_BRIDGE_UNAVAILABLE': 'רכיב החתימה (PAdES) אינו זמין בשרת',
  'PADES_VALUEERROR': 'החתימה נדחתה על ידי רכיב החתימה — בדקו את התעודה',
  'QUOTE_ALREADY_CONVERTED': 'הצעת המחיר כבר הומרה לחשבונית',
  'CREDIT_LIMIT_EXCEEDED': 'המסמך כבר זוכה — אין יתרה לזיכוי',
  'CONFIRMATION_REQUIRED': 'יש להקליד את מילת האישור כדי למחוק את החשבון',
  'REAUTH_REQUIRED':
      'כדי למחוק את החשבון יש לאמת שוב את הזהות (סיסמה או Apple)',
  'REAUTH_FAILED': 'לא הצלחנו לאמת את הזהות — נסו שוב',
  'CREDIT_DOCUMENT_REQUIRED': 'נדרש מסמך מקור שהופק כדי להוציא זיכוי',
  'DOCUMENT_ALREADY_FINALIZED': 'המסמך כבר הופק — לא ניתן לערוך או להפיק שוב',
  'DOCUMENT_ALLOCATION_LOCKED': 'המסמך נעול בזמן בקשת מספר הקצאה מרשות המסים',
  'DOCUMENT_NOT_DELIVERABLE': 'לא ניתן לשלוח מסמך זה — הורידו PDF תחילה',
  'APPROVAL_REASON_REQUIRED': 'יש לציין סיבת דחייה',
  'APPROVAL_NOT_REQUIRED': 'המסמך אינו דורש אישור — ניתן להפיק ישירות',
  'EXPENSE_VALIDATION_FAILED': 'ההוצאה חסרה נתונים לאישור (ספק, סכום או תאריך)',
  'UPLOAD_REJECTED': 'הקובץ נדחה — מותרים PDF או תמונה בגודל סביר',
  'SCANNER_INFECTED': 'הקובץ נחסם — זוהה תוכן זדוני',
  'SCANNER_UNAVAILABLE': 'סורק הקבצים אינו זמין כרגע — נסו שוב בעוד רגע',
  'SCAN_PENDING': 'הקובץ התקבל ונסרק ברקע — יופיע ברשימה בעוד רגע',
  'SCAN_FAILED': 'הסריקה נכשלה — נסו להעלות שוב',
  'UPLOAD_EXPIRED': 'חלון ההעלאה פג — נסו להעלות שוב',
  'UPLOAD_NOT_PENDING': 'ההעלאה כבר טופלה — רעננו את הדף',
  'UPLOAD_NOT_FOUND': 'ההעלאה לא נמצאה',
  'UPLOAD_BYTES_MISSING': 'הקובץ לא הגיע לשרת — נסו להעלות שוב',
  'COMPLIANCE_DECISION_NOT_VERIFIED': 'הפעולה דורשת אישור ציות מאומת',
  'TAX_DATE_FORMAT': 'תאריך לא תקין — יש להזין בפורמט YYYY-MM-DD',
  'UNIFORM_FORMAT_VALIDATION_FAILED':
      'הייצוא נכשל בבדיקת מבנה אחיד — בדקו את פרטי העסק והמסמכים',
  'EXPORT_RECONCILIATION_FAILED':
      'סיכומי הייצוא אינם תואמים לספרים — פנו לתמיכה',
  'EXPORT_INCOMPLETE': 'הייצוא טרם הושלם',
  'ARTIFACT_INTEGRITY_VIOLATION':
      'קובץ המסמך אינו תואם לחתימה שנשמרה — פנו לתמיכה',
  'MALFORMED_SNAPSHOT': 'נתוני המסמך השמורים פגומים — פנו לתמיכה',
  'OCR_MALFORMED_EXTRACTION':
      'הזיהוי האוטומטי החזיר נתונים לא תקינים — הזינו ידנית',
  'CONSENT_NOT_FOUND': 'לא נמצאה הסכמה תואמת',
  'DELIVERY_NOT_FOUND': 'המשלוח לא נמצא',
  'TRANSMISSION_NOT_FOUND': 'השידור לא נמצא',
  'CONFLICT': 'הנתונים השתנו בינתיים — רעננו את הדף ונסו שוב',
  'DUPLICATE': 'רשומה כזו כבר קיימת',
  'BAD_REQUEST': 'הבקשה לא תקינה',
  'ERROR': 'שגיאה לא צפויה',
};

const Map<String, String> _validationMessages = {
  'you cannot change your own role': 'לא ניתן לשנות את התפקיד של עצמך',
  'you cannot change your own permissions': 'לא ניתן לשנות את ההרשאות של עצמך',
  'you cannot remove yourself': 'לא ניתן להסיר את עצמך מהעסק',
  'the owner role cannot be changed here':
      'לא ניתן לשנות את תפקיד בעל העסק כאן',
  'the owner already has every permission': 'לבעל העסק כבר יש את כל ההרשאות',
  'role must be ADMIN, ACCOUNTANT, EMPLOYEE or READ_ONLY': 'תפקיד לא תקין',
  'permissions must be an array of strings': 'רשימת ההרשאות לא תקינה',
  'email is invalid': 'כתובת האימייל לא תקינה',
  'nextNumber must be a positive integer':
      'המספר הבא חייב להיות מספר שלם חיובי',
  'logo must be a png/jpeg/webp/svg image data URI':
      'הלוגו חייב להיות תמונה מסוג PNG/JPEG/WebP/SVG',
  'accent colour must be a #rrggbb hex value':
      'צבע לא תקין — יש להזין קוד צבע כמו #1a73e8',
  'complianceDecisionId is required': 'נדרש מזהה החלטת ציות',
  'a preview needs at least one line': 'לתצוגה מקדימה נדרשת לפחות שורה אחת',
  'request contains an invalid value': 'הבקשה מכילה ערך לא תקין',
};
