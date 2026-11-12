-- Row level security, leader rules, invite RPCs, storage and realtime.
--
-- Model: you see a trip (and its dogs, people, items, ...) only if you are a member of it.
-- The trip creator is the "leader": only they change trip settings, confirm plans, or edit
-- what is already confirmed. Everything else any member can do.

------------------------------------------------------------------------------------------------
-- helper predicates (SECURITY DEFINER so policies can read membership without recursion)
------------------------------------------------------------------------------------------------
create function public.is_trip_member(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trip_members where trip_id = tid and user_id = auth.uid())
$$;

create function public.is_trip_leader(tid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.trips where id = tid and creator_id = auth.uid())
$$;

create function public.shares_trip_with(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.trip_members a
    join public.trip_members b on b.trip_id = a.trip_id
    where a.user_id = auth.uid() and b.user_id = uid
  )
$$;

revoke execute on function public.is_trip_member(uuid), public.is_trip_leader(uuid), public.shares_trip_with(uuid) from public, anon;
grant  execute on function public.is_trip_member(uuid), public.is_trip_leader(uuid), public.shares_trip_with(uuid) to authenticated;

------------------------------------------------------------------------------------------------
-- table privileges: nothing for anon; trips are updatable only in the columns the leader may edit
------------------------------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
alter default privileges in schema public revoke all on tables from anon;

revoke update on public.trips from authenticated;
grant update (name, place, lat, lon, tz, start_date, end_date, status, interests, dist, filters, pace, budget)
  on public.trips to authenticated;   -- invite_code / invite_expires / creator_id change only through RPCs

------------------------------------------------------------------------------------------------
-- new-user bootstrap
------------------------------------------------------------------------------------------------
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, ''), '@', 1)));
  insert into public.user_settings (id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Creator is always a member of their own trip.
create function public.add_creator_as_member() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.trip_members (trip_id, user_id) values (new.id, new.creator_id);
  return new;
end $$;

create trigger trips_add_creator after insert on public.trips
  for each row execute function public.add_creator_as_member();

-- When someone leaves: their dogs leave the trip with them, and their RSVPs/votes go away.
create function public.on_member_left() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.trip_dogs td using public.dogs d
   where td.trip_id = old.trip_id and td.dog_id = d.id and d.owner_id = old.user_id;
  delete from public.reactions where trip_id = old.trip_id and user_id = old.user_id;
  return old;
end $$;

create trigger trip_members_left after delete on public.trip_members
  for each row execute function public.on_member_left();

------------------------------------------------------------------------------------------------
-- leader rules on items
------------------------------------------------------------------------------------------------
create function public.items_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if auth.uid() is null then   -- service role / migrations / seed
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.confirmed and not public.is_trip_leader(new.trip_id) then
      raise exception 'only the trip leader can confirm items' using errcode = '42501';
    end if;
    new.created_by := auth.uid();
  else
    if new.trip_id <> old.trip_id then
      raise exception 'items cannot move between trips' using errcode = '42501';
    end if;
    if (old.confirmed or new.confirmed) and not public.is_trip_leader(new.trip_id) then
      raise exception 'only the trip leader can change confirmed items' using errcode = '42501';
    end if;
    new.created_by := old.created_by;
    if new.deleted_at is distinct from old.deleted_at then
      new.deleted_by := case when new.deleted_at is null then null else auth.uid() end;
    end if;
  end if;

  new.edited_by := auth.uid();
  new.edited_at := now();
  return new;
end $$;

create trigger items_guard_trg before insert or update on public.items
  for each row execute function public.items_guard();

------------------------------------------------------------------------------------------------
-- RLS
------------------------------------------------------------------------------------------------
alter table public.profiles      enable row level security;
alter table public.user_settings enable row level security;
alter table public.dogs          enable row level security;
alter table public.trips         enable row level security;
alter table public.trip_members  enable row level security;
alter table public.trip_dogs     enable row level security;
alter table public.items         enable row level security;
alter table public.item_dogs     enable row level security;
alter table public.comments      enable row level security;
alter table public.reactions     enable row level security;

-- profiles: yourself + people you share a trip with
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_trip_with(id));
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- user_settings: private
create policy user_settings_all on public.user_settings for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- dogs: owner manages; co-travellers can read
create policy dogs_select on public.dogs for select to authenticated
  using (owner_id = auth.uid() or public.shares_trip_with(owner_id));
create policy dogs_insert on public.dogs for insert to authenticated
  with check (owner_id = auth.uid());
create policy dogs_update on public.dogs for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy dogs_delete on public.dogs for delete to authenticated
  using (owner_id = auth.uid());

-- trips: members read; anyone can create their own; only the leader edits / deletes.
-- (creator_id is allowed in select so INSERT ... RETURNING works before the member row exists.)
create policy trips_select on public.trips for select to authenticated
  using (creator_id = auth.uid() or public.is_trip_member(id));
create policy trips_insert on public.trips for insert to authenticated
  with check (creator_id = auth.uid());
