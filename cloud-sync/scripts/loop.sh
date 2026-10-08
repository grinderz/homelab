#!/bin/sh
# Runs every remote in $REMOTES, sleeps $INTERVAL, repeats. First run at container start.
set -u
while :; do
    for r in $REMOTES; do
        /scripts/sync.sh "$r"
    done
    echo "$(date '+%F %T') sleeping $INTERVAL"
    sleep "$INTERVAL"
done
