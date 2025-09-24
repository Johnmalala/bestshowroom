/*
# [Fix has_users Function Permissions]
This migration updates the `has_users` function to run with `SECURITY DEFINER` privileges. This is necessary to allow the application to check if any users exist in the `auth.users` table without granting direct read access to anonymous users, resolving a "permission denied" error on initial application load.

## Query Description: [This operation modifies a database function to enhance security. It allows the function to temporarily use the definer's permissions to check for the existence of users, which is a safe and standard practice for this type of check. There is no impact on existing data.]

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Modifies function: `public.has_users()`

## Security Implications:
- RLS Status: [Not Applicable]
- Policy Changes: [No]
- Auth Requirements: [The function will now run with definer privileges, which is a deliberate security enhancement to avoid exposing `auth.users`.]

## Performance Impact:
- Indexes: [No change]
- Triggers: [No change]
- Estimated Impact: [None]
*/
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
