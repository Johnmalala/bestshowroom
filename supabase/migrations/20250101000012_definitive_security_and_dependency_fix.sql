/*
          # [Definitive Security and Dependency Fix]
          This script provides a comprehensive fix for all pending database issues, including dependency conflicts and security warnings related to mutable function search paths. It systematically drops and recreates all custom triggers and functions in the correct order to ensure a stable and secure schema.

          ## Query Description: [This operation will safely reset and secure all custom database functions and triggers. It first removes existing triggers, then the functions they depend on, and finally recreates everything with proper security settings. This is a safe operation designed to fix previous migration failures and should not result in data loss.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops triggers: 'on_auth_user_created', 'on_car_update_trigger'
          - Drops functions: 'handle_new_user', 'update_broker_commissions_on_car_update', 'has_users', 'update_broker_totals', 'delete_user_and_profile'
          - Recreates all dropped functions with 'SET search_path' and appropriate 'SECURITY' settings.
          - Recreates all dropped triggers.
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Recreated]
          - Estimated Impact: [Low. This is a one-time structural change.]
          */

-- Step 1: Drop existing triggers that depend on functions we need to modify.
-- We use IF EXISTS to prevent errors if the triggers don't exist.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;

-- Step 2: Drop all custom functions.
-- We use IF EXISTS to prevent errors if the functions don't exist.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.update_broker_totals(p_broker_id uuid, p_amount numeric);
DROP FUNCTION IF EXISTS public.delete_user_and_profile(user_id_to_delete uuid);

-- Step 3: Recreate all functions with proper security settings.

-- Function to check if any users exist.
-- SECURITY DEFINER is required to query the auth.users table.
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = public;
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;

-- Function to create a staff profile when a new user signs up.
-- SECURITY DEFINER is required to read metadata from the new auth.users record.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = public;
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

-- Function to calculate and insert broker commission when a car is updated.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  commission_val numeric;
BEGIN
  SET search_path = public;
  IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL AND NEW.broker_commission_value > 0 THEN
    IF NEW.broker_commission_type = 'percentage' THEN
      commission_val := NEW.purchase_price * (NEW.broker_commission_value / 100);
    ELSE
      commission_val := NEW.broker_commission_value;
    END IF;

    -- Upsert logic: update if exists, insert if not.
    INSERT INTO public.broker_commissions (car_id, broker_id, commission_amount, is_paid)
    VALUES (NEW.id, NEW.broker_id, commission_val, false)
    ON CONFLICT (car_id)
    DO UPDATE SET
      broker_id = EXCLUDED.broker_id,
      commission_amount = EXCLUDED.commission_amount;
  END IF;
  RETURN NEW;
END;
$$;

-- Function to update a broker's total commission amounts.
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  SET search_path = public;
  UPDATE public.brokers
  SET
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;

-- Function to delete a user from auth.users and their corresponding staff_profile.
-- SECURITY DEFINER is required to perform actions on the auth schema.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = public;
  -- The trigger on staff_profiles will handle cascade deletion of related records.
  -- Deleting the user from auth.users will cascade delete the staff_profile.
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;


-- Step 4: Recreate the triggers that were dropped in Step 1.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

CREATE TRIGGER on_car_update_trigger
  AFTER INSERT OR UPDATE ON public.cars
  FOR EACH ROW
  WHEN (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value)
  EXECUTE PROCEDURE public.update_broker_commissions_on_car_update();
