-- Fixes from `supabase db advisors`:
--  1. trigger-only SECURITY DEFINER functions must not be callable through the REST API
--  2. wrap auth.uid() in (select ...) so Postgres evaluates it once per statement, not once per row
--  3. no overlapping permissive policies (split "for all" into per-command policies)
-- The remaining "authenticated can execute" warnings are intentional: RLS helpers and the invite RPCs.

-- 1 ---------------------------------------------------------------------------------------------
revoke execute on function public.handle_new_user(), public.add_creator_as_member(), public.on_member_left()
  from public, anon, authenticated;

-- 2 + 3 -----------------------------------------------------------------------------------------
drop policy profiles_select on public.profiles;
drop policy profiles_insert on public.profiles;
drop policy profiles_update on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or public.shares_trip_with(id));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy user_settings_all on public.user_settings;
create policy user_settings_all on public.user_settings for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy dogs_select on public.dogs;
drop policy dogs_insert on public.dogs;
drop policy dogs_update on public.dogs;
drop policy dogs_delete on public.dogs;
create policy dogs_select on public.dogs for select to authenticated
  using (owner_id = (select auth.uid()) or public.shares_trip_with(owner_id));
create policy dogs_insert on public.dogs for insert to authenticated
  with check (owner_id = (select auth.uid()));
create policy dogs_update on public.dogs for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy dogs_delete on public.dogs for delete to authenticated
  using (owner_id = (select auth.uid()));

drop policy trips_select on public.trips;
drop policy trips_insert on public.trips;
drop policy trips_update on public.trips;
drop policy trips_delete on public.trips;
create policy trips_select on public.trips for select to authenticated
  using (creator_id = (select auth.uid()) or public.is_trip_member(id));
create policy trips_insert on public.trips for insert to authenticated
  with check (creator_id = (select auth.uid()));
create policy trips_update on public.trips for update to authenticated
  using (creator_id = (select auth.uid())) with check (creator_id = (select auth.uid()));
create policy trips_delete on public.trips for delete to authenticated
  using (creator_id = (select auth.uid()));

drop policy trip_members_leave on public.trip_members;
create policy trip_members_leave on public.trip_members for delete to authenticated
  using (user_id = (select auth.uid()) and not public.is_trip_leader(trip_id));

drop policy trip_dogs_insert on public.trip_dogs;
drop policy trip_dogs_delete on public.trip_dogs;
create policy trip_dogs_insert on public.trip_dogs for insert to authenticated
  with check (
    public.is_trip_member(trip_id)
    and exists (select 1 from public.dogs d where d.id = dog_id and d.owner_id = (select auth.uid()))
  );
create policy trip_dogs_delete on public.trip_dogs for delete to authenticated
  using (
    public.is_trip_leader(trip_id)
    or exists (select 1 from public.dogs d where d.id = dog_id and d.owner_id = (select auth.uid()))
  );

drop policy item_dogs_select on public.item_dogs;
drop policy item_dogs_write on public.item_dogs;
create policy item_dogs_select on public.item_dogs for select to authenticated
  using (public.is_trip_member(trip_id));
create policy item_dogs_insert on public.item_dogs for insert to authenticated
  with check (public.is_trip_member(trip_id));
create policy item_dogs_update on public.item_dogs for update to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));
create policy item_dogs_delete on public.item_dogs for delete to authenticated
  using (public.is_trip_member(trip_id));

drop policy comments_insert on public.comments;
drop policy comments_delete on public.comments;
create policy comments_insert on public.comments for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = (select auth.uid()));
create policy comments_delete on public.comments for delete to authenticated
  using (user_id = (select auth.uid()));

drop policy reactions_select on public.reactions;
drop policy reactions_write on public.reactions;
create policy reactions_select on public.reactions for select to authenticated
  using (public.is_trip_member(trip_id));
create policy reactions_insert on public.reactions for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = (select auth.uid()));
create policy reactions_update on public.reactions for update to authenticated
  using (public.is_trip_member(trip_id) and user_id = (select auth.uid()))
  with check (public.is_trip_member(trip_id) and user_id = (select auth.uid()));
create policy reactions_delete on public.reactions for delete to authenticated
  using (public.is_trip_member(trip_id) and user_id = (select auth.uid()));
