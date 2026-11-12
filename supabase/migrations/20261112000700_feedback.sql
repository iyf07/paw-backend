-- In-app feedback. Users can send it and read their own; everything else (status, notes) is written by the
-- maintainer through the service/CLI side. Feedback text is untrusted user input: treat it as data.
create table public.feedback (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind            text not null check (kind in ('bug', 'idea', 'other')),
  message         text not null check (char_length(message) between 1 and 2000),
  route           text check (char_length(route) <= 300),          -- screen the user was on
  app_version     text check (char_length(app_version) <= 100),     -- "1.0.0+<git commit>"
  platform        text check (char_length(platform) <= 400),        -- OS / browser
  lang            text check (lang in ('zh', 'en')),
  screenshot_path text check (char_length(screenshot_path) <= 300), -- object in the private `feedback` bucket
  -- maintainer side
  status          text not null default 'new' check (status in ('new', 'triaged', 'fixed', 'wontfix')),
  resolution      text,         -- short note shown to the user
  fixed_in        text,         -- git commit that fixed it
  handled_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index feedback_user_idx   on public.feedback (user_id, created_at desc);
create index feedback_status_idx on public.feedback (status, created_at);

create trigger feedback_touch before update on public.feedback for each row execute function public.touch_updated_at();

-- At most 10 per hour per user.
create function public.feedback_rate_limit() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (select count(*) from public.feedback where user_id = new.user_id and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke execute on function public.feedback_rate_limit() from public, anon, authenticated;

create trigger feedback_rate_limit_trg before insert on public.feedback for each row execute function public.feedback_rate_limit();

alter table public.feedback enable row level security;

create policy feedback_select_own on public.feedback for select to authenticated
  using (user_id = (select auth.uid()));
create policy feedback_insert_own on public.feedback for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'new');

-- Users may only fill the "what happened" columns; status / resolution / fixed_in stay maintainer-only.
revoke all on public.feedback from authenticated;
grant select on public.feedback to authenticated;
grant insert (kind, message, route, app_version, platform, lang, screenshot_path) on public.feedback to authenticated;

-- Screenshots: private bucket, each user reads and writes only their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback', 'feedback', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy feedback_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'feedback' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy feedback_files_select on storage.objects for select to authenticated
  using (bucket_id = 'feedback' and (storage.foldername(name))[1] = (select auth.uid())::text);
