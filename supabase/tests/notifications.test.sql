-- Run with: supabase test db
begin;
select plan(14);
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}');
update public.profiles set handle = 'morgan_t' where id = '22222222-2222-4222-8222-222222222222';
update public.profiles set handle = 'casey_t' where id = '33333333-3333-4333-8333-333333333333';
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.request_buddy('morgan_t');
select public.request_buddy('casey_t');
select is((select count(*)::int from public.notifications), 0, 'asking creates no notification for me');

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select public.respond_buddy('11111111-1111-4111-8111-111111111111', true);
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select public.respond_buddy('11111111-1111-4111-8111-111111111111', false);
select is((select count(*)::int from public.notifications), 0, 'the one who answers gets nothing');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select is((select count(*)::int from public.notifications), 2, 'the asker gets both answers');
select is((select actor_name from public.notifications where kind = 'friend_declined'), 'Casey', 'the decliner''s name is kept although the row is gone');
select throws_ok($$insert into public.notifications (user_id, kind) values ('11111111-1111-4111-8111-111111111111', 'friend_accepted')$$, '42501', null, 'no direct inserts');
select lives_ok($$select public.dismiss_notification((select id from public.notifications where kind = 'friend_declined'))$$, 'dismiss one');
select is((select count(*)::int from public.notifications where read_at is null), 1, 'one left unread');

select public.set_buddy_relation('22222222-2222-4222-8222-222222222222', 'bestie');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select public.respond_buddy_relation('11111111-1111-4111-8111-111111111111', false);
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select is((select relation from public.notifications where kind = 'relation_declined'), 'bestie', 'a declined label is reported with the label');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.notifications), 0, 'other people''s notifications stay private');

-- family events
reset role;
update public.profiles set display_name = 'Casey' where id = '33333333-3333-4333-8333-333333333333';
insert into public.buddies (requester_id, addressee_id, status) values ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'accepted') on conflict do nothing;
update public.buddies set status = 'accepted' where requester_id = '11111111-1111-4111-8111-111111111111' and addressee_id = '33333333-3333-4333-8333-333333333333';
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.create_family('Home');
select public.invite_to_family('22222222-2222-4222-8222-222222222222');
select public.invite_to_family('33333333-3333-4333-8333-333333333333');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select public.respond_family_invite((select id from public.families limit 1), true);
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select public.respond_family_invite((select id from public.families limit 1), true);
select public.leave_family();
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select is((select count(*)::int from public.notifications where kind = 'family_left' and subject = 'Home'), 1, 'the admin hears that Casey left');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.notifications where kind = 'family_left'), 1, 'so does the other member');
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.disband_family();
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.notifications where kind = 'family_disbanded' and subject = 'Home'), 1, 'members hear about the disbanding');
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select is((select count(*)::int from public.notifications where kind = 'family_disbanded'), 0, 'the admin gets no notification about their own action');
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select is((select count(*)::int from public.notifications where kind = 'family_disbanded'), 0, 'someone who had already left is not told');
select * from finish();
rollback;
