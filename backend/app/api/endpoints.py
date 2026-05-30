from fastapi import APIRouter, HTTPException, Header, Depends
from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime, timedelta
import logging

from app.db.supabase import get_supabase_client
from app.schemas.api_schemas import (
    DashboardSummaryResponse,
    CategorizeTransactionRequest,
    CategorizeTransactionResponse
)

router = APIRouter()
logger = logging.getLogger(__name__)

# Basic dependency to get the current user device_id from headers.
# Since we have biometric local auth, we'll identify users via device_id.
def get_device_id(x_device_id: Optional[str] = Header(None)):
    if not x_device_id:
        # Provide a fallback for development testing
        return "dev-device-123"
    return x_device_id

@router.get("/dashboard/summary", response_model=DashboardSummaryResponse)
def get_dashboard_summary(device_id: str = Depends(get_device_id)):
    """
    Returns total balance (savings), remaining limit, next bill date, and days until due.
    For this MVP, we'll query the cards table for the given device_id's user.
    """
    supabase = get_supabase_client()
    try:
        # Find user by device_id
        user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
        if not user_res.data:
            # For MVP, if user doesn't exist, return mock dashboard data 
            # to allow Flutter to work without a strict backend seed.
            logger.warning(f"User with device {device_id} not found. Returning mock data.")
            today = date.today()
            next_bill = date(today.year, today.month, 15)
            if next_bill < today:
                next_bill = date(today.year, today.month + 1, 15)
            due_date = next_bill + timedelta(days=20)
            
            return DashboardSummaryResponse(
                total_balance=45320.50,
                remaining_limit=156780.00,
                next_bill_date=next_bill,
                days_until_due=(due_date - today).days
            )

        user_id = user_res.data[0]['id']
        
        # Get primary card
        cards_res = supabase.table("cards").select("*").eq("user_id", user_id).limit(1).execute()
        if not cards_res.data:
            raise HTTPException(status_code=404, detail="No active cards found for user.")
            
        card = cards_res.data[0]
        
        # Calculate dates based on billing cycle day
        today = date.today()
        billing_day = card.get('billing_cycle_day', 1)
        
        # Handle month rollover for billing date
        try:
            next_bill = date(today.year, today.month, billing_day)
        except ValueError:
            # Handle cases like Feb 30 -> jump to next valid or use next month
            next_bill = date(today.year, today.month, 28)
            
        if next_bill <= today:
            month = today.month + 1 if today.month < 12 else 1
            year = today.year if today.month < 12 else today.year + 1
            try:
                next_bill = date(year, month, billing_day)
            except ValueError:
                next_bill = date(year, month, 28)
                
        # Due date is typically 20 days after bill date
        due_date = next_bill + timedelta(days=20)
        days_until_due = (due_date - today).days
        
        # We assume total_balance (savings) is static for now 
        # or would be fetched from a bank account table
        total_balance = 45320.50 
        
        return DashboardSummaryResponse(
            total_balance=total_balance,
            remaining_limit=card.get('available_limit', 0.0),
            next_bill_date=next_bill,
            days_until_due=days_until_due
        )
        
    except Exception as e:
        logger.error(f"Error fetching dashboard summary: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/transactions/categorize/{transaction_id}", response_model=CategorizeTransactionResponse)
def categorize_transaction(
    transaction_id: str, 
    request: CategorizeTransactionRequest,
    device_id: str = Depends(get_device_id)
):
    """
    Updates a transaction's category.
    Handles 'Transaction Not Found'.
    Recalculates or fetches the 'Remaining Limit' to return.
    """
    supabase = get_supabase_client()
    try:
        # Check if transaction exists
        txn_res = supabase.table("transactions").select("id, card_id").eq("id", transaction_id).execute()
        if not txn_res.data:
            raise HTTPException(status_code=404, detail=f"Transaction with ID {transaction_id} not found")
            
        card_id = txn_res.data[0]['card_id']
            
        # Update the category
        update_res = supabase.table("transactions").update({
            "category": request.category,
            "updated_at": datetime.now().isoformat()
        }).eq("id", transaction_id).execute()
        
        if not update_res.data:
            raise HTTPException(status_code=500, detail="Failed to update transaction category")

        # Get the updated remaining limit from the associated card
        card_res = supabase.table("cards").select("available_limit").eq("id", card_id).execute()
        remaining_limit = card_res.data[0]['available_limit'] if card_res.data else 0.0
        
        # Return the response with the updated limit
        return CategorizeTransactionResponse(
            id=transaction_id,
            category=request.category,
            remaining_limit=remaining_limit,
            message="Transaction categorized successfully"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error categorizing transaction: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")
