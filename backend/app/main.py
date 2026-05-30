from fastapi import FastAPI
from contextlib import asynccontextmanager
from apscheduler.schedulers.asyncio import AsyncIOScheduler
import logging

from app.services.email_parser import fetch_icici_emails
from app.core.config import get_settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Scheduler for background IMAP tasks
scheduler = AsyncIOScheduler()


def check_emails():
    """
    Scheduled job: Fetch and parse ICICI transaction emails via IMAP.
    Parsed transactions are logged and ready for Supabase insertion.
    """
    logger.info("Checking emails for transactions...")
    try:
        transactions = fetch_icici_emails()
        for txn in transactions:
            logger.info(
                f"[{'REFUND' if txn.is_refund else 'TXN'}] "
                f"₹{txn.amount} | {txn.merchant} | "
                f"UPI:{txn.upi_ref_id} | {txn.card_masked}"
            )
            # TODO: Insert into Supabase (deduplicated by UPI ref UNIQUE constraint)
            # TODO: Send FCM push notification for categorization
        logger.info(f"Processed {len(transactions)} transaction(s)")
    except Exception as e:
        logger.error(f"Email check failed: {e}", exc_info=True)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Start the scheduler
    settings = get_settings()
    scheduler.add_job(
        check_emails,
        "interval",
        minutes=settings.EMAIL_CHECK_INTERVAL_MINUTES,
    )
    scheduler.start()
    logger.info(
        f"APScheduler started (interval: {settings.EMAIL_CHECK_INTERVAL_MINUTES}m)"
    )
    yield
    # Shutdown: Stop the scheduler
    scheduler.shutdown()
    logger.info("APScheduler stopped")


from app.api.endpoints import router as api_router

app = FastAPI(title="Foundational Finance Friend API", lifespan=lifespan)

app.include_router(api_router)


@app.get("/")
def read_root():
    return {"message": "Welcome to Foundational Finance Friend API"}


@app.get("/health")
def health_check():
    return {"status": "healthy", "scheduler_running": scheduler.running}
