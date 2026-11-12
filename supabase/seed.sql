-- Local development seed (runs on `supabase start` / `supabase db reset`; never on the cloud project).
-- Two test accounts, password "password123":  alex@test.local (trip leader), morgan@test.local (member).

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new, email_change_token_current,
  phone_change, phone_change_token, reauthentication_token
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated',
   'alex@test.local',   extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"name":"Alex"}',   now(), now(), '', '', '', '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000b2', 'authenticated', 'authenticated',
   'morgan@test.local', extensions.crypt('password123', extensions.gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{"name":"Morgan"}', now(), now(), '', '', '', '', '', '', '', '');

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), u.id, u.id::text, 'email',
       jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true), now(), now(), now()
from auth.users u where u.email in ('alex@test.local', 'morgan@test.local');

-- Dogs
insert into public.dogs (id, owner_id, name, weight_lb, energy, temp, with_dogs, with_people, alone, car, recall) values
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-0000000000a1', 'Biscuit', 65.0, 3, 5, 3, 5, 3, 4, 'comes'),
  ('00000000-0000-4000-8000-00000000d002', '00000000-0000-4000-8000-0000000000b2', 'Noodle',  18.0, 5, 2, 5, 3, 2, 3, 'runner');

-- Trip: a weekend starting next Friday. Creator (Alex) is added as a member by trigger.
insert into public.trips (id, name, place, lat, lon, tz, start_date, end_date, creator_id, interests, invite_code)
values ('00000000-0000-4000-8000-0000000000f1', 'Shenandoah Weekend', 'Luray, VA', 38.67, -78.46, 'America/New_York',
        current_date + ((5 - extract(dow from current_date)::int + 7) % 7) + 7,
        current_date + ((5 - extract(dow from current_date)::int + 7) % 7) + 9,
        '00000000-0000-4000-8000-0000000000a1', '{hiking,restaurants}', 'seed1-code1');

insert into public.trip_members (trip_id, user_id) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b2');
insert into public.trip_dogs (trip_id, dog_id, added_by) values
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000d002', '00000000-0000-4000-8000-0000000000b2');

with t as (select id, start_date from public.trips where id = '00000000-0000-4000-8000-0000000000f1')
insert into public.items (id, trip_id, type, cat, title, emoji, confirmed, date, start_min, end_min, stay_from, stay_to, place, addr, notes, travel_min, created_by)
select * from (
  select '00000000-0000-4000-8000-0000000001a1'::uuid, t.id, 'stay', 'stay', 'Skyland Cabin', '🏡', true, null::date, null::int, null::int,
         t.start_date, t.start_date + 2, 'Skyland Cabin 4B', 'Skyline Drive, Luray, VA 22835', 'Check-in 3 PM. Pet fee paid.', null::int, '00000000-0000-4000-8000-0000000000a1'::uuid from t
  union all
  select '00000000-0000-4000-8000-0000000001a2', t.id, 'activity', 'outdoors', 'Stony Man Trail', '🥾', true, t.start_date + 1, 630, 810,
         null, null, 'Stony Man Trail', 'Luray, VA 22835', 'Leash required', 22, '00000000-0000-4000-8000-0000000000a1' from t
  union all
  select '00000000-0000-4000-8000-0000000001a3', t.id, 'food', 'coffee', 'Breakfast', '🍳', false, t.start_date + 1, 540, 600,
         null, null, 'Gathering Grounds', 'E Main St, Luray, VA 22835', 'They have pup cups!', null, '00000000-0000-4000-8000-0000000000b2' from t
  union all
  select '00000000-0000-4000-8000-0000000001a4', t.id, 'activity', 'outdoors', 'Dark Hollow Falls', '🏔️', false, null, null, null,
         null, null, 'Dark Hollow Falls Trail', 'Skyline Drive mile 50.7', 'Check dogs are allowed', null, '00000000-0000-4000-8000-0000000000b2' from t
) x;

insert into public.item_dogs (item_id, trip_id, dog_id, mode) values
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000d001', 'with'),
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000d002', 'with'),
  ('00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-00000000d001', 'with');

insert into public.reactions (item_id, trip_id, user_id, vote, rsvp) values
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000a1', 'up', 'going'),
  ('00000000-0000-4000-8000-0000000001a2', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b2', 'up', 'going'),
  ('00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b2', 'up', 'going');

insert into public.comments (item_id, trip_id, user_id, text) values
  ('00000000-0000-4000-8000-0000000001a3', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000b2', 'They have pup cups!');

-- Seed users skip the first-run onboarding.
update public.profiles set onboarded_at = now() where id in ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000b2');
