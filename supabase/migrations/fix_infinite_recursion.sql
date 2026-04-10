-- Drop the recursive policy from deliveries
DROP POLICY IF EXISTS "deliveries: motoboy vê pendentes" ON public.deliveries;

-- Recreate it using `users` table instead of `motoboys` to break the infinite recursion cycle
CREATE POLICY "deliveries: motoboy vê pendentes"
  ON public.deliveries FOR SELECT
  USING (
    status = 'pending'
    AND auth.uid() IN (SELECT id FROM public.users WHERE role = 'motoboy')
  );
