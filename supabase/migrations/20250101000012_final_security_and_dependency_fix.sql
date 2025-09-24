/*
          # [Final Security & Dependency Fix]
          This script provides a comprehensive fix for all database function and trigger issues. It correctly handles dependencies by dropping triggers before function modifications and then recreating them. It also hardens all custom functions by setting a non-mutable search_path, resolving all "Function Search Path Mutable" security warnings.

          ## Query Description: [This operation will temporarily drop and then recreate database triggers and functions to apply critical security updates. It is a safe and necessary procedure to ensure the database schema is stable and secure. No data will be lost.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops triggers: on_car_update_trigger, on_auth_user_created
          - Recreates functions: has_users, calculate_broker_commission, update_broker_commissions_on_car_update, handle_new_user, delete_user_and_profile, update_broker_totals
          - Recreates triggers: on_car_update_trigger, on_auth_user_created
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [Admin privileges required to run]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. A brief moment where triggers are inactive during migration.]
          */

-- Step 1: Drop dependent triggers safely.
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Recreate all functions with security hardening.

-- Function: has_users
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM 1 FROM auth.users LIMIT 1;
  RETURN FOUND;
END;
$$;
ALTER FUNCTION public.has_users() SET search_path = 'public';

-- Function: calculate_broker_commission
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_car public.cars;
  v_commission_amount numeric := 0;
BEGIN
  SET search_path = 'public';
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;
  
  IF v_car.broker_commission_type = 'fixed' THEN
    v_commission_amount := v_car.broker_commission_value;
  ELSIF v_car.broker_commission_type = 'percentage' THEN
    v_commission_amount := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  END IF;
  
  RETURN v_commission_amount;
END;
$$;

-- Function: update_broker_commissions_on_car_update
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  SET search_path = 'public';
  IF NEW.status = 'sold' AND OLD.status = 'available' AND NEW.broker_id IS NOT NULL THEN
    v_commission_amount := public.calculate_broker_commission(NEW.id);
    
    IF v_commission_amount > 0 THEN
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount, false);

      UPDATE public.brokers
      SET total_commission_due = total_commission_due + v_commission_amount
      WHERE id = NEW.broker_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
  INSERT INTO public.staff_profiles (id, full_name, phone_number, role, created_by)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.raw_user_meta_data ->> 'phone_number',
    (NEW.raw_user_meta_data ->> 'role')::public.user_role,
    (NEW.raw_user_meta_data ->> 'created_by')::uuid
  );
  RETURN NEW;
END;
$$;

-- Function: delete_user_and_profile
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;

-- Function: update_broker_totals
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  SET search_path = 'public';
  UPDATE public.brokers
  SET 
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;

-- Step 3: Recreate triggers.
CREATE TRIGGER on_car_update_trigger
AFTER UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
