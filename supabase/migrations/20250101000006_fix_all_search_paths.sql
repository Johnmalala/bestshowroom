/*
          # [SECURITY FIX] Set Secure Search Path for All Functions
          [This migration hardens the database by explicitly setting the search_path for all user-defined functions. This resolves the "Function Search Path Mutable" security advisory by preventing potential privilege escalation attacks where a malicious user could temporarily alter the search path to execute code with elevated permissions.]

          ## Query Description: [This operation redefines all existing database functions to include `SET search_path = public`. It is a safe, non-destructive operation that enhances security without affecting data or core functionality. It drops and recreates the associated triggers to ensure they are linked to the updated functions.]
          
          ## Metadata:
          - Schema-Category: ["Safe", "Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions affected: `calculate_broker_commission`, `handle_new_user`, `has_users`, `update_broker_commissions_on_car_update`
          - Triggers affected: `on_car_update_trigger`, `on_auth_user_created`
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          - Mitigates: "Function Search Path Mutable" warning.
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible performance impact. This is a one-time security update.]
*/

-- Drop existing triggers before redefining functions
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Redefine function: calculate_broker_commission
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(car_id_param uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    car_record RECORD;
    commission_amount NUMERIC;
BEGIN
    SELECT * INTO car_record FROM cars WHERE id = car_id_param;

    IF car_record.broker_id IS NULL OR car_record.broker_commission_value IS NULL THEN
        RETURN 0;
    END IF;

    IF car_record.broker_commission_type = 'percentage' THEN
        commission_amount := (car_record.purchase_price * car_record.broker_commission_value) / 100;
    ELSE
        commission_amount := car_record.broker_commission_value;
    END IF;

    RETURN commission_amount;
END;
$$;

-- Redefine function: handle_new_user
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

-- Redefine function: has_users
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

-- Redefine function: update_broker_commissions_on_car_update
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    commission_val NUMERIC;
BEGIN
    -- Check if the car status has been changed to 'sold'
    IF NEW.status = 'sold' AND OLD.status = 'available' AND NEW.broker_id IS NOT NULL THEN
        -- Calculate the commission
        commission_val := public.calculate_broker_commission(NEW.id);

        IF commission_val > 0 THEN
            -- Insert a new record into broker_commissions
            INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount, is_paid)
            VALUES (NEW.broker_id, NEW.id, commission_val, false);

            -- Update the broker's total_commission_due
            UPDATE public.brokers
            SET total_commission_due = total_commission_due + commission_val
            WHERE id = NEW.broker_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

-- Recreate triggers with the updated functions
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_car_update_trigger
AFTER UPDATE ON public.cars
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
