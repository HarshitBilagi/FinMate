from fastapi import APIRouter, HTTPException, Header, Depends, status
from fastapi.responses import Response
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from typing import Optional, List
from datetime import date, datetime, timedelta, timezone
import logging

from app.core.config import get_settings
from app.db.supabase import get_supabase_client
from app.core.automated_reporter import (
    generate_monthly_user_report,
    send_monthly_report_email,
    send_fcm_notification
)
from app.schemas.api_schemas import (
    DashboardSummaryResponse,
    CategorizeTransactionRequest,
    CategorizeTransactionResponse,
    BatchCategorizeRequest,
    BatchCategorizeResponse,
    IgnoreTransactionResponse,
    CreateTransactionRequest,
    CreateTransactionResponse,
    TransactionListItem,
    TransactionsListResponse,
    CategoryBudgetSetItem,
    SetCategoryBudgetsRequest,
    CategoryBudgetStatusItem,
    CategoryBudgetsResponse,
    SetCategoryBudgetsResponse
)

IST = timezone(timedelta(hours=5, minutes=30))

def normalize_timestamp(date_str: Optional[str]) -> str:
    """
    Parses and normalizes incoming timestamp strings to ensure they are
    timezone-aware and accurately stored in Supabase TIMESTAMPTZ.
    If naive, explicitly assigns IST (+05:30) offset.
    """
    now_ist = datetime.now(IST)
    if not date_str or not date_str.strip():
        return now_ist.isoformat()
    
    cleaned = date_str.strip()
    if "T" not in cleaned and " " not in cleaned:
        cleaned = f"{cleaned}T{now_ist.strftime('%H:%M:%S.%f')[:-3]}"
    else:
        cleaned = cleaned.replace(" ", "T")
    
    try:
        if cleaned.endswith("Z"):
            cleaned = cleaned[:-1] + "+00:00"
        dt = datetime.fromisoformat(cleaned)
    except Exception:
        return now_ist.isoformat()
    
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=IST)
        
    return dt.isoformat()

class TriggerReportRequest(BaseModel):
    user_id: Optional[str] = None
    month: Optional[int] = None
    year: Optional[int] = None
    email: Optional[str] = None

class TriggerReportResponse(BaseModel):
    user_id: str
    month: int
    year: int
    email: str
    email_sent: bool
    fcm_sent: bool
    filename: str
    message: str

router = APIRouter()
logger = logging.getLogger(__name__)

security = HTTPBearer(auto_error=False)

