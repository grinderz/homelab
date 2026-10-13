# backrest

[Backrest](https://github.com/garethgeorge/backrest): web UI and scheduler over
restic. Backs up the server's own data (appdata first, the cloud mirror and
photos later) into a local restic repository on another disk; an offsite repo
(Yandex via rclone, or the backup host) is the next step.

    backrest/
      compose.yaml          backrest, UI on PORT, state in DATA_DIR
      config/config.json    seed: repos, plans, hooks (rendered by dotfiles, gitignored)

## How the config flows

`config/config.json` is rendered by dotfiles from `[data.homelab.backrest_plans]`
and the repo password from `passp` (`{{passp:restic/homelab-local}}`),
copied in by make and shipped with `make secrets.push`. The container copies it
into `DATA_DIR` **only when no config exists there**; after that backrest owns
its config (the UI edits it, backrest adds repo GUIDs and bumps `modno`). To
apply a changed seed: stop the stack, delete `DATA_DIR/config.json`, start.
Auth is disabled: the UI is reachable on the LAN only.

## Plans (seed)

- `appdata` — `/userdata/appdata` daily at 03:00, excludes caches, the old
  Appdata Backup archives and live database directories (those stacks dump
  into `*/dumps/` instead, e.g. miniflux `db-dump`). Retention 7 daily /
  4 weekly / 6 monthly. Repo `local` → `REPO_DIR`, prune weekly, check monthly.

- `flash` (Unraid host only) — `/userdata/boot/config` daily at 03:30: licence
  key, array assignments (`super.dat`), shares, plugins, Compose Manager
  pointers. Retention 14 / 8 / 12. `/boot` is a host-specific mount and comes
  through `compose.override.yaml` (rendered from `[data.homelab.backrest_mounts]`).

Hooks on every plan: snapshot error → notify stack (shoutrrr `generic+http`,
tag `primary`); snapshot success → gatus heartbeat `backrest_<host>-<plan>`
(26h deadline), so a plan that stopped running is noticed too.

## Setup

1. `cp .env.example .env` or let dotfiles render it (`[data.homelab.backrest]`).
2. `make deploy && make secrets.push && make up.backrest`; the repo is
   initialised by backrest on the first run (`autoInitialize`).
3. UI on `PORT`: run the plan once by hand, check the snapshot, restore a file
   into `/tmp` to prove the round trip.

## Operations

- Restore: UI → snapshot → browse → restore to a path under `/data` or
  `/repos/local/../restore`; or `restic -r /repos/local --password-file …`
  from inside the container (`make compose.backrest ARGS="exec backrest sh"`).
- The repo password is the key to everything: it is in `passp` and nowhere
  else outside the config.
- Adding a source: a read-only volume in `compose.yaml` and a plan in the
  toml (then re-seed) or in the UI.
