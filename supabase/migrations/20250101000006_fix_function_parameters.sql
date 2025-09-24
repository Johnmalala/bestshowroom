/*
          # [Fix] Correct Function Definitions and Parameters
          [This migration script corrects the definitions of several database functions to resolve a migration error related to changing function parameter names. It safely drops and recreates all custom functions to ensure they are up-to-date and have the correct, secure definitions.]

          ## Query Description: [This operation is safe and will not affect any existing data. It drops and recreates several custom database functions (calculate_broker_commission, update_broker_commissions_on_car_update, update_car_status_on_payment, delete_user_and_profile, has_users) and their associated triggers. By using 'DROP IF EXISTS', the script ensures it can run successfully even if the functions were not created or were created incorrectly in a previous step. This resolves the 'cannot change name of input parameter' error and hardens security by setting a fixed search_path for each function.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Functions Affected:
            - public.calculate_broker_commission(uuid)
            - public.update_broker_commissions_on_car_update()
            - public.update_car_status_on_payment()
            - public.delete_user_and_profile(uuid)
            - public.has_users()
          - Triggers Affected:
            - on_car_update_for_commission
            - on_payment_for_car_status
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [No Change]
          - Security Hardening: All functions will have their search_path explicitly set to prevent search path hijacking attacks.
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. This is a one-time structural change.]
          */

-- Drop existing functions and triggers if they exist to prevent conflicts
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP TRIGGER IF EXISTS on_car_update_for_commission ON public.cars;
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP TRIGGER IF EXISTS on_payment_for_car_status ON public.payments;
DROP FUNCTION IF EXISTS public.update_car_status_on_payment();
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.has_users();

-- Recreate function to calculate broker commission
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_car record;
    v_commission numeric;
BEGIN
    SELECT purchase_price, broker_commission_type, broker_commission_value
    INTO v_car
    FROM public.cars
    WHERE id = p_car_id;

    IF v_car IS NULL OR v_car.broker_commission_value IS NULL THEN
        RETURN 0;
    END IF;

    IF v_car.broker_commission_type = 'percentage' THEN
        v_commission := (v_car.purchase_price * v_car.broker_commission_value) / 100;
    ELSE -- fixed
        v_commission := v_car.broker_commission_value;
    END IF;

    RETURN v_commission;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission(uuid) SET search_path = '';

-- Recreate function and trigger for updating broker commissions when a car is updated
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_commission_amount numeric;
BEGIN
    IF (OLD.broker_id IS DISTINCT FROM NEW.broker_id OR OLD.status IS DISTINCT FROM NEW.status) AND NEW.status = 'sold' AND NEW.broker_id IS NOT NULL THEN
        -- Calculate commission
        v_commission_amount := public.calculate_broker_commission(NEW.id);

        -- Insert or update commission record
        INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
        VALUES (NEW.broker_id, NEW.id, v_commission_amount, false)
        ON CONFLICT (car_id) DO UPDATE
        SET broker_id = EXCLUDED.broker_id,
            commission_amount = EXCLUDED.commission_amount,
            is_paid = false; -- Reset payment status if broker/car details change
    END IF;
    RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = '';

CREATE TRIGGER on_car_update_for_commission
AFTER UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();

-- Recreate function and trigger to update car status on full payment
CREATE OR REPLACE FUNCTION public.update_car_status_on_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.payment_type = 'full_purchase' AND NEW.car_id IS NOT NULL THEN
        UPDATE public.cars
        SET status = 'sold'
        WHERE id = NEW.car_id;
    END IF;
    RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_car_status_on_payment() SET search_path = '';

CREATE TRIGGER on_payment_for_car_status
AFTER INSERT ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.update_car_status_on_payment();

-- Recreate function to delete a user and their profile (callable by owner)
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Must be called by an authenticated user who is an owner
    IF auth.uid() IS NULL OR (SELECT role FROM public.staff_profiles WHERE id = auth.uid()) <> 'owner' THEN
        RAISE EXCEPTION 'Only owners can delete users.';
    END IF;

    -- Delete from auth.users table
    DELETE FROM auth.users WHERE id = user_id_to_delete;
    -- The trigger on auth.users will handle deleting the staff_profile
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) SET search_path = '';

-- Recreate function to check if any users exist (for initial setup)
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;
ALTER FUNCTION public.has_users() SET search_path = '';
