-- Run with: supabase test db
begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev'),
  ('22222222-2222-4222-8222-222222222222', 'alex@other.dev');

select matches((select handle from public.profiles where id = '11111111-1111-4111-8111-111111111111'), '^alex_[0-9]{4}$', 'new account gets a generated handle');
select isnt((select handle from public.profiles where id = '11111111-1111-4111-8111-111111111111'), (select handle from public.profiles where id = '22222222-2222-4222-8222-222222222222'), 'two alex@ emails get different handles');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$update public.profiles set handle = 'nick_the_dog' where id = '11111111-1111-4111-8111-111111111111'$$, 'user can choose their own handle');
select is(public.handle_available('nick_the_dog'), true, 'own handle counts as available to its owner');

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is(public.handle_available('Nick_The_Dog'), false, 'taken handle is not available (case-insensitive)');
select throws_ok($$update public.profiles set handle = 'nick_the_dog' where id = '22222222-2222-4222-8222-222222222222'$$, '23505', null, 'duplicate handle is rejected');
select throws_ok($$update public.profiles set handle = 'Bad Name!' where id = '22222222-2222-4222-8222-222222222222'$$, '23514', null, 'invalid characters are rejected');
select throws_ok($$update public.profiles set handle = 'admin' where id = '22222222-2222-4222-8222-222222222222'$$, '23514', null, 'reserved handle is rejected');
select is(public.handle_available('ab'), false, 'too short is not available');

select * from finish();
rollback;
