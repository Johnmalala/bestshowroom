/*
# [Create has_users function & Secure Existing Functions]
This migration accomplishes two things:
1. It creates a new `has_users()` SQL function to check if any staff members exist. This is essential for the application's new initial setup flow.
2. It secures existing database functions by setting a fixed `search_path`, which mitigates the "Function Search Path Mutable" security warning.

## Query Description: [This is a safe, low-risk operation. It adds one new read-only function and modifies the definition of four existing functions to make them more secure. It does not alter any table data. Applying this change is recommended for security and to enable the initial user setup feature.]

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Creates function: public.has_users()
- Modifies function: public.handle_new_user()
- Modifies function: public.update_broker_commissions_on_car_update()
- Modifies function: public.calculate_commission_on_car_insert()
- Modifies function: public.update_car_status_on_payment()

## Security Implications:
- RLS Status: [N/A]
- Policy Changes: [No]
- Auth Requirements: [The has_users() function is granted to the 'anon' role.]
- Fixes security warning: "Function Search Path Mutable"

## Performance Impact:
- Indexes: [N/A]
- Triggers: [N/A]
- Estimated Impact: [None]
*/

-- Secure existing functions
ALTER FUNCTION public.handle_new_user() SET search_path = public;
ALTER FUNCTION public.update_broker_commissions_on_car_update() SET search_path = public;
ALTER FUNCTION public.calculate_commission_on_car_insert() SET search_path = public;
ALTER FUNCTION public.update_car_status_on_payment() SET search_path = public;

-- Create function for setup check
CREATE OR REPLACE FUNCTION public.has_users()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT EXISTS (SELECT 1 FROM public.staff_profiles);
$$;

-- Grant execute permission to anon and authenticated roles
GRANT EXECUTE ON FUNCTION public.has_users() TO anon;
GRANT EXECUTE ON FUNCTION public.has_users() TO authenticated;
