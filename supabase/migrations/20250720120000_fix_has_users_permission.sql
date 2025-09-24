/*
# [Function Update] Fix has_users permission
[This operation updates the 'has_users' function to run with definer-level security privileges. This is necessary to allow the function to check for the existence of users in the 'auth.users' table, which is normally restricted.]

## Query Description: [This query modifies the 'has_users' function to include the 'SECURITY DEFINER' clause. This allows the function to execute with the permissions of the user who defined it (the owner), rather than the user who calls it (an anonymous user). This is a safe and standard practice for checking system tables like 'auth.users' without granting broad permissions to anonymous users. There is no risk to existing data.]

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function affected: public.has_users()

## Security Implications:
- RLS Status: Not applicable
- Policy Changes: No
- Auth Requirements: This change is required for the initial auth setup flow to work correctly. It resolves a 'permission denied' error.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible.
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
