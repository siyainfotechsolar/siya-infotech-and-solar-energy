-- Migration to add lead_id, address, remarks, follow_up_date, notes, created_by to leads table
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS lead_id TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS remarks TEXT,
  ADD COLUMN IF NOT EXISTS follow_up_date DATE,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES public.staff(id);

-- Update leads_status_check constraint to include new, follow_up, qualified, converted, lost, pending, archived
ALTER TABLE public.leads DROP CONSTRAINT IF EXISTS leads_status_check;

ALTER TABLE public.leads ADD CONSTRAINT leads_status_check 
  CHECK (status IN ('new', 'pending', 'follow_up', 'qualified', 'converted', 'lost', 'archived'));
