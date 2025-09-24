/*
          # [Definitive Security & Dependency Fix]
          This migration provides a comprehensive fix for all recurring dependency errors and "Function Search Path Mutable" security warnings. It ensures the database schema is stable, secure, and correctly configured.

          ## Query Description: [This operation will safely reset all custom database functions and triggers. It first removes all existing triggers to break dependencies, then removes the functions themselves. Finally, it recreates all functions with the required security hardening (explicit search paths) and re-establishes the triggers. This is a safe reset procedure for the application's custom logic and does not affect any stored data in your tables.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops all custom triggers: `on_auth_user_created`, `on_car_update_trigger`.
          - Drops all custom functions: `handle_new_user`, `calculate_broker_commission`, `update_broker_commissions_on_car_update`, `update_broker_totals`, `has_users`, `delete_user_and_profile`.
          - Recreates all functions with `SET search_path = 'public'`.
          - Recreates `has_users` and `delete_user_and_profile` with `SECURITY DEFINER` for necessary permissions.
          - Recreates all triggers to link to the new, secure functions.
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [None for execution]
          - This migration explicitly resolves all "Function Search Path Mutable" warnings.
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. A one-time structural change.]
          */

-- STEP 1: Drop all dependent triggers to remove dependencies.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;

-- STEP 2: Drop all custom functions.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);


-- STEP 3: Recreate all functions with proper security settings.

-- Function to create a staff profile when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
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
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';

-- Function to calculate broker commission for a car.
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission numeric;
  v_car record;
BEGIN
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;
  IF v_car.broker_id IS NULL OR v_car.broker_commission_value IS NULL THEN
    RETURN 0;
  END IF;
  IF v_car.broker_commission_type = 'percentage' THEN
    v_commission := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  ELSE
    v_commission := v_car.broker_commission_value;
  END IF;
  RETURN v_commission;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission(uuid) SET search_path = 'public';

-- Function to create/update broker commission when a car is updated.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND (
    new.broker_id IS DISTINCT FROM old.broker_id OR
    new.broker_commission_type IS DISTINCT FROM old.broker_commission_type OR
    new.broker_commission_value IS DISTINCT FROM old.broker_commission_value OR
    new.purchase_price IS DISTINCT FROM old.purchase_price
  ))) AND new.broker_id IS NOT NULL THEN
    
    -- Calculate new commission
    v_commission_amount := public.calculate_broker_commission(new.id);
    
    -- If commission is valid, upsert it
    IF v_commission_amount > 0 THEN
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (new.broker_id, new.id, v_commission_amount, false)
      ON CONFLICT (car_id)
      DO UPDATE SET
        broker_id = EXCLUDED.broker_id,
        commission_amount = EXCLUDED.commission_amount,
        is_paid = false; -- Reset payment status on commission change
    ELSE
      -- If no valid commission, delete existing one
      DELETE FROM public.broker_commissions WHERE car_id = new.id;
    END IF;
  END IF;
  RETURN new;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = 'public';

-- Function to update broker's total commission stats.
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
ALTER FUNCTION public.update_broker_totals(uuid, numeric) SET search_path = 'public';

-- Function to check if any users exist (for initial setup).
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;
ALTER FUNCTION public.has_users() SET search_path = 'public';

-- Function to delete a user and their corresponding staff profile.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) SET search_path = 'public';


-- STEP 4: Recreate all triggers.

-- Trigger to handle new user creation.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update broker commissions when car details change.
CREATE TRIGGER on_car_update_trigger
  AFTER INSERT OR UPDATE ON public.cars
  FOR EACH ROW EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
