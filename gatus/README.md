# gatus

[gatus](https://github.com/TwiN/gatus): uptime checks with a status page. The
checks live in `config/config.yaml`, which is host-side like `.env` (gitignored,
rendered by dotfiles from `[data.homelab.gatus_monitor]` in the private toml,
copied in by make, shipped with `make secrets.push`): LAN hosts and personal
names stay out of the repo. History is sqlite under `DATA_DIR`.

    gatus/
      compose.yaml          gatus, UI on PORT, sqlite in DATA_DIR
      config/config.yaml    checks + alerting (rendered, see above)

## Checks

Three kinds from the toml, each entry `name`, `group`, `url`, optional
`interval` (1m) and `conditions`:

- `icmp://host`, `tcp://host:port` — default condition `[CONNECTED] == true`
- `http(s)://…` — default `[STATUS] == 200`
- `url` = a DNS server plus `dns = { query_name, query_type }` — default
  `[DNS_RCODE] == NOERROR`

Push ("external") endpoints have no check of their own: a producer POSTs its
result and gatus alerts when the result is a failure or when nothing arrives
within `heartbeat`:

    curl -X POST -H "Authorization: Bearer $TOKEN" \
        "http://gatus:8080/api/v1/endpoints/cloud-sync_yandex/external?success=true"

Key = `<group>_<name>`; the token is one for all of them (`passp
service/gatus/heartbeat-token`). cloud-sync does this after every run.

## Alerts

`alerting.custom` posts to the notify stack (tag `primary`) on failure and on
recovery: title `DOWN|UP group/name`, body with the failing conditions.
Thresholds come from the toml (`failure_threshold`, `success_threshold`).

## Setup

1. `cp .env.example .env` or let dotfiles render it (`[data.homelab.gatus]`).
2. `make deploy && make secrets.push && make networks && make up.gatus`.
3. UI on `PORT`; `make logs.gatus` shows config errors on start.
