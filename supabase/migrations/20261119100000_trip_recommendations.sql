-- Gemini-written suggestions for a trip day, cached so the model is called once per trip day (and language), not per view.
create table public.trip_recommendations (
  trip_id      uuid not null references public.trips (id) on delete cascade,
  day          date not null,
  lang         text not null check (lang in ('zh', 'en')),
  payload      jsonb not null,
  requested_by uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  primary key (trip_id, day, lang)
);
alter table public.trip_recommendations enable row level security;
-- trip members read; only the Edge Function (service role) writes
create policy trip_recommendations_select on public.trip_recommendations for select to authenticated using (public.is_trip_member(trip_id));
revoke insert, update, delete on public.trip_recommendations from anon, authenticated;
