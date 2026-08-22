ALTER TABLE public.customers
ADD COLUMN IF NOT EXISTS manual_priority TEXT DEFAULT 'NORMAL' CHECK (manual_priority IN ('NORMAL', 'MEDIUM', 'HIGH')),
ADD COLUMN IF NOT EXISTS last_meaningful_update TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
ADD COLUMN IF NOT EXISTS next_followup_date DATE,
ADD COLUMN IF NOT EXISTS followup_note TEXT;

ALTER TABLE public.leads
ADD COLUMN IF NOT EXISTS manual_priority TEXT DEFAULT 'NORMAL' CHECK (manual_priority IN ('NORMAL', 'MEDIUM', 'HIGH')),
ADD COLUMN IF NOT EXISTS last_meaningful_update TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()),
ADD COLUMN IF NOT EXISTS next_followup_date DATE,
ADD COLUMN IF NOT EXISTS followup_note TEXT;
