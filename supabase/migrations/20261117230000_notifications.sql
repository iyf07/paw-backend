-- Notifications: the answer to something I asked (friend request, relationship label) shows up for me.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('friend_accepted', 'friend_declined', 'relation_accepted', 'relation_declined')),
  actor_id uuid references public.profiles (id) on delete set null,
  -- the other person's name and photo as they were, because after a decline we can no longer read their profile
  actor_name text not null default '',
  actor_avatar text,
  relation text,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index notifications_user_unread on public.notifications (user_id, created_at desc) where read_at is null;

alter table public.notifications enable row level security;
create policy notifications_select on public.notifications for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.notifications from authenticated;

create function public.notify(p_user uuid, p_kind text, p_relation text default null) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, actor_id, actor_name, actor_avatar, relation)
  select p_user, p_kind, auth.uid(), coalesce(p.display_name, ''), p.avatar_url, p_relation
  from public.profiles p where p.id = auth.uid();
end $$;
revoke all on function public.notify(uuid, text, text) from public, anon, authenticated;

create function public.dismiss_notification(p_id uuid) returns void
language sql security definer set search_path = '' as $$
  update public.notifications set read_at = now() where id = p_id and user_id = auth.uid() and read_at is null
$$;
revoke all on function public.dismiss_notification(uuid) from public, anon;
grant execute on function public.dismiss_notification(uuid) to authenticated;

-- friend request answered: tell the person who asked
create or replace function public.respond_buddy(p_from uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  if p_accept then
    update public.buddies set status = 'accepted', accepted_at = now()
    where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
    get diagnostics n = row_count;
    if n > 0 then perform public.notify(p_from, 'friend_accepted'); end if;
  else
    delete from public.buddies where requester_id = p_from and addressee_id = auth.uid() and status = 'pending';
    get diagnostics n = row_count;
    if n > 0 then perform public.notify(p_from, 'friend_declined'); end if;
  end if;
end $$;

-- relationship label answered: tell the person who proposed it
create or replace function public.respond_buddy_relation(p_other uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare lbl text;
begin
  if not public.is_accepted_buddy(p_other) then raise exception 'not_a_friend'; end if;
  select relation_proposed into lbl from public.buddies
  where status = 'accepted' and relation_proposed is not null and relation_proposed_by = p_other
    and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
  if lbl is null then return; end if;
  if p_accept then
    update public.buddies set relation = relation_proposed, relation_proposed = null, relation_proposed_by = null
    where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
    perform public.notify(p_other, 'relation_accepted', lbl);
  else
    update public.buddies set relation_proposed = null, relation_proposed_by = null
    where status = 'accepted' and ((requester_id = auth.uid() and addressee_id = p_other) or (addressee_id = auth.uid() and requester_id = p_other));
    perform public.notify(p_other, 'relation_declined', lbl);
  end if;
end $$;
