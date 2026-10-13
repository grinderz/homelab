# homelab

Every service is a docker compose stack in its own directory. The repo is the
only thing a host needs besides docker: deploy it, fill `.env` files, start
stacks. Currently on Unraid, meant to move to Proxmox or anything else.

    homelab/
      networks.sh        creates shared networks (run once per host)
      <stack>/
        compose.yaml     the service
        .env.example     every host-specific value, with comments
        .env             real values, gitignored
        README.md        setup and operations for that stack

## Rules

- One directory per stack, one `compose.yaml` per directory. A stack is what
  gets started and stopped together; unrelated services do not share a file.
- Host-specific values (paths, uid/gid, ports, hostnames, secrets) live in
  `.env` only. `compose.yaml` must be identical on every host.
- Shared networks are external, created by `networks.sh`, referenced with
  `external: true`. Only services that talk to each other join `proxy`.
- Data stays outside the repo. Config a service writes to itself (tokens,
  databases) is mounted as a directory, gitignored.
- Images are pinned to a minor version, not `latest`.
  Renovate (`renovate.json`) opens the bump PRs: minor/patch of all images in
  one weekly PR, majors one by one; merge, then `make deploy` and
  `make update.<stack>`.

## New host

The host needs docker with the compose plugin and ssh, nothing else; the repo
never lives there as a git checkout. From the laptop:

    cp local.mk.example local.mk        # or ~/.config/homelab/config.mk from dotfiles
    make deploy                         # rsync the repo to DEPLOY_HOST:DEPLOY_PATH
    make secrets.push                   # <stack>/.env and config/*.filter (rendered from dotfiles), rclone.conf
    make networks                       # shared docker networks, once
    make up.<stack>                     # per stack

Another laptop against the same host: `chezmoi apply` (the private toml with
`[data.homelab.*]` has to have synced first), then `make secrets.pull` once —
`config/rclone.conf` is rewritten on the host on every token refresh and only
exists there and in this tree copy, nothing renders it.

Unraid: the Compose Manager plugin runs each directory as a stack (a pointer
dir under its projects folder, `indirect` = the stack directory).

## Makefile

The host comes from `~/.config/homelab/config.mk` (dotfiles renders it from
`[data.homelab]` in the private chezmoi.toml) or a repo-local `local.mk`
(`cp local.mk.example local.mk`). Then `make help`; the gist:

    make deploy.diff / deploy                 rsync the repo to the host (.env, rclone.conf untouched)
    make up.<stack> / logs.<stack> / update.<stack>   docker compose on the host
    make lint                                 compose config, shellcheck, pre-commit
    make secrets.pull / secrets.push          host-side .env, compose.override.yaml, rclone.conf, config/* <-> gitignored tree copy;
                                              they come from ~/.config/homelab/<stack>/ (dotfiles) when present

## Stacks

- `cloud-sync` — mirrors Yandex Disk and Google Drive to local disk with rclone.
- `backrest` — backups of the server itself (restic + web UI) into a local
  repository, offsite later; alerts via `notify`, heartbeats to `gatus`.
- `beszel` — server monitoring: hub (UI, sqlite history) and the agent of the
  docker host; alerts go through `notify`.
- `gatus` — uptime checks and status page; cloud-sync heartbeats land here,
  alerts go through `notify`.
- `miniflux` — feed reader with its own postgres.
- `notify` — Apprise gateway: every stack and the laptops post alerts to one
  URL, channels (Telegram now, XMPP/Discord/mail later) live in the private toml.
