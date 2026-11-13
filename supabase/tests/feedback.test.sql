-- Run with: supabase test db
begin;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'a@t.dev'),
  ('22222222-2222-4222-8222-222222222222', 'b@t.dev');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$insert into public.feedback (kind, message, route) values ('bug', 'it broke', '/trip/x/plan')$$, 'user sends feedback');
select throws_ok($$insert into public.feedback (user_id, kind, message) values ('22222222-2222-4222-8222-222222222222', 'bug', 'as someone else')$$, '42501', null, 'cannot send as another user');
select throws_ok($$insert into public.feedback (kind, message, status) values ('bug', 'x', 'fixed')$$, '42501', null, 'cannot set status');
select throws_ok($$update public.feedback set status = 'fixed'$$, '42501', null, 'cannot update feedback');
select is((select count(*)::int from public.feedback), 1, 'sender sees their own feedback');

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.feedback), 0, 'others cannot see it');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select throws_ok($$insert into public.feedback (kind, message) values ('rant', 'bad kind')$$, '23514', null, 'unknown kind is rejected');

-- rate limit: 60 per hour
insert into public.feedback (kind, message) select 'other', 'spam ' || g from generate_series(1, 59) g;
select throws_ok($$insert into public.feedback (kind, message) values ('other', 'one too many')$$, 'P0001', 'rate_limited', '61st feedback in an hour is rejected');


select * from finish();
rollback;
