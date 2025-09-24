-- Drop dependent triggers first
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;

-- Now, safely drop all custom functions
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.has_users();

/*
# [Recreate Function: has_users]
[This function checks if any users exist in the auth.users table. It is used for the initial setup flow.]

## Query Description: [Recreates the has_users function with SECURITY DEFINER to allow an anonymous user to check for the existence of any user, which is necessary for the initial setup screen to appear correctly. This is safe as it only returns a boolean and exposes no user data.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Security Implications:
- RLS Status: [Not Applicable]
- Policy Changes: [No]
- Auth Requirements: [Runs with definer's rights]
*/
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- SET search_path = 'auth'; -- This is not needed with SECURITY DEFINER and can cause issues. The object is schema-qualified.
  RETURN EXISTS (SELECT 1 FROM auth.users);
END;
$$;
-- Reset ownership to the appropriate role
ALTER FUNCTION public.has_users() OWNER TO postgres;
-- Grant execute permission to the anon role so it can be called
GRANT EXECUTE ON FUNCTION public.has_users() TO anon;


/*
# [Recreate Function: delete_user_and_profile]
[Deletes a user from auth.users and their corresponding profile from public.staff_profiles.]

## Query Description: [Recreates the function to allow an authenticated user (specifically the owner) to delete other users. It runs with SECURITY DEFINER to get the necessary permissions on the auth.users table. This is a privileged operation.]

## Metadata:
- Schema-Category: ["Dangerous"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Security Implications:
- RLS Status: [Bypassed for auth.users]
- Policy Changes: [No]
- Auth Requirements: [Runs with definer's rights, should be called by owner]
*/
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
  -- First, delete from the public staff_profiles table
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  -- Then, delete the user from the auth.users table
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.delete_user_and_profile(uuid) TO authenticated;


/*
# [Recreate Function: update_broker_totals]
[Updates the total commission due and paid for a broker.]

## Query Description: [Recreates the function to update broker totals. It's a standard data manipulation function.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [true]

## Security Implications:
- RLS Status: [Enabled on target table]
- Policy Changes: [No]
- Auth Requirements: [Authenticated user]
*/
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
ALTER FUNCTION public.update_broker_totals(uuid, numeric) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.update_broker_totals(uuid, numeric) TO authenticated;


/*
# [Recreate Function: update_broker_commissions_on_car_update]
[Creates or updates a broker commission record when a car is updated.]

## Query Description: [Recreates the function that calculates and inserts/updates broker commissions. This is triggered when a car's details are changed.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [true]

## Security Implications:
- RLS Status: [Enabled on target table]
- Policy Changes: [No]
- Auth Requirements: [Trigger function]
*/
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  commission_val numeric;
BEGIN
  SET search_path = 'public';
  -- Only proceed if a broker is assigned and commission details are present
  IF NEW.broker_id IS NOT NULL AND NEW.broker_commission_value IS NOT NULL AND NEW.broker_commission_value > 0 THEN
    -- Calculate commission amount
    IF NEW.broker_commission_type = 'percentage' THEN
      commission_val := NEW.purchase_price * (NEW.broker_commission_value / 100.0);
    ELSE -- fixed
      commission_val := NEW.broker_commission_value;
    END IF;

    -- Upsert into broker_commissions table
    INSERT INTO broker_commissions (broker_id, car_id, commission_amount, is_paid)
    VALUES (NEW.broker_id, NEW.id, commission_val, false)
    ON CONFLICT (car_id)
    DO UPDATE SET
      broker_id = EXCLUDED.broker_id,
      commission_amount = EXCLUDED.commission_amount,
      is_paid = false, -- Reset payment status if commission changes
      paid_date = NULL;
  ELSE
    -- If broker is removed or commission is set to 0, delete the commission record
    DELETE FROM broker_commissions WHERE car_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() OWNER TO postgres;

-- Finally, recreate the trigger that was dropped
CREATE TRIGGER on_car_update_trigger
AFTER INSERT OR UPDATE ON public.cars
FOR EACH ROW
EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
