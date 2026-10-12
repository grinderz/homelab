#!/bin/sh
# sync.sh <remote>: mirror <remote>: into /data/<remote>.
# Deleted or overwritten files land in /history/<remote>/<date>; those older than
# $HISTORY_DAYS are pruned. $HEARTBEAT_URL (gatus external endpoint, %s = the
# remote) gets the result after every run with $HEARTBEAT_TOKEN as bearer, so
# gatus alerts on a failed or a missing run.
# $NOTIFY_URL (the notify stack, Apprise) gets a message on failure, tag
# primary, then fallback if the gateway reports a delivery failure; with
# NOTIFY_OK=1 also one line on success.
set -u
remote=$1
data=/data/$remote
hist=/history/$remote
day=$(date +%F)
log=$hist/sync.log
conf=/config/rclone/rclone.conf
filter=/config/rclone/$remote.filter

# notify <tag> <title> <body>: one POST to the Apprise gateway, 10s timeout,
# never fails the run. Returns the gateway's verdict (0 = delivered).
notify() {
    [ -n "${NOTIFY_URL:-}" ] || return 0
    wget -qO- -T 10 --post-data "tag=$1&title=$(urlenc "$2")&body=$(urlenc "$3")" \
        "$NOTIFY_URL" >/dev/null 2>&1
}
urlenc() {
    printf '%s' "$1" | od -An -tx1 -v | tr ' ' '%' | tr -d '\n'
}
# notify_fail <title> <body>: primary, once more after 5s (the gateway does
# not retry a channel that blipped), then fallback
notify_fail() {
    notify primary "$1" "$2" || { sleep 5; notify primary "$1" "$2"; } \
        || notify fallback "$1" "$2" \
        || echo "$(date '+%F %T') $remote: notify failed" | tee -a "$log"
}

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
if [ "$rc" -ne 0 ]; then
    last=$(grep ' ERROR ' "$log" | tail -1 | cut -c1-300)
    notify_fail "cloud-sync: $remote failed" "rc=$rc${last:+
$last}"
elif [ "${NOTIFY_OK:-}" = 1 ]; then
    stats=$(grep -E 'NOTICE: +[0-9.]+ [KMG]?i?B / ' "$log" | tail -1 | sed -E 's/.*NOTICE: +//')
    notify primary "cloud-sync: $remote ok" "${stats:-done}" || true
fi
if [ -n "${HEARTBEAT_URL:-}" ]; then
    # shellcheck disable=SC2059  # %s in the URL is the remote slot by design
    hb=$(printf "$HEARTBEAT_URL" "$remote")
    ok=true; [ "$rc" -eq 0 ] || ok=false
    wget -qO- -T 10 --post-data "" --header "Authorization: Bearer ${HEARTBEAT_TOKEN:-}" \
        "$hb?success=$ok&error=$(urlenc "rc=$rc")" >/dev/null 2>&1 \
        || echo "$(date '+%F %T') $remote: heartbeat failed" | tee -a "$log"
fi
exit $rc
