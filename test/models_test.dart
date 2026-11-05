import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/api/models/models.dart';

void main() {
  test('DocumentSummary parses both /documents (camel) and dashboard (snake) rows', () {
    final list = DocumentSummary.fromJson({
      'id': 'd1', 'documentType': 'TAX_INVOICE', 'status': 'ARCHIVED', 'documentNumber': '1042',
      'customerId': 'c1', 'customerName': 'דנה כהן', 'issueDate': '2026-10-30', 'currency': 'ILS',
      'totalMinor': '118000', 'balanceMinor': '0',
    });
    expect(list.totalMinor, BigInt.from(118000));
    expect(list.isPaid, isTrue);
    expect(list.customerName, 'דנה כהן');

    final recent = DocumentSummary.fromJson({
      'id': 'd2', 'document_type': 'RECEIPT', 'status': 'ARCHIVED', 'document_number': '7',
      'issue_date': '2026-10-29', 'total_minor': '5000', 'currency': 'ILS',
    });
    expect(recent.documentType, 'RECEIPT');
    expect(recent.balanceMinor, isNull);
    expect(recent.isPaid, isFalse);
    expect(recent.isOpen, isFalse);
  });

  test('read gating: a redacted total (null) is hidden, not ₪0, and survives the cache', () {
    final d = DocumentSummary.fromJson({
      'id': 'd2', 'documentType': 'TAX_INVOICE', 'status': 'FINALIZED', 'currency': 'ILS',
      'totalMinor': null, 'balanceMinor': null, 'openMinor': null,
    });
    expect(d.amountHidden, isTrue);
    expect(d.isOpen, isFalse);
    expect(DocumentSummary.fromJson(d.toJson()).amountHidden, isTrue);
    expect(DocumentSummary.fromJson({...d.toJson(), 'totalMinor': '5900'}).amountHidden, isFalse);
  });

  test('DashboardSummary', () {
    final d = DashboardSummary.fromJson({
      'summary': {
        'month_income': '1248000', 'month_income_count': 17, 'month_expenses': '0',
        'unpaid_count': 4, 'unpaid_balance': '320000', 'review_count': 2, 'open_quotes': 0,
        'pending_approval': 1,
      },
      'recent': [],
    });
    expect(d.monthIncomeMinor, BigInt.from(1248000));
    expect(d.unpaidCount, 4);
    expect(d.reviewCount, 2);
  });

  test('DocumentDetail + lines (snake_case)', () {
    final d = DocumentDetail.fromJson({
      'document': {
        'id': 'd1', 'document_type': 'TAX_INVOICE_RECEIPT', 'status': 'ARCHIVED',
        'document_number': '1042', 'currency': 'ILS', 'issue_date': '2026-10-30',
        'subtotal_minor': '100000', 'tax_total_minor': '18000', 'total_minor': '118000',
        'paid_total_minor': '118000', 'balance_minor': '0', 'allocation_number': null,
        'customer_id': 'c1', 'numbering_scope_key': 'default',
      },
      'lines': [
        {
          'position': 1, 'item_id': null, 'description': 'ייעוץ', 'quantity': '1.000000',
          'quantity_micros': '1000000', 'unit_price_minor': '100000', 'discount_minor': '0',
          'subtotal_minor': '100000', 'tax_rate_basis_points': 1800,
          'tax_amount_minor': '18000', 'total_minor': '118000',
        }
      ],
    });
    expect(d.hasOriginal, isTrue);
    expect(d.lines.single.taxRateBasisPoints, 1800);
    expect(d.lines.single.quantityMicros, BigInt.from(1000000));
  });

  test('Me: V1 shape (no BE-02 fields) and the extended BE-02 shape', () {
    final v1 = Me.fromJson({
      'userId': 'u', 'role': 'EMPLOYEE', 'mfaEnrolled': false,
      'onboarding': {'completed': true, 'step': 7}, 'canFinalize': true, 'canConfigure': false,
      'canApproveExpenses': false,
      'approvalPolicy': {'mode': 'THRESHOLD', 'thresholdMinor': '500000', 'selfApprovalAllowed': false},
    });
    expect(v1.hasEffectivePermissions, isFalse);
    expect(v1.isOwner, isNull);
    expect(v1.approvalPolicy.thresholdMinor, BigInt.from(500000));
    expect(v1.approvalPolicy.selfApprovalAllowed, isFalse);
    expect(v1.onboardingStep, 7);

    final v2 = Me.fromJson({
      'userId': 'u', 'role': 'EMPLOYEE', 'isOwner': false,
      'permissions': ['document:read', 'document:finalize'],
      'businessType': 'OSEK_MURSHE', 'vatReporting': 'BIMONTHLY', 'memberCount': 3,
      'approvalPolicy': {'mode': 'THRESHOLD', 'thresholdMinor': '500000', 'includesVat': true,
        'selfApprovalAllowed': false, 'otherApproverExists': true},
      'shaam': {'status': 'CONNECTED', 'refreshTokenExpiresAt': '2027-01-10T00:00:00Z',
        'manualEntryEnabled': false, 'canConfigure': false},
      'signing': {'configured': true, 'unlocked': false},
      'exports': {'uniformFormatReady': true},
      'rules': {'exemptCeilingMinor': '12000000', 'exemptCeilingYear': 2026, 'yearTurnoverMinor': '8400000'},
      'onboarding': {'completed': true, 'step': 7},
      'enforcement': {'readGating': false},
    });
    expect(v2.permissions, ['document:read', 'document:finalize']);
    expect(v2.isOwner, isFalse);
    expect(v2.businessType, 'OSEK_MURSHE');
    expect(v2.memberCount, 3);
    expect(v2.approvalPolicy.otherApproverExists, isTrue);
    expect(v2.shaam!.refreshTokenExpiresAt, '2027-01-10T00:00:00Z');
    expect(v2.signingConfigured, isTrue);
    expect(v2.uniformFormatReady, isTrue);
    expect(v2.rules.exemptCeilingMinor, BigInt.from(12000000));
    expect(Me.fromJson(v2.toJson()).permissions, v2.permissions);
  });

  test('DocumentSummary: BE-10a / BE-37 fields; openMinor falls back on balance', () {
    final old = DocumentSummary.fromJson({'id': 'a', 'documentType': 'TAX_INVOICE', 'status': 'ARCHIVED',
      'totalMinor': '118000', 'balanceMinor': '50000'});
    expect(old.openMinor, BigInt.from(50000));
    final row = DocumentSummary.fromJson({'id': 'a', 'documentType': 'TAX_INVOICE', 'status': 'ARCHIVED',
      'totalMinor': '118000', 'balanceMinor': '118000', 'creditedMinor': '20000', 'openMinor': '98000',
      'createdBy': 'u1', 'submittedBy': 'u2', 'rejection': {'reason': 'חסר פירוט', 'by': 'u3', 'at': 'x'}});
    expect(row.openMinor, BigInt.from(98000));
    expect(row.creditedMinor, BigInt.from(20000));
    expect(row.rejection!.reason, 'חסר פירוט');
    expect(DocumentSummary.fromJson(row.toJson()).openMinor, BigInt.from(98000));
  });

  test('BusinessProfile, Customer, Item, MobileAccount', () {
    final p = BusinessProfile.fromJson({
      'legalName': 'דנה בע"מ', 'businessType': 'OSEK_PATUR', 'paymentLinkUrl': 'https://pay.me/x',
      'identityLocked': true, 'onboarding': {'completed': true},
    });
    expect(p.isVatExempt, isTrue);
    expect(p.paymentLinkUrl, 'https://pay.me/x');

    final c = Customer.fromJson({'id': 'c', 'name': 'דנה', 'tax_id': null, 'phone': '0501234567',
      'email': null, 'archived_at': null, 'vat_dealer_status': 'UNKNOWN'});
    expect(Customer.fromJson(c.toJson()).phone, '0501234567');

    final i = Item.fromJson({'id': 'i', 'name': 'שעת עבודה', 'item_type': 'SERVICE',
      'default_unit_price_minor': '25000', 'currency': 'ILS', 'is_active': true});
    expect(i.defaultUnitPriceMinor, BigInt.from(25000));

    final a = MobileAccount.fromJson({'userId': 'u', 'email': 'a@b.co', 'displayName': null,
      'businesses': [{'businessId': 'b', 'legalName': 'עסק', 'role': 'OWNER'}]});
    expect(MobileAccount.fromJson(a.toJson()).businesses.single.role, 'OWNER');
  });
}
