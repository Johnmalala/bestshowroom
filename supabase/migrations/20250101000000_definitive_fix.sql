-- Comprehensive Migration to Fix All Trigger and Function Issues

-- Step 1: Drop existing triggers to remove dependencies
DROP TRIGGER IF EXISTS on_car_update_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_car_insert_trigger ON public.cars;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop existing functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_broker_commissions_on_car_update();
DROP FUNCTION IF EXISTS public.calculate_broker_commission(uuid);
DROP FUNCTION IF EXISTS public.delete_user_and_profile(uuid);
DROP FUNCTION IF EXISTS public.update_broker_totals(uuid, numeric);
DROP FUNCTION IF EXISTS public.has_users();

-- Step 3: Recreate all functions with correct definitions and security settings

/*
# [Function] has_users
Checks if any users exist in the auth.users table.
SECURITY DEFINER is required to allow anonymous access for the initial setup check.
*/
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SET search_path = public;
  SELECT EXISTS (SELECT 1 FROM auth.users);
$$;

/*
# [Function] handle_new_user
Creates a corresponding profile in public.staff_profiles when a new user signs up.
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.staff_profiles (id, full_name, phone_number, role, created_by)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'phone_number',
    (NEW.raw_user_meta_data->>'role')::public.user_role,
    (NEW.raw_user_meta_data->>'created_by')::uuid
  );
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.handle_new_user() SET search_path = public;

/*
# [Function] calculate_broker_commission
Calculates the commission amount for a given car.
*/
CREATE OR REPLACE FUNCTION public.calculate_broker_commission(p_car_id uuid)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_car public.cars;
  v_commission_amount numeric := 0;
BEGIN
  SELECT * INTO v_car FROM public.cars WHERE id = p_car_id;

  IF v_car.broker_id IS NOT NULL AND v_car.broker_commission_value IS NOT NULL AND v_car.broker_commission_value > 0 THEN
    IF v_car.broker_commission_type = 'fixed' THEN
      v_commission_amount := v_car.broker_commission_value;
    ELSIF v_car.broker_commission_type = 'percentage' THEN
      v_commission_amount := v_car.purchase_price * (v_car.broker_commission_value / 100.0);
    END IF;
  END IF;

  RETURN v_commission_amount;
END;
$$;
ALTER FUNCTION public.calculate_broker_commission(uuid) SET search_path = public;

/*
# [Function] update_broker_commissions_on_car_update
Trigger function to create or update a broker commission record when a car is inserted or updated.
*/
CREATE OR REPLACE FUNCTION public.update_broker_commissions_on_car_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_commission_amount numeric;
BEGIN
  -- Calculate commission for the new/updated car state
  v_commission_amount := public.calculate_broker_commission(NEW.id);

  -- If there's a broker and a commission is calculated
  IF NEW.broker_id IS NOT NULL AND v_commission_amount > 0 THEN
    -- Upsert the commission record
    INSERT INTO public.broker_commissions (car_id, broker_id, commission_amount, is_paid)
    VALUES (NEW.id, NEW.broker_id, v_commission_amount, false)
    ON CONFLICT (car_id)
    DO UPDATE SET
      broker_id = EXCLUDED.broker_id,
      commission_amount = EXCLUDED.commission_amount,
      is_paid = false, -- Reset payment status if commission changes
      paid_date = NULL;
  ELSE
    -- If no broker or no commission, delete any existing commission record for this car
    DELETE FROM public.broker_commissions WHERE car_id = NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = public;


/*
# [Function] update_broker_totals
RPC to update broker's total commission due and paid.
*/
CREATE OR REPLACE FUNCTION public.update_broker_totals(p_broker_id uuid, p_amount numeric)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE public.brokers
  SET
    total_commission_due = total_commission_due - p_amount,
    total_commission_paid = total_commission_paid + p_amount
  WHERE id = p_broker_id;
END;
$$;
ALTER FUNCTION public.update_broker_totals(uuid, numeric) SET search_path = public;


/*
# [Function] delete_user_and_profile
Deletes a user from auth.users and their corresponding staff_profile.
Requires SECURITY DEFINER to perform actions as an admin.
*/
CREATE OR REPLACE FUNCTION public.delete_user_and_profile(user_id_to_delete uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Check if the requesting user is an owner
  IF (SELECT role FROM public.staff_profiles WHERE id = auth.uid()) <> 'owner' THEN
    RAISE EXCEPTION 'Only owners can delete users.';
  END IF;

  -- Delete from staff_profiles first
  DELETE FROM public.staff_profiles WHERE id = user_id_to_delete;
  -- Then delete from auth.users
  DELETE FROM auth.users WHERE id = user_id_to_delete;
END;
$$;
ALTER FUNCTION public.delete_user_and_profile(uuid) SET search_path = public;


-- Step 4: Recreate triggers with correct definitions

-- Trigger for new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger for car INSERTION
CREATE TRIGGER on_car_insert_trigger
  AFTER INSERT ON public.cars
  FOR EACH ROW
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();

-- Trigger for car UPDATE
CREATE TRIGGER on_car_update_trigger
  AFTER UPDATE ON public.cars
  FOR EACH ROW
  WHEN (
    OLD.broker_id IS DISTINCT FROM NEW.broker_id OR
    OLD.broker_commission_type IS DISTINCT FROM NEW.broker_commission_type OR
    OLD.broker_commission_value IS DISTINCT FROM NEW.broker_commission_value OR
    OLD.purchase_price IS DISTINCT FROM NEW.purchase_price
  )
  EXECUTE FUNCTION public.update_broker_commissions_on_car_update();
