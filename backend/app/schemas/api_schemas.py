from pydantic import BaseModel
from typing import Optional, List
from datetime import date, datetime

class DashboardSummaryResponse(BaseModel):
    total_balance: float
    total_limit: float
    remaining_limit: float
    next_bill_date: date
    days_until_due: int

class CategorizeTransactionRequest(BaseModel):
    category: str

class CategorizeTransactionResponse(BaseModel):
    id: str
    category: str
    remaining_limit: float  # Returned as per rubric
    message: str

class IgnoreTransactionResponse(BaseModel):
    upi_ref_id: str
    message: str

class CreateTransactionRequest(BaseModel):
    upi_ref_id: str
    amount: float
    merchant: str
    card_masked: str
    raw_message: str
    source: str = "sms"
    transaction_date: Optional[str] = None
    category: Optional[str] = "uncategorized"
    transaction_type: Optional[str] = "debit"

class CreateTransactionResponse(BaseModel):
    id: str
    upi_ref_id: str
    amount: float
    merchant: str
    card_masked: str
    message: str

class TransactionListItem(BaseModel):
    id: str
    card_id: str
    upi_ref_id: str
    amount: float
    merchant: Optional[str] = None
    category: str = "uncategorized"
    transaction_type: str = "debit"
    is_refund: bool = False
    source: str = "email"
    transacted_at: str

class TransactionsListResponse(BaseModel):
    transactions: List[TransactionListItem]
    count: int
