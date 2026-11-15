-- Buddies are people, not groups: you ask someone (by their public ID), they accept, and from then on you can add
-- each other to trips. Replaces the group model from the previous migration (no data existed yet).

drop policy if exists profiles_select_buddies on public.profiles;
drop table if exists public.buddy_members cascade;
drop table if exists public.buddy_groups cascade;
drop function if exists public.buddy_group_owner_member() cascade;
drop function if exists public.is_buddy_owner(uuid);
drop function if exists public.in_buddy_group(uuid);
drop function if exists public.shares_buddy_group_with(uuid);
drop function if exists public.invite_buddy(uuid, text);
drop function if exists public.respond_buddy(uuid, boolean);
drop function if exists public.add_buddies_to_trip(uuid, uuid, boolean);

create table public.buddies (
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  primary key (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);
create index buddies_addressee_idx on public.buddies (addressee_id);

alter table public.buddies enable row level security;

-- both sides see the row; either side can end it (cancel, decline, remove). Creating and accepting go through RPCs.
create policy buddies_select on public.buddies for select to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());
create policy buddies_delete on public.buddies for delete to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- buddies (pending or accepted) can see each other's name, avatar and ID
create function public.is_buddy_of(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.buddies
    where (requester_id = auth.uid() and addressee_id = uid) or (addressee_id = auth.uid() and requester_id = uid)
  )
$$;
create function public.is_accepted_buddy(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.buddies
    where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = uid) or (addressee_id = auth.uid() and requester_id = uid))
  )
$$;
create policy profiles_select_buddies on public.profiles for select to authenticated
  using (public.is_buddy_of(id));

-- Ask someone to be your buddy. If they already asked you, this accepts.
create function public.request_buddy(p_handle text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid;
begin
  select id into uid from public.profiles where handle = lower(ltrim(trim(p_handle), '@'));
  if uid is null then raise exception 'unknown_handle' using errcode = 'P0001'; end if;
  if uid = auth.uid() then raise exception 'self' using errcode = 'P0001'; end if;
  if exists (select 1 from public.buddies where requester_id = uid and addressee_id = auth.uid()) then
    update public.buddies set status = 'accepted' where requester_id = uid and addressee_id = auth.uid();
  else
    insert into public.buddies (requester_id, addressee_id) values (auth.uid(), uid) on conflict do nothing;
  end if;
end $$;

-- Answer a request someone sent you.
create function public.respond_buddy(p_from uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_accept then
    update public.buddies set status = 'accepted' where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  else
    delete from public.buddies where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  end if;
end $$;

-- Trip leader: add buddies (accepted ones only) to a trip, and, if asked, those people's dogs. Returns how many joined.
create function public.add_buddies_to_trip(p_trip uuid, p_buddies uuid[], p_dogs boolean default true) returns integer
language plpgsql security definer set search_path = '' as $$
declare ids uuid[]; n integer;
begin
  if not public.is_trip_leader(p_trip) then raise exception 'only the trip leader can do this' using errcode = '42501'; end if;
  select coalesce(array_agg(u), '{}') into ids from unnest(p_buddies) u where public.is_accepted_buddy(u);
  insert into public.trip_members (trip_id, user_id) select p_trip, u from unnest(ids) u on conflict do nothing;
  get diagnostics n = row_count;
  if p_dogs then
    insert into public.trip_dogs (trip_id, dog_id) select p_trip, d.id from public.dogs d where d.owner_id = any (ids) on conflict do nothing;
  end if;
  return n;
end $$;

revoke all on function public.is_buddy_of(uuid), public.is_accepted_buddy(uuid), public.request_buddy(text),
  public.respond_buddy(uuid, boolean), public.add_buddies_to_trip(uuid, uuid[], boolean) from public, anon;
grant execute on function public.is_buddy_of(uuid), public.is_accepted_buddy(uuid), public.request_buddy(text),
  public.respond_buddy(uuid, boolean), public.add_buddies_to_trip(uuid, uuid[], boolean) to authenticated;
