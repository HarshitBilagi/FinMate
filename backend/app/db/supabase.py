from supabase import create_client, Client
from app.core.config import get_settings
import logging

logger = logging.getLogger(__name__)

def get_supabase_client() -> Client:
    """
    Creates and returns a Supabase client using settings from the environment.
    Note: If credentials are empty (e.g. during local dev without setup), this might fail.
    """
    settings = get_settings()
    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        logger.warning("Supabase URL or Key is not configured. Supabase client will not work properly.")
    
    # Initialize the client. For a production app, you might want to reuse a single instance
    return create_client(
        settings.SUPABASE_URL or "https://placeholder.supabase.co", 
        settings.SUPABASE_KEY or "placeholder-key"
    )