create policy trips_update on public.trips for update to authenticated
  using (creator_id = auth.uid()) with check (creator_id = auth.uid());
create policy trips_delete on public.trips for delete to authenticated
  using (creator_id = auth.uid());

-- trip_members: members read; join happens only through join_trip(); you can leave, the leader cannot
create policy trip_members_select on public.trip_members for select to authenticated
  using (public.is_trip_member(trip_id));
create policy trip_members_leave on public.trip_members for delete to authenticated
  using (user_id = auth.uid() and not public.is_trip_leader(trip_id));

-- trip_dogs: bring your own dogs; you or the leader can take a dog off
create policy trip_dogs_select on public.trip_dogs for select to authenticated
  using (public.is_trip_member(trip_id));
create policy trip_dogs_insert on public.trip_dogs for insert to authenticated
  with check (
    public.is_trip_member(trip_id)
    and exists (select 1 from public.dogs d where d.id = dog_id and d.owner_id = auth.uid())
  );
create policy trip_dogs_delete on public.trip_dogs for delete to authenticated
  using (
    public.is_trip_leader(trip_id)
    or exists (select 1 from public.dogs d where d.id = dog_id and d.owner_id = auth.uid())
  );

-- items: members read / add / edit (leader rules are in items_guard); nobody hard-deletes, deleting is
-- a soft delete (deleted_at) so "Recently deleted" can restore it.
create policy items_select on public.items for select to authenticated
  using (public.is_trip_member(trip_id));
create policy items_insert on public.items for insert to authenticated
  with check (public.is_trip_member(trip_id));
create policy items_update on public.items for update to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));

-- item_dogs: members arrange dogs for an item
create policy item_dogs_select on public.item_dogs for select to authenticated
  using (public.is_trip_member(trip_id));
create policy item_dogs_write on public.item_dogs for all to authenticated
  using (public.is_trip_member(trip_id)) with check (public.is_trip_member(trip_id));

-- comments: members read and write their own; you can delete your own
create policy comments_select on public.comments for select to authenticated
  using (public.is_trip_member(trip_id));
create policy comments_insert on public.comments for insert to authenticated
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());
create policy comments_delete on public.comments for delete to authenticated
  using (user_id = auth.uid());

-- reactions: members read; you only write your own row
create policy reactions_select on public.reactions for select to authenticated
  using (public.is_trip_member(trip_id));
create policy reactions_write on public.reactions for all to authenticated
  using (public.is_trip_member(trip_id) and user_id = auth.uid())
  with check (public.is_trip_member(trip_id) and user_id = auth.uid());

------------------------------------------------------------------------------------------------
-- invite RPCs
------------------------------------------------------------------------------------------------
-- Preview a trip from its code before joining (non-members cannot read trips directly).
create function public.peek_trip(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare t public.trips;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into t from public.trips where invite_code = lower(trim(p_code));
  if not found then return null; end if;
  return jsonb_build_object(
    'id', t.id, 'name', t.name, 'place', t.place,
    'start_date', t.start_date, 'end_date', t.end_date,
    'members', (select count(*) from public.trip_members where trip_id = t.id),
    'dogs',    (select count(*) from public.trip_dogs    where trip_id = t.id),
    'expired', t.invite_expires < current_date,
    'already_member', exists (select 1 from public.trip_members where trip_id = t.id and user_id = auth.uid())
  );
end $$;

create function public.join_trip(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare t public.trips;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into t from public.trips where invite_code = lower(trim(p_code));
  if not found then raise exception 'invalid_code' using errcode = 'P0001'; end if;
  if t.invite_expires < current_date then raise exception 'code_expired' using errcode = 'P0001'; end if;
  insert into public.trip_members (trip_id, user_id) values (t.id, auth.uid()) on conflict do nothing;
  return t.id;
end $$;

-- Leader only: replace the invite code and extend it 30 days.
create function public.rotate_invite_code(p_trip uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare c text := public.new_invite_code();
begin
  if not public.is_trip_leader(p_trip) then raise exception 'only the trip leader can do this' using errcode = '42501'; end if;
  update public.trips set invite_code = c, invite_expires = current_date + 30 where id = p_trip;
  return c;
end $$;

revoke execute on function public.peek_trip(text), public.join_trip(text), public.rotate_invite_code(uuid) from public, anon;
grant  execute on function public.peek_trip(text), public.join_trip(text), public.rotate_invite_code(uuid) to authenticated;

------------------------------------------------------------------------------------------------
-- storage: one public bucket for avatars and dog photos, each user writes only to their own folder
------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy photos_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy photos_update_own on storage.objects for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy photos_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

------------------------------------------------------------------------------------------------
-- realtime: live updates for the open trip
------------------------------------------------------------------------------------------------
alter publication supabase_realtime add table
  public.trips, public.trip_members, public.trip_dogs, public.dogs, public.profiles,
  public.items, public.item_dogs, public.comments, public.reactions;
