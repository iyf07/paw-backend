alter table public.dogs add column interests text[] not null default '{}'::text[];
alter table public.dogs add constraint dogs_interests_allowed check (interests <@ array['dog_park','trails','camping','swimming','paddling','snow','sand','sunbathing','sniffing','fetch','treats','sleeping','off_leash']::text[]);

-- Exact public-ID lookup, explicitly requested for pre-friend profile previews.
-- Authenticated callers receive only selected interests and explicit dog profile fields.
create or replace function public.find_friend_profile(p_handle text)
returns table(id uuid,display_name text,avatar_url text,handle text,relation text,interests text[],dogs jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'not signed in' using errcode='28000'; end if;
 return query
 select f.id,f.display_name,f.avatar_url,f.handle,f.relation,p.interests,
 coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'photo_url',d.photo_url,'weight_lb',d.weight_lb,'weight_unit',d.weight_unit,'energy',d.energy,'temp',d.temp,'with_dogs',d.with_dogs,'with_people',d.with_people,'alone',d.alone,'car',d.car,'recall_level',d.recall_level,'interests',d.interests) order by d.created_at,d.id) from public.dogs d where d.owner_id=f.id),'[]'::jsonb)
 from public.find_buddy(p_handle) f join public.profiles p on p.id=f.id;
end $$;
revoke all on function public.find_friend_profile(text) from public,anon;
grant execute on function public.find_friend_profile(text) to authenticated;
