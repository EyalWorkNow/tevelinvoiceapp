import 'package:flutter_test/flutter_test.dart';
import 'package:invoice/util/errors_he.dart';

void main() {
  test('known codes map to Hebrew', () {
    expect(errorMessageHe('INVALID_CREDENTIALS'), 'האימייל או הסיסמה שגויים');
    expect(errorMessageHe('CREDIT_LIMIT_EXCEEDED'), contains('לזכות'));
    expect(errorMessageHe('SCANNER_INFECTED'), contains('נחסם'));
  });

  test('new contract codes are mapped', () {
    for (final code in [
      'APPLE_TOKEN_INVALID',
      'APPLE_SIGNIN_DISABLED',
      'NO_LINKED_ACCOUNT',
      'EXEMPT_BUSINESS_VAT_FORBIDDEN',
      'DOCUMENT_TYPE_NOT_ALLOWED_FOR_BUSINESS',
      'CUSTOMER_NOT_FOUND',
      'ARTIFACT_REQUIRED',
      'MFA_REQUIRED',
      'RATE_LIMITED',
    ]) {
      expect(
        errorMessageHe(code),
        isNot(startsWith('שגיאה לא צפויה')),
        reason: code,
      );
    }
  });

  test('V2 codes (SPEC-v2 §14) are mapped', () {
    for (final code in [
      'FORBIDDEN',
      'DOCUMENT_ACTION_FORBIDDEN',
      'CREDIT_SOURCE_TYPE_INVALID',
      'BACKDATING_OWNER_ONLY',
      'APPROVAL_NO_OTHER_APPROVER',
      'PAYMENT_LOCKED_IN_DOCUMENT',
      'SECTION46_APPROVAL_REQUIRED',
      'INVITATION_EXPIRED',
      'INVITATION_REVOKED',
      'CUSTOMER_VAT_STATUS_UNKNOWN',
      'CUSTOMER_VAT_NUMBER_MISSING',
      'DOCUMENT_HAS_PAYMENTS',
      'DOCUMENT_VOID_NOT_ALLOWED',
      'OWNERSHIP_CODE_INVALID',
      'WEB_HANDOFF_THROTTLED',
      'EMAIL_MISSING',
      'ALLOCATION_NUMBER_RESERVED',
    ]) {
      expect(
        errorMessageHe(code),
        isNot(startsWith('שגיאה לא צפויה')),
        reason: code,
      );
    }
    // Walkthrough #8: the refused action's own error says what happened.
    expect(
      errorMessageHe('DOCUMENT_ACTION_FORBIDDEN'),
      'אין לך הרשאה לפעולה הזו',
    );
  });

  test(
    'allocation-uniqueness codes (ALLOC-UNIQUE-001 / RECON-CONFLICT-002) are mapped',
    () {
      for (final code in [
        'ALLOCATION_RECONCILE_DEFERRED',
        'ALLOCATION_NUMBER_HELD',
      ]) {
        expect(
          errorMessageHe(code),
          isNot(startsWith('שגיאה לא צפויה')),
          reason: code,
        );
      }
    },
  );

  test('identical-facts codes (IDENTICAL-FACTS-001) are mapped', () {
    for (final code in ['ALLOCATION_IDENTICAL_FACTS_PENDING']) {
      expect(
        errorMessageHe(code),
        isNot(startsWith('שגיאה לא צפויה')),
        reason: code,
      );
    }
  });

  test('F6: no error sends the user to a browser', () {
    expect(errorMessageHe('NO_LINKED_ACCOUNT'), isNot(contains('דפדפן')));
    expect(errorMessageHe('NO_LINKED_ACCOUNT'), contains('Apple'));
  });

  test('status fallbacks for unknown codes', () {
    expect(errorMessageHe('WHATEVER', status: 429), contains('יותר מדי'));
    expect(errorMessageHe('WHATEVER', status: 503), contains('לא זמין'));
    expect(
      errorMessageHe('WHATEVER', status: 500),
      'שגיאה לא צפויה (WHATEVER)',
    );
  });

  test('VALIDATION uses the server message', () {
    expect(
      errorMessageHe('VALIDATION'),
      'קלט לא תקין — בדקו את השדות ונסו שוב',
    );
    expect(
      errorMessageHe(
        'VALIDATION',
        serverMessage: 'VALIDATION: email is invalid',
      ),
      'כתובת האימייל לא תקינה',
    );
    expect(
      errorMessageHe(
        'VALIDATION',
        serverMessage: 'name must be at most 80 characters',
      ),
      'השדה "name" ארוך מדי (עד 80 תווים)',
    );
    expect(
      errorMessageHe('VALIDATION', serverMessage: 'odd thing'),
      'הנתונים לא תקינים: odd thing',
    );
  });

  test(
    'report 04 · M1 codes are mapped, unknown codes fall back to Hebrew from the server',
    () {
      for (final code in [
        'CUSTOMER_PHONE_INVALID',
        'WHATSAPP_SEND_FAILED',
        'BILLING_CONSENT_REQUIRED',
        'PLAN_INVALID',
        'APPLE_TRANSACTION_ALREADY_LINKED',
        'APPLE_ACCOUNT_MISMATCH',
        'IDEMPOTENCY_KEY_INVALID',
        'ACCOUNT_ALREADY_EXISTS',
        'EMAIL_INVALID',
        'BUSINESS_NAME_INVALID',
        'TAX_RATE_MISSING',
        'QUOTE_CHANGED',
        'PUSH_MFA_REQUIRED',
        'API_CONFIG_INVALID',
      ]) {
        expect(
          errorMessageHe(code),
          isNot(startsWith('שגיאה לא צפויה')),
          reason: code,
        );
      }
      expect(
        errorMessageHe(
          'PAYMENT_PROVIDER_UNAVAILABLE',
          serverMessage: 'ספק התשלום אינו זמין כרגע',
          status: 502,
        ),
        'ספק התשלום אינו זמין כרגע',
      );
      expect(
        errorMessageHe(
          'SOMETHING_NEW',
          serverMessage: 'internal detail',
          status: 500,
        ),
        'שגיאה לא צפויה (SOMETHING_NEW)',
      );
    },
  );

  test(
    'production 2026-11-15: blockers speak to the user, not the developer',
    () {
      final allocation = errorMessageHe('ALLOCATION_RULE_NOT_CONFIGURED');
      expect(allocation, isNot(contains('כללי הקצאת')));
      expect(allocation, contains('טיוטות נשמרות'));
      for (final code in [
        'APPLE_ENVIRONMENT_NOT_ALLOWED',
        'APPLE_VERIFICATION_NOT_CONFIGURED',
      ]) {
        expect(
          errorMessageHe(code),
          appStorePurchaseUnavailableHe,
          reason: code,
        );
      }
      expect(appStorePurchaseUnavailableHe, isNot(contains('Connect')));
      expect(
        appStorePurchaseUnavailableHe,
        contains('להמשיך להשתמש באפליקציה'),
      );
    },
  );
}
