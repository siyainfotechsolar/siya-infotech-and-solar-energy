-- Ensure activity_log table exists and has proper RLS policies
CREATE TABLE IF NOT EXISTS public.activity_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    action TEXT NOT NULL,
    description TEXT NOT NULL,
    performed_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.activity_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow select for authenticated on activity_log" ON public.activity_log;
DROP POLICY IF EXISTS "Allow insert for authenticated on activity_log" ON public.activity_log;
DROP POLICY IF EXISTS "Allow update for authenticated on activity_log" ON public.activity_log;

CREATE POLICY "Allow select for authenticated on activity_log" ON public.activity_log FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert for authenticated on activity_log" ON public.activity_log FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update for authenticated on activity_log" ON public.activity_log FOR UPDATE TO authenticated USING (true);
