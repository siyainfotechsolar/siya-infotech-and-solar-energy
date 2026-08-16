-- Supabase Security Migration: Role-Specific Task Details & Field-Level Access Control

-- 1. Delivery Task Details RPC
CREATE OR REPLACE FUNCTION public.get_delivery_task_details(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_user_role TEXT;
  v_result JSONB;
BEGIN
  v_user_id := auth.uid();
  
  -- Check user role from staff table
  SELECT role INTO v_user_role FROM public.staff WHERE id = v_user_id;

  -- Ensure caller is admin or assigned to the task / delivery
  IF v_user_role != 'admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.task_staff WHERE task_id = p_task_id AND staff_id = v_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.tasks WHERE id = p_task_id AND created_by = v_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.material_dispatches md
      JOIN public.tasks t ON t.customer_id = md.customer_id
      WHERE t.id = p_task_id AND md.delivery_staff_id = v_user_id
    ) THEN
      RAISE EXCEPTION 'Access Denied: You are not assigned to this delivery task.';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'task_id', t.id,
    'name', t.name,
    'description', t.description,
    'due_date', t.due_date,
    'priority', t.priority,
    'status', t.status,
    'completion_remark', t.completion_remark,
    'created_at', t.created_at,
    'customer_id', c.id,
    'customer_name', c.name,
    'customer_mobile', c.mobile,
    'delivery_address', COALESCE(c.address, c.village),
    'village', c.village,
    'pm_surya_ghar_application_id', c.consumer_number,
    'assigned_staff', (
      SELECT jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role))
      FROM public.task_staff ts
      JOIN public.staff s ON s.id = ts.staff_id
      WHERE ts.task_id = t.id
    ),
    'materials', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', sm.id,
        'material_type', sm.material_type,
        'structure_type', sm.structure_type,
        'panel_brand', sm.panel_brand,
        'panel_wattage', sm.panel_wattage,
        'inverter_brand', sm.inverter_brand,
        'inverter_capacity', sm.inverter_capacity,
        'required_qty', sm.required_qty,
        'dispatched_qty', sm.dispatched_qty,
        'installed_qty', sm.installed_qty,
        'status', sm.status
      ))
      FROM public.site_materials sm
      WHERE sm.customer_id = t.customer_id
    ),
    'delivery_dispatches', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', md.id,
        'material_type', md.material_type,
        'status', md.status,
        'dispatch_date', md.dispatch_date,
        'remarks', md.remarks
      ))
      FROM public.material_dispatches md
      WHERE md.customer_id = t.customer_id
    ),
    'delivery_photos', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', ta.id,
        'file_name', ta.file_name,
        'file_path', ta.file_path,
        'file_type', ta.file_type,
        'created_at', ta.created_at
      ))
      FROM public.task_attachments ta
      WHERE ta.task_id = t.id
    )
  ) INTO v_result
  FROM public.tasks t
  JOIN public.customers c ON c.id = t.customer_id
  WHERE t.id = p_task_id;

  RETURN v_result;
END;
$$;


-- 2. Structure Task Details RPC
CREATE OR REPLACE FUNCTION public.get_structure_task_details(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_user_role TEXT;
  v_result JSONB;
BEGIN
  v_user_id := auth.uid();
  SELECT role INTO v_user_role FROM public.staff WHERE id = v_user_id;

  IF v_user_role != 'admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.task_staff WHERE task_id = p_task_id AND staff_id = v_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.tasks WHERE id = p_task_id AND created_by = v_user_id
    ) THEN
      RAISE EXCEPTION 'Access Denied: You are not assigned to this structure task.';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'task_id', t.id,
    'name', t.name,
    'description', t.description,
    'due_date', t.due_date,
    'priority', t.priority,
    'status', t.status,
    'completion_remark', t.completion_remark,
    'created_at', t.created_at,
    'customer_id', c.id,
    'customer_name', c.name,
    'customer_mobile', c.mobile,
    'address', COALESCE(c.address, c.village),
    'village', c.village,
    'pm_surya_ghar_application_id', c.consumer_number,
    'installation_tasks', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', sit.id,
        'task_type', sit.task_type,
        'status', sit.status,
        'remark', sit.remark
      ))
      FROM public.site_installation_tasks sit
      WHERE sit.customer_id = t.customer_id
    ),
    'photos', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', ta.id,
        'file_name', ta.file_name,
        'file_path', ta.file_path,
        'file_type', ta.file_type,
        'created_at', ta.created_at
      ))
      FROM public.task_attachments ta
      WHERE ta.task_id = t.id
    )
  ) INTO v_result
  FROM public.tasks t
  JOIN public.customers c ON c.id = t.customer_id
  WHERE t.id = p_task_id;

  RETURN v_result;
END;
$$;


-- 3. Wireman Task Details RPC
CREATE OR REPLACE FUNCTION public.get_wireman_task_details(p_task_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_user_role TEXT;
  v_result JSONB;
BEGIN
  v_user_id := auth.uid();
  SELECT role INTO v_user_role FROM public.staff WHERE id = v_user_id;

  IF v_user_role != 'admin' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.task_staff WHERE task_id = p_task_id AND staff_id = v_user_id
    ) AND NOT EXISTS (
      SELECT 1 FROM public.tasks WHERE id = p_task_id AND created_by = v_user_id
    ) THEN
      RAISE EXCEPTION 'Access Denied: You are not assigned to this wireman task.';
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'task_id', t.id,
    'name', t.name,
    'description', t.description,
    'due_date', t.due_date,
    'priority', t.priority,
    'status', t.status,
    'completion_remark', t.completion_remark,
    'created_at', t.created_at,
    'customer_id', c.id,
    'customer_name', c.name,
    'customer_mobile', c.mobile,
    'address', COALESCE(c.address, c.village),
    'village', c.village,
    'pm_surya_ghar_application_id', c.consumer_number,
    'installation_tasks', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', sit.id,
        'task_type', sit.task_type,
        'status', sit.status,
        'remark', sit.remark
      ))
      FROM public.site_installation_tasks sit
      WHERE sit.customer_id = t.customer_id
    ),
    'electrical_materials', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', sm.id,
        'material_type', p.name,
        'status', sm.status
      ))
      FROM public.site_materials sm
      LEFT JOIN public.products p ON sm.product_id = p.id
      WHERE (sm.site_id = t.customer_id OR sm.customer_id = t.customer_id)
    ),
    'photos', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', ta.id,
        'file_name', ta.file_name,
        'file_path', ta.file_path,
        'file_type', ta.file_type,
        'created_at', ta.created_at
      ))
      FROM public.task_attachments ta
      WHERE ta.task_id = t.id
    )
  ) INTO v_result
  FROM public.tasks t
  JOIN public.customers c ON c.id = t.customer_id
  WHERE t.id = p_task_id;

  RETURN v_result;
END;
$$;
