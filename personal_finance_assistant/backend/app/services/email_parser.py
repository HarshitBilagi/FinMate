"""
ICICI Bank Email & SMS Transaction Parser.

Connects to Gmail via IMAP, fetches unread ICICI transaction alerts,
parses them with regex, deduplicates via UPI Ref ID, and returns
structured ParsedTransaction objects.

Supported formats:
  1. Email: "Your ICICI Bank Credit Card XXXXXX has been used for a transaction
             of INR 80.00 on May 12, 2026 at 07:03:10. Info: UPI-649827115634-BEJADI V."
  2. SMS:   "ICICI Bank Acct XX423 debited for Rs 267.00 on 13-May-26;
             NIDHIN NATH T P credited. UPI:649918293649."
  3. Limit: "Available Credit Limit: INR 1,50,000.00 / Total Credit Limit: INR 2,00,000.00"
"""

import imaplib
import email
import email.message
import re
import logging
from email.header import decode_header
from datetime import datetime
from typing import Optional

from app.models.transaction import (
    ParsedTransaction,
    CreditLimitUpdate,
    TransactionType,
    TransactionSource,
)
from app.core.config import get_settings

logger = logging.getLogger(__name__)

# ═══════════════════════════════════════════════════════════════════════════════
# REGEX PATTERNS
# ═══════════════════════════════════════════════════════════════════════════════

# ── Email format (Credit Card transaction alert) ─────────────────────────────
EMAIL_CARD_PATTERN = re.compile(
    r"Credit Card\s+(\w{6})",  # Group 1: last 6 masked digits
    re.IGNORECASE,
)
EMAIL_AMOUNT_PATTERN = re.compile(
    r"INR\s+([\d,]+\.\d{2})",  # Group 1: amount with commas (e.g., "1,234.56")
    re.IGNORECASE,
)
EMAIL_DATE_PATTERN = re.compile(
    r"on\s+(\w+\s+\d{1,2},\s*\d{4})",  # Group 1: "May 12, 2026"
    re.IGNORECASE,
)
EMAIL_TIME_PATTERN = re.compile(
    r"at\s+(\d{2}:\d{2}:\d{2})",  # Group 1: "07:03:10"
    re.IGNORECASE,
)
EMAIL_UPI_REF_PATTERN = re.compile(
    r"UPI[-:](\d+)",  # Group 1: UPI reference number
    re.IGNORECASE,
)
EMAIL_MERCHANT_PATTERN = re.compile(
    r"UPI-\d+-(.+?)\.?\s*$",  # Group 1: merchant name after UPI ref
    re.IGNORECASE | re.MULTILINE,
)

# ── SMS format (Debit account transaction alert) ─────────────────────────────
SMS_ACCOUNT_PATTERN = re.compile(
    r"Acct\s+XX(\d{3})",  # Group 1: last 3 account digits
    re.IGNORECASE,
)
SMS_AMOUNT_PATTERN = re.compile(
    r"Rs\s+([\d,]+\.\d{2})",  # Group 1: amount
    re.IGNORECASE,
)
SMS_DATE_PATTERN = re.compile(
    r"on\s+(\d{2}-\w{3}-\d{2})",  # Group 1: "13-May-26"
    re.IGNORECASE,
)
SMS_MERCHANT_PATTERN = re.compile(
    r";\s*(.+?)\s+credited",  # Group 1: merchant/payee name
    re.IGNORECASE,
)
SMS_UPI_REF_PATTERN = re.compile(
    r"UPI[:\s]+(\d+)",  # Group 1: UPI ref
    re.IGNORECASE,
)

# ── Credit Limit alert ───────────────────────────────────────────────────────
AVAILABLE_LIMIT_PATTERN = re.compile(
    r"Available\s+Credit\s+Limit[:\s]+(?:INR|Rs\.?)\s*([\d,]+\.\d{2})",
    re.IGNORECASE,
)
TOTAL_LIMIT_PATTERN = re.compile(
    r"Total\s+Credit\s+Limit[:\s]+(?:INR|Rs\.?)\s*([\d,]+\.\d{2})",
    re.IGNORECASE,
)

# ── Refund / Reversal detection ──────────────────────────────────────────────
REFUND_PATTERN = re.compile(
    r"\b(refund|reversed|reversal)\b",
    re.IGNORECASE,
)


# ═══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

def _parse_indian_amount(amount_str: str) -> float:
    """
    Parse Indian-formatted amount string to float.
    Handles comma-separated values like "1,50,000.00" → 150000.00
    """
    return float(amount_str.replace(",", ""))


