-- Run with: supabase test db
begin;
select plan(11);
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}');
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.create_family('Home');
create temp table t_code as select public.rotate_family_code()->>'code' as code;
grant select on t_code to authenticated;
select matches((select code from t_code), '^[0-9a-f]{5}-[0-9a-f]{5}$', 'admin gets a code');
select throws_ok($$select invite_code from public.families$$, '42501', null, 'the code cannot be read from the table');

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select throws_ok($$select public.rotate_family_code()$$, '42501', null, 'a non-member cannot make a code');
select is((select public.peek_family((select code from t_code))->>'name'), 'Home', 'peek shows the family');
select is(public.peek_family('nope-nope'), null, 'unknown code finds nothing');
select throws_ok($$select public.join_family('nope-nope')$$, 'P0001', 'invalid_code', 'bad code rejected');
select lives_ok($$select public.join_family((select code from t_code))$$, 'Morgan joins with the code');
select is(public.is_family_mate('11111111-1111-4111-8111-111111111111'), true, 'now family mates');
select throws_ok($$select public.join_family((select code from t_code))$$, 'P0001', 'already_in_family', 'cannot join twice');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.rotate_family_code();
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select throws_ok($$select public.join_family((select code from t_code))$$, 'P0001', 'invalid_code', 'a new code replaces the old one');
reset role;
update public.families set invite_expires = now() - interval '1 minute';
select pg_temp.as_user('33333333-3333-4333-8333-333333333333');
select throws_ok($$select public.join_family('whatever-1')$$, 'P0001', 'invalid_code', 'expired or unknown rejected');
select * from finish();
rollback;
