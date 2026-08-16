-- Migration: Central Staff & Data Access Management
-- Date: 2026-08-16

-- 1. Staff Category Column & Constraint
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS category TEXT;

ALTER TABLE public.staff DROP CONSTRAINT IF EXISTS staff_role_check;
ALTER TABLE public.staff ADD CONSTRAINT staff_role_check 
  CHECK (role IN ('admin', 'supervisor', 'installer', 'wireman', 'delivery_staff', 'office_staff', 'other_staff'));

UPDATE public.staff SET category = CASE 
  WHEN role = 'admin' THEN 'Admin'
  WHEN role = 'supervisor' THEN 'Supervisor'
  WHEN role = 'installer' THEN 'Structure Installer'
  WHEN role = 'wireman' THEN 'Wireman / Electrical Installer'
  WHEN role = 'delivery_staff' THEN 'Delivery Staff'
  ELSE 'Other Staff'
END WHERE category IS NULL;

-- 2. Staff Permissions Table
CREATE TABLE IF NOT EXISTS public.staff_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL UNIQUE REFERENCES public.staff(id) ON DELETE CASCADE,
    category TEXT NOT NULL DEFAULT 'Other Staff',
    data_access_level TEXT NOT NULL DEFAULT 'ASSIGNED_DATA' CHECK (data_access_level IN ('ALL_DATA', 'TEAM_DATA', 'ASSIGNED_DATA', 'LIMITED_DATA', 'NO_ACCESS')),
    permissions JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_by UUID REFERENCES public.staff(id) ON DELETE SET NULL
);

ALTER TABLE public.staff_permissions ENABLE ROW LEVEL SECURITY;

-- 3. Audit Logs Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.staff(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    module TEXT NOT NULL,
    entity_id TEXT,
    details JSONB DEFAULT '{}'::jsonb,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- 4. Security Functions
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.staff
    WHERE id = auth.uid() 
      AND status = 'active' 
      AND (role = 'admin' OR category = 'Admin')
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_supervisor_or_admin()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.staff
    WHERE id = auth.uid() 
      AND status = 'active' 
      AND (role IN ('admin', 'supervisor') OR category IN ('Admin', 'Supervisor'))
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.is_active_staff()
RETURNS boolean AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.staff
    WHERE id = auth.uid() AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.has_permission(p_module text, p_action text)
RETURNS boolean AS $$
DECLARE
    v_role text;
    v_status text;
    v_perms jsonb;
BEGIN
    SELECT role, status INTO v_role, v_status FROM public.staff WHERE id = auth.uid();
    IF v_status IS NULL OR v_status != 'active' THEN
        RETURN false;
    END IF;
    IF v_role = 'admin' THEN
        RETURN true;
    END IF;
    SELECT permissions INTO v_perms FROM public.staff_permissions WHERE staff_id = auth.uid();
    IF v_perms IS NULL THEN
        RETURN false;
    END IF;
    IF (v_perms -> p_module) IS NULL THEN
        RETURN false;
    END IF;
    IF (v_perms -> p_module ->> 'enabled')::boolean IS NOT TRUE THEN
        RETURN false;
    END IF;
    IF p_action IS NULL OR p_action = 'view' THEN
        RETURN true;
    END IF;
    RETURN COALESCE((v_perms -> p_module -> 'actions' ->> p_action)::boolean, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_staff_access_level(p_module text)
RETURNS text AS $$
DECLARE
    v_role text;
    v_level text;
BEGIN
    SELECT role INTO v_role FROM public.staff WHERE id = auth.uid();
    IF v_role = 'admin' THEN
        RETURN 'ALL_DATA';
    END IF;
    SELECT data_access_level INTO v_level FROM public.staff_permissions WHERE staff_id = auth.uid();
    RETURN COALESCE(v_level, 'ASSIGNED_DATA');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RLS Policies
DROP POLICY IF EXISTS "Allow active staff select on staff" ON public.staff;
DROP POLICY IF EXISTS "Allow admin full access on staff" ON public.staff;

CREATE POLICY "Allow active staff select on staff" ON public.staff
  FOR SELECT TO authenticated
  USING (public.is_active_staff());

CREATE POLICY "Allow admin full access on staff" ON public.staff
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Allow admin full access on staff_permissions" ON public.staff_permissions;
DROP POLICY IF EXISTS "Allow user select own staff_permissions" ON public.staff_permissions;

CREATE POLICY "Allow admin full access on staff_permissions" ON public.staff_permissions
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "Allow user select own staff_permissions" ON public.staff_permissions
  FOR SELECT TO authenticated
  USING (staff_id = auth.uid());

DROP POLICY IF EXISTS "Allow admin select on audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Allow active staff insert on audit_logs" ON public.audit_logs;

CREATE POLICY "Allow admin select on audit_logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE POLICY "Allow active staff insert on audit_logs" ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (public.is_active_staff());

DROP POLICY IF EXISTS "Allow select on customers" ON public.customers;
DROP POLICY IF EXISTS "Allow insert on customers" ON public.customers;
DROP POLICY IF EXISTS "Allow update on customers" ON public.customers;
DROP POLICY IF EXISTS "Allow delete on customers" ON public.customers;

CREATE POLICY "Allow select on customers" ON public.customers
  FOR SELECT TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR
      public.has_permission('customers', 'view') AND (
        public.get_staff_access_level('customers') = 'ALL_DATA' OR
        public.get_staff_access_level('customers') = 'TEAM_DATA' OR
        EXISTS (
          SELECT 1 FROM public.tasks t
          JOIN public.task_staff ts ON ts.task_id = t.id
          WHERE t.customer_id = customers.id AND ts.staff_id = auth.uid()
        ) OR
        EXISTS (
          SELECT 1 FROM public.material_dispatches md
          WHERE md.customer_id = customers.id AND md.delivery_staff_id = auth.uid()
        )
      )
    )
  );

