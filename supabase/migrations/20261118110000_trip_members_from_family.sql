-- The leader can add family mates to a trip as well as friends (a family mate who joined with a code is not necessarily a friend).
create or replace function public.add_buddies_to_trip(p_trip uuid, p_buddies uuid[], p_dogs boolean default true) returns integer
language plpgsql security definer set search_path = '' as $$
declare ids uuid[]; n integer;
begin
  if not public.is_trip_leader(p_trip) then raise exception 'only the trip leader can do this' using errcode = '42501'; end if;
  select coalesce(array_agg(u), '{}') into ids from unnest(p_buddies) u where public.is_accepted_buddy(u) or public.is_family_mate(u);
  insert into public.trip_members (trip_id, user_id) select p_trip, u from unnest(ids) u on conflict do nothing;
  get diagnostics n = row_count;
  if p_dogs then
    insert into public.trip_dogs (trip_id, dog_id) select p_trip, d.id from public.dogs d where d.owner_id = any (ids) on conflict do nothing;
  end if;
  return n;
end $$;
