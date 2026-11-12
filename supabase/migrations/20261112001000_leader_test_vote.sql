-- TEMPORARY testing aid: the trip leader may set RSVPs on behalf of any member of the trip,
-- so one person can test a whole group without switching accounts.
-- To remove: re-create the three policies below with only `user_id = (select auth.uid())`.
drop policy reactions_insert on public.reactions;
drop policy reactions_update on public.reactions;
drop policy reactions_delete on public.reactions;

create policy reactions_insert on public.reactions for insert to authenticated
  with check (
    public.is_trip_member(trip_id)
    and (
      user_id = (select auth.uid())
      or (public.is_trip_leader(trip_id)
          and exists (select 1 from public.trip_members m where m.trip_id = reactions.trip_id and m.user_id = reactions.user_id))
    )
  );
create policy reactions_update on public.reactions for update to authenticated
  using (public.is_trip_member(trip_id) and (user_id = (select auth.uid()) or public.is_trip_leader(trip_id)))
  with check (
    public.is_trip_member(trip_id)
    and (
      user_id = (select auth.uid())
      or (public.is_trip_leader(trip_id)
          and exists (select 1 from public.trip_members m where m.trip_id = reactions.trip_id and m.user_id = reactions.user_id))
    )
  );
create policy reactions_delete on public.reactions for delete to authenticated
  using (public.is_trip_member(trip_id) and (user_id = (select auth.uid()) or public.is_trip_leader(trip_id)));
