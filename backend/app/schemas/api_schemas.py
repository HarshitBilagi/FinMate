from pydantic import BaseModel
from typing import Optional
from datetime import date

class DashboardSummaryResponse(BaseModel):
    total_balance: float
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

class CreateTransactionResponse(BaseModel):
    id: str
    upi_ref_id: str
    amount: float
    merchant: str
    card_masked: str
    message: str