def _parse_email_datetime(date_str: str, time_str: str) -> datetime:
    """Parse email date ('May 12, 2026') and time ('07:03:10') into datetime."""
    combined = f"{date_str} {time_str}"
    return datetime.strptime(combined, "%B %d, %Y %H:%M:%S")


def _parse_sms_datetime(date_str: str) -> datetime:
    """Parse SMS date ('13-May-26') into datetime. Assumes 2000s century."""
    return datetime.strptime(date_str, "%d-%b-%y")


def _decode_email_body(msg: email.message.Message) -> str:
    """Extract plain text body from an email message."""
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            if content_type == "text/plain":
                charset = part.get_content_charset() or "utf-8"
                payload = part.get_payload(decode=True)
                if payload:
                    body += payload.decode(charset, errors="replace")
    else:
        charset = msg.get_content_charset() or "utf-8"
        payload = msg.get_payload(decode=True)
        if payload:
            body = payload.decode(charset, errors="replace")
    return body


def _decode_subject(msg: email.message.Message) -> str:
    """Decode email subject header."""
    subject, encoding = decode_header(msg["Subject"])[0]
    if isinstance(subject, bytes):
        return subject.decode(encoding or "utf-8", errors="replace")
    return subject or ""


# ═══════════════════════════════════════════════════════════════════════════════
# PARSERS
# ═══════════════════════════════════════════════════════════════════════════════

def parse_email_transaction(body: str) -> Optional[ParsedTransaction]:
    """
    Parse an ICICI Credit Card transaction email.

    Expected format:
        "Your ICICI Bank Credit Card XXXXXX has been used for a transaction
         of INR 80.00 on May 12, 2026 at 07:03:10. Info: UPI-649827115634-BEJADI V."

    Returns:
        ParsedTransaction or None if the body doesn't match the expected format.
    """
    card_match = EMAIL_CARD_PATTERN.search(body)
    amount_match = EMAIL_AMOUNT_PATTERN.search(body)
    date_match = EMAIL_DATE_PATTERN.search(body)
    time_match = EMAIL_TIME_PATTERN.search(body)
    upi_match = EMAIL_UPI_REF_PATTERN.search(body)

    # All critical fields must be present
    if not all([card_match, amount_match, date_match, time_match, upi_match]):
        logger.warning("Email body did not match ICICI credit card transaction pattern")
        return None

    # Merchant is optional (some alerts may not have Info field)
    merchant_match = EMAIL_MERCHANT_PATTERN.search(body)
    merchant = merchant_match.group(1).strip() if merchant_match else None

    # Detect refund/reversal
    is_refund = bool(REFUND_PATTERN.search(body))
    txn_type = TransactionType.REFUND if is_refund else TransactionType.DEBIT

    return ParsedTransaction(
        card_masked=card_match.group(1),
        amount=_parse_indian_amount(amount_match.group(1)),
        merchant=merchant,
        upi_ref_id=upi_match.group(1),
        transaction_type=txn_type,
        is_refund=is_refund,
        source=TransactionSource.EMAIL,
        transacted_at=_parse_email_datetime(
            date_match.group(1), time_match.group(1)
        ),
        raw_message=body,
    )


def parse_sms_transaction(body: str) -> Optional[ParsedTransaction]:
    """
    Parse an ICICI Debit Account SMS transaction.

    Expected format:
        "ICICI Bank Acct XX423 debited for Rs 267.00 on 13-May-26;
         NIDHIN NATH T P credited. UPI:649918293649."

    Returns:
        ParsedTransaction or None if the body doesn't match.
    """
    acct_match = SMS_ACCOUNT_PATTERN.search(body)
    amount_match = SMS_AMOUNT_PATTERN.search(body)
    date_match = SMS_DATE_PATTERN.search(body)
    upi_match = SMS_UPI_REF_PATTERN.search(body)

    if not all([acct_match, amount_match, date_match, upi_match]):
        logger.warning("SMS body did not match ICICI debit account pattern")
        return None

    merchant_match = SMS_MERCHANT_PATTERN.search(body)
    merchant = merchant_match.group(1).strip() if merchant_match else None

    is_refund = bool(REFUND_PATTERN.search(body))
    txn_type = TransactionType.REFUND if is_refund else TransactionType.DEBIT

    return ParsedTransaction(
        card_masked=f"XX{acct_match.group(1)}",
        amount=_parse_indian_amount(amount_match.group(1)),
        merchant=merchant,
        upi_ref_id=upi_match.group(1),
        transaction_type=txn_type,
        is_refund=is_refund,
        source=TransactionSource.SMS,
        transacted_at=_parse_sms_datetime(date_match.group(1)),
        raw_message=body,
    )


