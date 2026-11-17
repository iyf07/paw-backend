-- The admin does not "leave": they disband the family (everyone is removed, dogs and trips stay).
create function public.disband_family() returns void
language plpgsql security definer set search_path = '' as $$
declare fid uuid := public.my_family_id();
begin
  if fid is null or not exists (select 1 from public.family_members where family_id = fid and user_id = auth.uid() and role = 'admin') then
    raise exception 'only the family admin can do this' using errcode = '42501';
  end if;
  delete from public.families where id = fid;
end $$;
revoke all on function public.disband_family() from public, anon;
grant execute on function public.disband_family() to authenticated;
