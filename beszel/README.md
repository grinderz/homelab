# beszel

[beszel](https://github.com/henrygd/beszel): lightweight server monitoring. The
hub keeps history in sqlite under `DATA_DIR` and serves the UI on `PORT`; the
agent runs on the host network, reads docker stats from the socket and reports
to the hub over ssh (the hub's key, `AGENT_KEY`).

    beszel/
      compose.yaml          hub + agent for this host
      .env                  DATA_DIR, PORT, AGENT_PORT, AGENT_KEY, TZ (rendered by dotfiles)

## Setup

1. `cp .env.example .env` or let dotfiles render it (`[data.homelab.beszel]`).
   On a fresh host leave `AGENT_KEY` empty for the first `up`, open the UI,
   create the admin, read the public key under *Add system*, put it into the
   toml, `make secrets.push && make up.beszel`.
2. `make deploy && make secrets.push && make networks && make up.beszel`.
3. In the UI add the system with the host address and `AGENT_PORT`
   (an existing `DATA_DIR` already has it).

## Alerts

Hub → Settings → Notifications, one shoutrrr URL through the notify stack
(`generic+http` = plain http to the gateway, `template=json`, `$tag` becomes a
field of the JSON body; verified with the shoutrrr fork beszel embeds):

    generic+http://notify:8000/notify/homelab?template=json&messagekey=body&titlekey=title&$tag=primary

Thresholds per system in the UI (CPU, memory, disk, status). Nothing
Telegram-specific lives here.

## Operations

- Agent on another host: copy the `beszel-agent` service only, same `KEY`,
  `LISTEN` reachable from the hub; add the system in the UI.
- Extra disks: the agent only sees docker's backing device as "root", so real
  disks are extra filesystems — `compose.override.yaml` (host-side like `.env`,
  rendered from `[data.homelab.beszel_extra_fs]`, label = a directory on the
  disk, mounted read-only at `/extra-filesystems/<label>`). docker compose and
  Compose Manager both pick the file up on their own.
- Data is tiny (a few MB); it is part of the appdata backup, nothing else to do.
