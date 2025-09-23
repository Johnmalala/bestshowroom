/*
# [Security Fix] Set Function Search Path
This migration fixes a security warning by explicitly setting the `search_path` for database functions. This prevents potential hijacking attacks by ensuring functions only search for objects within the 'public' schema.

## Query Description: This operation alters existing database functions to make them more secure. It does not modify any data or table structures. There is no risk to existing data.

## Metadata:
- Schema-Category: ["Safe", "Security"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true (by removing the SET clause)

## Structure Details:
- Functions affected:
  - handle_new_user()
  - update_car_status_on_payment()
  - calculate_broker_commission()
  - update_broker_totals_on_commission_change()

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- Mitigates: "Function Search Path Mutable" warning.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible performance impact.
*/

ALTER FUNCTION public.handle_new_user() SET search_path = 'public';
ALTER FUNCTION public.update_car_status_on_payment() SET search_path = 'public';
ALTER FUNCTION public.calculate_broker_commission() SET search_path = 'public';
ALTER FUNCTION public.update_broker_totals_on_commission_change() SET search_path = 'public';
