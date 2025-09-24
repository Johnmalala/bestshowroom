/*
          # [Function] `calculate_broker_commission`
          [This function calculates the commission for a car sale based on its price and the broker's commission type/value.]

          ## Query Description: [This operation safely drops and recreates the function to add a secure search_path, preventing potential SQL injection vectors. It has no impact on existing data.]
          
          ## Metadata:
          - Schema-Category: ["Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Function: `public.calculate_broker_commission`
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [N/A]
          - Triggers: [N/A]
          - Estimated Impact: [None]
          */
DROP FUNCTION IF EXISTS public.calculate_broker_commission(p_car_id uuid);
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission numeric;
  v_car record;
BEGIN
  SET search_path = 'public';
  
  SELECT purchase_price, broker_commission_type, broker_commission_value 
  INTO v_car
  FROM cars
  WHERE id = p_car_id;

  IF v_car.broker_commission_type IS NULL OR v_car.broker_commission_value IS NULL THEN
    RETURN 0;
  END IF;

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

/*
          # [Trigger & Function] `on_car_update_trigger` & `update_broker_commissions_on_car_update`
          [This trigger automatically creates or updates a broker commission record when a car's status is changed to 'sold'.]

          ## Query Description: [This operation safely drops the dependent trigger, then drops and recreates the function with a secure search_path, and finally recreates the trigger. This prevents SQL injection risks and has no impact on existing data.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Trigger: `on_car_update_trigger` on `public.cars`
          - Function: `public.update_broker_commissions_on_car_update`
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [N/A]
          - Triggers: [Modified]
          - Estimated Impact: [Negligible]
          */
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_commission_amount numeric;
BEGIN
    SET search_path = 'public';

    -- Check if the car status is updated to 'sold' and it has a broker
    IF NEW.status = 'sold' AND OLD.status <> 'sold' AND NEW.broker_id IS NOT NULL THEN
        -- Calculate commission
        v_commission_amount := calculate_broker_commission(NEW.id);

        IF v_commission_amount > 0 THEN
            -- Insert a new commission record
            INSERT INTO broker_commissions (broker_id, car_id, commission_amount, is_paid)
            VALUES (NEW.broker_id, NEW.id, v_commission_amount, false);

            -- Update the broker's total due amount
            UPDATE brokers
            SET total_commission_due = total_commission_due + v_commission_amount
            WHERE id = NEW.broker_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_car_update_trigger
AFTER UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();


/*
          # [Function] `update_broker_totals`
          [This function updates the total_commission_paid and total_commission_due for a broker when a commission is paid.]

          ## Query Description: [This operation safely drops and recreates the function to add a secure search_path, preventing potential SQL injection vectors. It has no impact on existing data.]
          
          ## Metadata:
          - Schema-Category: ["Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Function: `public.update_broker_totals`
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [N/A]
          - Triggers: [N/A]
          - Estimated Impact: [None]
          */
DROP FUNCTION IF EXISTS public.update_broker_totals(p_broker_id uuid, p_amount numeric);
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  SET search_path = 'public';
  UPDATE brokers
  SET 
    total_commission_paid = total_commission_paid + p_amount,
    total_commission_due = total_commission_due - p_amount
  WHERE id = p_broker_id;
END;
$$;

/*
          # [Function] `has_users`
          [This function checks if any users exist in the auth.users table, used for the initial setup flow.]

          ## Query Description: [This operation safely drops and recreates the function with SECURITY DEFINER and a secure search_path. This allows an anonymous user to safely check for the existence of any user without being able to read user data, fixing a permission error.]
          
          ## Metadata:
          - Schema-Category: ["Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Function: `public.has_users`
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [Uses SECURITY DEFINER to bypass RLS for a specific, safe check.]
          
          ## Performance Impact:
          - Indexes: [N/A]
          - Triggers: [N/A]
          - Estimated Impact: [None]
          */
DROP FUNCTION IF EXISTS public.has_users();
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'auth';
  RETURN EXISTS (SELECT 1 FROM users);
END;
$$;

/*
          # [Function] `delete_user_and_profile`
          [This function allows an owner to delete a staff member's auth account and their corresponding profile record.]

          ## Query Description: [This operation safely drops and recreates the function with SECURITY DEFINER and a secure search_path. This allows an authenticated owner to delete a user from the protected auth.users table.]
          
          ## Metadata:
          - Schema-Category: ["Dangerous"]
          - Impact-Level: ["High"]
          - Requires-Backup: [true]
          - Reversible: [false]
          
          ## Structure Details:
          - Function: `public.delete_user_and_profile`
          
          ## Security Implications:
          - RLS Status: [N/A]
          - Policy Changes: [No]
          - Auth Requirements: [Uses SECURITY DEFINER. Should only be callable by an 'owner' role via RLS on the function itself or through application logic.]
          
          ## Performance Impact:
          - Indexes: [N/A]
          - Triggers: [N/A]
          - Estimated Impact: [None]
          */
DROP FUNCTION IF EXISTS public.delete_user_and_profile(user_id_to_delete uuid);
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'auth', 'public';
  
  -- Check if the calling user is an owner
  IF (SELECT role FROM public.staff_profiles WHERE id = auth.uid()) <> 'owner' THEN
    RAISE EXCEPTION 'Only owners can delete users.';
  END IF;

  -- Delete from auth.users, which will cascade to staff_profiles
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;
