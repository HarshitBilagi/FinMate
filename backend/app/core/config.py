"""
Core configuration module.
Loads environment variables for IMAP, Supabase, and Firebase credentials.
"""

from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    """Application settings loaded from environment variables or .env file."""

    # ── IMAP (Gmail) ──────────────────────────────────────────────────────
    IMAP_HOST: str = "imap.gmail.com"
    IMAP_PORT: int = 993
    IMAP_EMAIL: str = "harshabilagihb@gmail.com"        # Gmail address
    IMAP_PASSWORD: str = ""     # Gmail App Password (NOT account password)

    # ── Supabase & JWT Auth ───────────────────────────────────────────────
    SUPABASE_URL: str = "https://ydjcljiouvlwplcmdovt.supabase.co"
    SUPABASE_KEY: str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkamNsamlvdXZsd3BsY21kb3Z0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODgxNjk2OSwiZXhwIjoyMDk0MzkyOTY5fQ.2oOyKxY9aI7YptE8V3DU8ahX2B3czneoYF3lVbj_ek0"      # Service role key (backend DB operations)
    SUPABASE_JWT_SECRET: str = "c4f7040d-cf0a-4c75-89ea-03b5b84e3c74" # Used by FastAPI to decode & verify incoming JWTs

    # ── Firebase (FCM) ────────────────────────────────────────────────────
    FIREBASE_CREDENTIALS_PATH: str = "firebase_service_account.json"

    # ── Polling ───────────────────────────────────────────────────────────
    EMAIL_CHECK_INTERVAL_MINUTES: int = 15

    # ── ICICI Search Filter ──────────────────────────────────────────────
    IMAP_SEARCH_FROM: str = "alerts@icicibank.com"
    IMAP_SEARCH_SUBJECT: str = "transaction"

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "case_sensitive": True,
    }


@lru_cache()
def get_settings() -> Settings:
    """Cached settings singleton."""
    return Settings()