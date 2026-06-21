from fastapi import APIRouter, HTTPException, Header, Depends
from pydantic import BaseModel
from typing import Optional
from datetime import date, datetime, timedelta
import logging

from app.db.supabase import get_supabase_client
from app.schemas.api_schemas import (
    DashboardSummaryResponse,
    CategorizeTransactionRequest,
    CategorizeTransactionResponse,
    IgnoreTransactionResponse,
    CreateTransactionRequest,
    CreateTransactionResponse,
    TransactionListItem,
    TransactionsListResponse
)

router = APIRouter()
logger = logging.getLogger(__name__)

@router.get("/health")
def health_check():
    return {"status": "ok"}

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
                total_limit=90000.00,
                remaining_limit=90000.00,
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
            total_limit=90000.00,
            remaining_limit=float(card.get('available_limit', 0.0)),
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

@router.post("/transactions/ignore/{upi_ref_id}", response_model=IgnoreTransactionResponse)
def ignore_transaction(upi_ref_id: str, device_id: str = Depends(get_device_id)):
    """
    Flags the transaction as ignored using the unique UPI Ref ID.
    """
    supabase = get_supabase_client()
    try:
        logger.info(f"Flagging transaction with UPI Ref ID {upi_ref_id} as ignored.")
        
        # Try updating Supabase (setting category to 'ignored' or updating an is_ignored boolean if exists)
        try:
            supabase.table("transactions").update({
                "category": "ignored",
                "updated_at": datetime.now().isoformat()
            }).eq("upi_ref_id", upi_ref_id).execute()
        except Exception as e:
            logger.warning(f"Could not update Supabase for ignore: {e}")
            
        return IgnoreTransactionResponse(
            upi_ref_id=upi_ref_id,
            message="Transaction ignored successfully"
        )
    except Exception as e:
        logger.error(f"Error ignoring transaction: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/transactions", response_model=CreateTransactionResponse)
def create_transaction(
    request: CreateTransactionRequest,
    device_id: str = Depends(get_device_id)
):
    supabase = get_supabase_client()
    try:
        # Find user by device_id
        user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
        if not user_res.data:
            user_res = supabase.table("users").insert({"device_id": device_id}).execute()
            if not user_res.data:
                raise HTTPException(status_code=500, detail="Failed to create user")
        
        user_id = user_res.data[0]['id']
        
        # Find card by user_id and card_masked
        card_res = supabase.table("cards").select("id, available_limit").eq("user_id", user_id).eq("card_masked", request.card_masked).execute()
        if not card_res.data:
            card_data = {
                "user_id": user_id,
                "card_masked": request.card_masked,
                "card_type": "credit_card",
                "total_limit": 90000.00,
                "available_limit": 90000.00,
                "billing_cycle_day": 15
            }
            card_res = supabase.table("cards").insert(card_data).execute()
            if not card_res.data:
                raise HTTPException(status_code=500, detail="Failed to create card")
                
        card = card_res.data[0]
        card_id = card['id']
        current_limit = float(card['available_limit'])
        
        # Use client-parsed SMS date when provided, else fallback to server time
        transacted_at = request.transaction_date if request.transaction_date else datetime.now().isoformat()
        
        # Insert transaction
        txn_data = {
            "card_id": card_id,
            "upi_ref_id": request.upi_ref_id,
            "amount": request.amount,
            "merchant": request.merchant,
            "category": "uncategorized",
            "transaction_type": "debit",
            "is_refund": False,
            "source": request.source,
            "raw_message": request.raw_message,
            "transacted_at": transacted_at
        }
        
        try:
            txn_res = supabase.table("transactions").insert(txn_data).execute()
            if not txn_res.data:
                raise HTTPException(status_code=500, detail="Failed to insert transaction")
                
            new_limit = current_limit - request.amount
            supabase.table("cards").update({"available_limit": new_limit}).eq("id", card_id).execute()
            
            created_txn = txn_res.data[0]
            return CreateTransactionResponse(
                id=created_txn['id'],
                upi_ref_id=request.upi_ref_id,
                amount=request.amount,
                merchant=request.merchant,
                card_masked=request.card_masked,
                message="Transaction created successfully"
            )
        except Exception as e:
            existing = supabase.table("transactions").select("id").eq("upi_ref_id", request.upi_ref_id).execute()
            if existing.data:
                return CreateTransactionResponse(
                    id=existing.data[0]['id'],
                    upi_ref_id=request.upi_ref_id,
                    amount=request.amount,
                    merchant=request.merchant,
                    card_masked=request.card_masked,
                    message="Transaction already exists"
                )
            raise e
            
    except Exception as e:
        logger.error(f"Error creating transaction: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/transactions", response_model=TransactionsListResponse)
def get_transactions(device_id: str = Depends(get_device_id)):
    """
    Returns a list of all transactions for the user's card(s).
    """
    supabase = get_supabase_client()
    try:
        # Find user by device_id
        user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
        if not user_res.data:
            return TransactionsListResponse(transactions=[], count=0)
            
        user_id = user_res.data[0]['id']
        
        # Get user's card(s)
        cards_res = supabase.table("cards").select("id").eq("user_id", user_id).execute()
        if not cards_res.data:
            return TransactionsListResponse(transactions=[], count=0)
            
        card_ids = [card['id'] for card in cards_res.data]
        
        # Get all transactions for these card(s)
        txns_res = supabase.table("transactions").select("*").in_("card_id", card_ids).order("transacted_at", desc=True).execute()
        
        transactions = []
        for txn in txns_res.data:
            transacted_at_val = txn.get('transacted_at')
            if isinstance(transacted_at_val, (datetime, date)):
                transacted_at_val = transacted_at_val.isoformat()
            
            transactions.append(
                TransactionListItem(
                    id=str(txn['id']),
                    card_id=str(txn['card_id']),
                    upi_ref_id=str(txn['upi_ref_id']),
                    amount=float(txn['amount']),
                    merchant=txn.get('merchant'),
                    category=txn.get('category', 'uncategorized'),
                    transaction_type=txn.get('transaction_type', 'debit'),
                    is_refund=bool(txn.get('is_refund', False)),
                    source=txn.get('source', 'email'),
                    transacted_at=str(transacted_at_val)
                )
            )
            
        return TransactionsListResponse(
            transactions=transactions,
            count=len(transactions)
        )
        
    except Exception as e:
        logger.error(f"Error fetching transactions: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")
