"""
Automated End-of-Month PDF Reporting and Notification System for FinMate.
Decoupled module responsible for:
1. Generating monthly executive PDF reports via ReportLab.
2. Emailing generated PDF reports as attachments via SMTP.
3. Dispatching push notifications via Firebase Cloud Messaging (FCM).
"""

import io
import os
import smtplib
import logging
from datetime import datetime, timezone, timedelta
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.application import MIMEApplication
from typing import Dict, List, Optional, Tuple

from reportlab.lib.pagesizes import letter, A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether, HRFlowable
)

from app.core.config import get_settings
from app.db.supabase import get_supabase_client

logger = logging.getLogger(__name__)

IST = timezone(timedelta(hours=5, minutes=30))

# Master Category list matching FinMate standards
CATEGORIES_ORDER = [
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

CATEGORY_LABELS = {
    "rent": "Rent",
    "whey protein": "Whey Protein",
    "daily protein": "Daily Protein",
    "eggs": "Eggs",
    "sip": "SIP",
    "stocks": "Stocks",
    "gym fees": "Gym Fees",
    "beverages": "Beverages",
    "outside food": "Outside Food",
    "subscriptions": "Subscriptions",
    "groceries": "Groceries",
    "transportion": "Transportation",
    "transportation": "Transportation",
    "transport": "Transportation",
    "medicine": "Medicine",
    "shopping": "Shopping",
    "uncategorized": "Uncategorized",
}


def _format_currency(amount: float) -> str:
    """Format float amount into INR currency string."""
    return f"Rs. {amount:,.2f}"


def _format_ist_datetime(dt_str: str) -> str:
    """Parse ISO timestamp and format in Indian Standard Time (IST)."""
    try:
        dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=IST)
        else:
            dt = dt.astimezone(IST)
        return dt.strftime("%d %b, %I:%M %p")
    except Exception:
        return dt_str[:16] if dt_str else ""


