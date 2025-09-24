/*
  # [Fix] Correct Function Definitions and Search Paths

  [This migration corrects an issue from a previous script that failed when trying to drop a non-existent function. It safely drops and recreates all trigger and utility functions using `IF EXISTS` to prevent errors. It also ensures all functions have their `search_path` set to an empty string to address security warnings.]

  ## Query Description: [This script will safely redefine several database functions. It first attempts to drop the existing versions and then creates them with updated security settings. There is no risk to existing data as this only affects function definitions.]
  
  ## Metadata:
  - Schema-Category: ["Structural", "Safe"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [false]
  
  ## Structure Details:
  - Drops and recreates the following functions:
    - `handle_new_user`
    - `update_broker_commissions_on_car_update`
    - `update_car_status_on_payment`
    - `calculate_broker_commission_on_insert`
    - `has_users`
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [None]
  - Mitigates "Function Search Path Mutable" warnings by explicitly setting `search_path`.
  
  ## Performance Impact:
  - Indexes: [None]
  - Triggers: [Functions are used by triggers, but the logic remains the same.]
  - Estimated Impact: [Negligible. A one-time redefinition of functions.]
*/

-- Drop existing functions safely
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.update_car_status_on_payment();
DROP FUNCTION IF EXISTS public.calculate_broker_commission_on_insert();
DROP FUNCTION IF EXISTS public.has_users();

-- Recreate function to handle new user and create a profile
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
ALTER FUNCTION public.handle_new_user() SET search_path = '';

-- Recreate function to update car status on full payment
CREATE OR REPLACE FUNCTION public.update_car_status_on_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.payment_type = 'full_purchase' THEN
    UPDATE public.cars
    SET status = 'sold'
    WHERE id = NEW.car_id;
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_car_status_on_payment() SET search_path = '';

-- Recreate function to calculate broker commission when a car is updated to 'sold'
CREATE OR REPLACE FUNCTION public.calculate_broker_commission_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  commission_val NUMERIC;
BEGIN
  -- Only calculate if the car is being marked as 'sold' and has a broker
  IF NEW.status = 'sold' AND OLD.status = 'available' AND NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL THEN
    IF NEW.broker_commission_type = 'percentage' THEN
      commission_val := (NEW.purchase_price * NEW.broker_commission_value) / 100;
    ELSE -- 'fixed'
      commission_val := NEW.broker_commission_value;
    END IF;

    -- Insert into broker_commissions table
    INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
    VALUES (NEW.broker_id, NEW.id, commission_val, false);
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission_on_insert() SET search_path = '';

-- Recreate function to update broker commission if car details change
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  commission_val NUMERIC;
BEGIN
  -- Check if broker details or price changed
  IF OLD.broker_id IS DISTINCT FROM NEW.broker_id OR
     OLD.broker_commission_type IS DISTINCT FROM NEW.broker_commission_type OR
     OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value OR
     OLD.purchase_price IS DISTINCT FROM NEW.purchase_price THEN

    -- Delete existing unpaid commission for this car
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id AND is_paid = false;

    -- If car is sold and has a new broker config, create a new commission record
    IF NEW.status = 'sold' AND NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL THEN
      IF NEW.broker_commission_type = 'percentage' THEN
        commission_val := (NEW.purchase_price * NEW.broker_commission_value) / 100;
      ELSE -- 'fixed'
        commission_val := NEW.broker_commission_value;
      END IF;

      INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
      VALUES (NEW.broker_id, NEW.id, commission_val, false);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = '';

-- Recreate function to check if any users exist in the system
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;
ALTER FUNCTION public.has_users() SET search_path = '';
