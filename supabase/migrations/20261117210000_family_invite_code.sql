-- Join a family with a short-lived invite code (like trips). The admin gets a fresh code each time they open the popup;
-- the code is never readable from the table (only returned to the admin by rotate_family_code).
alter table public.families
  add column invite_code text unique,
  add column invite_expires timestamptz;

revoke select on public.families from authenticated;
grant select (id, name, created_by, created_at) on public.families to authenticated;

create function public.rotate_family_code() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id(); c text := public.new_invite_code(); exp timestamptz := now() + interval '1 hour';
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  update public.families set invite_code = c, invite_expires = exp where id = fid;
  return jsonb_build_object('code', c, 'expires', exp);
end $$;

create function public.peek_family(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare f public.families;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into f from public.families where invite_code = lower(trim(p_code));
  if not found then return null; end if;
  return jsonb_build_object(
    'name', f.name,
    'members', (select count(*) from public.family_members where family_id = f.id and status = 'accepted'),
    'expired', f.invite_expires is null or f.invite_expires < now(),
    'already_in_family', public.my_family_id() is not null
  );
end $$;

create function public.join_family(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare f public.families;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into f from public.families where invite_code = lower(trim(p_code));
  if not found then raise exception 'invalid_code'; end if;
  if f.invite_expires is null or f.invite_expires < now() then raise exception 'code_expired'; end if;
  if public.my_family_id() is not null then raise exception 'already_in_family'; end if;
  delete from public.family_members where user_id = auth.uid() and status = 'pending';
  insert into public.family_members (family_id, user_id, role, status) values (f.id, auth.uid(), 'member', 'accepted');
  return f.id;
end $$;

revoke all on function public.rotate_family_code(), public.peek_family(text), public.join_family(text) from public, anon;
grant execute on function public.rotate_family_code(), public.peek_family(text), public.join_family(text) to authenticated;
