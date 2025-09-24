/*
          # [Function Security Hardening]
          [This migration provides a comprehensive fix for all "Function Search Path Mutable" warnings by explicitly setting the search_path for each custom function. It also ensures all functions are created with the correct permissions and definitions.]

          ## Query Description: [This operation will safely drop and recreate all custom database functions to apply necessary security settings. It is designed to be non-destructive to your data and will resolve persistent security warnings.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions being replaced:
            - has_users()
            - calculate_broker_commission(uuid)
            - update_broker_commissions_on_car_update()
            - delete_user_and_profile(uuid)
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [admin]
          
          ## Performance Impact:
          - Indexes: [No change]
          - Triggers: [No change]
          - Estimated Impact: [Negligible. A one-time, quick re-creation of functions.]
          */

-- Drop existing functions if they exist to prevent conflicts
DROP FUNCTION IF EXISTS public.has_users();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);

-- Recreate has_users with security definer and fixed search path
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

-- Recreate calculate_broker_commission with fixed search path
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_commission_amount numeric;
  v_car record;
BEGIN
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;

  IF v_car.broker_commission_type IS NULL OR v_car.broker_commission_value IS NULL THEN
    RETURN 0;
  END IF;

  IF v_car.broker_commission_type = 'fixed' THEN
    v_commission_amount := v_car.broker_commission_value;
  ELSIF v_car.broker_commission_type = 'percentage' THEN
    v_commission_amount := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
  ELSE
    v_commission_amount := 0;
  END IF;

  RETURN v_commission_amount;
END;
$$;

-- Recreate update_broker_commissions_on_car_update trigger function with fixed search path
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  -- If the car is marked as sold and has a broker
  IF NEW.status = 'sold' AND OLD.status = 'available' AND NEW.broker_id IS NOT NULL THEN
    -- Calculate the commission
    v_commission_amount := public.calculate_broker_commission(NEW.id);

    -- If there's a commission to be paid, insert it into the commissions table
    IF v_commission_amount > 0 THEN
      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, v_commission_amount, false)
      ON CONFLICT (car_id) DO NOTHING; -- Prevent duplicate commission entries for the same car
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate delete_user_and_profile with security definer and fixed search path
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- First, delete from the public staff_profiles table
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  -- Then, delete the user from the auth.users table
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;

-- Grant execute permissions to the authenticated role for necessary functions
GRANT EXECUTE ON FUNCTION public.has_users() TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_broker_commission(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_and_profile(uuid) TO authenticated;
