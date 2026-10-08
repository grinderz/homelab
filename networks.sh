#!/bin/sh
# Creates the shared docker networks once. Safe to rerun. Stacks reference them
# with `external: true`, so they start in any order and never own the network.
set -eu
# shellcheck disable=SC2043  # one network today, the loop is the extension point
for n in proxy; do
    docker network inspect "$n" >/dev/null 2>&1 || docker network create "$n"
done
