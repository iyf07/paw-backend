-- PostgREST can only embed related rows across a foreign key. These tables reference auth.users;
-- add a second FK to public.profiles (same id) so the app can select `profiles(display_name, avatar_url)`
-- together with members, dogs, comments and reactions in a single request.
alter table public.trip_members add constraint trip_members_profile_fk foreign key (user_id)  references public.profiles (id) on delete cascade;
alter table public.dogs         add constraint dogs_profile_fk         foreign key (owner_id) references public.profiles (id) on delete cascade;
alter table public.comments     add constraint comments_profile_fk     foreign key (user_id)  references public.profiles (id) on delete cascade;
alter table public.reactions    add constraint reactions_profile_fk    foreign key (user_id)  references public.profiles (id) on delete cascade;
alter table public.trips        add constraint trips_creator_profile_fk foreign key (creator_id) references public.profiles (id) on delete cascade;
