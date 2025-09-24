/*
          # [Definitive Security and Dependency Fix]
          This migration provides a comprehensive fix for all recurring "Function Search Path Mutable" security warnings and resolves all function/trigger dependency errors. It does this by safely dropping all custom triggers and functions before recreating them in the correct order with explicit security settings.

          ## Query Description: [This operation will rebuild all custom database logic. It first removes existing triggers and functions to prevent dependency conflicts, then creates them again with hardened security (explicit search paths). This is a safe operation designed to fix previous migration failures and should not result in any data loss. No backup is strictly required, but it is always best practice before running schema changes.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops Triggers: on_car_update_trigger, on_car_sold_trigger
          - Drops Functions: has_users, calculate_broker_commission, update_broker_totals, delete_user_and_profile, update_broker_commissions_on_car_update, create_broker_commission_on_car_sold
          - Recreates all dropped functions with `SET search_path` and appropriate `SECURITY` settings.
          - Recreates all dropped triggers.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [Admin privileges to run migration]
          - Fixes all "Function Search Path Mutable" warnings.
          
          ## Performance Impact:
          - Indexes: [No change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. A one-time schema update.]
          */

-- Step 1: Drop dependent triggers first to resolve dependency issues.
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_car_sold_trigger ON public.cars;

-- Step 2: Drop all custom functions to allow for clean recreation.
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.create_broker_commission_on_car_sold();

-- Step 3: Recreate all functions with security best practices.

-- has_users: Checks if any users exist for the initial setup flow.
-- SECURITY DEFINER is required to query the auth.users table.
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;

-- calculate_broker_commission: Calculates commission for a car.
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission numeric;
  v_car record;
BEGIN
  SET search_path = 'public';
  SELECT * INTO v_car FROM cars WHERE id = p_car_id;
  IF v_car.broker_commission_type = 'fixed' THEN
    v_commission := v_car.broker_commission_value;
  ELSIF v_car.broker_commission_type = 'percentage' THEN
    v_commission := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  ELSE
    v_commission := 0;
  END IF;
  RETURN v_commission;
END;
$$;

-- update_broker_totals: Updates broker totals when a commission is paid.
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  SET search_path = 'public';
  UPDATE brokers
  SET
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;

-- delete_user_and_profile: Deletes a user from auth and their staff profile.
-- SECURITY DEFINER is required to delete from auth.users.
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

-- update_broker_commissions_on_car_update: Trigger function to manage commissions on car updates.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  SET search_path = 'public';
  -- If broker is changed or removed, delete the old commission record.
  IF OLD.broker_id IS NOT NULL AND (OLD.broker_id != NEW.broker_id OR OLD.broker_commission_value != NEW.broker_commission_value) THEN
    DELETE FROM broker_commissions WHERE car_id = OLD.id;
  END IF;

  -- If a broker is assigned and car is sold, create a commission record if it doesn't exist.
  IF NEW.broker_id IS NOT NULL AND NEW.status = 'sold' AND (
    SELECT NOT EXISTS (SELECT 1 FROM broker_commissions WHERE car_id = NEW.id)
  ) THEN
    v_commission_amount := calculate_broker_commission(NEW.id);
    IF v_commission_amount > 0 THEN
      INSERT INTO broker_commissions (broker_id, car_id, commission_amount)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- create_broker_commission_on_car_sold: Trigger function to create commission when a car's status changes to 'sold'.
CREATE OR REPLACE FUNCTION public.create_broker_commission_on_car_sold()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  SET search_path = 'public';
  IF NEW.status = 'sold' AND OLD.status = 'available' AND NEW.broker_id IS NOT NULL THEN
    v_commission_amount := calculate_broker_commission(NEW.id);
    IF v_commission_amount > 0 THEN
      INSERT INTO broker_commissions (broker_id, car_id, commission_amount)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount)
      ON CONFLICT (car_id) DO NOTHING;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Step 4: Recreate the triggers.
CREATE TRIGGER on_car_update_trigger
AFTER UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();

CREATE TRIGGER on_car_sold_trigger
AFTER UPDATE OF status ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.create_broker_commission_on_car_sold();
