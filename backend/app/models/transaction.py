"""
Pydantic models for parsed transaction data.
These are in-memory models used between the parser and the database layer.
"""

# pyrefly: ignore [missing-import]
from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from enum import Enum


class TransactionType(str, Enum):
    DEBIT = "debit"
    CREDIT = "credit"
    REFUND = "refund"


class TransactionSource(str, Enum):
    EMAIL = "email"
    SMS = "sms"
    MANUAL = "manual"


class ParsedTransaction(BaseModel):
    """Represents a single parsed transaction from an ICICI email or SMS."""

    card_masked: str = Field(
        ...,
        description="Masked card/account identifier (e.g., 'XX4326' or last 6 digits)",
    )
    amount: float = Field(
        ...,
        gt=0,
        description="Transaction amount in INR",
    )
    merchant: Optional[str] = Field(
        None,
        description="Merchant name parsed from the Info/credited field",
    )
    upi_ref_id: str = Field(
        ...,
        description="UPI Reference ID — deduplication key",
    )
    transaction_type: TransactionType = Field(
        default=TransactionType.DEBIT,
    )
    is_refund: bool = Field(
        default=False,
        description="True if email contained 'Refund' or 'Reversed' keywords",
    )
    refund_of_upi_ref: Optional[str] = Field(
        None,
        description="UPI ref of the original transaction if this is a refund",
    )
    source: TransactionSource = Field(
        default=TransactionSource.EMAIL,
    )
    transacted_at: datetime = Field(
        ...,
        description="Timestamp when the transaction occurred",
    )
    raw_message: Optional[str] = Field(
        None,
        description="Original email/SMS body for audit trail",
    )


class CreditLimitUpdate(BaseModel):
    """Parsed from ICICI credit limit alert emails."""

    card_masked: str
    available_limit: float = Field(
        ...,
        description="Available Credit Limit in INR",
    )
    total_limit: float = Field(
        ...,
        description="Total Credit Limit in INR",
    )


class FCMNotificationPayload(BaseModel):
    """
    Push notification payload sent to Flutter app.
    Includes amount and merchant for the categorization prompt.
    """

    transaction_id: str
    amount: str = Field(description="Formatted amount string, e.g., '80.00'")
    merchant: str = Field(description="Merchant name for display")
    upi_ref_id: str
    card_masked: str
    action: str = Field(default="categorize")

    def to_notification(self) -> dict:
        """Build the FCM message payload."""
        return {
            "notification": {
                "title": "New Transaction Detected",
                "body": f"₹{self.amount} at {self.merchant}",
            },
            "data": {
                "transaction_id": self.transaction_id,
                "amount": self.amount,
                "merchant": self.merchant,
                "upi_ref_id": self.upi_ref_id,
                "card_masked": self.card_masked,
                "action": self.action,
            },
        }
