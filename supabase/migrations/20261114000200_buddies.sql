-- Buddies: named groups of people you often travel with ("我们家", "周末搭子"). Joining needs consent:
-- the owner invites someone by their public ID, the invitee accepts or declines. When you create a trip you can
-- add a whole group at once (only people who accepted); they can still leave the trip.

create table public.buddy_groups (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.buddy_members (
  group_id   uuid not null references public.buddy_groups (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  status     text not null default 'invited' check (status in ('invited', 'accepted')),
  invited_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index buddy_members_user_idx on public.buddy_members (user_id);

create function public.is_buddy_owner(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.buddy_groups where id = gid and owner_id = auth.uid())
$$;

-- member in any state (an invitee may see the group they were invited to)
create function public.in_buddy_group(gid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.buddy_members where group_id = gid and user_id = auth.uid())
$$;

create function public.shares_buddy_group_with(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.buddy_members a join public.buddy_members b on b.group_id = a.group_id
    where a.user_id = auth.uid() and b.user_id = uid
  )
$$;

-- the owner is the first (accepted) member
create function public.buddy_group_owner_member() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.buddy_members (group_id, user_id, status, invited_by) values (new.id, new.owner_id, 'accepted', new.owner_id);
  return new;
end $$;
create trigger buddy_groups_owner_member after insert on public.buddy_groups
  for each row execute function public.buddy_group_owner_member();

alter table public.buddy_groups  enable row level security;
alter table public.buddy_members enable row level security;

create policy buddy_groups_select on public.buddy_groups for select to authenticated
  using (owner_id = auth.uid() or public.in_buddy_group(id));
create policy buddy_groups_insert on public.buddy_groups for insert to authenticated
  with check (owner_id = auth.uid());
create policy buddy_groups_update on public.buddy_groups for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy buddy_groups_delete on public.buddy_groups for delete to authenticated
  using (owner_id = auth.uid());

create policy buddy_members_select on public.buddy_members for select to authenticated
  using (public.in_buddy_group(group_id));
-- leave the group yourself (the owner deletes the group instead), or the owner removes someone else
create policy buddy_members_delete on public.buddy_members for delete to authenticated
  using (
    (user_id = auth.uid() and not public.is_buddy_owner(group_id))
    or (public.is_buddy_owner(group_id) and user_id <> auth.uid())
  );

-- people in a group with you can see each other's name, avatar and ID
create policy profiles_select_buddies on public.profiles for select to authenticated
  using (public.shares_buddy_group_with(id));

-- Owner: invite someone by their public ID. They get a pending invitation they must accept.
create function public.invite_buddy(p_group uuid, p_handle text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid;
begin
  if not public.is_buddy_owner(p_group) then raise exception 'only the owner can invite' using errcode = '42501'; end if;
  select id into uid from public.profiles where handle = lower(ltrim(trim(p_handle), '@'));
  if uid is null then raise exception 'unknown_handle' using errcode = 'P0001'; end if;
  if uid = auth.uid() then raise exception 'self' using errcode = 'P0001'; end if;
  if (select count(*) from public.buddy_members where group_id = p_group) >= 12 then raise exception 'group_full' using errcode = 'P0001'; end if;
  insert into public.buddy_members (group_id, user_id, status, invited_by) values (p_group, uid, 'invited', auth.uid()) on conflict do nothing;
end $$;

-- Invitee: accept or decline.
create function public.respond_buddy(p_group uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_accept then
    update public.buddy_members set status = 'accepted' where group_id = p_group and user_id = auth.uid() and status = 'invited';
  else
    delete from public.buddy_members where group_id = p_group and user_id = auth.uid() and status = 'invited';
  end if;
end $$;

-- Trip leader: add everyone in one of their groups who accepted (and, if asked, those people's dogs). Returns how many joined.
create function public.add_buddies_to_trip(p_trip uuid, p_group uuid, p_dogs boolean default true) returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if not public.is_trip_leader(p_trip) then raise exception 'only the trip leader can do this' using errcode = '42501'; end if;
  if not exists (select 1 from public.buddy_members where group_id = p_group and user_id = auth.uid() and status = 'accepted') then
    raise exception 'not in that group' using errcode = '42501';
  end if;
  insert into public.trip_members (trip_id, user_id)
    select p_trip, user_id from public.buddy_members where group_id = p_group and status = 'accepted' and user_id <> auth.uid()
    on conflict do nothing;
  get diagnostics n = row_count;
  if p_dogs then
    insert into public.trip_dogs (trip_id, dog_id)
      select p_trip, d.id from public.dogs d
      join public.buddy_members m on m.user_id = d.owner_id and m.group_id = p_group and m.status = 'accepted' and m.user_id <> auth.uid()
      on conflict do nothing;
  end if;
  return n;
end $$;

revoke all on function public.is_buddy_owner(uuid), public.in_buddy_group(uuid), public.shares_buddy_group_with(uuid),
  public.invite_buddy(uuid, text), public.respond_buddy(uuid, boolean), public.add_buddies_to_trip(uuid, uuid, boolean) from public, anon;
grant execute on function public.is_buddy_owner(uuid), public.in_buddy_group(uuid), public.shares_buddy_group_with(uuid),
  public.invite_buddy(uuid, text), public.respond_buddy(uuid, boolean), public.add_buddies_to_trip(uuid, uuid, boolean) to authenticated;
