-- A new optional numeric recall answer, independent of the legacy two-choice field.
-- Existing recall text is preserved; no unrequested guesses or data rewriting.
alter table public.dogs add column recall_level smallint check (recall_level between 1 and 5);
comment on column public.dogs.recall_level is '1 escape artist; 5 highly reliable off-leash recall. Optional; legacy recall text is retained separately.';
