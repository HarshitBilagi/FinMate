import sys
import os

sys.path.insert(0, os.path.abspath("backend"))

from app.db.supabase import get_supabase_client
from app.core.automated_reporter import generate_monthly_user_report, _format_currency, CATEGORIES_ORDER

supabase = get_supabase_client()
users = supabase.table("users").select("id").execute().data
print(f"Found {len(users)} users in database.")

if users:
    user_id = users[0]["id"]
    print(f"Generating test monthly report for user: {user_id}...")
    pdf_bytes, filename = generate_monthly_user_report(user_id, month=8, year=2026)
    print(f"Generated PDF successfully! Size: {len(pdf_bytes)} bytes, Filename: {filename}")
    
    # Save a copy to scratch for verification
    out_path = os.path.join("scratch", filename)
    os.makedirs("scratch", exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(pdf_bytes)
    print(f"Saved test PDF to {out_path}")
