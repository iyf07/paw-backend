-- Invite codes expire after one hour (was 30 days): the column becomes a timestamp.
alter table public.trips alter column invite_expires drop default;
alter table public.trips alter column invite_expires type timestamptz
  using least(invite_expires::timestamptz, now() + interval '1 hour');   -- older long-lived codes are cut to 1 hour too
alter table public.trips alter column invite_expires set default (now() + interval '1 hour');

create or replace function public.peek_trip(p_code text) returns jsonb
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
    'expired', t.invite_expires < now(),
    'already_member', exists (select 1 from public.trip_members where trip_id = t.id and user_id = auth.uid())
  );
end $$;

create or replace function public.join_trip(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare t public.trips;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into t from public.trips where invite_code = lower(trim(p_code));
  if not found then raise exception 'invalid_code' using errcode = 'P0001'; end if;
  if t.invite_expires < now() then raise exception 'code_expired' using errcode = 'P0001'; end if;
  insert into public.trip_members (trip_id, user_id) values (t.id, auth.uid()) on conflict do nothing;
  return t.id;
end $$;

-- Leader only: replace the invite code and make it valid for one hour.
create or replace function public.rotate_invite_code(p_trip uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare c text := public.new_invite_code();
begin
  if not public.is_trip_leader(p_trip) then raise exception 'only the trip leader can do this' using errcode = '42501'; end if;
  update public.trips set invite_code = c, invite_expires = now() + interval '1 hour' where id = p_trip;
  return c;
end $$;
