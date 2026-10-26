#!/bin/sh
# Kill tunnel sessions older than MAX_AGE_HOURS so a forgotten tunnel never
# stays public forever. Each sish tunnel is one established TCP connection to
# :2222; those sockets live in the container's network namespace, so ss runs
# there via nsenter. Reconnecting (autossh does it automatically) rebinds the
# same name.
set -eu
MAX_AGE_HOURS=12
state=/run/tunnel-reaper
mkdir -p "$state"
pid=$(docker inspect -f '{{.State.Pid}}' tunnel-sish-1 2>/dev/null) || exit 0
[ "$pid" -gt 0 ] || exit 0
ns() { nsenter -t "$pid" -n "$@"; }

now=$(date +%s)
peers=$(ns ss -Htn state established '( sport = :2222 )' | awk '{print $NF}')

for p in $peers; do
	f="$state/$p"
	if [ ! -e "$f" ]; then
		echo "$now" >"$f"
		continue
	fi
	if [ $((now - $(cat "$f"))) -ge $((MAX_AGE_HOURS * 3600)) ]; then
		ip=${p%:*}
		port=${p##*:}
		ns ss -K dst "$ip" dport = "$port" >/dev/null || true
		rm -f "$f"
		logger -t reap-tunnels "killed tunnel session from $p (over ${MAX_AGE_HOURS}h)"
	fi
done

# Forget sessions that ended on their own.
for f in "$state"/*; do
	[ -e "$f" ] || continue
	case "$peers" in *"$(basename "$f")"*) ;; *) rm -f "$f" ;; esac
done
