-- A relationship label needs the other friend's yes: one side proposes, the other accepts or declines.
alter table public.buddies
  add column relation_proposed text check (relation_proposed in ('brother', 'sister', 'bestie', 'pal', 'lover', 'spouse', 'family', 'classmate', 'colleague', 'neighbor')),
  add column relation_proposed_by uuid references public.profiles (id) on delete set null;

-- Propose a label (or clear the current one / withdraw a proposal with an empty value).
create or replace function public.set_buddy_relation(p_other uuid, p_relation text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_accepted_buddy(p_other) then raise exception 'not_a_friend'; end if;
  if nullif(p_relation, '') is null then
    update public.buddies set relation = null, relation_proposed = null, relation_proposed_by = null
    where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
  else
    update public.buddies set relation_proposed = p_relation, relation_proposed_by = auth.uid()
    where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
  end if;
end $$;

-- The friend who did not propose answers.
create function public.respond_buddy_relation(p_other uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_accepted_buddy(p_other) then raise exception 'not_a_friend'; end if;
  if p_accept then
    update public.buddies set relation = relation_proposed, relation_proposed = null, relation_proposed_by = null
    where status = 'accepted' and relation_proposed is not null and relation_proposed_by = p_other
      and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
  else
    update public.buddies set relation_proposed = null, relation_proposed_by = null
    where status = 'accepted' and relation_proposed_by = p_other
      and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
  end if;
end $$;
revoke all on function public.respond_buddy_relation(uuid, boolean) from public, anon;
grant execute on function public.respond_buddy_relation(uuid, boolean) to authenticated;
