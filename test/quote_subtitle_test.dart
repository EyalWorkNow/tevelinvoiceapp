// Quotes owner feedback 2026-11-16: the list row says the quote number and
// whether it is still valid, short enough for one row.
import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/inbox.dart';
import 'package:invoice/screens/home/doc_rows.dart';

String plain(String s) => s.replaceAll(RegExp('[⁦-⁩]'), '');

void main() {
  QuoteRow row({String? n, bool expired = false, String? until}) => QuoteRow(
    id: 'q',
    status: 'SENT',
    totalMinor: BigInt.one,
    quoteNumber: n,
    expired: expired,
    validUntil: until,
    createdAt: '2026-11-01',
  );

  test('number + validity', () {
    expect(
      plain(quoteSubtitle(row(n: '12', until: '2026-12-01'))),
      'מס׳ 12 · עד 1.12.2026',
    );
    expect(
      plain(quoteSubtitle(row(n: '12', until: '2026-11-14', expired: true))),
      'מס׳ 12 · פג ב-14.11.2026',
    );
  });

  test('older server (no number) keeps the old wording', () {
    expect(
      plain(quoteSubtitle(row(until: '2026-12-01'))),
      'בתוקף עד 1.12.2026',
    );
    expect(
      plain(quoteSubtitle(row(until: '2026-11-14', expired: true))),
      'פג תוקף ב-14.11.2026',
    );
    expect(plain(quoteSubtitle(row())), 'נוצרה 1.11.2026');
  });
}
