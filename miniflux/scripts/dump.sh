#!/bin/sh
# dump.sh: pg_dump the miniflux database once a day into /dumps, keep the last
# $KEEP files. Runs in the postgres image next to the db service, so the dump
# is consistent while the live data directory is excluded from backups.
set -eu
mkdir -p /dumps
while :; do
    f=/dumps/miniflux-$(date +%F).dump
    if pg_dump -h db -U miniflux -Fc miniflux > "$f.tmp"; then
        mv "$f.tmp" "$f"
        echo "$(date '+%F %T') dumped $(du -h "$f" | cut -f1) $f"
        find /dumps -name "miniflux-*.dump" -type f | sort -r | tail -n +"$((KEEP + 1))" | xargs -r rm -f
    else
        rm -f "$f.tmp"
        echo "$(date '+%F %T') dump failed"
    fi
    sleep 24h
done
