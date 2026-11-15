-- Optional 1..5 personal preferences; existing values and RLS stay intact.
alter table public.profiles
  add column temperature smallint check (temperature between 1 and 5),
  add column pace smallint check (pace between 1 and 5),
  add column spending smallint check (spending between 1 and 5);
comment on column public.profiles.temperature is '1 very cold-sensitive; 5 very heat-sensitive';
comment on column public.profiles.pace is '1 very relaxed itinerary; 5 packed itinerary';
comment on column public.profiles.spending is '1 budget-conscious; 5 luxury spending style';
