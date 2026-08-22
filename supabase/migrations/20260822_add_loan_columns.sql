ALTER TABLE public.customers
ADD COLUMN IF NOT EXISTS bank_name TEXT,
ADD COLUMN IF NOT EXISTS loan_amount NUMERIC,
ADD COLUMN IF NOT EXISTS loan_stage TEXT DEFAULT 'NOT STARTED' CHECK (loan_stage IN ('NOT STARTED', 'OFFICE FILE READY', 'PRINTED', 'SENT TO BANK', '1ST STAGE', '2ND STAGE', 'APPROVED', 'REJECTED')),
ADD COLUMN IF NOT EXISTS loan_issue_status TEXT DEFAULT 'NO ISSUE' CHECK (loan_issue_status IN ('NO ISSUE', 'OPEN PROBLEM', 'RESOLVED')),
ADD COLUMN IF NOT EXISTS loan_problem_type TEXT CHECK (loan_problem_type IN ('Document Missing', 'Customer Signature Pending', 'Bank Query', 'Eligibility Issue', 'Income Document Problem', 'Name / Document Mismatch', 'Technical Problem', 'Other')),
ADD COLUMN IF NOT EXISTS loan_problem_remarks TEXT,
ADD COLUMN IF NOT EXISTS loan_resolution_remarks TEXT,
ADD COLUMN IF NOT EXISTS loan_updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now());
