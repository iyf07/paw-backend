-- lets the API embed a buddy's profile (name, avatar, ID) in one query, like trip_members
alter table public.buddy_members
  add constraint buddy_members_profile_fk foreign key (user_id) references public.profiles (id) on delete cascade;
