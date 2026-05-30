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
    IMAP_EMAIL: str = ""        # Gmail address
    IMAP_PASSWORD: str = ""     # Gmail App Password (NOT account password)

    # ── Supabase ──────────────────────────────────────────────────────────
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""      # Service role key (backend only)

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
