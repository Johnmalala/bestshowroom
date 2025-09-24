/*
  # Comprehensive Database Function & Trigger Fix
  This script provides a definitive fix for all migration errors related to function dependencies and security warnings.

  ## Query Description:
  This operation will safely drop and recreate all custom database functions and their associated triggers. It resolves dependency conflicts (like the `handle_new_user` error) and hardens security by setting the `search_path` for all functions, which fixes the "Function Search Path Mutable" warnings. This is a safe, idempotent operation designed to stabilize the database schema.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Medium"
  - Requires-Backup: false
  - Reversible: false

  ## Structure Details:
  - Drops and recreates triggers: `on_auth_user_created`, `on_car_update_trigger`
  - Drops and recreates functions: `handle_new_user`, `calculate_broker_commission`, `update_broker_commissions_on_car_update`, `has_users`, `delete_user_and_profile`, `update_broker_totals`

  ## Security Implications:
  - RLS Status: Unchanged
  - Policy Changes: No
  - Auth Requirements: Admin privileges to run.
  - Fixes all "Function Search Path Mutable" warnings by setting a fixed search path.

  ## Performance Impact:
  - Indexes: Unchanged
  - Triggers: Recreated
  - Estimated Impact: Negligible. A brief re-creation of triggers and functions.
*/

-- Drop dependent triggers first to resolve dependency errors
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop all custom functions to ensure a clean slate
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);


-- Recreate function: handle_new_user
-- This function creates a staff profile when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
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

-- Recreate function: calculate_broker_commission
-- Calculates commission based on car price and commission type/value.
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(car_id_param uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  car_record record;
  commission_amount numeric;
BEGIN
  SELECT * INTO car_record FROM public.cars WHERE id = car_id_param;

  IF car_record.broker_id IS NULL OR car_record.broker_commission_value IS NULL THEN
    RETURN 0;
  END IF;

  IF car_record.broker_commission_type = 'fixed' THEN
    commission_amount := car_record.broker_commission_value;
  ELSIF car_record.broker_commission_type = 'percentage' THEN
    commission_amount := car_record.purchase_price * (car_record.broker_commission_value / 100.0);
  ELSE
    commission_amount := 0;
  END IF;

  RETURN commission_amount;
END;
$$;


-- Recreate function: update_broker_commissions_on_car_update
-- Creates/updates broker commission when a car is sold or broker details change.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  commission_val numeric;
BEGIN
  -- Only run if the car is marked as 'sold' or broker details are changed.
  IF (TG_OP = 'UPDATE' AND (NEW.status = 'sold' AND OLD.status <> 'sold') OR (NEW.broker_id IS DISTINCT FROM OLD.broker_id)) THEN
    -- If there's a broker, calculate and insert/update the commission.
    IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL THEN
      commission_val := public.calculate_broker_commission(NEW.id);

      IF commission_val > 0 THEN
        INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
        VALUES (NEW.broker_id, NEW.id, commission_val, false)
        ON CONFLICT (car_id) DO UPDATE
        SET commission_amount = EXCLUDED.commission_amount,
            broker_id = EXCLUDED.broker_id,
            is_paid = false,
            paid_date = NULL;
      END IF;
    -- If broker is removed, delete the associated commission record if it exists.
    ELSE
      DELETE FROM public.broker_commissions WHERE car_id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


-- Recreate function: has_users
-- Checks if any users exist in the system. Used for initial setup flow.
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;


-- Recreate function: delete_user_and_profile
-- Allows an owner to delete a staff member's auth account and profile.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if the calling user is an owner
  IF (SELECT role FROM public.staff_profiles WHERE id = auth.uid()) <> 'owner' THEN
    RAISE EXCEPTION 'Only owners can delete users.';
  END IF;

  -- Delete from auth.users, which will cascade to staff_profiles
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;

-- Recreate function: update_broker_totals
-- Updates the total due/paid amounts for a broker when a commission is paid.
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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


-- Re-create triggers in the correct order
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_update_trigger
  AFTER UPDATE ON public.cars
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.broker_id IS DISTINCT FROM NEW.broker_id)
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