def generate_monthly_user_report(user_id: str, month: int, year: int) -> Tuple[bytes, str]:
    """
    Generates a monthly executive PDF expense and budget report for a given user.
    Returns (pdf_bytes, filename).
    """
    supabase = get_supabase_client()
    settings = get_settings()

    # 1. Fetch user's cards to determine monthly budget
    cards_res = supabase.table("cards").select("*").eq("user_id", user_id).execute()
    monthly_budget = 90000.00
    card_masked = "XX4326"
    if cards_res.data:
        card = cards_res.data[0]
        monthly_budget = float(card.get("total_limit") or 90000.00)
        card_masked = card.get("card_masked") or "XX4326"

    # 2. Fetch transactions for the user for this month
    # Get all cards for user
    card_ids = [c["id"] for c in cards_res.data] if cards_res.data else []
    
    # Define month date bounds in UTC/IST
    start_dt = datetime(year, month, 1, 0, 0, 0, tzinfo=IST)
    if month == 12:
        end_dt = datetime(year + 1, 1, 1, 0, 0, 0, tzinfo=IST)
    else:
        end_dt = datetime(year, month + 1, 1, 0, 0, 0, tzinfo=IST)

    query = supabase.table("transactions").select("*").gte(
        "transacted_at", start_dt.isoformat()
    ).lt(
        "transacted_at", end_dt.isoformat()
    ).order("transacted_at", desc=False)

    if card_ids:
        query = query.in_("card_id", card_ids)

    txns_res = query.execute()
    transactions = txns_res.data or []

    # 3. Calculate Math & Metrics
    total_debits = 0.0
    total_credits = 0.0
    category_debits: Dict[str, float] = {k: 0.0 for k in CATEGORIES_ORDER}
    category_credits: Dict[str, float] = {k: 0.0 for k in CATEGORIES_ORDER}

    for txn in transactions:
        amt = float(txn.get("amount", 0.0))
        txn_type = (txn.get("transaction_type") or "debit").lower()
        is_refund = txn.get("is_refund", False) or txn_type == "credit"
        raw_cat = (txn.get("category") or "uncategorized").lower().strip()
        cat = "transportion" if raw_cat in ("transportation", "transport") else raw_cat
        cat_key = cat if cat in category_debits else "uncategorized"

        if is_refund:
            total_credits += amt
            category_credits[cat_key] += amt
        else:
            total_debits += amt
            category_debits[cat_key] += amt

    total_outflow = total_debits - total_credits
    remaining_budget = monthly_budget - total_outflow

    # 4. Build ReportLab PDF
    month_name = start_dt.strftime("%B %Y")
    filename = f"FinMate_Expense_Report_{start_dt.strftime('%B_%Y')}.pdf"
    generated_on = datetime.now(IST).strftime("%d %b %Y, %I:%M %p IST")

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=36,
        rightMargin=36,
        topMargin=36,
        bottomMargin=36
    )

    styles = getSampleStyleSheet()
    
    # Custom Palette Colors
    primary_teal = colors.HexColor("#0D9488")
    dark_teal = colors.HexColor("#115E59")
    text_dark = colors.HexColor("#0F172A")
    text_muted = colors.HexColor("#64748B")
    border_color = colors.HexColor("#E2E8F0")
    header_bg = colors.HexColor("#F8FAFC")
    positive_green = colors.HexColor("#059669")
    negative_red = colors.HexColor("#E11D48")

    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontName='Helvetica-Bold',
        fontSize=20,
        leading=24,
        textColor=primary_teal
    )
    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=11,
        leading=15,
        textColor=text_muted
    )
    right_header_title = ParagraphStyle(
        'RightHeaderTitle',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=14,
        leading=18,
        alignment=2, # Right
        textColor=text_dark
    )
    right_header_sub = ParagraphStyle(
        'RightHeaderSub',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=9,
        leading=12,
        alignment=2, # Right
        textColor=text_muted
    )
    section_title = ParagraphStyle(
        'SectionTitle',
        parent=styles['Heading2'],
        fontName='Helvetica-Bold',
        fontSize=13,
        leading=16,
        textColor=text_dark,
        spaceAfter=6
    )
    cell_style = ParagraphStyle(
        'CellText',
        parent=styles['Normal'],
        fontName='Helvetica',
        fontSize=8.5,
        leading=11,
        textColor=text_dark
    )
    cell_style_bold = ParagraphStyle(
        'CellTextBold',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=8.5,
        leading=11,
        textColor=text_dark
    )
    cell_header = ParagraphStyle(
        'CellHeader',
        parent=styles['Normal'],
        fontName='Helvetica-Bold',
        fontSize=9,
        leading=12,
        textColor=text_dark
    )

    story = []

    # ── Header ─────────────────────────────────────────────────────────────
    header_table_data = [
        [
            Paragraph("<b>FinMate</b>", title_style),
            Paragraph(f"<b>{month_name}</b>", right_header_title)
        ],
        [
            Paragraph("Monthly Expense & Budget Report", subtitle_style),
            Paragraph(f"Generated: {generated_on}", right_header_sub)
        ]
    ]
    header_table = Table(header_table_data, colWidths=[280, 240])
    header_table.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 2),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
    ]))
    story.append(header_table)
    story.append(Spacer(1, 10))
    story.append(HRFlowable(width="100%", thickness=1, color=border_color, spaceAfter=14))

    # ── KPI Summary Cards ──────────────────────────────────────────────────
    kpi_data = [
        [
            Paragraph("<b>Monthly Budget</b>", ParagraphStyle('KpiTitle', fontName='Helvetica', fontSize=9, textColor=text_muted)),
            Paragraph("<b>Total Outflow</b>", ParagraphStyle('KpiTitle', fontName='Helvetica', fontSize=9, textColor=text_muted)),
            Paragraph("<b>Net Remaining</b>", ParagraphStyle('KpiTitle', fontName='Helvetica', fontSize=9, textColor=text_muted))
        ],
        [
            Paragraph(f"<b>{_format_currency(monthly_budget)}</b>", ParagraphStyle('KpiVal1', fontName='Helvetica-Bold', fontSize=13, textColor=dark_teal)),
            Paragraph(f"<b>{_format_currency(total_outflow)}</b>", ParagraphStyle('KpiVal2', fontName='Helvetica-Bold', fontSize=13, textColor=negative_red)),
            Paragraph(f"<b>{_format_currency(remaining_budget)}</b>", ParagraphStyle('KpiVal3', fontName='Helvetica-Bold', fontSize=13, textColor=positive_green if remaining_budget >= 0 else negative_red))
        ]
    ]
    kpi_table = Table(kpi_data, colWidths=[173, 173, 174])
    kpi_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), header_bg),
        ('BOX', (0, 0), (-1, -1), 1, border_color),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, border_color),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
    ]))
    story.append(kpi_table)
    story.append(Spacer(1, 18))

    # ── Category Summary Table ─────────────────────────────────────────────
    story.append(Paragraph("Category Summary", section_title))
    
    cat_table_rows = [
        [
            Paragraph("Category", cell_header),
            Paragraph("Debits", cell_header),
            Paragraph("Credits", cell_header),
            Paragraph("Net Spent", cell_header),
            Paragraph("% Budget", cell_header)
        ]
    ]

    active_cats = [
        c for c in CATEGORIES_ORDER 
        if (category_debits[c] > 0 or category_credits[c] > 0)
    ]

    if not active_cats:
        cat_table_rows.append([
            Paragraph("No expenses recorded for this period", cell_style),
            Paragraph("Rs. 0.00", cell_style),
            Paragraph("Rs. 0.00", cell_style),
            Paragraph("Rs. 0.00", cell_style),
            Paragraph("0.0%", cell_style),
        ])
    else:
        for c in active_cats:
            deb = category_debits[c]
            cred = category_credits[c]
            net = deb - cred
            pct = f"{(net / monthly_budget * 100):.1f}%" if monthly_budget > 0 else "0.0%"
            cat_label = CATEGORY_LABELS.get(c, c.title())
            
            cat_table_rows.append([
                Paragraph(cat_label, cell_style),
                Paragraph(_format_currency(deb), cell_style),
                Paragraph(_format_currency(cred), cell_style),
                Paragraph(f"<b>{_format_currency(net)}</b>", cell_style_bold),
                Paragraph(pct, cell_style),
            ])

    # Total Outflow Row
    pct_total = f"{(total_outflow / monthly_budget * 100):.1f}%" if monthly_budget > 0 else "0.0%"
    cat_table_rows.append([
        Paragraph("<b>Total Outflow</b>", cell_header),
        Paragraph(f"<b>{_format_currency(total_debits)}</b>", cell_header),
        Paragraph(f"<b>{_format_currency(total_credits)}</b>", cell_header),
        Paragraph(f"<b>{_format_currency(total_outflow)}</b>", cell_header),
        Paragraph(f"<b>{pct_total}</b>", cell_header),
    ])

    cat_table = Table(cat_table_rows, colWidths=[160, 90, 90, 100, 80])
    cat_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), header_bg),
        ('BACKGROUND', (0, -1), (-1, -1), header_bg),
        ('GRID', (0, 0), (-1, -1), 0.5, border_color),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('ALIGN', (1, 0), (-1, -1), 'RIGHT'),
    ]))
    story.append(cat_table)
    story.append(Spacer(1, 20))

    # ── Itemized Transactions Ledger ───────────────────────────────────────
    story.append(Paragraph(f"Itemized Transaction Ledger ({len(transactions)} records)", section_title))
    
    ledger_rows = [
        [
            Paragraph("Date & Time", cell_header),
            Paragraph("Merchant / Description", cell_header),
            Paragraph("Category", cell_header),
            Paragraph("Type", cell_header),
            Paragraph("Amount", cell_header)
        ]
    ]

    if not transactions:
        ledger_rows.append([
            Paragraph("No transactions recorded", cell_style),
            Paragraph("-", cell_style),
            Paragraph("-", cell_style),
            Paragraph("-", cell_style),
            Paragraph("Rs. 0.00", cell_style),
        ])
    else:
        for txn in transactions:
            txn_amt = float(txn.get("amount", 0.0))
            txn_type = (txn.get("transaction_type") or "debit").upper()
            is_credit = txn.get("is_refund", False) or txn_type == "CREDIT"
            sign = "+" if is_credit else "-"
            amt_str = f"{sign}{_format_currency(txn_amt)}"
            amt_color = positive_green if is_credit else negative_red
            
            raw_cat = (txn.get("category") or "uncategorized").lower().strip()
            cat_label = CATEGORY_LABELS.get(raw_cat, raw_cat.title())
            date_label = _format_ist_datetime(txn.get("transacted_at") or "")
            merchant = txn.get("merchant") or "Unknown"

            amt_style = ParagraphStyle(
                'LedgerAmt',
                parent=styles['Normal'],
                fontName='Helvetica-Bold',
                fontSize=8.5,
                leading=11,
                textColor=amt_color,
                alignment=2
            )

            ledger_rows.append([
                Paragraph(date_label, cell_style),
                Paragraph(merchant, cell_style),
                Paragraph(cat_label, cell_style),
                Paragraph(txn_type, cell_style),
                Paragraph(amt_str, amt_style),
            ])

    ledger_table = Table(ledger_rows, colWidths=[105, 175, 100, 50, 90])
    ledger_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), header_bg),
        ('GRID', (0, 0), (-1, -1), 0.5, border_color),
        ('TOPPADDING', (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('RIGHTPADDING', (0, 0), (-1, -1), 6),
        ('ALIGN', (4, 0), (4, -1), 'RIGHT'),
    ]))
    story.append(ledger_table)

    doc.build(story)
    pdf_bytes = buffer.getvalue()
    buffer.close()

    return pdf_bytes, filename


