/*
          # [Final Security & Dependency Fix]
          This script provides a comprehensive fix for all persistent database issues, including dependency conflicts during migrations and "Function Search Path Mutable" security warnings. It safely drops and recreates all custom functions and triggers in the correct order with proper security settings.

          ## Query Description: [This operation will reset all custom database functions and triggers to a known, secure state. It is designed to be safe and non-destructive to your data, but as a best practice for any significant schema change, a database backup is recommended before proceeding.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [true]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops and recreates all triggers: on_car_status_change, on_new_user_profile.
          - Drops and recreates all functions: handle_new_user, calculate_broker_commission, update_broker_commissions_on_car_update, has_users, delete_user_and_profile, update_broker_totals.
          - Applies `SET search_path = public` to all recreated functions.
          - Applies `SECURITY DEFINER` where necessary.
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None for execution]
          - Fixes all "Function Search Path Mutable" warnings.
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. A brief moment of re-linking functions and triggers.]
          */

-- Drop dependent triggers first to avoid errors
DROP TRIGGER IF EXISTS on_car_status_change ON public.cars;
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_car_sold_commission ON public.cars;
DROP TRIGGER IF EXISTS on_new_user_profile ON auth.users;

-- Drop all custom functions to ensure a clean slate
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);

-- Recreate function: handle_new_user (for creating staff profiles)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
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
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- Recreate function: calculate_broker_commission
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission numeric;
  v_car record;
BEGIN
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;
  
  IF v_car.broker_commission_type = 'percentage' THEN
    v_commission := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  ELSIF v_car.broker_commission_type = 'fixed' THEN
    v_commission := v_car.broker_commission_value;
  ELSE
    v_commission := 0;
  END IF;
  
  RETURN v_commission;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission(uuid) SET search_path = public;

-- Recreate function: update_broker_commissions_on_car_update
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- If car is marked as sold and has a broker
  IF NEW.status = 'sold' AND OLD.status <> 'sold' AND NEW.broker_id IS NOT NULL THEN
    -- Check if a commission already exists to prevent duplicates
    IF NOT EXISTS (SELECT 1 FROM public.broker_commissions WHERE car_id = NEW.id) THEN
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, public.calculate_broker_commission(NEW.id), FALSE);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = public;

-- Recreate function: has_users (for initial setup check)
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;
ALTER FUNCTION public.has_users() SET search_path = public;

-- Recreate function: delete_user_and_profile (for staff management)
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- First, delete from the public profile table
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  -- Then, delete from the auth users table
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) SET search_path = public;

-- Recreate function: update_broker_totals (for commission payments)
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.brokers
  SET 
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;
ALTER FUNCTION public.update_broker_totals(uuid, numeric) SET search_path = public;

-- Recreate all necessary triggers
CREATE TRIGGER on_new_user_profile
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_status_change
AFTER UPDATE OF status ON public.cars
FOR EACH ROW
WHEN (NEW.status = 'sold' AND OLD.status <> 'sold')
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
