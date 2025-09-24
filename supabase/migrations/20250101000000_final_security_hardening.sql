-- =============================================
-- FINAL DATABASE HARDENING AND STABILIZATION
-- =============================================
-- This script performs a full reset of all custom functions and triggers
-- to resolve persistent dependency errors and security warnings.
-- It uses DROP ... CASCADE to safely remove all dependent objects before
-- recreating them with the correct security settings.

-- Step 1: Drop all dependent triggers and functions safely.
-- The CASCADE option will automatically remove triggers that depend on these functions.

DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.delete_user_and_profile(user_id_to_delete uuid) CASCADE;
DROP FUNCTION IF EXISTS public.has_users() CASCADE;
DROP FUNCTION IF EXISTS public.calculate_broker_commission(p_car_id uuid) CASCADE;
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_insert() CASCADE;
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update() CASCADE;
DROP FUNCTION IF EXISTS public.update_broker_totals(p_broker_id uuid, p_amount numeric) CASCADE;

-- Step 2: Recreate all functions with proper security settings (SET search_path).

/*
# [Function: has_users]
[Checks if any users exist in the auth.users table. Used for initial setup flow.]
*/
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;


/*
# [Function: handle_new_user]
[Creates a staff_profile entry when a new user signs up.]
*/
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


/*
# [Function: delete_user_and_profile]
[Deletes a user from auth.users and their corresponding staff_profile.]
*/
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = public;
  -- First, delete the user from the auth.users table.
  -- The corresponding profile in public.staff_profiles will be deleted by the CASCADE constraint.
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;


/*
# [Function: calculate_broker_commission]
[Calculates the commission amount for a given car.]
*/
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission numeric;
  v_car public.cars;
BEGIN
  SET search_path = public;
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;
  
  IF v_car.broker_commission_type = 'percentage' THEN
    v_commission := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  ELSE
    v_commission := v_car.broker_commission_value;
  END IF;
  
  RETURN v_commission;
END;
$$;

/*
# [Function: update_broker_commissions_on_car_insert]
[Creates a commission record when a new car with a broker is inserted.]
*/
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  SET search_path = public;
  IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL THEN
    v_commission_amount := public.calculate_broker_commission(NEW.id);
    
    INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount)
    VALUES (NEW.broker_id, NEW.id, v_commission_amount);
  END IF;
  RETURN NEW;
END;
$$;

/*
# [Function: update_broker_commissions_on_car_update]
[Updates or creates a commission record when a car's broker info is updated.]
*/
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  SET search_path = public;
  -- Check if broker details have changed
  IF OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value THEN
    -- Delete existing commission record for this car if it exists
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id;

    -- If a new broker is assigned, create a new commission record
    IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL THEN
      v_commission_amount := public.calculate_broker_commission(NEW.id);
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

/*
# [Function: update_broker_totals]
[Updates the total commission due and paid for a broker.]
*/
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
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


-- Step 3: Recreate all triggers.

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_insert_trigger
  AFTER INSERT ON public.cars
  FOR EACH ROW
  EXECUTE FUNCTION public.update_broker_commissions_on_car_insert();

CREATE TRIGGER on_car_update_trigger
  AFTER UPDATE ON public.cars
  FOR EACH ROW
  WHEN (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value)
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
