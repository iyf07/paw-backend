-- Run with: supabase test db
begin;
select plan(5);
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}');
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

insert into public.trips (id, name, start_date, end_date, creator_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Weekend', current_date, current_date + 1, '11111111-1111-4111-8111-111111111111');
insert into public.trip_members (trip_id, user_id) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111') on conflict do nothing;
create temp table t_trip as select 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid as id;
grant select on t_trip to authenticated;
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select throws_ok($$insert into public.trip_recommendations (trip_id, day, lang, payload) select id, current_date, 'en', '{}' from t_trip$$, '42501', null, 'members cannot write recommendations');
reset role;
insert into public.trip_recommendations (trip_id, day, lang, payload) select id, current_date, 'en', '{"items":[]}' from t_trip;
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select is((select count(*)::int from public.trip_recommendations), 1, 'a trip member reads it');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.trip_recommendations), 0, 'a stranger sees nothing');
select throws_ok($$delete from public.trip_recommendations$$, '42501', null, 'strangers cannot delete');
select throws_ok($$update public.trip_recommendations set payload = '{}'$$, '42501', null, 'strangers cannot update');
select * from finish();
rollback;
