-- Testers send many short reports from their phones: allow 60 per hour (was 10), with a daily cap as an abuse guard.
create or replace function public.feedback_rate_limit() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (select count(*) from public.feedback where user_id = new.user_id and created_at > now() - interval '1 hour') >= 60
     or (select count(*) from public.feedback where user_id = new.user_id and created_at > now() - interval '1 day') >= 300 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  return new;
end $$;
