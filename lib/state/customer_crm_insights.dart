import 'customer_crm_store.dart';

/// Planning figures only. Never combine with document/receipt totals.
class CustomerCrmInsights {
  CustomerCrmInsights(
    Iterable<CustomerCrmJob> jobs, {
    required DateTime month,
    required DateTime now,
  }) {
    final relevant = jobs
        .where((job) => job.status != CustomerCrmJobStatus.cancelled)
        .toList();
    final monthly = relevant
        .where(
          (job) =>
              job.scheduledAt.year == month.year &&
              job.scheduledAt.month == month.month,
        )
        .toList();
    final completed = monthly
        .where((job) => job.status == CustomerCrmJobStatus.completed)
        .toList();
    completedCount = completed.length;
    unpricedCount = monthly
        .where((job) => job.budget.priceMinor == null)
        .length;
    completedPriceMinor = completed.fold(
      0,
      (sum, job) => sum + (job.budget.priceMinor ?? 0),
    );
    trackedPaidMinor = monthly.fold(
      0,
      (sum, job) => sum + job.budget.paidMinor,
    );
    openPriceMinor = monthly
        .where((job) => job.status.isOpen)
        .fold(0, (sum, job) => sum + (job.budget.priceMinor ?? 0));
    final costed = completed
        .where((job) => job.budget.contributionMinor != null)
        .toList();
    costedCount = costed.length;
    contributionMinor = costed.fold(
      0,
      (sum, job) => sum + job.budget.contributionMinor!,
    );
    final timed = costed
        .where((job) => job.budget.workMinutes != null)
        .toList();
    final minutes = timed.fold(0, (sum, job) => sum + job.budget.workMinutes!);
    final timedContribution = timed.fold(
      0,
      (sum, job) => sum + job.budget.contributionMinor!,
    );
    hourlyMinor = minutes == 0
        ? null
        : (timedContribution * 60 / minutes).round();
    collections =
        relevant
            .where(
              (job) =>
                  job.status == CustomerCrmJobStatus.completed &&
                  (job.budget.remainingMinor ?? 0) > 0,
            )
            .toList()
          ..sort(
            (a, b) => (a.budget.paymentDueAt ?? a.scheduledAt).compareTo(
              b.budget.paymentDueAt ?? b.scheduledAt,
            ),
          );
    remainingMinor = collections.fold(
      0,
      (sum, job) => sum + job.budget.remainingMinor!,
    );
    final today = DateTime(now.year, now.month, now.day);
    overdueCount = collections
        .where((job) => job.budget.paymentDueAt?.isBefore(today) ?? false)
        .length;
  }

  late final int completedCount,
      unpricedCount,
      completedPriceMinor,
      trackedPaidMinor,
      openPriceMinor,
      costedCount,
      contributionMinor,
      remainingMinor,
      overdueCount;
  late final int? hourlyMinor;
  late final List<CustomerCrmJob> collections;
}
