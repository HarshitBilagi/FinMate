-- ============================================================================
-- Foundational Finance Friend — Supabase PostgreSQL Schema
-- ============================================================================
-- Design Principles:
--   1. UUID v4 primary keys for all tables (Supabase default)
--   2. UPI Ref ID as UNIQUE constraint on transactions (deduplication key)
--   3. No LLM categorization — category defaults to 'uncategorized'
--   4. Refund/Reversed handling via is_refund flag + refund_of_upi_ref
--   5. Static billing cycle date per card
--   6. FCM token stored per user for push notifications
-- ============================================================================

-- Enable UUID extension (Supabase has this by default)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── USERS ──────────────────────────────────────────────────────────────────
-- No password field: auth is local biometric only.
-- device_id is the unique hardware identifier from the Flutter app.
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id   TEXT NOT NULL UNIQUE,
    fcm_token   TEXT,              -- Firebase Cloud Messaging token
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── CARDS ──────────────────────────────────────────────────────────────────
-- Represents a credit card linked to a user.
-- card_masked stores the last 6 digits (e.g., "XX4326") as seen in ICICI alerts.
-- billing_cycle_day: static day of month (e.g., 15 means cycle resets on 15th).
CREATE TABLE cards (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    card_masked         TEXT NOT NULL,               -- Last 6 digits: "XX4326"
    card_type           TEXT NOT NULL DEFAULT 'credit_card',  -- 'credit_card' | 'debit_account'
    total_limit         NUMERIC(12, 2),              -- Total credit limit (INR)
    available_limit     NUMERIC(12, 2),              -- Available credit limit (INR)
    billing_cycle_day   INTEGER NOT NULL DEFAULT 1,  -- Day of month (1-28)
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, card_masked)
);

-- ─── TRANSACTIONS ───────────────────────────────────────────────────────────
-- Core transaction table.
-- upi_ref_id is the deduplication key (UNIQUE constraint).
-- category defaults to 'uncategorized'; user sets via push notification action.
-- is_refund: TRUE if the email contained "Refund" or "Reversed" keywords.
-- refund_of_upi_ref: links to the original transaction's UPI ref if this is a refund.
CREATE TABLE transactions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id             UUID NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    upi_ref_id          TEXT NOT NULL UNIQUE,         -- Deduplication: UPI Ref ID
    amount              NUMERIC(12, 2) NOT NULL,
    merchant            TEXT,                          -- Parsed from email "Info" field
    category            TEXT NOT NULL DEFAULT 'uncategorized',
    transaction_type    TEXT NOT NULL DEFAULT 'debit', -- 'debit' | 'credit' | 'refund'
    is_refund           BOOLEAN NOT NULL DEFAULT FALSE,
    refund_of_upi_ref   TEXT REFERENCES transactions(upi_ref_id),
    source              TEXT NOT NULL DEFAULT 'email', -- 'email' | 'sms' | 'manual'
    raw_message         TEXT,                          -- Original email/SMS body for audit
    transacted_at       TIMESTAMPTZ NOT NULL,          -- When the txn actually happened
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── BILLING CYCLES ─────────────────────────────────────────────────────────
-- Tracks spending per billing cycle per card.
-- cycle_start and cycle_end are computed from cards.billing_cycle_day.
CREATE TABLE billing_cycles (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    card_id         UUID NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
    cycle_start     DATE NOT NULL,
    cycle_end       DATE NOT NULL,
    total_spent     NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_refunded  NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    net_spent       NUMERIC(12, 2) GENERATED ALWAYS AS (total_spent - total_refunded) STORED,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (card_id, cycle_start)
);

-- ─── INDEXES ────────────────────────────────────────────────────────────────
CREATE INDEX idx_transactions_card_id ON transactions(card_id);
CREATE INDEX idx_transactions_transacted_at ON transactions(transacted_at);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE INDEX idx_billing_cycles_card_id ON billing_cycles(card_id);
CREATE INDEX idx_cards_user_id ON cards(user_id);

-- ─── ROW LEVEL SECURITY (Supabase) ─────────────────────────────────────────
-- Enable RLS on all tables (policies to be configured in Supabase dashboard)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_cycles ENABLE ROW LEVEL SECURITY;

-- ─── UPDATED_AT TRIGGER ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_cards_updated_at
    BEFORE UPDATE ON cards
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
