-- Migration: Recreate advance_customer_stage function to handle customer_id auto-generation during Lead conversion
-- Date: 2026-08-22

CREATE OR REPLACE FUNCTION public.advance_customer_stage(
  p_customer_id UUID,
  p_old_stage TEXT,
  p_new_stage TEXT,
  p_changed_by UUID
) RETURNS VOID AS $$
DECLARE
  v_customer_id_text TEXT;
  v_lead_name TEXT;
  v_lead_mobile TEXT;
  v_lead_village TEXT;
  v_lead_address TEXT;
  v_lead_remarks TEXT;
  v_lead_created_by UUID;
  v_lead_created_at TIMESTAMP WITH TIME ZONE;
  v_lead_payment_type TEXT;
BEGIN
  -- 1. Check if the customer already exists in customers table
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer_id) THEN
    -- If it does not exist, it means we are converting from leads!
    -- Fetch the lead details
    SELECT 
      name, 
      mobile, 
      village, 
      address, 
      remarks, 
      created_by, 
      created_at, 
      COALESCE(payment_type, 'CASH')
    INTO 
      v_lead_name, 
      v_lead_mobile, 
      v_lead_village, 
      v_lead_address, 
      v_lead_remarks, 
      v_lead_created_by, 
      v_lead_created_at, 
      v_lead_payment_type
    FROM public.leads
    WHERE id = p_customer_id;
    
    -- Generate custom customer_id text like C000001
    SELECT 'C' || lpad((COALESCE(count(*), 0) + 1)::text, 6, '0')
    INTO v_customer_id_text
    FROM public.customers;
    
    -- Insert into customers table
    INSERT INTO public.customers (
      id, 
      customer_id, 
      name, 
      mobile, 
      village, 
      address, 
      remarks, 
      stage, 
      created_by, 
      created_at, 
      updated_at,
      payment_type,
      loan_required
    ) VALUES (
      p_customer_id,
      v_customer_id_text,
      COALESCE(v_lead_name, 'N/A'),
      COALESCE(v_lead_mobile, 'N/A'),
      v_lead_village,
      v_lead_address,
      v_lead_remarks,
      p_new_stage,
      v_lead_created_by,
      COALESCE(v_lead_created_at, now()),
      now(),
      v_lead_payment_type,
      v_lead_payment_type = 'LOAN'
    );
    
    -- Update lead status to converted
    UPDATE public.leads
    SET status = 'converted'
    WHERE id = p_customer_id;
  ELSE
    -- If customer already exists, just update their stage
    UPDATE public.customers
    SET stage = p_new_stage,
        updated_at = now()
    WHERE id = p_customer_id;
  END IF;

  -- 2. Insert stage history
  INSERT INTO public.stage_history (
    customer_id, 
    old_stage, 
    new_stage, 
    changed_by, 
    created_at
  ) VALUES (
    p_customer_id, 
    p_old_stage, 
    p_new_stage, 
    p_changed_by, 
    now()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
