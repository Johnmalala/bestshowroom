/*
          # [Definitive Security and Dependency Fix]
          This script provides a comprehensive fix for all pending database issues, including dependency errors during migrations and persistent "Function Search Path Mutable" security warnings. It safely drops and recreates all custom triggers and functions in the correct order, ensuring a stable and secure database schema.

          ## Query Description: [This operation will reset and secure all custom database functions and triggers. It resolves previous migration failures by correctly managing object dependencies. No data will be lost, but it is a critical structural change. A backup is always recommended before major schema updates.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: true
          - Reversible: false
          
          ## Structure Details:
          - Drops triggers: on_auth_user_created, on_car_insert_trigger, on_car_update_trigger
          - Drops functions: handle_new_user, delete_user_and_profile, has_users, update_broker_commissions_on_car_update, update_broker_totals
          - Recreates all dropped functions with proper security settings (SET search_path, SECURITY DEFINER where needed).
          - Recreates all dropped triggers to restore application logic.
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None for execution]
          - Fixes all "Function Search Path Mutable" warnings by explicitly setting the search_path for each function.
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. This is a one-time structural fix.]
          */

-- Step 1: Drop existing triggers that depend on the functions.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_car_insert_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;

-- Step 2: Drop all existing custom functions.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);

-- Step 3: Recreate the has_users function with SECURITY DEFINER and a fixed search_path.
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;

-- Step 4: Recreate the handle_new_user function with a fixed search_path.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.staff_profiles (id, full_name, phone_number, role, created_by)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone_number',
    (new.raw_user_meta_data->>'role')::public.user_role,
    (new.raw_user_meta_data->>'created_by')::uuid
  );
  RETURN new;
END;
$$;

-- Step 5: Recreate the delete_user_and_profile function with a fixed search_path.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;

-- Step 6: Recreate the update_broker_totals function with a fixed search_path.
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  UPDATE public.brokers
  SET
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;

-- Step 7: Recreate the update_broker_commissions_on_car_update function with a fixed search_path.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  commission_val numeric;
BEGIN
  -- This function handles both INSERT and UPDATE
  IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value)) THEN
    
    -- If there's an old commission, delete it first on update
    IF TG_OP = 'UPDATE' THEN
      DELETE FROM public.broker_commissions WHERE car_id = OLD.id;
    END IF;

    -- If a new broker is assigned, create a new commission record
    IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL AND NEW.broker_commission_value > 0 THEN
      IF NEW.broker_commission_type = 'percentage' THEN
        commission_val := (NEW.purchase_price * NEW.broker_commission_value) / 100;
      ELSE
        commission_val := NEW.broker_commission_value;
      END IF;

      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, commission_val, false);
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

-- Step 8: Recreate the triggers to call the new functions.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_insert_trigger
  AFTER INSERT ON public.cars
  FOR EACH ROW
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();

CREATE TRIGGER on_car_update_trigger
  AFTER UPDATE ON public.cars
  FOR EACH ROW
  WHEN (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value)
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
