-- Tell the other family members when someone leaves, the family is disbanded, or someone is removed.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in
  ('friend_accepted', 'friend_declined', 'relation_accepted', 'relation_declined', 'family_left', 'family_disbanded', 'family_removed'));
alter table public.notifications add column subject text;   -- e.g. the family name

drop function public.notify(uuid, text, text);
create function public.notify(p_user uuid, p_kind text, p_relation text default null, p_subject text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, actor_id, actor_name, actor_avatar, relation, subject)
  select p_user, p_kind, auth.uid(), coalesce(p.display_name, ''), p.avatar_url, p_relation, p_subject
  from public.profiles p where p.id = auth.uid();
end $$;
revoke all on function public.notify(uuid, text, text, text) from public, anon, authenticated;

create or replace function public.leave_family() returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id(); was_admin boolean; nxt uuid; fname text; m uuid;
begin
  if fid is null then raise exception 'not_in_family'; end if;
  select name into fname from public.families where id = fid;
  select role = 'admin' into was_admin from public.family_members where family_id = fid and user_id = auth.uid();
  delete from public.family_members where family_id = fid and user_id = auth.uid();
  for m in select user_id from public.family_members where family_id = fid and status = 'accepted' loop
    perform public.notify(m, 'family_left', null, fname);
  end loop;
  select user_id into nxt from public.family_members where family_id = fid and status = 'accepted' order by created_at limit 1;
  if nxt is null then
    delete from public.families where id = fid;
  elsif was_admin and not exists (select 1 from public.family_members where family_id = fid and role = 'admin' and status = 'accepted') then
    update public.family_members set role = 'admin' where family_id = fid and user_id = nxt;
  end if;
end $$;

create or replace function public.disband_family() returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id(); fname text; m uuid;
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  select name into fname from public.families where id = fid;
  for m in select user_id from public.family_members where family_id = fid and status = 'accepted' and user_id <> auth.uid() loop
    perform public.notify(m, 'family_disbanded', null, fname);
  end loop;
  delete from public.families where id = fid;
end $$;

create or replace function public.remove_family_member(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id(); fname text; was_member boolean;
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  if p_user = auth.uid() then raise exception 'use leave_family'; end if;
  select name into fname from public.families where id = fid;
  select status = 'accepted' into was_member from public.family_members where family_id = fid and user_id = p_user;
  delete from public.family_members where family_id = fid and user_id = p_user;
  if coalesce(was_member, false) then perform public.notify(p_user, 'family_removed', null, fname); end if;
end $$;
