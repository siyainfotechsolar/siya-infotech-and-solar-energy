-- Migration: Add incomplete task details, installation details, serials, and geo-tag columns to tasks table

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS incomplete_reason TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS incomplete_details TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS incomplete_marked_by TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS incomplete_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS system_capacity TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS inverter_serial TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS meter_number TEXT;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS generation_reading TEXT;

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS panel_serials JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS electrical_work_status JSONB DEFAULT '{}'::jsonb;

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS geo_lat DOUBLE PRECISION;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS geo_long DOUBLE PRECISION;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS geo_timestamp TEXT;
