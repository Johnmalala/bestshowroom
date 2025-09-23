/*
# [Function] handle_new_user
[This function creates a new staff profile when a new user signs up in Supabase Auth.]

## Query Description: [This operation redefines the handle_new_user function to set a secure search_path, mitigating potential security risks. It does not alter existing data but ensures future user creations are handled more securely.]

## Metadata:
- Schema-Category: ["Security"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Function: public.handle_new_user()

## Security Implications:
- RLS Status: [N/A]
- Policy Changes: [No]
- Auth Requirements: [N/A]

## Performance Impact:
- Indexes: [N/A]
- Triggers: [N/A]
- Estimated Impact: [None]
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
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

/*
# [Function] update_car_status_on_payment
[This function updates the car status to 'sold' when a 'full_purchase' payment is recorded.]

## Query Description: [This operation redefines the update_car_status_on_payment function to set a secure search_path. This enhances security without changing the function's core logic or affecting existing data.]

## Metadata:
- Schema-Category: ["Security"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Function: public.update_car_status_on_payment()

## Security Implications:
- RLS Status: [N/A]
- Policy Changes: [No]
- Auth Requirements: [N/A]

## Performance Impact:
- Indexes: [N/A]
- Triggers: [N/A]
- Estimated Impact: [None]
*/
CREATE OR REPLACE FUNCTION public.update_car_status_on_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new.payment_type = 'full_purchase' AND new.car_id IS NOT NULL THEN
    UPDATE public.cars
    SET status = 'sold'
    WHERE id = new.car_id;
  END IF;
  RETURN new;
END;
$$;

/*
# [Function] calculate_broker_commission
[This function calculates and inserts a broker commission record when a car with a broker is marked as 'sold'.]

## Query Description: [This operation redefines the calculate_broker_commission function to set a secure search_path, preventing potential security vulnerabilities. The function's behavior remains the same, and no existing data is modified.]

## Metadata:
- Schema-Category: ["Security"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Function: public.calculate_broker_commission()

## Security Implications:
- RLS Status: [N/A]
- Policy Changes: [No]
- Auth Requirements: [N/A]

## Performance Impact:
- Indexes: [N/A]
- Triggers: [N/A]
- Estimated Impact: [None]
*/
CREATE OR REPLACE FUNCTION public.calculate_broker_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  commission_amt numeric;
BEGIN
  IF new.status = 'sold' AND old.status = 'available' AND new.broker_id IS NOT NULL AND new.broker_commission_value IS NOT NULL THEN
    IF new.broker_commission_type = 'percentage' THEN
      commission_amt := (new.purchase_price * new.broker_commission_value) / 100;
    ELSE -- fixed
      commission_amt := new.broker_commission_value;
    END IF;

    INSERT INTO public.broker_commissions (broker_id, car_id, commission_amount)
    VALUES (new.broker_id, new.id, commission_amt);
  END IF;
  RETURN new;
END;
$$;
