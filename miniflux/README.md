# miniflux

[miniflux](https://miniflux.app): minimalist feed reader. Two services: the app
and its own postgres (per-stack database, nothing shared), data under
`DATA_DIR`. The database is only on the stack's internal network; the app is on
`proxy` too (gatus checks `http://miniflux:8080/healthcheck`).

    miniflux/
      compose.yaml          miniflux 2.3 + postgres 16 + daily pg_dump sidecar
      scripts/dump.sh       the dump loop
      .env                  PORT, DATA_DIR, TZ, DB_PASSWORD (rendered by dotfiles)

## Setup

1. `cp .env.example .env` or let dotfiles render it (`[data.homelab.miniflux]`,
   password from `passp service/miniflux/db`).
2. Fresh install: `CREATE_ADMIN=1` with `ADMIN_USERNAME`/`ADMIN_PASSWORD` for the
   first `make up.miniflux`, then back to 0.
3. Existing database: `make up.miniflux ARGS=db`, then
   `docker compose exec -T db pg_restore -U miniflux -d miniflux --no-owner --role=miniflux < dump`,
   then `make up.miniflux`.

## Operations

- Backup: the `db-dump` service writes `pg_dump -Fc` daily into `DUMP_DIR`
  (keeps `DUMP_KEEP`); backrest backs those up and excludes the live `db/`.
  Restore: `docker compose exec -T db pg_restore -U miniflux -d miniflux --clean --no-owner --role=miniflux < dump`.
- Postgres major upgrade (16 → 17/18): dump, bump the image tag and `DATA_DIR`
  to a new directory, restore. Renovate does not open PRs for postgres majors
  (`renovate.json`), check for a new major by hand.
- Logs: `make logs.miniflux`; feed polling errors show up per feed in the UI.
