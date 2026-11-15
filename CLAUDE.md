# PawTrip backend — instructions for every agent

This repo is the Supabase backend for PawTrip. **Read `/Users/ivan/workplace/pawtrip-app/docs/AGENT_HANDOFF.md` first**
(sections 3 and 8 cover migrations, tests, deploy and how agents coordinate) and update it before you stop.

- Never edit a migration that was already pushed; add a new one (`YYYYMMDDHHMMSS_name.sql`).
- `supabase migration up --local`, then `supabase test db` (all pass), then `supabase db push --linked --dry-run` and the real push for additive changes.
- Ask the user before any migration that rewrites or deletes production data.
- Regenerate `pawtrip-app/pawtrip/src/lib/database.types.ts` after schema changes.
