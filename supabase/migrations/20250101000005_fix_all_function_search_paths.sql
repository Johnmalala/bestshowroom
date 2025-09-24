/*
          # [Function Security Hardening]
          [This migration hardens the security of all custom database functions by explicitly setting their search_path. This prevents potential context-switching attacks and resolves all "Function Search Path Mutable" security warnings.]

          ## Query Description: [This operation will safely drop and recreate all custom functions to apply a strict search_path. It is a non-destructive operation for your data, but it ensures that the functions operate in a more secure and predictable environment. No data will be lost.]
          
          ## Metadata:
          - Schema-Category: ["Security", "Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions being replaced:
            - `public.has_users()`
            - `public.delete_user_and_profile(uuid)`
            - `public.calculate_broker_commission(uuid)`
            - `public.update_broker_commissions_on_car_update()`
            - `public.update_broker_totals(uuid, numeric)`
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [No Change]
          - Fixes all "Function Search Path Mutable" warnings.
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [No Change]
          - Estimated Impact: [Negligible. Function logic remains the same, but execution context is secured.]
          */

-- Drop existing functions if they exist to prevent conflicts
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(user_id_to_delete uuid);
DROP FUNCTION IF EXISTS public.calculate_broker_commission(p_car_id uuid);
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.update_broker_totals(p_broker_id uuid, p_amount numeric);


-- Function to check if any users exist (for initial setup)
-- Runs with definer's privileges to securely check auth.users.
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
ALTER FUNCTION public.has_users() OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.has_users() TO anon, authenticated;


-- Function to delete a user and their corresponding staff profile
-- Must be called by an authenticated user with 'owner' role.
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  requesting_user_role text;
BEGIN
  -- Check if the requesting user is an owner
  SELECT raw_user_meta_data->>'role' INTO requesting_user_role
  FROM auth.users
  WHERE id = auth.uid();

  IF requesting_user_role = 'owner' THEN
    -- Delete from staff_profiles first
    DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
    -- Then delete from auth.users
    DELETE FROM auth.users WHERE id = user_id_to_delete;
  ELSE
    RAISE EXCEPTION 'Insufficient permissions. Only an owner can delete users.';
  END IF;
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.delete_user_and_profile(uuid) TO authenticated;


-- Function to calculate broker commission for a given car
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_commission_type text;
  v_commission_value numeric;
  v_purchase_price numeric;
  v_commission_amount numeric;
BEGIN
  SELECT
    broker_commission_type,
    broker_commission_value,
    purchase_price
  INTO
    v_commission_type,
    v_commission_value,
    v_purchase_price
  FROM public.cars
  WHERE id = p_car_id;

  IF v_commission_type IS NULL OR v_commission_value IS NULL THEN
    RETURN 0;
  END IF;

  IF v_commission_type = 'fixed' THEN
    v_commission_amount := v_commission_value;
  ELSIF v_commission_type = 'percentage' THEN
    v_commission_amount := (v_purchase_price * v_commission_value) / 100;
  ELSE
    v_commission_amount := 0;
  END IF;

  RETURN v_commission_amount;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.calculate_broker_commission(uuid) TO authenticated;


-- Function to update broker commissions when a car is updated
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  IF NEW.broker_id IS NOT NULL AND (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value OR OLD.purchase_price IS DISTINCT FROM NEW.purchase_price) THEN
    -- Calculate new commission
    v_commission_amount := public.calculate_broker_commission(NEW.id);

    -- Delete old commission if it exists
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id;

    -- Insert new commission record if amount > 0
    IF v_commission_amount > 0 THEN
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount, false);
    END IF;
  ELSIF NEW.broker_id IS NULL AND OLD.broker_id IS NOT NULL THEN
    -- If broker is removed, delete the commission record
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() OWNER TO postgres;


-- Trigger to execute the function on car update
CREATE TRIGGER on_car_update_trigger
AFTER UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();


-- Function to update broker's total paid and due commissions
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
ALTER FUNCTION public.update_broker_totals(uuid, numeric) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.update_broker_totals(uuid, numeric) TO authenticated;
