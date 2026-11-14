-- Run with: supabase test db
begin;
select plan(12);

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

-- Morgan has a dog
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
insert into public.dogs (id, name) values ('d0000000-0000-4000-8000-000000000002', 'Noodle');

-- Alex creates a group and invites Morgan and Casey by ID
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
insert into public.buddy_groups (id, name) values ('b0000000-0000-4000-8000-000000000001', 'Us');
select is((select status from public.buddy_members where user_id = '11111111-1111-4111-8111-111111111111'), 'accepted', 'owner is an accepted member');
select lives_ok($$select public.invite_buddy('b0000000-0000-4000-8000-000000000001', '@Morgan_T')$$, 'invite by ID (with @ and capitals)');
select lives_ok($$select public.invite_buddy('b0000000-0000-4000-8000-000000000001', 'casey_t')$$, 'invite a second person');
select throws_ok($$select public.invite_buddy('b0000000-0000-4000-8000-000000000001', 'nobody_here')$$, 'P0001', 'unknown_handle', 'unknown ID rejected');

-- Morgan sees the invitation and the group, accepts; Casey has not answered
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.buddy_groups), 1, 'invitee sees the group');
select lives_ok($$select public.respond_buddy('b0000000-0000-4000-8000-000000000001', true)$$, 'Morgan accepts');
select throws_ok($$select public.invite_buddy('b0000000-0000-4000-8000-000000000001', 'casey_t')$$, '42501', 'only the owner can invite', 'a member cannot invite');

-- Alex creates a trip and adds the group: only Morgan (accepted) joins, with the dog
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
insert into public.trips (id, name, start_date, end_date) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'T', current_date, current_date + 1);
select is(public.add_buddies_to_trip('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'b0000000-0000-4000-8000-000000000001', true), 1, 'only the person who accepted joins');
select is((select count(*)::int from public.trip_dogs where trip_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), 1, 'their dog came along');

-- Casey (pending) was not added, and can decline
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select is((select count(*)::int from public.trips), 0, 'pending invitee is not on the trip');
select lives_ok($$select public.respond_buddy('b0000000-0000-4000-8000-000000000001', false)$$, 'Casey declines');
select is((select count(*)::int from public.buddy_groups), 0, 'after declining the group is gone from their view');

select * from finish();
rollback;
