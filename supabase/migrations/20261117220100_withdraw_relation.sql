-- Withdraw my own open relationship proposal (keeps the current label).
create function public.withdraw_buddy_relation(p_other uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.buddies set relation_proposed = null, relation_proposed_by = null
  where status = 'accepted' and relation_proposed_by = auth.uid()
    and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
end $$;
revoke all on function public.withdraw_buddy_relation(uuid) from public, anon;
grant execute on function public.withdraw_buddy_relation(uuid) to authenticated;
