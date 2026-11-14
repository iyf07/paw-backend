-- Run with: supabase test db
begin;
select plan(7);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
insert into public.trips (id, name, start_date, end_date) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'T', '2027-03-10', '2027-03-12');
insert into public.items (id, trip_id, type, title, date, start_min, end_min, confirmed) values
  ('e0000000-0000-4000-8000-000000000001', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'activity', 'Hike', '2027-03-11', 540, 600, true);
insert into public.items (id, trip_id, type, title, stay_from, stay_to) values
  ('e0000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'stay', 'Cabin', '2027-03-10', '2027-03-12');
insert into public.items (id, trip_id, type, title) values
  ('e0000000-0000-4000-8000-000000000003', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'activity', 'Idea');

select is(public.move_trip('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2027-04-01', '2027-04-03'), 2, 'leader moves the trip; 2 scheduled items change');
select is((select start_date::text || ' ' || end_date::text from public.trips where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '2027-04-01 2027-04-03', 'dates moved');
select is((select count(*)::int from public.items where trip_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' and (date is not null or stay_from is not null or confirmed)), 0, 'all items are ideas now');
select is((select count(*)::int from public.items where trip_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 3, 'no item lost');
select throws_ok($$select public.move_trip('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2027-04-05', '2027-04-01')$$, '22023', 'end before start', 'bad range rejected');

-- a member who is not the leader cannot move it
reset role;
insert into public.trip_members (trip_id, user_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select throws_ok($$select public.move_trip('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '2027-05-01', '2027-05-02')$$, '42501', 'only the trip leader can move the trip', 'member cannot move');
reset role;
select is((select start_date::text from public.trips where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), '2027-04-01', 'dates unchanged by the member');

select * from finish();
rollback;
