-- Joining a family with its code makes you friends with the family's admin (the person whose code you used),
-- so someone invited by code does not have to send a friend request separately.
create or replace function public.join_family(p_code text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare f public.families; adm uuid;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into f from public.families where invite_code = lower(trim(p_code));
  if not found then raise exception 'invalid_code'; end if;
  if f.invite_expires is null or f.invite_expires < now() then raise exception 'code_expired'; end if;
  if public.my_family_id() is not null then raise exception 'already_in_family'; end if;
  delete from public.family_members where user_id = auth.uid() and status = 'pending';
  insert into public.family_members (family_id, user_id, role, status) values (f.id, auth.uid(), 'member', 'accepted');
  for adm in select user_id from public.family_members where family_id = f.id and role = 'admin' and status = 'accepted' and user_id <> auth.uid() loop
    -- an open request between the two (either direction) becomes accepted; otherwise a new accepted friendship
    update public.buddies set status = 'accepted'
      where (requester_id = auth.uid() and addressee_id = adm) or (requester_id = adm and addressee_id = auth.uid());
    if not found then
      insert into public.buddies (requester_id, addressee_id, status) values (adm, auth.uid(), 'accepted');
    end if;
  end loop;
  return f.id;
end $$;
