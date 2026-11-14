-- Move a trip to new dates (calendar drag). Everything that was scheduled (a date, a time or a stay) turns into an
-- idea: no date, no time, no stay, not confirmed. Runs as the caller, so only the leader can do it (RLS + items_guard).
create function public.move_trip(p_trip uuid, p_start date, p_end date)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  n integer;
begin
  if p_end < p_start then
    raise exception 'end before start' using errcode = '22023';
  end if;
  if not public.is_trip_leader(p_trip) then
    raise exception 'only the trip leader can move the trip' using errcode = '42501';
  end if;

  update public.trips set start_date = p_start, end_date = p_end where id = p_trip;

  update public.items
     set date = null, start_min = null, end_min = null, stay_from = null, stay_to = null, confirmed = false
   where trip_id = p_trip
     and (date is not null or stay_from is not null or confirmed);
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.move_trip(uuid, date, date) from public, anon;
grant execute on function public.move_trip(uuid, date, date) to authenticated;
