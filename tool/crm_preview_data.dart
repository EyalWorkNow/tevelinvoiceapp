// Disposable fixtures for the isolated simulator entrypoint; never used by main.dart.
import 'package:invoice/state/customer_crm_job_budget.dart';
import 'package:invoice/state/customer_crm_store.dart';

Future<void> seedCrmPreview(String businessId) async {
  final store = CustomerCrmStore.instance;
  await store.loadForBusiness(businessId);
  if (store.jobs.isNotEmpty) return;
  final now = DateTime.now();
  await store.addJob(
    'c1',
    CustomerCrmJob(
      id: 'crm-demo-done',
      customerId: 'c1',
      customerName: 'דניאל רוזן',
      title: 'תיקון נזילה במטבח',
      address: 'רחוב הדוגמה 12',
      details: 'הוחלף ברז ונבדק לחץ מים',
      scheduledAt: DateTime(now.year, now.month, now.day - 1, 9),
      createdAt: now,
      status: CustomerCrmJobStatus.completed,
      budget: CustomerCrmJobBudget(
        priceMinor: 125000,
        costMinor: 25000,
        workMinutes: 120,
        paidMinor: 30000,
        paymentDueAt: DateTime(now.year, now.month, now.day - 1),
      ),
      checklist: const [
        CustomerCrmChecklistItem(
          id: 'crm-done-1',
          text: 'החלפת הברז',
          done: true,
        ),
        CustomerCrmChecklistItem(
          id: 'crm-done-2',
          text: 'בדיקת לחץ מים',
          done: true,
        ),
      ],
    ),
  );
  await store.addJob(
    'c1',
    CustomerCrmJob(
      id: 'crm-demo-next',
      customerId: 'c1',
      customerName: 'דניאל רוזן',
      title: 'תחזוקת הגינה',
      address: 'רחוב הדוגמה 12',
      details: 'לתאם חצי שעה לפני ההגעה',
      scheduledAt: DateTime(now.year, now.month, now.day, 15),
      createdAt: now,
      budget: const CustomerCrmJobBudget(
        priceMinor: 45000,
        costMinor: 10000,
        workMinutes: 90,
      ),
      repeatEveryDays: 14,
      checklist: const [
        CustomerCrmChecklistItem(
          id: 'crm-next-1',
          text: 'לתאם גישה לחצר',
          done: true,
        ),
        CustomerCrmChecklistItem(id: 'crm-next-2', text: 'להביא דשן'),
        CustomerCrmChecklistItem(id: 'crm-next-3', text: 'לבדוק השקיה'),
      ],
    ),
  );
  await store.addNote('c1', 'מעדיף ביקורים אחר הצהריים. הכניסה מהשער הצדדי.');
}
