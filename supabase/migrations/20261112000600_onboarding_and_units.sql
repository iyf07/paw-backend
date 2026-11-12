-- First-run onboarding: set once the user has gone through (or skipped) the question flow.
alter table public.profiles add column onboarded_at timestamptz;

-- Default unit for new dogs' weight (per-dog display unit stays on the dog).
alter table public.user_settings add column weight_unit text not null default 'lb' check (weight_unit in ('lb', 'kg'));
