-- Run with: supabase test db
begin;
select plan(5);
insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}');
insert into public.dogs (id, owner_id, name) values ('d0000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Biscuit');
insert into public.buddies (requester_id, addressee_id, status) values ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'accepted');
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select public.create_family('Home');
select public.invite_to_family('22222222-2222-4222-8222-222222222222');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select public.respond_family_invite((select id from public.families limit 1), true);
select throws_ok($$select public.disband_family()$$, '42501', null, 'a member cannot disband');
select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.disband_family()$$, 'the admin disbands');
select is((select count(*)::int from public.families), 0, 'the family is gone');
select is((select count(*)::int from public.family_members), 0, 'and so are the memberships');
select is((select count(*)::int from public.dogs), 1, 'the dog is untouched');
select * from finish();
rollback;
