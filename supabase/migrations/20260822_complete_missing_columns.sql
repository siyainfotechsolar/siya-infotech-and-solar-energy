-- ============================================================
-- MASTER MIGRATION: Add all missing columns for Loan, Priority, & Leads
-- Run this in Supabase Dashboard -> SQL Editor -> Run
-- ============================================================

-- 1. LOAN COLUMNS (for customers table)
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS bank_name TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_amount NUMERIC;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_stage TEXT DEFAULT 'NOT STARTED';
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_issue_status TEXT DEFAULT 'NO ISSUE';
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_problem_type TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_problem_remarks TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_reference_number TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_application_date DATE;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_resolution_remarks TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS loan_required BOOLEAN DEFAULT false;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS payment_type VARCHAR DEFAULT 'CASH';

-- 2. PRIORITY & FOLLOW-UP COLUMNS (for customers & leads)
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS last_meaningful_update TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS manual_priority TEXT DEFAULT 'NORMAL';
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS next_followup_date DATE;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS followup_note TEXT;

ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS last_meaningful_update TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());
ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS payment_type VARCHAR DEFAULT 'CASH';

-- 3. RELOAD POSTGREST SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
