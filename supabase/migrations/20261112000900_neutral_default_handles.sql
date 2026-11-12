-- Default handles must not leak the email: a handle is visible to everyone on the same trip.
-- New accounts get "user_1234" (the user picks their own during onboarding).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, handle)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, ''), '@', 1)),
    public.make_handle('user')
  );
  insert into public.user_settings (id) values (new.id);
  return new;
end $$;

-- Replace the handles that were auto-generated from an email prefix by the previous migration.
-- A handle the user chose themselves does not match "<email prefix>_<4 digits>", so it is left alone.
do $$
declare r record;
begin
  for r in
    select p.id
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.handle ~ '_[0-9]{4}$'
      and left(p.handle, char_length(p.handle) - 5) = left(regexp_replace(lower(split_part(coalesce(u.email, ''), '@', 1)), '[^a-z0-9_]', '', 'g'), 14)
  loop
    update public.profiles set handle = public.make_handle('user') where id = r.id;
  end loop;
end $$;
