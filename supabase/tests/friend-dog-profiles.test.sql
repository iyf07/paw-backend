begin;
select plan(15);
insert into auth.users(id,email,raw_user_meta_data) values
('a1111111-1111-4111-8111-111111111111','friend-reader@t.dev','{"name":"Reader"}'),
('a2222222-2222-4222-8222-222222222222','friend-owner@t.dev','{"name":"Owner"}'),
('a3333333-3333-4333-8333-333333333333','friend-stranger@t.dev','{"name":"Stranger"}');
update public.profiles set handle='friend_owner_t', interests=array['hiking','pizza'] where id='a2222222-2222-4222-8222-222222222222';
create function pg_temp.as_user(uid uuid) returns void language plpgsql as $$
begin
 perform set_config('request.jwt.claims',json_build_object('sub',uid,'role','authenticated')::text,true);
 execute 'set local role authenticated';
end $$;
select pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
insert into public.dogs(id,name,energy) values('da000000-0000-4000-8000-000000000001','Friend Dog',4);
select pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
select is((select count(*)::int from public.dogs where id='da000000-0000-4000-8000-000000000001'),0,'stranger cannot read dog');
select is((select dogs->0->>'name' from public.find_friend_profile('@FRIEND_OWNER_T')),'Friend Dog','ID lookup can read dog before friendship');
select is((select interests from public.find_friend_profile('friend_owner_t')),array['hiking','pizza'],'ID lookup includes interests');
select is((select count(*)::int from public.find_friend_profile('unknown_friend_t')),0,'unknown ID returns no profile');
select is((select dogs->0->>'energy' from public.find_friend_profile('friend_owner_t')),'4','lookup includes dog scale values');
select is((select dogs->0 ? 'created_at' from public.find_friend_profile('friend_owner_t')),false,'lookup only exposes explicit dog profile fields');
reset role;
set local role anon;
select throws_ok($$select * from public.find_friend_profile('friend_owner_t')$$,'42501','permission denied for function find_friend_profile','anonymous lookup denied');
reset role;
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select * from public.find_friend_profile('friend_owner_t')$$,'28000','not signed in','authenticated role still needs a user identity');

select pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
select public.request_buddy('friend_owner_t');
select is((select count(*)::int from public.dogs where id='da000000-0000-4000-8000-000000000001'),0,'pending request does not expose dogs');
select pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
select public.respond_buddy('a1111111-1111-4111-8111-111111111111',true);
select pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
select is((select count(*)::int from public.dogs where id='da000000-0000-4000-8000-000000000001'),1,'accepted friend sees dog without shared trip');
select is((select interests from public.profiles where id='a2222222-2222-4222-8222-222222222222'),array['hiking','pizza'],'friend can read selected interests');
with changed as(update public.dogs set name='Unauthorized' where id='da000000-0000-4000-8000-000000000001' returning id) select is((select count(*)::int from changed),0,'friend cannot edit dog');
with removed as(delete from public.dogs where id='da000000-0000-4000-8000-000000000001' returning id) select is((select count(*)::int from removed),0,'friend cannot delete dog');
delete from public.buddies where requester_id=auth.uid();
select is((select count(*)::int from public.dogs where id='da000000-0000-4000-8000-000000000001'),0,'removing friend revokes dog access');
select pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
select is((select name from public.dogs where id='da000000-0000-4000-8000-000000000001'),'Friend Dog','owner retains unchanged dog');
select * from finish();
rollback;
