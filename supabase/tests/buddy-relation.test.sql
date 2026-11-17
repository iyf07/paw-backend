-- Run with: supabase test db
begin;
select plan(11);
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}');
update public.profiles set handle = 'alex_t' where id = '11111111-1111-4111-8111-111111111111';
update public.profiles set handle = 'morgan_t' where id = '22222222-2222-4222-8222-222222222222';
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.request_buddy('morgan_t');
select throws_ok($$select public.set_buddy_relation('22222222-2222-4222-8222-222222222222', 'bestie')$$, 'P0001', 'not_a_friend', 'no label before they accept');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select public.respond_buddy('11111111-1111-4111-8111-111111111111', true);
select isnt((select accepted_at from public.buddies), null, 'accepting records the date');
select lives_ok($$select public.set_buddy_relation('11111111-1111-4111-8111-111111111111', 'bestie')$$, 'Morgan proposes a label');
select is((select relation from public.buddies), null, 'a proposal alone does not set the label');
select is((select relation_proposed from public.buddies), 'bestie', 'the proposal is stored');
select lives_ok($$select public.respond_buddy_relation('11111111-1111-4111-8111-111111111111', true)$$, 'the proposer cannot accept their own proposal (no effect)');
select is((select relation from public.buddies), null, 'still not set after the proposer answers');
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.respond_buddy_relation('22222222-2222-4222-8222-222222222222', true)$$, 'Alex accepts');
select is((select relation from public.buddies), 'bestie', 'label stored after consent');
select throws_ok($$select public.set_buddy_relation('22222222-2222-4222-8222-222222222222', 'enemy')$$, '23514', null, 'only known labels');
select throws_ok($$select public.set_buddy_relation('33333333-3333-4333-8333-333333333333', 'pal')$$, 'P0001', 'not_a_friend', 'only for my own friends');
select * from finish();
rollback;
