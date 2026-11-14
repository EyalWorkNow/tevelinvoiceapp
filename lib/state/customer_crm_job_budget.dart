import 'package:flutter/foundation.dart';

/// Manual job planning, deliberately separate from issued documents and receipts.
@immutable
class CustomerCrmJobBudget {
  const CustomerCrmJobBudget({
    this.priceMinor,
    this.costMinor,
    this.workMinutes,
    this.paidMinor = 0,
    this.paymentDueAt,
  });

  final int? priceMinor;
  final int? costMinor;
  final int? workMinutes;
  final int paidMinor;
  final DateTime? paymentDueAt;

  int? get remainingMinor =>
      priceMinor == null ? null : priceMinor! - paidMinor;
  int? get contributionMinor =>
      priceMinor == null || costMinor == null ? null : priceMinor! - costMinor!;
  int? get hourlyMinor => contributionMinor == null || (workMinutes ?? 0) <= 0
      ? null
      : (contributionMinor! * 60 / workMinutes!).round();

  bool get isValid =>
      [
        priceMinor,
        costMinor,
      ].every((v) => v == null || (v >= 0 && v <= 99999999999)) &&
      (workMinutes == null || (workMinutes! > 0 && workMinutes! <= 60000)) &&
      paidMinor >= 0 &&
      paidMinor <= (priceMinor ?? 0);

  factory CustomerCrmJobBudget.fromJson(Map value) => CustomerCrmJobBudget(
    priceMinor: value['priceMinor'] as int?,
    costMinor: value['costMinor'] as int?,
    workMinutes: value['workMinutes'] as int?,
    paidMinor: value['paidMinor'] as int? ?? 0,
    paymentDueAt: value['paymentDueAt'] == null
        ? null
        : DateTime.parse(value['paymentDueAt'] as String),
  );

  Map<String, Object?> toJson() => {
    'priceMinor': priceMinor,
    'costMinor': costMinor,
    'workMinutes': workMinutes,
    'paidMinor': paidMinor,
    'paymentDueAt': paymentDueAt?.toIso8601String(),
  };
}

@immutable
class CustomerCrmChecklistItem {
  const CustomerCrmChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
  });
  final String id;
  final String text;
  final bool done;

  factory CustomerCrmChecklistItem.fromJson(Map value) =>
      CustomerCrmChecklistItem(
        id: value['id'] as String,
        text: value['text'] as String,
        done: value['done'] as bool? ?? false,
      );

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'done': done};
}
