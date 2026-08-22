-- Migration: Add site checklist and status columns to customers and tasks tables

ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS site_checklist JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS site_status TEXT DEFAULT 'NOT READY';
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS checklist_updated_by TEXT;
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS checklist_updated_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS site_checklist JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS site_status TEXT DEFAULT 'NOT READY';
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS checklist_updated_by TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS checklist_updated_at TIMESTAMP WITH TIME ZONE;
