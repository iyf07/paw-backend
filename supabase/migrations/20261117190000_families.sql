-- Families: friends who share their dogs. One family per person; the creator is the admin; joining needs the invitee's yes.
create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (family_id, user_id)
);
-- a person belongs to at most one family
create unique index family_members_one_family on public.family_members (user_id) where status = 'accepted';
create index family_members_user on public.family_members (user_id);

alter table public.families enable row level security;
alter table public.family_members enable row level security;

create function public.my_family_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select family_id from public.family_members where user_id = auth.uid() and status = 'accepted' limit 1
$$;

create function public.is_family_mate(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select uid is not null and exists (
    select 1 from public.family_members a join public.family_members b on a.family_id = b.family_id
    where a.user_id = auth.uid() and a.status = 'accepted' and b.user_id = uid and b.status = 'accepted'
  )
$$;

create function public.is_family_visible(fid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid())
$$;

-- read: my family, a family that invited me, and the people in them (no direct writes: everything goes through the functions below)
create policy families_select on public.families for select to authenticated using (public.is_family_visible(id));
create policy family_members_select on public.family_members for select to authenticated using (public.is_family_visible(family_id));
create policy profiles_select_family on public.profiles for select to authenticated
  using (public.is_family_mate(id) or exists (
    select 1 from public.family_members m
    where m.user_id = auth.uid() and m.status = 'pending' and m.invited_by = profiles.id
  ));

-- family mates share dogs: read and edit (never delete or hand over), and can bring each other's dogs on a trip
create policy dogs_select_family on public.dogs for select to authenticated using (public.is_family_mate(owner_id));
create policy dogs_update_family on public.dogs for update to authenticated
  using (public.is_family_mate(owner_id)) with check (public.is_family_mate(owner_id));
create function public.dogs_keep_owner() returns trigger language plpgsql as $$
begin
  if new.owner_id is distinct from old.owner_id then raise exception 'owner cannot change' using errcode = '42501'; end if;
  return new;
end $$;
create trigger dogs_keep_owner before update on public.dogs for each row execute function public.dogs_keep_owner();

create policy trip_dogs_insert_family on public.trip_dogs for insert to authenticated
  with check (
    public.is_trip_member(trip_id)
    and exists (select 1 from public.dogs d where d.id = dog_id and public.is_family_mate(d.owner_id))
  );
create policy trip_dogs_delete_family on public.trip_dogs for delete to authenticated
  using (exists (select 1 from public.dogs d where d.id = dog_id and public.is_family_mate(d.owner_id)));

create function public.create_family(p_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare fid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if public.my_family_id() is not null then raise exception 'already_in_family'; end if;
  insert into public.families (name, created_by) values (btrim(p_name), auth.uid()) returning id into fid;
  insert into public.family_members (family_id, user_id, role, status) values (fid, auth.uid(), 'admin', 'accepted');
  return fid;
end $$;

create function public.rename_family(p_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id();
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  update public.families set name = btrim(p_name) where id = fid;
end $$;

-- admin invites an accepted friend who is not in a family yet
create function public.invite_to_family(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id();
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  if not public.is_accepted_buddy(p_user) then raise exception 'not_a_friend'; end if;
  if exists (select 1 from public.family_members where user_id = p_user and status = 'accepted') then raise exception 'already_in_family'; end if;
  insert into public.family_members (family_id, user_id, invited_by) values (fid, p_user, auth.uid()) on conflict do nothing;
end $$;

create function public.respond_family_invite(p_family uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.family_members where family_id = p_family and user_id = auth.uid() and status = 'pending') then
    raise exception 'no_invite';
  end if;
  if p_accept then
    if public.my_family_id() is not null then raise exception 'already_in_family'; end if;
    update public.family_members set status = 'accepted' where family_id = p_family and user_id = auth.uid();
    -- one family only: drop my other open invitations
    delete from public.family_members where user_id = auth.uid() and status = 'pending';
  else
    delete from public.family_members where family_id = p_family and user_id = auth.uid() and status = 'pending';
  end if;
end $$;

-- admin removes a member or cancels an invitation
create function public.remove_family_member(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id();
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  if p_user = auth.uid() then raise exception 'use leave_family'; end if;
  delete from public.family_members where family_id = fid and user_id = p_user;
end $$;

-- leave; an admin leaving hands the family to the longest-standing member, the last one out closes it
create function public.leave_family() returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id(); was_admin boolean; nxt uuid;
begin
  if fid is null then raise exception 'not_in_family'; end if;
  select role = 'admin' into was_admin from public.family_members where family_id = fid and user_id = auth.uid();
  delete from public.family_members where family_id = fid and user_id = auth.uid();
  select user_id into nxt from public.family_members where family_id = fid and status = 'accepted' order by created_at limit 1;
  if nxt is null then
    delete from public.families where id = fid;
  elsif was_admin and not exists (select 1 from public.family_members where family_id = fid and role = 'admin' and status = 'accepted') then
    update public.family_members set role = 'admin' where family_id = fid and user_id = nxt;
  end if;
end $$;

revoke all on function public.my_family_id(), public.is_family_mate(uuid), public.is_family_visible(uuid), public.create_family(text),
  public.rename_family(text), public.invite_to_family(uuid), public.respond_family_invite(uuid, boolean),
  public.remove_family_member(uuid), public.leave_family() from public, anon;
grant execute on function public.my_family_id(), public.is_family_mate(uuid), public.is_family_visible(uuid), public.create_family(text),
  public.rename_family(text), public.invite_to_family(uuid), public.respond_family_invite(uuid, boolean),
  public.remove_family_member(uuid), public.leave_family() to authenticated;
