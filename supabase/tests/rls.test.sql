-- Run with: supabase test db
begin;
select plan(16);

-- fixtures: three users, Alex leads a trip, Morgan joins by code, Casey is an outsider
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;
create function pg_temp.as_postgres() returns void language plpgsql as $$
begin execute 'reset role'; end $$;

select is((select count(*)::int from public.profiles where id in ('11111111-1111-4111-8111-111111111111')), 1, 'profile auto-created on signup');

-- Alex creates a trip and a dog
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
insert into public.trips (id, name, start_date, end_date) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Test trip', current_date, current_date + 2);
insert into public.dogs (id, name) values ('d0000000-0000-4000-8000-000000000001', 'Biscuit');
insert into public.trip_dogs (trip_id, dog_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'd0000000-0000-4000-8000-000000000001');
select is((select count(*)::int from public.trip_members), 1, 'creator is auto-added as member');

insert into public.items (id, trip_id, type, title) values ('e0000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'activity', 'Idea');
insert into public.items (id, trip_id, type, title, confirmed) values ('e0000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'activity', 'Locked', true);
select is((select invite_code from public.trips) ~ '^[0-9a-f]{5}-[0-9a-f]{5}$', true, 'invite code generated');
create temp table code as select invite_code from public.trips;
grant select on code to authenticated;

-- Casey (outsider) sees nothing
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select is((select count(*)::int from public.trips), 0, 'outsider cannot see trips');
select is((select count(*)::int from public.items), 0, 'outsider cannot see items');
select is((select count(*)::int from public.dogs), 0, 'outsider cannot see dogs');
select throws_ok($$select public.join_trip('nope-nope1')$$, 'P0001', 'invalid_code', 'bad invite code rejected');

-- Morgan joins by code and now sees everything, including Alex's dog
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select lives_ok($$select public.join_trip((select invite_code from code))$$, 'join with code');
select is((select count(*)::int from public.items), 2, 'member sees items');
select is((select count(*)::int from public.dogs), 1, 'member sees co-traveller dog');

-- member rules
select lives_ok($$update public.items set notes = 'hi' where id = 'e0000000-0000-4000-8000-000000000001'$$, 'member edits an idea');
select throws_ok($$update public.items set confirmed = true where id = 'e0000000-0000-4000-8000-000000000001'$$, '42501', 'only the trip leader can change confirmed items', 'member cannot confirm');
select throws_ok($$update public.items set notes = 'x' where id = 'e0000000-0000-4000-8000-000000000002'$$, '42501', 'only the trip leader can change confirmed items', 'member cannot edit confirmed item');
update public.trips set name = 'hacked';   -- RLS hides the row from UPDATE: silently 0 rows
select is((select name from public.trips), 'Test trip', 'member cannot edit trip');
select lives_ok($$insert into public.reactions (item_id, trip_id, rsvp) values ('e0000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'going')$$, 'member RSVPs');

-- leader can confirm
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$update public.items set confirmed = true where id = 'e0000000-0000-4000-8000-000000000001'$$, 'leader confirms');

select * from finish();
rollback;
