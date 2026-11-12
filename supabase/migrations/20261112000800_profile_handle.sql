-- Public unique ID ("handle"): one-to-one with the account UUID, human readable, globally unique.
-- The display name stays free text and can repeat; the handle never does.

alter table public.profiles add column handle text;

-- Internal helper: "alex" -> "alex_4821", retried until it is free.
create function public.make_handle(base text) returns text
language plpgsql set search_path = '' as $$
declare
  stem text := left(regexp_replace(lower(coalesce(base, '')), '[^a-z0-9_]', '', 'g'), 14);
  candidate text;
begin
  if char_length(stem) < 3 then stem := 'user'; end if;
  loop
    candidate := stem || '_' || lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (select 1 from public.profiles where handle = candidate);
  end loop;
  return candidate;
end $$;
revoke execute on function public.make_handle(text) from public, anon, authenticated;

-- Everyone who exists already gets a generated one (they can change it in the app).
do $$
declare r record;
begin
  for r in select p.id, u.email, p.display_name from public.profiles p join auth.users u on u.id = p.id loop
    update public.profiles set handle = public.make_handle(coalesce(nullif(split_part(coalesce(r.email, ''), '@', 1), ''), r.display_name)) where id = r.id;
  end loop;
end $$;

alter table public.profiles alter column handle set not null;
alter table public.profiles add constraint profiles_handle_format check (handle ~ '^[a-z0-9_]{3,20}$');
alter table public.profiles add constraint profiles_handle_reserved check (handle not in ('admin', 'administrator', 'support', 'pawtrip', 'root', 'system', 'moderator', 'me', 'you', 'null', 'undefined'));
create unique index profiles_handle_key on public.profiles (handle);

-- New accounts get a generated handle; the onboarding flow lets them pick their own.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, handle)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, ''), '@', 1)),
    public.make_handle(coalesce(nullif(split_part(coalesce(new.email, ''), '@', 1), ''), 'user'))
  );
  insert into public.user_settings (id) values (new.id);
  return new;
end $$;

-- Live availability check for the UI. True if `p_handle` is valid and nobody else has it.
create function public.handle_available(p_handle text) returns boolean
language sql stable security definer set search_path = '' as $$
  select lower(p_handle) ~ '^[a-z0-9_]{3,20}$'
     and lower(p_handle) not in ('admin', 'administrator', 'support', 'pawtrip', 'root', 'system', 'moderator', 'me', 'you', 'null', 'undefined')
     and not exists (select 1 from public.profiles where handle = lower(p_handle) and id <> (select auth.uid()))
$$;
revoke execute on function public.handle_available(text) from public, anon;
grant  execute on function public.handle_available(text) to authenticated;