CREATE POLICY "Allow insert on customers" ON public.customers
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('customers', 'create')
    )
  );

CREATE POLICY "Allow update on customers" ON public.customers
  FOR UPDATE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('customers', 'edit')
    )
  )
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('customers', 'edit')
    )
  );

CREATE POLICY "Allow delete on customers" ON public.customers
  FOR DELETE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('customers', 'delete')
    )
  );

DROP POLICY IF EXISTS "Allow select on leads" ON public.leads;
DROP POLICY IF EXISTS "Allow insert on leads" ON public.leads;
DROP POLICY IF EXISTS "Allow update on leads" ON public.leads;
DROP POLICY IF EXISTS "Allow delete on leads" ON public.leads;

CREATE POLICY "Allow select on leads" ON public.leads
  FOR SELECT TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('leads', 'view')
    )
  );

CREATE POLICY "Allow insert on leads" ON public.leads
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('leads', 'create')
    )
  );

CREATE POLICY "Allow update on leads" ON public.leads
  FOR UPDATE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('leads', 'edit')
    )
  )
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('leads', 'edit')
    )
  );

CREATE POLICY "Allow delete on leads" ON public.leads
  FOR DELETE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('leads', 'delete')
    )
  );

DROP POLICY IF EXISTS "Allow select on tasks" ON public.tasks;
DROP POLICY IF EXISTS "Allow insert on tasks" ON public.tasks;
DROP POLICY IF EXISTS "Allow update on tasks" ON public.tasks;
DROP POLICY IF EXISTS "Allow delete on tasks" ON public.tasks;

CREATE POLICY "Allow select on tasks" ON public.tasks
  FOR SELECT TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR
      public.get_staff_access_level('tasks') IN ('ALL_DATA', 'TEAM_DATA') OR
      created_by = auth.uid() OR
      EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid())
    )
  );

CREATE POLICY "Allow insert on tasks" ON public.tasks
  FOR INSERT TO authenticated
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('tasks', 'create')
    )
  );

CREATE POLICY "Allow update on tasks" ON public.tasks
  FOR UPDATE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR
      (public.has_permission('tasks', 'edit') AND (
        public.get_staff_access_level('tasks') IN ('ALL_DATA', 'TEAM_DATA') OR
        created_by = auth.uid() OR
        EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid())
      ))
    )
  )
  WITH CHECK (
    public.is_active_staff() AND (
      public.is_admin() OR
      (public.has_permission('tasks', 'edit') AND (
        public.get_staff_access_level('tasks') IN ('ALL_DATA', 'TEAM_DATA') OR
        created_by = auth.uid() OR
        EXISTS (SELECT 1 FROM public.task_staff WHERE task_staff.task_id = id AND task_staff.staff_id = auth.uid())
      ))
    )
  );

CREATE POLICY "Allow delete on tasks" ON public.tasks
  FOR DELETE TO authenticated
  USING (
    public.is_active_staff() AND (
      public.is_admin() OR public.has_permission('tasks', 'delete')
    )
  );
