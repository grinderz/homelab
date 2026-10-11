# cloud-sync

Mirrors cloud drives (Yandex Disk, Google Drive) into a local tree with rclone,
inside one container. Nothing host-specific: move the directory, edit `.env`,
start it again.

    cloud-sync/
      compose.yaml          container definition
      scripts/loop.sh       entrypoint: sync every remote, sleep INTERVAL, repeat
      scripts/sync.sh       one remote: rclone sync + backup-dir + prune + ping
      config/rclone.conf    remotes and tokens (gitignored)
      .env                  host paths, uid/gid, interval (gitignored)

Layout on disk:

    $DATA_DIR/<remote>/                 current mirror, browse it as files
    $HISTORY_DIR/<remote>/<YYYY-MM-DD>/ what that day's run deleted or overwrote
    $HISTORY_DIR/<remote>/sync.log      rclone log

## Setup

1. `cp .env.example .env`, set paths and uid/gid — or let dotfiles render it
   (`[data.homelab.cloud_sync]` → `~/.config/homelab/cloud-sync/.env`, copied in
   by make; the same for `config/<remote>.filter` from
   `[data.homelab.cloud_sync_filters]`).
2. `cp config/rclone.conf.example config/rclone.conf`, paste tokens:
   - Yandex: on a machine with a browser run `rclone authorize yandex`, copy the
     token line.
   - Google: create an OAuth client (Desktop app) in Google Cloud Console with the
     Drive API enabled. Set the OAuth app to "In production" (Branding needs a
     name, support email and any URL you own; verification is not required) —
     in "Testing" the refresh token dies after 7 days. Then

         rclone authorize drive $(printf '%s' '{"client_id":"ID","client_secret":"SECRET","scope":"drive.readonly"}' | base64 | tr -d '\n=')

     (rclone 1.75 takes the JSON only as unpadded base64). The output is a
     base64 blob too: `base64 -d` it, take the `token` value. `scope =
     drive.readonly` keeps the token unable to touch the drive. In the browser
     expect "Google hasn't verified this app" → Advanced → continue.
   Optional `config/<remote>.filter` (rclone `--filter-from` syntax, host-side
   like `.env`, gitignored) excludes paths, e.g. shared files the owner forbids
   downloading:

       - /Some shared file.docx
       - /Some folder/**
3. Dry run from the directory:

       docker compose run --rm --entrypoint rclone cloud-sync sync yandex: /data/yandex --dry-run --config /config/rclone/rclone.conf

4. `docker compose up -d`.

## Host notes

- **Unraid**: Compose Manager plugin (Community Applications) runs compose.yaml
  and starts it with the array (autostart flag in the plugin's project dir).
- **Proxmox**: run it inside an LXC or VM that has docker; point DATA_DIR at the
  mounted datastore.

## Operations

Alerts: a failed run posts to the notify stack (`NOTIFY_URL`, tag `primary`,
then `fallback` when the gateway reports a delivery failure) with the exit code
and the last `ERROR` line; `NOTIFY_OK=1` adds one line per successful run with
the transfer stats. The gateway being down costs one log line, never the sync.

- Logs: `docker logs cloud-sync` (summary) and `$HISTORY_DIR/<remote>/sync.log`.
- Force a run now: `docker compose exec cloud-sync /scripts/sync.sh yandex`.
- Restore a file: it is a plain file under `$DATA_DIR`, or under the dated
  history directory if it was deleted.
- Token refresh: rclone rewrites `config/rclone.conf` itself; that is why the
  directory, not the file, is mounted.