def send_monthly_report_email(
    to_email: str,
    month_str: str,
    pdf_bytes: bytes,
    filename: str
) -> bool:
    """
    Sends the monthly PDF report as an email attachment via SMTP (Gmail).
    """
    settings = get_settings()
    sender_email = settings.IMAP_EMAIL
    sender_password = settings.IMAP_PASSWORD

    if not sender_email or not sender_password:
        logger.warning("SMTP email or password is not configured in Settings. Skipping email dispatch.")
        return False

    try:
        msg = MIMEMultipart()
        msg['From'] = f"FinMate <{sender_email}>"
        msg['To'] = to_email
        msg['Subject'] = f"FinMate: Your {month_str} Monthly Expense & Budget Report"

        body_html = f"""
        <html>
        <body style="font-family: Arial, sans-serif; color: #1e293b; line-height: 1.6;">
            <div style="max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e2e8f0; borderRadius: 8px;">
                <h2 style="color: #0d9488; margin-top: 0;">FinMate Expense Report</h2>
                <p>Hello,</p>
                <p>Your executive monthly expense and budget report for <strong>{month_str}</strong> has been generated and is attached to this email.</p>
                <p>This report includes:</p>
                <ul>
                    <li>Executive KPI Summary (Total Budget, Outflow, and Remaining Limits)</li>
                    <li>Granular Category Breakdown & Percentage of Budget</li>
                    <li>Full Itemized Transaction Ledger</li>
                </ul>
                <p style="margin-top: 24px; font-size: 12px; color: #64748b;">
                    Sent automatically by FinMate Backend Reporting System.
                </p>
            </div>
        </body>
        </html>
        """
        msg.attach(MIMEText(body_html, 'html'))

        # Attach PDF
        part = MIMEApplication(pdf_bytes, Name=filename)
        part['Content-Disposition'] = f'attachment; filename="{filename}"'
        msg.attach(part)

        # Connect to SMTP server
        logger.info(f"Connecting to SMTP server {settings.SMTP_HOST}:{settings.SMTP_PORT} to send report to {to_email}...")
        server = smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=20)
        server.starttls()
        server.login(sender_email, sender_password)
        server.send_message(msg)
        server.quit()

        logger.info(f"Successfully sent monthly report email to {to_email}")
        return True
    except Exception as e:
        logger.error(f"Failed to send email to {to_email}: {e}", exc_info=True)
        return False


