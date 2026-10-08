#!/bin/sh
# sync.sh <remote>: mirror <remote>: into /data/<remote>.
# Deleted or overwritten files land in /history/<remote>/<date>; those older than
# $HISTORY_DAYS are pruned. $PING_URL (healthchecks-style) gets a ping on success,
# $PING_URL/fail on error, both with the remote name appended as a query.
set -u
remote=$1
data=/data/$remote
hist=/history/$remote
day=$(date +%F)
log=$hist/sync.log
conf=/config/rclone/rclone.conf
filter=/config/rclone/$remote.filter

mkdir -p "$data" "$hist"
exec 9>"$hist/.lock"
flock -n 9 || { echo "$remote: previous run still going, skip"; exit 0; }

set --
[ -f "$filter" ] && set -- --filter-from "$filter"
echo "$(date '+%F %T') $remote: start" | tee -a "$log"
rclone sync "$remote:" "$data" "$@" \
    --config "$conf" \
    --backup-dir "$hist/$day" \
    --log-file "$log" --log-level NOTICE \
    --stats 10m --stats-one-line --stats-log-level NOTICE \
    --fast-list \
    --timeout 1m --contimeout 30s \
    --retries 5 --low-level-retries 3
rc=$?

find "$hist" -mindepth 1 -maxdepth 1 -type d -name '20??-??-??' -mtime +"$HISTORY_DAYS" \
    -exec rm -rf {} + 2>/dev/null

echo "$(date '+%F %T') $remote: done rc=$rc" | tee -a "$log"
if [ -n "${PING_URL:-}" ]; then
    url=$PING_URL
    [ "$rc" -eq 0 ] || url=$PING_URL/fail
    wget -qO- --timeout 10 "$url?remote=$remote" >/dev/null 2>&1 || true
fi
exit $rc
