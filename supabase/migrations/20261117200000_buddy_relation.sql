-- When two people became friends, and an optional shared label for the relationship (either side can set it).
alter table public.buddies
  add column accepted_at timestamptz,
  add column relation text check (relation in ('brother', 'sister', 'bestie', 'pal', 'lover', 'spouse', 'family', 'classmate', 'colleague', 'neighbor'));

create or replace function public.respond_buddy(p_from uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_accept then
    update public.buddies set status = 'accepted', accepted_at = now()
    where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  else
    delete from public.buddies where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
  end if;
end $$;

create function public.set_buddy_relation(p_other uuid, p_relation text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_accepted_buddy(p_other) then raise exception 'not_a_friend'; end if;
  update public.buddies set relation = nullif(p_relation, '')
  where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
end $$;
revoke all on function public.set_buddy_relation(uuid, text) from public, anon;
grant execute on function public.set_buddy_relation(uuid, text) to authenticated;