def send_fcm_notification(fcm_token: Optional[str], month_str: str) -> bool:
    """
    Dispatches a push notification via Firebase Cloud Messaging (FCM).
    """
    if not fcm_token:
        logger.info("No FCM token provided for user. Skipping push notification.")
        return False

    settings = get_settings()
    try:
        import firebase_admin
        from firebase_admin import credentials, messaging

        if not firebase_admin._apps:
            cred_path = settings.FIREBASE_CREDENTIALS_PATH
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                logger.info(f"Initialized Firebase Admin with credentials from {cred_path}")
            else:
                logger.warning(f"Firebase credentials not found at {cred_path}. Skipping FCM push notification.")
                return False

        message = messaging.Message(
            notification=messaging.Notification(
                title="FinMate Monthly Report",
                body=f"Your {month_str} Expense Report is ready in your email!"
            ),
            data={
                "type": "monthly_report",
                "month": month_str,
            },
            token=fcm_token,
        )

        response = messaging.send(message)
        logger.info(f"Successfully sent FCM push notification. Response: {response}")
        return True
    except Exception as e:
        logger.warning(f"Failed to send FCM push notification: {e}")
        return False


def run_end_of_month_reporting_job():
    """
    Scheduled job: Iterates through users in Supabase, generates monthly reports,
    emails them as attachments, and triggers FCM push notifications.
    """
    logger.info("Starting automated End-of-Month Reporting Job...")
    supabase = get_supabase_client()
    settings = get_settings()

    try:
        users_res = supabase.table("users").select("*").execute()
        users = users_res.data or []
        if not users:
            logger.info("No users found in database for report generation.")
            return

        # Determine target month & year (current month)
        now = datetime.now(IST)
        target_month = now.month
        target_year = now.year
        month_label = now.strftime("%B %Y")

        recipient_email = settings.IMAP_EMAIL

        for user in users:
            user_id = user["id"]
            fcm_token = user.get("fcm_token")
            logger.info(f"Generating monthly report for user {user_id} ({month_label})...")

            try:
                pdf_bytes, filename = generate_monthly_user_report(user_id, target_month, target_year)
                
                # Send email
                email_sent = send_monthly_report_email(
                    to_email=recipient_email,
                    month_str=month_label,
                    pdf_bytes=pdf_bytes,
                    filename=filename
                )

                # Send FCM push notification
                if fcm_token:
                    send_fcm_notification(fcm_token, month_label)

                logger.info(f"Report automation completed for user {user_id}. Email sent: {email_sent}")
            except Exception as user_err:
                logger.error(f"Error processing report for user {user_id}: {user_err}", exc_info=True)

    except Exception as e:
        logger.error(f"End-of-Month Reporting Job encountered error: {e}", exc_info=True)
