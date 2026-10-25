#!/bin/sh
# Runs on the host after secrets.push, from the repo copy. rsync created each
# <stack>/.env and config file as the ssh user with mode 600; chown them to the
# PUID:PGID the stack's .env names (0 when unset) so a service running as that
# uid can read them. Safe to rerun.
set -eu
for env in */.env; do
    [ -f "$env" ] || continue
    stack=${env%/.env}
    uid=$(sed -n 's/^PUID=//p' "$env")
    gid=$(sed -n 's/^PGID=//p' "$env")
    chown -R "${uid:-0}:${gid:-0}" "$env"
    if [ -d "$stack/config" ]; then
        chown -R "${uid:-0}:${gid:-0}" "$stack/config"
    fi
done
