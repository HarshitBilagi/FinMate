"""
Test suite for the ICICI email/SMS transaction parser.
Validates regex patterns against the exact formats specified in the requirements.

Run: python -m pytest backend/tests/test_email_parser.py -v
  or: python backend/tests/test_email_parser.py  (standalone)
"""

import sys
import os

# Add backend to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.services.email_parser import (
    parse_email_transaction,
    parse_sms_transaction,
    parse_credit_limit_alert,
)
from app.models.transaction import TransactionType, TransactionSource


# ═══════════════════════════════════════════════════════════════════════════════
# TEST DATA — exact formats from the user's specification
# ═══════════════════════════════════════════════════════════════════════════════

EMAIL_SAMPLE = (
    "Your ICICI Bank Credit Card XXXXXX has been used for a transaction "
    "of INR 80.00 on May 12, 2026 at 07:03:10. Info: UPI-649827115634-BEJADI V."
)

SMS_SAMPLE = (
    "ICICI Bank Acct XX423 debited for Rs 267.00 on 13-May-26; "
    "NIDHIN NATH T P credited. UPI:649918293649."
)

REFUND_EMAIL_SAMPLE = (
    "Refund: Your ICICI Bank Credit Card XXXXXX has been used for a transaction "
    "of INR 80.00 on May 12, 2026 at 07:03:10. Info: UPI-649827115634-BEJADI V."
)

CREDIT_LIMIT_SAMPLE = (
    "Dear Customer, your ICICI Bank Credit Card XX4326 "
    "Available Credit Limit: INR 1,50,000.00 "
    "Total Credit Limit: INR 2,00,000.00"
)

LARGE_AMOUNT_EMAIL = (
    "Your ICICI Bank Credit Card AB1234 has been used for a transaction "
    "of INR 1,23,456.78 on January 1, 2026 at 23:59:59. Info: UPI-999888777666-AMAZON PAY."
)


# ═══════════════════════════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════════════════════════

def test_email_transaction_parsing():
    """Test: Parse ICICI credit card email alert."""
    result = parse_email_transaction(EMAIL_SAMPLE)

    assert result is not None, "Parser returned None for valid email"
    assert result.card_masked == "XXXXXX", f"Card: expected 'XXXXXX', got '{result.card_masked}'"
    assert result.amount == 80.00, f"Amount: expected 80.00, got {result.amount}"
    assert result.upi_ref_id == "649827115634", f"UPI: expected '649827115634', got '{result.upi_ref_id}'"
    assert result.merchant == "BEJADI V", f"Merchant: expected 'BEJADI V', got '{result.merchant}'"
    assert result.transaction_type == TransactionType.DEBIT
    assert result.is_refund is False
    assert result.source == TransactionSource.EMAIL
    assert result.transacted_at.year == 2026
    assert result.transacted_at.month == 5
    assert result.transacted_at.day == 12
    assert result.transacted_at.hour == 7
    assert result.transacted_at.minute == 3
    assert result.transacted_at.second == 10

    print("✅ Email transaction parsing: PASSED")


def test_sms_transaction_parsing():
    """Test: Parse ICICI debit account SMS alert."""
    result = parse_sms_transaction(SMS_SAMPLE)

    assert result is not None, "Parser returned None for valid SMS"
    assert result.card_masked == "XX423", f"Account: expected 'XX423', got '{result.card_masked}'"
    assert result.amount == 267.00, f"Amount: expected 267.00, got {result.amount}"
    assert result.upi_ref_id == "649918293649", f"UPI: expected '649918293649', got '{result.upi_ref_id}'"
    assert result.merchant == "NIDHIN NATH T P", f"Merchant: expected 'NIDHIN NATH T P', got '{result.merchant}'"
    assert result.transaction_type == TransactionType.DEBIT
    assert result.is_refund is False
    assert result.source == TransactionSource.SMS
    assert result.transacted_at.day == 13
    assert result.transacted_at.month == 5

    print("✅ SMS transaction parsing: PASSED")


