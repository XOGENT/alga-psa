# Deploying Alga PSA (CE) on Coolify

`docker-compose.coolify.yaml` runs the Community Edition stack with Coolify's Docker Compose
build pack: Postgres (pgvector), PgBouncer, Redis, the one-shot `setup` job (roles, migrations,
seeds), the Next.js `server`, Temporal, and the workflow worker.

## How secrets work

Every service reads its secrets from `/run/secrets/*`, exactly as in the plain Compose stack.
Instead of a local `./secrets` directory, Coolify generates the values (`SERVICE_PASSWORD_64_ALGA*`)
on first deploy and persists them. The one-shot `secrets-init` service writes them into one
`secrets_<consumer>` volume per service (files `0400`, owned by the uid that reads them), so
each container sees only the secrets it needs. The server's `/run/secrets` is read-only apart
from `tenants/`, a separate `tenant_secrets` volume where per-tenant secrets are stored — back it
up together with the database.

- Do **not** rotate `SERVICE_PASSWORD_64_ALGAPOSTGRES` after the first deploy: Postgres only
  reads it when the data directory is initialised. (`..._ALGAAPPUSER` is safe to rotate; `setup`
  re-syncs the app user's password on every deploy.)
- Do **not** rotate `SERVICE_PASSWORD_64_ALGANEXTAUTH`: user password hashes are keyed on it, so
  every existing password stops working.
- Treat `SERVICE_PASSWORD_64_ALGACRYPTO` and `..._ALGACREDENTIAL` as permanent once data exists.
- Do **not** also add a secret (e.g. `NEXTAUTH_SECRET`) as a Coolify env var. Secrets are read from
  env before files, so a different env value silently overrides the file and breaks sign-in.
- Optional: set `EMAIL_PASSWORD`, `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` in Coolify;
  their files are only written when non-empty.

## Create the resource

1. DNS: point an `A` record for the app's domain at the server's IP.
2. In Coolify: **Projects → + Add** (e.g. `alga-psa`), open the `production` environment,
   **+ New → Public Repository** with the repository's HTTPS URL (a GitHub App source also
   works for private forks), choose the branch that contains `docker-compose.coolify.yaml`,
   and select the target server. Avoid `/` in the branch name.
3. **Build Pack:** Docker Compose. **Base Directory:** `/`.
   **Docker Compose Location:** `/docker-compose.coolify.yaml`. Click **Load Compose File**.
4. **Domains:** set the `server` service to `https://<your-domain>:3000`
   (`:3000` is the container port Traefik routes to; the public URL has no port).
5. **Environment Variables:** set `ALGA_PUBLIC_URL=https://<your-domain>`.
6. **Deploy.** The first deploy builds Redis, PgBouncer and the workflow worker from source and
   pulls the server image (adding the repository's setup scripts on top via
   `docker/coolify/app.Dockerfile`); `setup` then creates the databases and runs migrations before
   `server` starts. Watch `setup` logs if `server` never starts.

## First login

`setup` seeds a sample workspace (tenant "Oz") whose admin is `glinda@emeraldcity.oz`. In
production the server does **not** print or provision a password for it (that only happens with
`NODE_ENV=development`, despite what the general setup guide says), so set one once:

1. In Coolify open the application's **Terminal**, pick the `server` container, and run
   `bash /app/coolify/set-admin-password.sh` (optionally pass a different internal user's email).
2. Enter a password of at least 12 characters twice; it is read without echo and never logged.
3. Sign in at `https://<your-domain>/auth/msp/signin`, then change Glinda's name/email to a real
   admin account and remove the demo users and data you don't want.

The other seeded demo users have intentionally invalid password hashes and cannot sign in.

## Upgrades

`ALGA_IMAGE_TAG` (the 8-character commit SHA of a `main` commit with a published
`ghcr.io/nine-minds/alga-psa-ce` image) must match the commit the branch is deployed from,
because Redis, PgBouncer, setup scripts and the workflow worker come from the checkout. To
upgrade: rebase the deploy branch onto the new commit, set `ALGA_IMAGE_TAG` to its short SHA
(default in the compose file or a Coolify env var), and redeploy. `setup` runs new migrations.

## Known gaps (same as the upstream Compose stack)

- Redis has no data volume, so in-flight workflow event streams are lost when it is recreated.
- `redis/Dockerfile` and `pgbouncer/Dockerfile` build from floating `latest` base images.
- On the very first boot the workflow worker may restart once if Temporal is still registering
  its `default` namespace; `restart: unless-stopped` recovers it.

## Backups

Postgres data lives in the `postgres_data` volume, uploaded files in `files_data`, and
per-tenant secrets in `tenant_secrets`. These are
part of a Compose application, not a Coolify-managed database, so Coolify's database backup
scheduler does not cover them — add a scheduled task (e.g. `pg_dump` from the `postgres` service)
or volume-level backups.
