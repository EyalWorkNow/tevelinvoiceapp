import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/labels/labels.dart';

void main() {
  test('document type labels (web parity)', () {
    expect(docTypeLabels.length, 27);
    expect(docTypeLabel('TAX_INVOICE_RECEIPT'), 'חשבונית מס/קבלה');
    expect(docTypeLabel('TAX_INVOICE'), 'חשבונית מס');
    expect(docTypeLabel('RECEIPT'), 'קבלה');
    expect(docTypeLabel('TRANSACTION_INVOICE'), 'חשבון עסקה');
    expect(docTypeLabel('UNKNOWN_X'), 'UNKNOWN_X');
  });

  test('status labels and tones', () {
    expect(statusLabel('ARCHIVED'), 'הופק');
    expect(statusLabel('WAITING_FOR_ALLOCATION'), 'ממתין להקצאה');
    expect(statusTone('ARCHIVED'), Tone.ok);
    expect(statusTone('PENDING_APPROVAL'), Tone.warn);
    expect(statusTone('REJECTED'), Tone.danger);
    expect(statusTone('DRAFT'), Tone.neutral);
  });

  test('relative dates', () {
    final now = DateTime(2026, 10, 30, 15);
    expect(relativeDateHe('2026-10-30', now: now), 'היום');
    expect(relativeDateHe('2026-10-29', now: now), 'אתמול');
    expect(relativeDateHe('2026-10-27', now: now), 'לפני 3 ימים');
    expect(relativeDateHe('2026-09-01', now: now), '1.9.2026');
    expect(relativeDateHe(null, now: now), '');
    expect(formatDateHe('2026-01-05'), '5.1.2026');
  });
}