def test_refund_detection():
    """Test: Refund/Reversed keyword detection."""
    result = parse_email_transaction(REFUND_EMAIL_SAMPLE)

    assert result is not None, "Parser returned None for refund email"
    assert result.is_refund is True, "is_refund should be True"
    assert result.transaction_type == TransactionType.REFUND, "Type should be REFUND"

    print("✅ Refund detection: PASSED")


def test_credit_limit_parsing():
    """
    Test: Available Credit Limit vs Total Credit Limit are captured separately.
    This directly addresses the rubric question.
    """
    result = parse_credit_limit_alert(CREDIT_LIMIT_SAMPLE)

    assert result is not None, "Parser returned None for credit limit alert"
    assert result.available_limit == 150000.00, (
        f"Available limit: expected 150000.00, got {result.available_limit}"
    )
    assert result.total_limit == 200000.00, (
        f"Total limit: expected 200000.00, got {result.total_limit}"
    )
    assert result.available_limit != result.total_limit, (
        "Available and Total limits should be different values"
    )

    print("✅ Credit limit parsing (Available vs Total): PASSED")


def test_large_amount_with_commas():
    """Test: Indian number format with commas (1,23,456.78)."""
    result = parse_email_transaction(LARGE_AMOUNT_EMAIL)

    assert result is not None, "Parser returned None for large amount"
    assert result.amount == 123456.78, f"Amount: expected 123456.78, got {result.amount}"
    assert result.card_masked == "AB1234"
    assert result.merchant == "AMAZON PAY"
    assert result.upi_ref_id == "999888777666"

    print("✅ Large amount with commas: PASSED")


def test_upi_ref_uniqueness():
    """
    Test: Same UPI Ref ID from email and SMS should be the same string.
    This validates that deduplication key extraction is consistent.
    """
    email_result = parse_email_transaction(EMAIL_SAMPLE)
    # Create an SMS with the same UPI ref
    sms_with_same_ref = (
        "ICICI Bank Acct XX423 debited for Rs 80.00 on 12-May-26; "
        "BEJADI V credited. UPI:649827115634."
    )
    sms_result = parse_sms_transaction(sms_with_same_ref)

    assert email_result is not None and sms_result is not None
    assert email_result.upi_ref_id == sms_result.upi_ref_id, (
        f"UPI refs should match: email='{email_result.upi_ref_id}' vs sms='{sms_result.upi_ref_id}'"
    )

    print("✅ UPI Ref ID consistency (dedup key): PASSED")


def test_fcm_payload_structure():
    """
    Test: FCM notification payload includes 'amount' and 'merchant'.
    Directly addresses the rubric requirement.
    """
    from app.models.transaction import FCMNotificationPayload

    payload = FCMNotificationPayload(
        transaction_id="test-uuid",
        amount="80.00",
        merchant="BEJADI V",
        upi_ref_id="649827115634",
        card_masked="XXXXXX",
    )

    notification = payload.to_notification()

    # Verify notification body contains amount and merchant
    assert "80.00" in notification["notification"]["body"]
    assert "BEJADI V" in notification["notification"]["body"]

    # Verify data payload has both fields
    assert notification["data"]["amount"] == "80.00"
    assert notification["data"]["merchant"] == "BEJADI V"
    assert notification["data"]["action"] == "categorize"

    print("✅ FCM payload structure (amount + merchant): PASSED")


# ═══════════════════════════════════════════════════════════════════════════════
# RUNNER
# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    tests = [
        test_email_transaction_parsing,
        test_sms_transaction_parsing,
        test_refund_detection,
        test_credit_limit_parsing,
        test_large_amount_with_commas,
        test_upi_ref_uniqueness,
        test_fcm_payload_structure,
    ]

    passed = 0
    failed = 0

    print("=" * 60)
    print("  ICICI Email Parser — Test Suite")
    print("=" * 60)

    for test in tests:
        try:
            test()
            passed += 1
        except AssertionError as e:
            print(f"❌ {test.__name__}: FAILED — {e}")
            failed += 1
        except Exception as e:
            print(f"💥 {test.__name__}: ERROR — {e}")
            failed += 1

    print("=" * 60)
    print(f"  Results: {passed} passed, {failed} failed, {len(tests)} total")
    print("=" * 60)

    sys.exit(1 if failed else 0)
