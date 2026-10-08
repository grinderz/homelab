# Working in this repo

Docker compose stacks for the home server, one directory per stack. README.md
has the layout rules; keep them when adding a stack.

## Hosts

- **The docker host** (ssh alias = `DEPLOY_HOST` in ~/.config/homelab/config.mk or
  local.mk, never spelled out here) — Unraid 7.1.4, x86_64, 8 cores, 15 GB
  RAM, array 5.5 TB (2.2 TB free) at /mnt/user. No systemd, no `docker compose`
  binary; Compose Manager Plus plugin installed (`docker compose` v5.5), stacks
  registered as pointer dirs under /boot/config/plugins/compose.manager/projects/.
  Root over ssh. Working copy of this repo lives at /mnt/user/appdata/homelab,
  synced with `make deploy` (rsync, see Makefile; `make deploy.diff` first);
  the host never gets a git checkout. `config/` dirs on the server must stay 99:100 (rclone
  rewrites rclone.conf on token refresh). Files written by containers must be 99:100
  (nobody:users) or SMB cannot touch them. Unraid auto-creates a share for any
  directory made under /mnt/user.
- Existing containers there (dockerMan templates, not yet moved to this repo):
  syncthing, Postgres11 (postgres:16), miniflux, beszel, beszel-agent; templates
  also exist for emby, photoprism, archivebox, linkwarden, adguard, nginx,
  rutorrent, transmission, sftpgo, searxng, invidious, kavita, lychee, metube,
  torrserver, gatus, dozzle, zerotier, sing-box.
- Future target: Proxmox. Nothing in a stack may depend on Unraid.

## Division of labour

- The user commits and pushes; propose the command, stop.
- The user installs Unraid plugins and creates OAuth clients; anything that
  needs a browser is theirs.
- Everything else on the server (copying files, test runs, starting or
  stopping these stacks, creating directories) do without asking.
- Propose a change first, edit after an explicit ok; a question answered in
  the direction of the proposal counts.
- Edits in auto mode: show the diff of touched files in the reply.

## Verifying

A stack is not done because the yaml parses. Run it on the server against a
fake remote or throwaway data as the target uid, check what landed on disk and
who owns it. For cloud-sync the pattern is an `alias` remote pointing at a
/tmp directory, see git history of the first test.

## Tooling quirks

- A bash guard hook refuses any command whose text contains `.git`, including
  `rm -rf x/.git`. Move the whole directory or rsync with `--exclude='.g??'`.
