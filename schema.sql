-- Staff Table
CREATE TABLE public.staff (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'office_staff')),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    profile_photo_url TEXT
);

-- Leads Table
CREATE TABLE public.leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    mobile TEXT NOT NULL,
    village TEXT,
    requirement TEXT,
    source TEXT NOT NULL,
    remark TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'converted', 'archived')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Customers Table
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id TEXT UNIQUE NOT NULL, -- e.g., CRM-0001
    name TEXT NOT NULL,
    mobile TEXT UNIQUE NOT NULL,
    consumer_number TEXT UNIQUE,
    village TEXT,
    address TEXT,
    system_size TEXT,
    application_date DATE,
    stage TEXT NOT NULL DEFAULT 'Lead',
    priority BOOLEAN DEFAULT false,
    loan_required BOOLEAN DEFAULT NULL,
    remarks TEXT,
    created_by UUID REFERENCES public.staff(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Stage History
CREATE TABLE public.stage_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    old_stage TEXT,
    new_stage TEXT NOT NULL,
    changed_by UUID REFERENCES public.staff(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Tasks
CREATE TABLE public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    description TEXT,
    due_date DATE,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high')),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed')),
    created_by UUID REFERENCES public.staff(id),
    started_by UUID REFERENCES public.staff(id),
    started_at TIMESTAMP WITH TIME ZONE,
    completed_by UUID REFERENCES public.staff(id),
    completed_at TIMESTAMP WITH TIME ZONE,
    completion_remark TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Task Types Table (to save autocomplete options)
CREATE TABLE public.task_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Task Staff (Many-to-Many)
CREATE TABLE public.task_staff (
    task_id UUID REFERENCES public.tasks(id) ON DELETE CASCADE,
    staff_id UUID REFERENCES public.staff(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, staff_id)
);

-- Enable RLS
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stage_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_staff ENABLE ROW LEVEL SECURITY;

-- Helper function to check if the current user is an admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.staff
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. Staff Table Policies
CREATE POLICY "Allow all select for staff" ON public.staff FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert/update/delete only for admins on staff" ON public.staff FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 2. Leads Table Policies
CREATE POLICY "Allow all select for leads" ON public.leads FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert/update for staff and admins on leads" ON public.leads FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update for staff and admins on leads" ON public.leads FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow delete only for admins on leads" ON public.leads FOR DELETE TO authenticated USING (public.is_admin());

-- 3. Customers Table Policies
CREATE POLICY "Allow all select for customers" ON public.customers FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert/update for staff and admins on customers" ON public.customers FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update for staff and admins on customers" ON public.customers FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow delete only for admins on customers" ON public.customers FOR DELETE TO authenticated USING (public.is_admin());

-- 4. Stage History Table Policies
CREATE POLICY "Allow all select for stage_history" ON public.stage_history FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert for staff and admins on stage_history" ON public.stage_history FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update/delete only for admins on stage_history" ON public.stage_history FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 5. Tasks Table Policies
CREATE POLICY "Allow select for creator, assigned staff, and admins on tasks" ON public.tasks FOR SELECT TO authenticated USING (public.is_admin() OR created_by = auth.uid() OR EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid()));
CREATE POLICY "Allow insert for staff and admins on tasks" ON public.tasks FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update for creator, assigned staff, and admins on tasks" ON public.tasks FOR UPDATE TO authenticated USING (public.is_admin() OR created_by = auth.uid() OR EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid())) WITH CHECK (public.is_admin() OR created_by = auth.uid() OR EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid()));
CREATE POLICY "Allow delete only for admins on tasks" ON public.tasks FOR DELETE TO authenticated USING (public.is_admin());