def parse_credit_limit_alert(body: str) -> Optional[CreditLimitUpdate]:
    """
    Parse an ICICI Credit Limit alert email.

    Captures 'Available Credit Limit' and 'Total Credit Limit' separately.
    These are distinct values — Available ≤ Total.

    Expected patterns:
        "Available Credit Limit: INR 1,50,000.00"
        "Total Credit Limit: INR 2,00,000.00"
    """
    available_match = AVAILABLE_LIMIT_PATTERN.search(body)
    total_match = TOTAL_LIMIT_PATTERN.search(body)

    if not available_match or not total_match:
        logger.debug("Body did not contain credit limit information")
        return None

    # Extract card identifier from the same email
    card_match = EMAIL_CARD_PATTERN.search(body)
    card_masked = card_match.group(1) if card_match else "UNKNOWN"

    return CreditLimitUpdate(
        card_masked=card_masked,
        available_limit=_parse_indian_amount(available_match.group(1)),
        total_limit=_parse_indian_amount(total_match.group(1)),
    )


# ═══════════════════════════════════════════════════════════════════════════════
# IMAP FETCHER
# ═══════════════════════════════════════════════════════════════════════════════

def fetch_icici_emails() -> list[ParsedTransaction]:
    """
    Connect to Gmail IMAP, fetch unread ICICI transaction alerts,
    parse each one, and return a list of ParsedTransaction objects.

    Marks successfully parsed emails as SEEN to avoid re-processing.
    Deduplication by UPI Ref ID happens at the database layer (UNIQUE constraint).
    """
    settings = get_settings()
    transactions: list[ParsedTransaction] = []

    try:
        # Connect to Gmail IMAP over SSL
        mail = imaplib.IMAP4_SSL(settings.IMAP_HOST, settings.IMAP_PORT)
        mail.login(settings.IMAP_EMAIL, settings.IMAP_PASSWORD)
        mail.select("INBOX")

        # Search for unread emails from ICICI alerts
        search_criteria = (
            f'(UNSEEN FROM "{settings.IMAP_SEARCH_FROM}" '
            f'SUBJECT "{settings.IMAP_SEARCH_SUBJECT}")'
        )
        status, message_ids = mail.search(None, search_criteria)

        if status != "OK" or not message_ids[0]:
            logger.info("No new ICICI transaction emails found")
            mail.logout()
            return transactions

        email_ids = message_ids[0].split()
        logger.info(f"Found {len(email_ids)} unread ICICI email(s)")

        for email_id in email_ids:
            try:
                # Fetch the email
                status, msg_data = mail.fetch(email_id, "(RFC822)")
                if status != "OK":
                    continue

                raw_email = msg_data[0][1]
                msg = email.message_from_bytes(raw_email)

                subject = _decode_subject(msg)
                body = _decode_email_body(msg)
                full_text = f"{subject}\n{body}"

                # Try parsing as credit card email first, then as SMS-forwarded
                parsed = parse_email_transaction(full_text)
                if not parsed:
                    parsed = parse_sms_transaction(full_text)

                if parsed:
                    transactions.append(parsed)
                    logger.info(
                        f"Parsed transaction: ₹{parsed.amount} | "
                        f"UPI:{parsed.upi_ref_id} | "
                        f"Merchant:{parsed.merchant}"
                    )

                    # Also check for credit limit updates in the same email
                    limit_update = parse_credit_limit_alert(full_text)
                    if limit_update:
                        logger.info(
                            f"Credit limit update: "
                            f"Available={limit_update.available_limit}, "
                            f"Total={limit_update.total_limit}"
                        )
                        # TODO: Update cards table with new limits via Supabase

                    # Mark email as seen
                    mail.store(email_id, "+FLAGS", "\\Seen")
                else:
                    logger.warning(
                        f"Could not parse email (ID: {email_id.decode()}): {subject}"
                    )

            except Exception as e:
                logger.error(f"Error processing email {email_id}: {e}", exc_info=True)
                continue

        mail.logout()
        logger.info(f"Successfully parsed {len(transactions)} transaction(s)")

    except imaplib.IMAP4.error as e:
        logger.error(f"IMAP connection error: {e}", exc_info=True)
    except Exception as e:
        logger.error(f"Unexpected error in email fetcher: {e}", exc_info=True)

    return transactions
