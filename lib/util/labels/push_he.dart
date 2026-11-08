// Push notifications wording (PUSH-001). The notification texts themselves come from the
// server's catalogue (GET /mobile/push/catalogue); these are the app's own screens.

abstract final class PushHe {
  // Settings › התראות
  static const settingsRow = 'התראות';
  static const settingsTitle = 'התראות';
  static const offTitle = 'ההתראות כבויות בטלפון';
  static const offDenied = 'כדי לקבל התראות צריך להפעיל אותן בהגדרות של iPhone';
  static const offAsk = 'אפשר להפעיל עכשיו, ולבחור כאן מה לקבל';
  static const enable = 'הפעל';
  static const openSettings = 'פתח הגדרות';
  static const alwaysOn = 'תמיד פעיל';
  static const defaultOff = 'כבוי כברירת מחדל';
  static const quietTitle = 'שעות שקט';
  static const quietBody =
      '22:00–08:00 ובשבת וחג ההתראות מחכות לבוקר. התראות אבטחה מגיעות תמיד';

  // The explanation before the iOS dialog.
  static const primerTitle = 'לקבל התראות?';
  static const primerBody =
      'נעדכן רק כשמשהו חשוב קורה: רשות המסים אישרה מסמך, לקוח שילם או חתם על הצעה, '
      'או כניסה לחשבון מטלפון חדש. בלי פרסומות, ואפשר לכבות בכל רגע בהגדרות.';
  static const primerWaitingAllocation =
      'רשות המסים עוד לא החזירה מספר הקצאה. נודיע לך ברגע שהיא מאשרת.';
  static const primerYes = 'הפעל התראות';
  static const primerNo = 'לא עכשיו';
}
