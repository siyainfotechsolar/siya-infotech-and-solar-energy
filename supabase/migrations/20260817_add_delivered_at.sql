-- Add delivered_at timestamp column to material_dispatches table
ALTER TABLE public.material_dispatches ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE;