def verify_token(credentials: Optional[HTTPAuthorizationCredentials] = Depends(security)) -> dict:
    """
    Validates the Authorization Bearer header against SUPABASE_JWT_SECRET 
    and returns the decoded user payload (including user_id/sub).
    """
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated"
        )
    
    token = credentials.credentials
    settings = get_settings()
    jwt_secret = settings.SUPABASE_JWT_SECRET
    static_token = getattr(settings, "STATIC_JWT_TOKEN", "YOUR_GENERATED_LONG_LIVED_JWT")

    if jwt_secret:
        try:
            import jwt
            # Decodes the token using your Supabase secret
            payload = jwt.decode(token, jwt_secret, algorithms=["HS256"], options={"verify_aud": False})
            return payload  # Returns dict containing 'sub' (User UID) and 'email'
        except Exception as e:
            logger.error(f"JWT Verification failed: {e}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token signature"
            )

    if token == static_token or token == "YOUR_GENERATED_LONG_LIVED_JWT":
        return {"sub": "dev-user-id", "email": "dev@example.com"}

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Server authentication misconfigured"
    )

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
def get_dashboard_summary(
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
):
    """
    Returns total balance (savings), remaining limit, next bill date, and days until due.
    For this MVP, we'll query the cards table for the given device_id's user.
    """
    supabase = get_supabase_client()
    try:
        now = datetime.now()
        start_of_month = datetime(now.year, now.month, 1).isoformat()

        # Find user by device_id
        user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
        if not user_res.data:
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
        
        cards_res = supabase.table("cards").select("*").eq("user_id", user_id).execute()
        if not cards_res.data:
            today = date.today()
            return DashboardSummaryResponse(
                total_balance=45320.50,
                total_limit=90000.00,
                remaining_limit=90000.00,
                next_bill_date=date(today.year, today.month, 15),
                days_until_due=20
            )

        card = cards_res.data[0]
        card_ids = [c['id'] for c in cards_res.data]

        # Calculate current month outflow strictly (.gte("transacted_at", start_of_month))
        # debit increases outflow, credit reduces outflow
        txns_res = supabase.table("transactions").select("amount, transaction_type").in_("card_id", card_ids).gte("transacted_at", start_of_month).execute()
        debit_total = sum(
            float(t['amount']) for t in txns_res.data if t.get('transaction_type', 'debit') == 'debit'
        )
        credit_total = sum(
            float(t['amount']) for t in txns_res.data if t.get('transaction_type') == 'credit'
        )
        month_outflow = debit_total - credit_total

        total_limit = float(card.get('total_limit', 90000.00))
        remaining_limit = total_limit - month_outflow

        today = date.today()
        billing_day = card.get('billing_cycle_day', 1)
        try:
            next_bill = date(today.year, today.month, billing_day)
        except ValueError:
            next_bill = date(today.year, today.month, 28)
            
        if next_bill <= today:
            month = today.month + 1 if today.month < 12 else 1
            year = today.year if today.month < 12 else today.year + 1
            try:
                next_bill = date(year, month, billing_day)
            except ValueError:
                next_bill = date(year, month, 28)
                
        due_date = next_bill + timedelta(days=20)
        days_until_due = (due_date - today).days
        
        return DashboardSummaryResponse(
            total_balance=45320.50,
            total_limit=total_limit,
            remaining_limit=remaining_limit,
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
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
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
            "category": request.category
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

@router.patch("/transactions/{transaction_id}/category", response_model=CategorizeTransactionResponse)
def categorize_transaction_patch(
    transaction_id: str, 
    request: CategorizeTransactionRequest,
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
):
    """
    Updates a transaction's category via PATCH.
    """
    return categorize_transaction(transaction_id, request, device_id)

@router.post("/transactions/batch-categorize", response_model=BatchCategorizeResponse)
def batch_categorize_transactions(
    request: BatchCategorizeRequest,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Updates the category for multiple transactions at once.
    """
    supabase = get_supabase_client()
    try:
        if not request.transaction_ids:
            return BatchCategorizeResponse(
                transaction_ids=[],
                category=request.category,
                updated_count=0,
                message="No transactions provided to categorize"
            )

        update_res = supabase.table("transactions").update({
            "category": request.category
        }).in_("id", request.transaction_ids).execute()

        count = len(update_res.data) if update_res.data else len(request.transaction_ids)

        return BatchCategorizeResponse(
            transaction_ids=request.transaction_ids,
            category=request.category,
            updated_count=count,
            message=f"{count} transactions categorized as {request.category}"
        )
    except Exception as e:
        logger.error(f"Error in batch categorize: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/transactions/ignore/{upi_ref_id}", response_model=IgnoreTransactionResponse)
def ignore_transaction(
    upi_ref_id: str,
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
):
    """
    Flags the transaction as ignored using the unique UPI Ref ID.
    """
    supabase = get_supabase_client()
    try:
        logger.info(f"Flagging transaction with UPI Ref ID {upi_ref_id} as ignored.")
        
        # Try updating Supabase (setting category to 'ignored' or updating an is_ignored boolean if exists)
        try:
            supabase.table("transactions").update({
                "category": "ignored"
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
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
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
        
        # Robust timezone-aware timestamp normalization
        transacted_at = normalize_timestamp(request.transaction_date)

        txn_category = request.category if request.category else "uncategorized"
        txn_type = request.transaction_type if request.transaction_type else "debit"
        
        # Insert transaction
        txn_data = {
            "card_id": card_id,
            "upi_ref_id": request.upi_ref_id,
            "amount": request.amount,
            "merchant": request.merchant,
            "category": txn_category,
            "transaction_type": txn_type,
            "is_refund": (txn_type == "credit"),
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
def get_transactions(
    device_id: str = Depends(get_device_id),
    token: str = Depends(verify_token)
):
    """
    Returns a list of all transactions for the user's card(s) in the current calendar month.
    """
    supabase = get_supabase_client()
    try:
        now = datetime.now()
        start_of_month = datetime(now.year, now.month, 1).isoformat()

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
        
        # Get transactions for current calendar month strictly (.gte("transacted_at", start_of_month))
        txns_res = supabase.table("transactions").select("*").in_("card_id", card_ids).gte("transacted_at", start_of_month).order("transacted_at", desc=True).execute()
        
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

@router.delete("/transactions/{transaction_id}")
def delete_transaction(
    transaction_id: str,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Permanently deletes a transaction by ID.
    """
    supabase = get_supabase_client()
    try:
        txn_res = supabase.table("transactions").select("id, card_id, amount, transaction_type").eq("id", transaction_id).execute()
        if not txn_res.data:
            raise HTTPException(status_code=404, detail=f"Transaction with ID {transaction_id} not found")
            
        txn = txn_res.data[0]
        card_id = txn['card_id']
        amount = float(txn.get('amount', 0.0))
        txn_type = txn.get('transaction_type', 'debit')

        del_res = supabase.table("transactions").delete().eq("id", transaction_id).execute()

        card_res = supabase.table("cards").select("available_limit").eq("id", card_id).execute()
        if card_res.data:
            curr_limit = float(card_res.data[0]['available_limit'])
            updated_limit = curr_limit + amount if txn_type == 'debit' else curr_limit - amount
            supabase.table("cards").update({"available_limit": updated_limit}).eq("id", card_id).execute()

        return {"message": "Transaction deleted successfully", "id": transaction_id}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error deleting transaction {transaction_id}: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/reports/trigger-monthly-report", response_model=TriggerReportResponse)
def trigger_monthly_report(
    request: Optional[TriggerReportRequest] = None,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Manually triggers generation and email delivery of the monthly PDF report.
    """
    supabase = get_supabase_client()
    settings = get_settings()
    now = datetime.now(IST)

    target_month = (request.month if request and request.month else None) or now.month
    target_year = (request.year if request and request.year else None) or now.year
    recipient_email = (request.email if request and request.email else None) or settings.IMAP_EMAIL

    # Find user
    target_user_id = request.user_id if request and request.user_id else None
    fcm_token = None
    if not target_user_id:
        user_res = supabase.table("users").select("*").eq("device_id", device_id).execute()
        if user_res.data:
            target_user_id = user_res.data[0]["id"]
            fcm_token = user_res.data[0].get("fcm_token")
        else:
            all_users = supabase.table("users").select("*").limit(1).execute()
            if all_users.data:
                target_user_id = all_users.data[0]["id"]
                fcm_token = all_users.data[0].get("fcm_token")
            else:
                raise HTTPException(status_code=404, detail="No user found for report generation")
    else:
        user_res = supabase.table("users").select("*").eq("id", target_user_id).execute()
        fcm_token = user_res.data[0].get("fcm_token") if user_res.data else None

    try:
        pdf_bytes, filename = generate_monthly_user_report(target_user_id, target_month, target_year)
        month_label = datetime(target_year, target_month, 1, tzinfo=IST).strftime("%B %Y")

        email_sent = send_monthly_report_email(
            to_email=recipient_email,
            month_str=month_label,
            pdf_bytes=pdf_bytes,
            filename=filename
        )

        fcm_sent = send_fcm_notification(fcm_token, month_label) if fcm_token else False

        return TriggerReportResponse(
            user_id=target_user_id,
            month=target_month,
            year=target_year,
            email=recipient_email,
            email_sent=email_sent,
            fcm_sent=fcm_sent,
            filename=filename,
            message="Monthly report generated and processed successfully"
        )
    except Exception as e:
        logger.error(f"Error triggering monthly report: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to generate monthly report: {str(e)}")

@router.get("/reports/download-monthly-report")
def download_monthly_report(
    month: Optional[int] = None,
    year: Optional[int] = None,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Directly returns the generated monthly PDF report bytes for download/viewing.
    """
    supabase = get_supabase_client()
    now = datetime.now(IST)
    target_month = month or now.month
    target_year = year or now.year

    user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
    if user_res.data:
        target_user_id = user_res.data[0]["id"]
    else:
        all_users = supabase.table("users").select("id").limit(1).execute()
        if all_users.data:
            target_user_id = all_users.data[0]["id"]
        else:
            raise HTTPException(status_code=404, detail="User not found")

    pdf_bytes, filename = generate_monthly_user_report(target_user_id, target_month, target_year)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )

# ── Per-Category Monthly Budget System ─────────────────────────────────────────

MASTER_CATEGORIES = [
    "rent",
    "whey protein",
    "daily protein",
    "eggs",
    "sip",
    "stocks",
    "gym fees",
    "beverages",
    "outside food",
    "subscriptions",
    "groceries",
    "transportion",
    "medicine",
    "shopping",
    "uncategorized"
]

def normalize_category_name(cat: Optional[str]) -> str:
    if not cat:
        return "uncategorized"
    norm = cat.strip().lower()
    if norm in ("transportation", "transport"):
        return "transportion"
    return norm

# Fallback store when Supabase category_budgets table is not yet migrated
# Key: f"{user_id}:{year}:{month}:{category}" -> float
_fallback_category_budgets: dict = {}

def get_auth_user_id(token: dict, device_id: str, supabase) -> str:
    sub = token.get("sub") if isinstance(token, dict) else None
    if sub and sub != "dev-user-id":
        return sub
    user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
    if user_res.data:
        return user_res.data[0]["id"]
    return "553f4a9d-2502-4fa1-bef0-f6f867d116b2"

@router.get("/budgets/categories", response_model=CategoryBudgetsResponse)
def get_category_budgets(
    month: Optional[int] = None,
    year: Optional[int] = None,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Fetches user budget limits from category_budgets for the requested month/year.
    Aggregates debits and credits for each category in that month.
    Returns each category with:
    - budget_limit: configured budget (or 0.00 if unset)
    - spent: sum(debit) - sum(credit)
    - remaining: budget_limit - spent
    - percentage_used: (spent / budget_limit) * 100 (safely calculated)
    """
    supabase = get_supabase_client()
    now = datetime.now(IST)
    target_month = month or now.month
    target_year = year or now.year

    auth_user_id = get_auth_user_id(token, device_id, supabase)

    # 1. Fetch user's cards to filter transactions
    user_res = supabase.table("users").select("id").eq("device_id", device_id).execute()
    card_ids = []
    if user_res.data:
        u_id = user_res.data[0]["id"]
        cards_res = supabase.table("cards").select("id").eq("user_id", u_id).execute()
        if cards_res.data:
            card_ids = [c["id"] for c in cards_res.data]

    # 2. Fetch configured budget limits
    budget_limits_map: dict = {cat: 0.0 for cat in MASTER_CATEGORIES}
    try:
        budgets_res = supabase.table("category_budgets").select("category, budget_limit").eq("user_id", auth_user_id).eq("month", target_month).eq("year", target_year).execute()
        if budgets_res.data:
            for b in budgets_res.data:
                c_norm = normalize_category_name(b.get("category"))
                budget_limits_map[c_norm] = float(b.get("budget_limit", 0.0))
    except Exception as e:
        logger.warning(f"Could not read from Supabase category_budgets table ({e}). Checking fallback cache.")

    # Overlay with fallback store if unset
    for cat in MASTER_CATEGORIES:
        fb_key = f"{auth_user_id}:{target_year}:{target_month}:{cat}"
        if fb_key in _fallback_category_budgets and budget_limits_map[cat] == 0.0:
            budget_limits_map[cat] = _fallback_category_budgets[fb_key]

    # 3. Aggregate debits and credits for the target month
    start_dt = datetime(target_year, target_month, 1, 0, 0, 0, tzinfo=IST)
    if target_month == 12:
        end_dt = datetime(target_year + 1, 1, 1, 0, 0, 0, tzinfo=IST)
    else:
        end_dt = datetime(target_year, target_month + 1, 1, 0, 0, 0, tzinfo=IST)

    query = supabase.table("transactions").select("amount, category, transaction_type, is_refund").gte(
        "transacted_at", start_dt.isoformat()
    ).lt(
        "transacted_at", end_dt.isoformat()
    )

    if card_ids:
        query = query.in_("card_id", card_ids)

    txns_res = query.execute()
    txns = txns_res.data or []

    category_debits: dict = {cat: 0.0 for cat in MASTER_CATEGORIES}
    category_credits: dict = {cat: 0.0 for cat in MASTER_CATEGORIES}

    for t in txns:
        amt = float(t.get("amount", 0.0))
        t_type = (t.get("transaction_type") or "debit").lower()
        is_refund = t.get("is_refund", False) or t_type == "credit"
        cat_norm = normalize_category_name(t.get("category"))
        if cat_norm not in category_debits:
            cat_norm = "uncategorized"

        if is_refund:
            category_credits[cat_norm] += amt
        else:
            category_debits[cat_norm] += amt

    # 4. Build category status items
    items: List[CategoryBudgetStatusItem] = []
    for cat in MASTER_CATEGORIES:
        limit = budget_limits_map.get(cat, 0.0)
        spent = category_debits[cat] - category_credits[cat]
        remaining = limit - spent
        if limit > 0:
            pct = round((spent / limit) * 100.0, 2)
            pct = max(0.0, pct)
        else:
            pct = 100.0 if spent > 0 else 0.0

        items.append(
            CategoryBudgetStatusItem(
                category=cat,
                budget_limit=round(limit, 2),
                spent=round(spent, 2),
                remaining=round(remaining, 2),
                percentage_used=pct
            )
        )

    total_budget = round(sum(c.budget_limit for c in items), 2)
    total_spent = round(sum(c.spent for c in items), 2)
    total_remaining = round(total_budget - total_spent, 2)

    return CategoryBudgetsResponse(
        month=target_month,
        year=target_year,
        categories=items,
        total_budget=total_budget,
        total_spent=total_spent,
        total_remaining=total_remaining
    )

@router.post("/budgets/categories", response_model=SetCategoryBudgetsResponse)
def set_category_budgets(
    request: SetCategoryBudgetsRequest,
    device_id: str = Depends(get_device_id),
    token: dict = Depends(verify_token)
):
    """
    Upserts the list of category budgets into category_budgets using user_id, category, month, and year.
    """
    supabase = get_supabase_client()
    auth_user_id = get_auth_user_id(token, device_id, supabase)
    now_iso = datetime.now(timezone.utc).isoformat()

    records = []
    for item in request.budgets:
        cat_norm = normalize_category_name(item.category)
        limit_val = float(item.budget_limit)
        records.append({
            "user_id": auth_user_id,
            "category": cat_norm,
            "budget_limit": limit_val,
            "month": request.month,
            "year": request.year,
            "updated_at": now_iso
        })
        # Always store in memory fallback cache
        _fallback_category_budgets[f"{auth_user_id}:{request.year}:{request.month}:{cat_norm}"] = limit_val

    # Attempt Supabase upsert
    try:
        supabase.table("category_budgets").upsert(
            records,
            on_conflict="user_id,category,month,year"
        ).execute()
    except Exception as e:
        logger.warning(f"Supabase upsert to category_budgets failed: {e}. Saved in fallback store.")

    return SetCategoryBudgetsResponse(
        message=f"Successfully updated {len(request.budgets)} category budgets",
        updated_count=len(request.budgets),
        month=request.month,
        year=request.year,
        budgets=request.budgets
    )
