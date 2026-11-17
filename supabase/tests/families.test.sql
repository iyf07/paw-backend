-- Run with: supabase test db
begin;
select plan(20);

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'alex@t.dev',   '{"name":"Alex"}'),
  ('22222222-2222-4222-8222-222222222222', 'morgan@t.dev', '{"name":"Morgan"}'),
  ('33333333-3333-4333-8333-333333333333', 'casey@t.dev',  '{"name":"Casey"}'),
  ('44444444-4444-4444-8444-444444444444', 'drew@t.dev',   '{"name":"Drew"}');
insert into public.dogs (id, owner_id, name) values
  ('d0000000-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'Biscuit'),
  ('d0000000-0000-4000-8000-000000000002', '22222222-2222-4222-8222-222222222222', 'Noodle'),
  ('d0000000-0000-4000-8000-000000000004', '44444444-4444-4444-8444-444444444444', 'Stranger');
-- friends: Alex-Morgan, Alex-Casey (Drew is nobody's friend)
insert into public.buddies (requester_id, addressee_id, status) values
  ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', 'accepted'),
  ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333', 'accepted');

create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.create_family('  Home  ')$$, 'Alex creates a family');
select is((select name from public.families), 'Home', 'name is trimmed');
select throws_ok($$select public.create_family('Second')$$, 'P0001', 'already_in_family', 'only one family per person');
select throws_ok($$select public.invite_to_family('44444444-4444-4444-8444-444444444444')$$, 'P0001', 'not_a_friend', 'only friends can be invited');
select lives_ok($$select public.invite_to_family('22222222-2222-4222-8222-222222222222')$$, 'invite a friend');
select is(public.is_family_mate('22222222-2222-4222-8222-222222222222'), false, 'a pending invitation shares nothing yet');

select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is((select count(*)::int from public.family_members), 2, 'Morgan sees the family he is invited to');
select is((select count(*)::int from public.profiles where id = '11111111-1111-4111-8111-111111111111'), 1, 'and who invited him');
select throws_ok($$select public.invite_to_family('33333333-3333-4333-8333-333333333333')$$, '42501', null, 'a pending member cannot invite');
select lives_ok(format($$select public.respond_family_invite(%L, true)$$, (select id from public.families limit 1)), 'Morgan accepts');

-- sharing: read and edit mates'' dogs, never delete, never take over
select is(public.is_family_mate('11111111-1111-4111-8111-111111111111'), true, 'Morgan is Alex''s family mate');
update public.dogs set name = 'Biscuit II' where id = 'd0000000-0000-4000-8000-000000000001';
select is((select name from public.dogs where id = 'd0000000-0000-4000-8000-000000000001'), 'Biscuit II', 'mate can edit the dog');
select throws_ok($$update public.dogs set owner_id = '22222222-2222-4222-8222-222222222222' where id = 'd0000000-0000-4000-8000-000000000001'$$, '42501', null, 'mate cannot take the dog over');
delete from public.dogs where id = 'd0000000-0000-4000-8000-000000000001';
select is((select count(*)::int from public.dogs where id = 'd0000000-0000-4000-8000-000000000001'), 1, 'mate cannot delete the dog');
select is((select count(*)::int from public.dogs where owner_id = '44444444-4444-4444-8444-444444444444'), 0, 'strangers'' dogs stay private');

-- Alex cannot invite someone who is already in a family; Casey can be invited, a non-admin cannot remove people
select throws_ok($$select public.remove_family_member('11111111-1111-4111-8111-111111111111')$$, '42501', null, 'a member cannot remove the admin');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.remove_family_member('22222222-2222-4222-8222-222222222222')$$, 'admin removes Morgan');
select pg_temp.as_user('22222222-2222-4222-8222-222222222222');
select is(public.is_family_mate('11111111-1111-4111-8111-111111111111'), false, 'removal stops sharing at once');

select pg_temp.as_user('11111111-1111-4111-8111-111111111111');
select lives_ok($$select public.leave_family()$$, 'the last member leaving closes the family');
select is((select count(*)::int from public.families), 0, 'family is gone');

select * from finish();
rollback;
