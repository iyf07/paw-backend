-- PawTrip core schema.
-- Mirrors the prototype's data model, but relational. Display text never lives here: only codes
-- (e.g. 'hiking', 'planning', 30) so the UI can be translated. Times are minutes after midnight,
-- dates are plain dates, so items survive trip date changes.

------------------------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------------------------
create function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- Invite code like "3fa9c-1b07e": random, unguessable enough for a 30-day link.
create function public.new_invite_code() returns text
language sql volatile set search_path = '' as $$
  with u as (select replace(gen_random_uuid()::text, '-', '') as s)
  select substr(s, 1, 5) || '-' || substr(s, 6, 5) from u
$$;

------------------------------------------------------------------------------------------------
-- people
------------------------------------------------------------------------------------------------
-- Shareable part of a person: visible to everyone you share a trip with.
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 60),
  avatar_url   text,
  interests    text[] not null default '{}',
  diet         text[] not null default '{}',
  walking      smallint check (walking between 1 and 5),
  noise        smallint check (noise between 1 and 5),
  morning      smallint check (morning between 1 and 5),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Private to the user.
create table public.user_settings (
  id          uuid primary key references auth.users (id) on delete cascade,
  lang        text not null default 'zh' check (lang in ('zh', 'en')),
  temp_unit   text not null default 'F' check (temp_unit in ('F', 'C')),
  time_format text not null default '12' check (time_format in ('12', '24')),
  theme       text not null default 'system' check (theme in ('system', 'light', 'dark')),
  last_pace   text,
  last_budget text,
  updated_at  timestamptz not null default now()
);

-- Every scale is an integer 1-5 (null = not set), see DOG_SCALES in the prototype.
create table public.dogs (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 40),
  photo_url    text,
  weight_lb    numeric(5, 1) check (weight_lb >= 0),   -- canonical unit is lb
  weight_unit  text not null default 'lb' check (weight_unit in ('lb', 'kg')),  -- display only
  energy       smallint check (energy between 1 and 5),
  temp         smallint check (temp between 1 and 5),
  with_dogs    smallint check (with_dogs between 1 and 5),
  with_people  smallint check (with_people between 1 and 5),
  alone        smallint check (alone between 1 and 5),
  car          smallint check (car between 1 and 5),
  recall       text check (recall in ('runner', 'comes')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index dogs_owner_idx on public.dogs (owner_id);

------------------------------------------------------------------------------------------------
-- trips
------------------------------------------------------------------------------------------------
create table public.trips (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (char_length(name) between 1 and 80),
  place          text not null default '',
  lat            double precision,
  lon            double precision,
  tz             text not null default 'America/New_York',
  start_date     date not null,
  end_date       date not null,
  status         text not null default 'planning' check (status in ('planning', 'active', 'completed')),
  creator_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  interests      text[] not null default '{}',
  dist           smallint not null default 30 check (dist between 1 and 500),   -- search radius, miles
  filters        text[] not null default '{outdoors,food,coffee,sights}',
  pace           text,
  budget         text,
  invite_code    text not null unique default public.new_invite_code(),
  invite_expires date not null default (current_date + 30),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (end_date >= start_date)
);
create index trips_creator_idx on public.trips (creator_id);

create table public.trip_members (
  trip_id   uuid not null references public.trips (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);
create index trip_members_user_idx on public.trip_members (user_id);

create table public.trip_dogs (
  trip_id  uuid not null references public.trips (id) on delete cascade,
  dog_id   uuid not null references public.dogs (id) on delete cascade,
  added_by uuid default auth.uid() references auth.users (id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (trip_id, dog_id)
);
create index trip_dogs_dog_idx on public.trip_dogs (dog_id);

------------------------------------------------------------------------------------------------
-- plan content
------------------------------------------------------------------------------------------------
-- One row per idea / plan entry. "confirmed" is the leader's decision that it is in the plan;
-- whether everyone has answered (the prototype's readiness()) is computed in the client.
create table public.items (
  id          uuid primary key default gen_random_uuid(),
  trip_id     uuid not null references public.trips (id) on delete cascade,
  type        text not null check (type in ('activity', 'food', 'stay', 'transit', 'note')),
  cat         text check (cat in ('outdoors', 'food', 'coffee', 'sights', 'shopping', 'drinks', 'fun', 'stay', 'transit')),
  title       text not null default '' check (char_length(title) <= 120),
  emoji       text,
  confirmed   boolean not null default false,
  date        date,
  start_min   smallint check (start_min between 0 and 1440),
  end_min     smallint check (end_min between 0 and 1440),
  stay_from   date,
  stay_to     date,
  place       text not null default '',
  addr        text not null default '',
  notes       text not null default '',
  travel_min  smallint check (travel_min >= 0),
  lat         double precision,
  lon         double precision,
  ai          jsonb,          -- reserved for LLM suggestions (disabled for now)
  ai_key      text,
  source      text,           -- where the idea came from (e.g. discover)
  deleted_at  timestamptz,
  deleted_by  uuid references auth.users (id) on delete set null,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  edited_by   uuid references auth.users (id) on delete set null,
  edited_at   timestamptz not null default now(),
  unique (id, trip_id),       -- lets child rows prove they belong to the same trip
  check (start_min is null or end_min is null or end_min > start_min)
);
create index items_trip_idx on public.items (trip_id);

-- What each dog does during an item: along / watched by a sitter / left alone / not decided.
-- mood is the after-the-fact "how did they enjoy it" feedback (prototype MOODS).
create table public.item_dogs (
  item_id uuid not null,
  trip_id uuid not null,
  dog_id  uuid not null,
  mode    text not null default 'tbd' check (mode in ('with', 'sitter', 'alone', 'tbd')),
  mood    text check (mood in ('yay', 'ok', 'meh')),
  primary key (item_id, dog_id),
  foreign key (item_id, trip_id) references public.items (id, trip_id) on delete cascade,
  foreign key (trip_id, dog_id)  references public.trip_dogs (trip_id, dog_id) on delete cascade
);
create index item_dogs_trip_idx on public.item_dogs (trip_id);

create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  item_id    uuid not null,
  trip_id    uuid not null,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text       text not null check (char_length(text) between 1 and 2000),
  created_at timestamptz not null default now(),
  foreign key (item_id, trip_id) references public.items (id, trip_id) on delete cascade
);
create index comments_item_idx on public.comments (item_id);
create index comments_trip_idx on public.comments (trip_id);

-- One row per person per item: a vote and/or an RSVP.
create table public.reactions (
  item_id    uuid not null,
  trip_id    uuid not null,
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  vote       text check (vote in ('up', 'down')),
  rsvp       text check (rsvp in ('going', 'maybe', 'no')),
  updated_at timestamptz not null default now(),
  primary key (item_id, user_id),
  foreign key (item_id, trip_id) references public.items (id, trip_id) on delete cascade
);
create index reactions_trip_idx on public.reactions (trip_id);

------------------------------------------------------------------------------------------------
-- updated_at triggers
------------------------------------------------------------------------------------------------
create trigger profiles_touch      before update on public.profiles      for each row execute function public.touch_updated_at();
create trigger user_settings_touch before update on public.user_settings for each row execute function public.touch_updated_at();
create trigger dogs_touch          before update on public.dogs          for each row execute function public.touch_updated_at();
create trigger trips_touch         before update on public.trips         for each row execute function public.touch_updated_at();
create trigger reactions_touch     before update on public.reactions     for each row execute function public.touch_updated_at();
