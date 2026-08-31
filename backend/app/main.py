from fastapi import FastAPI
from contextlib import asynccontextmanager
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
import logging

from app.services.email_parser import fetch_icici_emails
from app.core.config import get_settings
from app.core.automated_reporter import run_end_of_month_reporting_job

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Scheduler for background tasks
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
    
    # 1. IMAP Email polling
    scheduler.add_job(
        check_emails,
        "interval",
        minutes=settings.EMAIL_CHECK_INTERVAL_MINUTES,
        id="email_check_interval",
        replace_existing=True,
    )

    # 2. Automated End-of-Month PDF Report Generation at 22:00 on the last day of each month
    scheduler.add_job(
        run_end_of_month_reporting_job,
        CronTrigger(day="last", hour=22, minute=0, timezone="Asia/Kolkata"),
        id="eom_report_automation",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        f"APScheduler started (Email interval: {settings.EMAIL_CHECK_INTERVAL_MINUTES}m, EOM Cron: 22:00 on last day of month)"
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
