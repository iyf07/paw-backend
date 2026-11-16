-- Accepted friends may read dog profiles even without a shared trip.
-- Existing owner-only INSERT/UPDATE/DELETE policies remain unchanged.
create policy dogs_select_accepted_friends on public.dogs
for select to authenticated
using (public.is_accepted_buddy(owner_id));