-- 6. Task Staff Policies
CREATE POLICY "Allow all select for task_staff" ON public.task_staff FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert/update/delete for staff and admins on task_staff" ON public.task_staff FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 7. Task Types Policies
CREATE POLICY "Allow all select for task_types" ON public.task_types FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert for staff and admins on task_types" ON public.task_types FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update/delete only for admins on task_types" ON public.task_types FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- 8. Task Activity
CREATE TABLE public.task_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    staff_id UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    activity_type TEXT NOT NULL CHECK (activity_type IN ('started', 'completed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.task_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all select for task_activity" ON public.task_activity FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert for task_activity" ON public.task_activity FOR INSERT TO authenticated WITH CHECK (true);

-- 9. App Releases & Staff Version Tracking
CREATE TABLE IF NOT EXISTS public.app_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    app_name TEXT NOT NULL DEFAULT 'Siya Solar Staff',
    platform TEXT NOT NULL DEFAULT 'android',
    latest_version TEXT NOT NULL,
    latest_version_code INTEGER NOT NULL,
    minimum_supported_version_code INTEGER NOT NULL,
    apk_download_url TEXT NOT NULL,
    release_notes TEXT,
    update_type TEXT NOT NULL CHECK (update_type IN ('OPTIONAL', 'MANDATORY')) DEFAULT 'OPTIONAL',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.app_releases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow select for all on app_releases" ON public.app_releases FOR SELECT TO public USING (true);


-- Staff tracking columns (added via migration)
-- ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS app_version TEXT;
-- ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS build_number INTEGER;
-- ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP WITH TIME ZONE;

-- 10. Site Installation Tasks (Phase 2 Parallel Work)
CREATE TABLE public.site_installation_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    task_type TEXT NOT NULL CHECK (task_type IN ('Structure Installation', 'Panel Uploading', 'Wiring')),
    status TEXT NOT NULL DEFAULT 'Not Started' CHECK (status IN ('Not Started', 'In Progress', 'Completed')),
    started_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    completed_at TIMESTAMP WITH TIME ZONE,
    remark TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_customer_task_type UNIQUE (customer_id, task_type)
);

ALTER TABLE public.site_installation_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow select for authenticated on site_installation_tasks" ON public.site_installation_tasks FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow update for authenticated on site_installation_tasks" ON public.site_installation_tasks FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow insert for authenticated on site_installation_tasks" ON public.site_installation_tasks FOR INSERT TO authenticated WITH CHECK (true);

-- 11. Site Materials (Phase 2 Material Tracker)
CREATE TABLE IF NOT EXISTS public.site_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL CHECK (material_type IN ('Structure', 'Solar Panel', 'Inverter', 'Generation Meter')),
    -- Type-specific fields
    structure_type TEXT,
    panel_brand TEXT,
    panel_wattage TEXT,
    inverter_brand TEXT,
    inverter_capacity TEXT,
    meter_number TEXT,
    meter_installation_date DATE,
    -- Quantities
    required_qty INTEGER NOT NULL DEFAULT 0 CHECK (required_qty >= 0),
    dispatched_qty INTEGER NOT NULL DEFAULT 0 CHECK (dispatched_qty >= 0),
    installed_qty INTEGER NOT NULL DEFAULT 0 CHECK (installed_qty >= 0),
    -- Status
    status TEXT NOT NULL DEFAULT 'Pending' CHECK (status IN ('Not Required','Pending','Dispatched','Partially Used','Installed','Completed')),
    remark TEXT,
    -- Metadata
    created_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT unique_customer_material UNIQUE (customer_id, material_type),
    CONSTRAINT installed_lte_dispatched CHECK (installed_qty <= dispatched_qty)
);

-- 12. Material Transactions (audit log)
CREATE TABLE IF NOT EXISTS public.material_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_material_id UUID NOT NULL REFERENCES public.site_materials(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('dispatch', 'usage', 'adjustment')),
    quantity INTEGER NOT NULL,
    old_qty INTEGER,
    new_qty INTEGER,
    field_changed TEXT,
    remark TEXT,
    created_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.site_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.material_transactions ENABLE ROW LEVEL SECURITY;

-- site_materials RLS
CREATE POLICY "Allow select on site_materials" ON public.site_materials FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert on site_materials" ON public.site_materials FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Allow update on site_materials for admin" ON public.site_materials FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY "Allow delete on site_materials for admin" ON public.site_materials FOR DELETE TO authenticated USING (public.is_admin());

-- material_transactions RLS
CREATE POLICY "Allow select on material_transactions" ON public.material_transactions FOR SELECT TO authenticated USING (true);
CREATE POLICY "Allow insert on material_transactions" ON public.material_transactions FOR INSERT TO authenticated WITH CHECK (
    (transaction_type IN ('dispatch', 'adjustment') AND public.is_admin()) OR
    transaction_type = 'usage'
);
CREATE POLICY "No delete on material_transactions" ON public.material_transactions FOR DELETE TO authenticated USING (public.is_admin());

-- Add to realtime publication
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.site_materials;
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.material_transactions;

-- Task Attachments Table
CREATE TABLE public.task_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_size INTEGER NOT NULL,
    uploaded_by UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);
ALTER TABLE public.task_attachments ENABLE ROW LEVEL SECURITY;

