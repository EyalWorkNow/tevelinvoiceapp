# תבל – חשבוניות · ארכיטקטורת V2 (מעטפת, בעלות, מוסכמות)

> בעלים: INT · ענף `v2` · מקור האמת: `docs/SPEC-v2-he.md` (§4, §5, §15.5, §18).
> המסמך הזה מתאר את המעטפת שנבנתה ב-INT ואת הכללים שכל צוות עובד לפיהם.
> קוד V1 המלא נמצא בקומיט `bbf0fb0` (`git show bbf0fb0:lib/screens/home/home_screen.dart` וכו').

## 1. מבנה

```
lib/
  main.dart               MaterialApp: navigatorKey, messengerKey, AppRouter observer
  router.dart             INT · טבלת הנתיבים של §5, go(), עוזרים טיפוסיים, tevel://, שומר יכולות
  app_shell.dart          INT · סרגל לשוניות RTL: בית · לקוחות · [＋] · עסק
  api/
    client.dart           INT · HTTP יחיד; 403 FORBIDDEN/DOCUMENT_ACTION_FORBIDDEN → ApiEvent.forbidden
    models/models.dart    INT · barrel (שורת export אחת לכל קובץ דומיין)
    models/json.dart      INT · jBig/jStr/jPick… (כסף = BigInt אגורות)
    models/me.dart        INT · Me מורחב (BE-02) – כל שדה אופציונלי
    models/account.dart   INT · Business, MobileAccount, BusinessProfile
    models/<domain>.dart  צוותים (טבלה ב-§2)
    *_api.dart            צוותים
  state/
    session.dart          INT · טוקן, עסק נבחר, /me + profile (+ מטמון /me ≤24ש')
    cache.dart            INT
    caps.dart             INT · enum Cap, Preset, Caps.fromMe – המקום היחיד שמשווה תפקידים
    business_context.dart INT · caps, סוג עסק, שם, רענון /me (פתיחה, foreground>60ש', 403)
  util/
    labels/labels.dart    INT · barrel; common_he + status_he של INT, השאר צוותים
    status_map.dart       INT · §15.5 → DocStatus / QuoteListStatus / DocAttribute
    errors_he.dart        INT · קוד שגיאה → עברית (כולל קודי V2 של §14)
    allowed_urls.dart     INT · AT-95: launchAllowed (wa.me/mailto/tel), openSafari (רשימה לבנה)
  screens/<folder>/       צוותים (stub עם שם המחלקה הסופי – ממלאים את הגוף)
  ui/                     DS
test/
  fakes/fake_api.dart     INT · barrel: FakeBackend, FakeLauncher, me_fixtures, <domain>_fake.dart
```

## 2. בעלות על קבצים (SPEC §18.1 – מחייב)

| צוות | תיקיות / קבצים |
|---|---|
| **INT** | `lib/router.dart`, `lib/app_shell.dart`, `lib/main.dart`, `lib/state/**`, `lib/api/client.dart`, `lib/api/models/{models,json,me,account}.dart`, `lib/util/labels/{labels,common_he,status_he}.dart`, `lib/util/{status_map,errors_he,allowed_urls}.dart`, `lib/screens/stub.dart`, `pubspec.yaml`, `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`, `test/fakes/{fake_api,fake_backend,fake_launcher,me_fixtures}.dart`, `tool/**`, `docs/ARCHITECTURE-v2.md` |
| **DS** | `lib/ui/**`, `test/golden/**` |
| **A** בית ופעילות | `lib/screens/home/**`, `lib/screens/activity/**`, `lib/api/inbox_api.dart`, `lib/api/models/inbox.dart`, `lib/util/labels/inbox_he.dart`, `test/fakes/inbox_fake.dart` |
| **B** Composer | `lib/screens/compose/**` (כולל `sheets/s1_create.dart`, `sheets/s3_more.dart`, `fields/`), `lib/api/issue_api.dart`, `lib/api/quotes_api.dart`, `lib/api/models/{document,quote}.dart`, `lib/util/{intent_resolver,composer_config}.dart`, `lib/util/labels/compose_he.dart`, `test/fakes/issue_fake.dart`; V1 לעיון: `lib/screens/new_document/{issue_form,pdf_preview_page}.dart`, `lib/util/doc_type.dart` |
| **C** מסמך וכסף | `lib/screens/document/**` (כולל `sheets/s5_payment.dart`, `s6_share.dart`, `s8_cancel.dart`), `lib/api/{actions_api,payments_api,signing_api}.dart`, `lib/api/models/payment.dart`, `lib/util/cancel_policy.dart`, `lib/util/labels/{document_he,payment_he}.dart`, `test/fakes/actions_fake.dart` |
| **D** אנשים והוצאות | `lib/screens/people/**` (כולל `sheets/s2_customer.dart`), `lib/screens/expense/**`, `lib/api/{customers_api,suppliers_api,items_api,expenses_api}.dart`, `lib/api/models/{customer,item,expense}.dart`, `lib/util/labels/people_he.dart`, `test/fakes/people_fake.dart`; V1 לעיון: `lib/screens/customers/customer_form_sheet.dart` |
| **E** עסק, צוות, דוחות, כניסה | `lib/screens/auth/**`, `lib/screens/business/**` (כולל `sheets/s13_editor.dart`, `s14_switch.dart`, `delete_account_screen.dart`), `lib/screens/reports/**`, `lib/api/{team_api,reports_api,settings_api,branding_api,shaam_api,auth_api}.dart`, `lib/api/models/{member,report}.dart`, `lib/util/labels/business_he.dart`, `test/fakes/business_fake.dart` |
| **QA** | `integration_test/**`, `docs/screenshots/v2/**`, `docs/STATUS-v2-he.md` |

**Barrels** (`models.dart`, `labels.dart`, `fake_api.dart`) כבר מכילים שורת export לכל קובץ דומיין. קובץ דומיין חדש = בקשה ל-INT לשורת export אחת (append-only).
**גיליון** חי בתיקיית הצוות שבונה אותו; צוות אחר רק מייבא את פונקציית ה-`show…`.

## 3. מסכים וגיליונות (stub → מימוש)

| מזהה | נתיב | מחלקה | קובץ | צוות |
|---|---|---|---|---|
| A | `/gate`, `/setup` | `LoginScreen`, `OnboardingScreen` (+ `InviteScreen` stub) | `screens/auth/` | E |
| H | `/home` (לשונית) | `HomeScreen` | `screens/home/home_screen.dart` | A |
| L | `/activity?chip=` | `ActivityScreen(chip)` | `screens/activity/activity_screen.dart` | A |
| C | `/compose?intent=&customerId=&fromDocId=&fromQuoteId=&draftId=` | `ComposeScreen(intent, …)` | `screens/compose/compose_screen.dart` | B |
| D | `/doc/:id`, `/quote/:id` | `DocumentScreen(id, isQuote)` | `screens/document/document_screen.dart` | C |
| P | `/people?chip=` (לשונית) | `PeopleScreen(chip)` | `screens/people/people_screen.dart` | D |
| P2 | `/person/:id[?kind=supplier]` | `PersonScreen(id, isSupplier)` | `screens/people/person_screen.dart` | D |
| E | `/expenses?id=` | `ExpensesScreen(expenseId)` (+ `ExpenseCaptureScreen` לא נספר) | `screens/expense/` | D |
| R | `/reports?period=`, `/reports/:kind` | `ReportsScreen(period, kind, embedded)` | `screens/reports/reports_screen.dart` | E |
| B | `/business` (לשונית), `/business/:section` | `BusinessScreen(section)` | `screens/business/business_screen.dart` | E |
| S1 | — | `CreateSheet` / `showCreateSheet` | `screens/compose/sheets/s1_create.dart` | B |
| S2 | — | `CustomerSheet` / `showCustomerSheet` → `Customer?` | `screens/people/sheets/s2_customer.dart` | D |
| S3 | — | `MoreDetailsSheet` / `showMoreDetailsSheet` | `screens/compose/sheets/s3_more.dart` | B |
| S5 | — | `PaymentSheet` / `showPaymentSheet(documentId)` | `screens/document/sheets/s5_payment.dart` | C |
| S6 | — | `ShareSheet` / `showShareSheet(documentId)` | `screens/document/sheets/s6_share.dart` | C |
| S8 | — | `CancelSheet` / `showCancelSheet(documentId)` | `screens/document/sheets/s8_cancel.dart` | C |
| S13 | — | `EditorSheet` / `showEditorSheet(instance)` | `screens/business/sheets/s13_editor.dart` | E |
| S14 | — | `SwitchBusinessSheet` / `showSwitchBusinessSheet` (מאציל ל-V1 picker עד ש-E כותב) | `screens/business/sheets/s14_switch.dart` | E |

חתימות ה-stub הן **החוזה** בין הצוותים (הראוטר והמעטפת בונים אותן). מותר להוסיף פרמטרים אופציונליים; שינוי שם מחלקה/פרמטר חובה – דרך INT.
`/business/:section` – slug מתוך `BusinessSection` ב-`router.dart`: `team, profile, branding, approvals, shaam, account, desktop, numbering` (+ היכולת הנדרשת ב-`sectionCap`).

## 4. מוסכמות

1. **ניווט:** רק דרך `router.dart` – `openCompose(context, intent: 'PAID')`, `openDocument(context, id, replace: true)`, `openPerson`, `openActivity`, `openExpenses`, `openReports/openReport`, `openBusinessSection`, `openPeople()`, `openBusiness()`, `resetToHome()`, או `go('/doc/1')` / `go('tevel://doc/1')`. כל מסלול נדחף עם `RouteSettings.name` = המיקום, ולכן שומר היכולות יודע מה פתוח.
2. **יכולות:** `businessContext.can(Cap.x)` / `businessContext.caps`. אסור `role ==` מחוץ ל-`caps.dart` (AT-48 – `test/caps_test.dart` סורק את `lib/`). אין "אין הרשאה" ואין כפתור אפור (F5) – אזור בלי יכולת לא נבנה. `caps.approvalNeeded(totalMinor)` = "שלח לאישור" (§4.8, `>=`, כולל מע״מ). `caps.homeIsReports`, `caps.showCreateTab`, `caps.showIntentButtons`, `caps.roleTag`.
3. **סוג עסק:** `businessContext.businessType` / `isVatExempt` (פטור/עמותה – לא בונים אף רכיב מע״מ, §4.7).
4. **רענון יכולות (§4.6):** אוטומטי. 403 עם `FORBIDDEN`/`DOCUMENT_ACTION_FORBIDDEN` → `/me` מתרענן → toast "ההרשאות שלך עודכנו" → אם במחסנית יש מסך שכבר אסור – חזרה לבית. foreground אחרי >60 ש' → `/me`. `/me` ישן מ-24 ש' → `Caps.none`. מסך לא צריך לעשות כלום מלבד להאזין ל-`businessContext` (ChangeNotifier).
5. **סטטוסים:** רק `docListState(...)` / `quoteListStatus(...)` מ-`util/status_map.dart` → `StatusPill` של DS. התוויות ב-`labels/status_he.dart`. "נשלח"/"נצפה" הן `DocAttribute`, לא סטטוס.
6. **מחרוזות:** כל תווית פעולה מ-`lib/util/labels/*` (F11, AT-92). מילים משותפות: `CommonHe` (`send`, `issue`, `paid`, `requestPayment`, `approve`, `reject`, `save`, `share`, `retry`, `offlineButton`, `permissionsUpdated`…). מילים של דומיין – בקובץ ה-`_he` של הצוות.
7. **שגיאות:** `ApiException.messageHe` (מ-`errors_he.dart`). קוד חדש מהשרת → בקשה ל-INT (או PR של שורה).
8. **קישורים חיצוניים:** `launchAllowed(uri)` (wa.me / mailto / tel) ו-`openSafari(uri)` (פרטיות, תנאים, תמיכה) מ-`allowed_urls.dart` בלבד. אסור `launchUrl` ישיר (AT-95). בבדיקות: `FakeLauncher`.
9. **כסף:** `BigInt` אגורות בלבד; JSON דרך `jBig`.
10. **מודלים:** כל שדה V2 שהשרת אולי עוד לא מחזיר – nullable/ברירת מחדל, כך שהאפליקציה עובדת מול שרת לפני ואחרי BE-xx.
11. **קוד V1:** `bbf0fb0`. קבצי V1 שנשארו לעיון (מתקמפלים, לא מיובאים מהמעטפת): `screens/new_document/{issue_form,pdf_preview_page}.dart`, `screens/customers/customer_form_sheet.dart`, `screens/auth/business_picker_sheet.dart`, `util/doc_type.dart`. הצוות הבעלים מוחק אותם כשהמימוש שלו מחליף אותם.

## 5. קישורי עומק

- `ios/Runner/Info.plist`: `CFBundleURLTypes` עם הסכמה `tevel` + `FlutterDeepLinkingEnabled=true` (המנוע שולח את ה-URL המלא, גם דרך `FlutterSceneDelegate`).
- `AppRouter` (ב-`router.dart`) מקבל את הקישור ב-`didPushRouteInformation`, מנרמל `tevel://doc/1` → `/doc/1`, ופותח מיד אם המשתמש מחובר והמעטפת עומדת; אחרת שומר ופותח אחרי `resetToHome()`.
- Universal links (`/m/invite/:token`, `/m/shaam/callback`) – אחרי BE-00 §5 + BE-42 (Associated Domains ב-`Runner.entitlements`, INT).

## 6. בדיקות מול fakes – איך מוסיפים fake

```dart
import 'fakes/fake_api.dart';

late FakeBackend backend;
setUp(() {
  resetSession();
  backend = FakeBackend()..install();          // מחליף את ApiClient.instance.httpClient
  installInboxFakes(backend);                   // ברירות מחדל של הדומיין
});

testWidgets('...', (tester) async {
  await tester.runAsync(() => signInAs(backend, Preset.employee, businessType: 'OSEK_PATUR'));
  backend.json('GET', '/documents', {'total': 0, 'documents': []});            // דריסה לבדיקה
  backend.on('POST', '/documents/:id/finalize', (r) => FakeResponse(200, {'status': 'FINALIZED'}));
  backend.error('POST', '/documents/:id/credit', 403, 'DOCUMENT_ACTION_FORBIDDEN');
  // ... pump ...
  expect(backend.calls('POST', '/documents/:id/finalize'), hasLength(1));
  expect(backend.last('POST', '/documents/:id/finalize')!.body['scopeKey'], 'default');
});
```

- **fake חדש לדומיין:** בקובץ `test/fakes/<domain>_fake.dart` של הצוות, בתוך `install<Domain>Fakes(FakeBackend b)` – `b.json(...)` / `b.on(...)` עם ברירות מחדל סבירות לכל endpoint של הדומיין, בצורת התשובה של §14 (גם לפני שהשרת קיים). הבדיקה דורסת נתיב בודד אחרי ההתקנה.
- **presets:** `meJson(Preset.x, businessType:, approvalPolicy:, be02:)`, `profileJson(...)`, `accountJson(count:)`, `signInAs(...)` – 7 presets × 5 סוגי עסק (AT-52). `be02: false` = שרת V1 (בדיקת fallback).
- **קישורים:** `final l = FakeLauncher()..install(); addTearDown(FakeLauncher.uninstall);` → `l.last` (AT-10: `https://wa.me/972…` עם `/d/`).
- **singletons בבדיקות widget:** `session`, `businessContext`, `AppRouter.instance` גלובליים; `resetSession()` ב-`setUp`, ו-`currentTab.value = AppTab.home`. קריאות HTTP אמיתיות של ה-fake רצות בתוך `tester.runAsync`.

## 7. מה ש-INT בודק

`test/router_test.dart` (AT-93 + פרסור קישורים + שומר), `test/caps_test.dart` (מטריצת §4.4, §4.8, fallback, AT-48), `test/status_map_test.dart` (§15.5 שורה-שורה), `test/business_context_test.dart` (§4.6), `test/shell_test.dart` (סרגל RTL, ＋ לפי יכולת, R כבית לרו״ח, 403 → toast + חזרה), `test/fakes_test.dart` (תשתית + AT-95), `test/errors_he_test.dart`, `test/models_test.dart`.
