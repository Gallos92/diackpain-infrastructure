#Runbook: Migration Drift Recovery

## Incident Summary

The application's Django migration files were squashed and reapplied
locally, but production already had a subset of the pre-squash migrations
applied. This left Django's migration history out of sync with the actual
database schema — new deploys couldn't run `migrate` cleanly because
Django's migration table no longer matched reality on disk.

## Symptoms

- `python manage.py migrate` fails with errors about migrations that
  don't exist, or attempts to re-run migrations whose schema changes are
  already present in the live database
- Deploys via the CI/CD pipeline start failing at the migration step
- Manual `migrate` attempts risk either erroring out or silently
  re-applying changes that could corrupt existing data

## Root Cause

Migration files were regenerated (squashed) in the app repo without
accounting for the fact that production's `django_migrations` table
still referenced the old, pre-squash migration names. Django tracks
"what's been applied" by migration filename/name, not by actual schema
state — so once the filenames changed, Django had no way to reconcile
the two.

## Recovery Steps

**1. Confirm the actual live schema before touching anything**

Connect to the running Postgres container and inspect the real tables
for the affected app:

```bash
docker compose exec db psql -U diackuser -d diackpain
\dt <app_name>_*
```

This confirms what tables/columns actually exist in production,
independent of what migration history claims.

**2. Fake-unapply the stale migrations**

Roll back Django's migration *record* (not the schema) to before the
squash point, without touching real data:

```bash
docker compose exec web python manage.py migrate <app_name> <last_known_good_migration> --fake
```

**3. Drop conflicting tables via raw SQL, if needed**

If the squash introduced a naming/structure mismatch that `--fake`
alone can't reconcile, drop only the specific affected tables directly
in psql (never a blanket drop):

```sql
DROP TABLE IF EXISTS <app_name>_<table_name> CASCADE;
```

Used carefully, scoped only to tables confirmed safe to rebuild via
Step 1's inspection.

**4. Delete stale migration files locally**

Remove the old pre-squash migration files from the app's `migrations/`
folder so they no longer conflict with the new squashed set.

**5. Regenerate and reapply**

```bash
docker compose exec web python manage.py makemigrations <app_name>
docker compose exec web python manage.py migrate <app_name>
```

**6. Verify**

Re-run the `\dt` inspection from Step 1 and diff it against a known-good
schema reference. Smoke-test the app's core flows (login, key CRUD
operations) before considering the incident closed.

## Prevention / Process Change

- Migrations are now squashed only in a controlled window, with a
  pre-deploy checklist step to check `django_migrations` state on
  production before pushing squashed migration files
- `\dt` schema inspection added as a standard first step for any
  migration-related deploy failure, before attempting any fix

## Debugging Tools Used

- `psql \dt <app>_*` — quick table existence/name check
- Django shell + `RequestFactory` — reproduce view-level errors outside
  the request/response cycle for faster iteration
