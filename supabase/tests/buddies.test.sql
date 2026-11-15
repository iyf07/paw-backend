-- Run with: supabase test db
begin;
select plan(16);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}');
update public.profiles set handle = 'alex_t' where id = '11111111-1111-4111-8111-111111111111';
update public.profiles set handle = 'morgan_t' where id = '22222222-2222-4222-8222-222222222222';
update public.profiles set handle = 'casey_t' where id = '33333333-3333-4333-8333-333333333333';

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
insert into public.dogs (id, name) values ('d0000000-0000-4000-8000-000000000002', 'Noodle');

-- Alex asks Morgan and Casey by ID
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.request_buddy('@Morgan_T')$$, 'ask by ID (with @ and capitals)');
select lives_ok($$select public.request_buddy('casey_t')$$, 'ask a second person');
select throws_ok($$select public.request_buddy('nobody_here')$$, 'P0001', 'unknown_handle', 'unknown ID rejected');
select throws_ok($$select public.request_buddy('alex_t')$$, 'P0001', 'self', 'cannot ask yourself');

-- look up before asking
select is((select display_name from public.find_buddy('@MORGAN_T')), 'Morgan', 'find by ID shows the name');
select is((select relation from public.find_buddy('morgan_t')), 'pending_out', 'relation: request sent');
select is((select relation from public.find_buddy('alex_t')), 'self', 'relation: yourself');
select is((select count(*)::int from public.find_buddy('nobody_here')), 0, 'unknown ID finds nothing');

-- Morgan sees the request (and who it is from) and accepts; Casey stays pending
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.buddies), 1, 'Morgan sees the request');
select is((select count(*)::int from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 1, 'Morgan can see Alex''s profile');
select is((select relation from public.find_buddy('alex_t')), 'pending_in', 'relation: they asked you');
select lives_ok($$select public.respond_buddy('11111111-1111-4111-8111-111111111111', true)$$, 'Morgan accepts');

-- Alex adds both to a trip: only the accepted buddy joins, with the dog
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
insert into public.trips (id, name, start_date, end_date) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'T', current_date, current_date + 1);
select is(public.add_buddies_to_trip('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', array['22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333']::uuid[], true), 1, 'only the accepted buddy joins');
select is((select count(*)::int from public.trip_dogs where trip_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'their dog came along');

-- Casey declines; the request is gone
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select lives_ok($$select public.respond_buddy('11111111-1111-4111-8111-111111111111', false)$$, 'Casey declines');
select is((select count(*)::int from public.buddies), 0, 'nothing left for Casey');

select * from finish();
rollback;
