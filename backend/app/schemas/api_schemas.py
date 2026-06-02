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
