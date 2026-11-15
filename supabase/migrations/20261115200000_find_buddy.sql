-- Look someone up by their public ID before asking them to be a buddy: name, avatar, ID and how you are related now.
-- Returns nothing for an unknown ID. Only public profile fields leave the function.
create or replace function public.find_buddy(p_handle text)
returns table (id uuid, display_name text, avatar_url text, handle text, relation text)
language plpgsql stable security definer set search_path = '' as $$
declare p public.profiles;
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  select * into p from public.profiles where profiles.handle = lower(ltrim(trim(p_handle), '@'));
  if not found then return; end if;
  return query select
    p.id, p.display_name, p.avatar_url, p.handle,
    case
      when p.id = auth.uid() then 'self'
      when exists (select 1 from public.buddies b where b.status = 'accepted' and ((b.requester_id = auth.uid() and b.addressee_id = p.id) or (b.addressee_id = auth.uid() and b.requester_id = p.id))) then 'accepted'
      when exists (select 1 from public.buddies b where b.status = 'pending' and b.requester_id = auth.uid() and b.addressee_id = p.id) then 'pending_out'
      when exists (select 1 from public.buddies b where b.status = 'pending' and b.requester_id = p.id and b.addressee_id = auth.uid()) then 'pending_in'
      else 'none'
    end;
end $$;

revoke all on function public.find_buddy(text) from public, anon;
grant execute on function public.find_buddy(text) to authenticated;
