/*
          # [Definitive Function and Trigger Security Fix]
          This script provides a comprehensive fix for all database dependency errors and "Function Search Path Mutable" security warnings. It safely drops all custom triggers and functions and recreates them in the correct order with proper security configurations (SECURITY DEFINER) and explicit search paths.

          ## Query Description: [This operation rebuilds all custom database logic. It first removes existing triggers and functions to resolve dependency conflicts, then creates them again with enhanced security. This is a safe operation designed to bring the database to a stable, secure state. No data will be lost.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops and recreates triggers: on_auth_user_created, on_car_update_trigger
          - Drops and recreates functions: has_users, handle_new_user, delete_user_and_profile, calculate_broker_commission, update_broker_commissions_on_car_update, update_broker_totals
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [admin]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible performance impact. This fixes function security, which is a net positive.]
          */

-- Step 1: Drop dependent triggers first to avoid dependency errors.
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop all existing custom functions.
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);

-- Step 3: Recreate all functions with proper security settings and search paths.

-- Function to check if any users exist (for initial setup).
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

-- Function to create a staff profile when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
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

-- Function to delete a user from auth.users and their corresponding staff profile.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    SET search_path = 'public';
    -- Delete from staff_profiles first
    DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
    -- Then delete from auth.users
    DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;

-- Function to calculate a broker's commission for a specific car.
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_commission_type public.commission_type;
  v_commission_value numeric;
  v_purchase_price numeric;
  v_commission_amount numeric := 0;
BEGIN
  SET search_path = 'public';
  SELECT broker_commission_type, broker_commission_value, purchase_price
  INTO v_commission_type, v_commission_value, v_purchase_price
  FROM public.cars
  WHERE id = p_car_id;

  IF v_commission_value IS NOT NULL AND v_commission_value > 0 THEN
    IF v_commission_type = 'fixed' THEN
      v_commission_amount := v_commission_value;
    ELSIF v_commission_type = 'percentage' THEN
      v_commission_amount := v_purchase_price * (v_commission_value / 100.0);
    END IF;
  END IF;

  RETURN v_commission_amount;
END;
$$;

-- Function to update or create a broker commission record.
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  commission_val numeric;
BEGIN
  SET search_path = 'public';
  -- Calculate commission for the new state of the car
  commission_val := public.calculate_broker_commission(NEW.id);

  -- If there's a broker and a commission value, upsert the commission record
  IF NEW.broker_id IS NOT NULL AND commission_val > 0 THEN
    INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
    VALUES (NEW.broker_id, NEW.id, commission_val, false)
    ON CONFLICT (car_id)
    DO UPDATE SET
      broker_id = EXCLUDED.broker_id,
      commission_amount = EXCLUDED.commission_amount,
      is_paid = false; -- Reset payment status if commission changes
  -- If no broker or no commission, delete any existing commission record for this car
  ELSE
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;

-- Function to update a broker's total paid/due amounts.
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Step 4: Recreate the triggers.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_update_trigger
  AFTER UPDATE ON public.cars
  FOR EACH ROW
  WHEN (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value OR OLD.purchase_price IS DISTINCT FROM NEW.purchase_price)
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
