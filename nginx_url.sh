#!/usr/bin/env bash
# Keep http://localhost:8081 pointed at the nginx app for the live demo.
#
#   ./nginx_url.sh start    run a port-forward in the background that reconnects to the current pod
#   ./nginx_url.sh status   show whether it's running and the HTTP code the app returns right now
#   ./nginx_url.sh stop     stop it
#
# kubectl port-forward attaches to one pod and exits when that pod goes away (scale, restart,
# rollback, reset), so the loop starts it again against whichever pod is current.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${NGINX_LOCAL_PORT:-8081}"
NS=application
SVC=nginx
PID_FILE="$SCRIPT_DIR/.nginx_url.pid"
LOG_FILE="$SCRIPT_DIR/nginx_url.log"
URL="http://localhost:$PORT"

running_pid() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE")"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "$pid"
  else
    rm -f "$PID_FILE"
    return 1
  fi
}

http_code() {
  curl -s -o /dev/null -m 2 -w '%{http_code}' "$URL" || true
}

case "${1:-}" in
  start)
    if pid="$(running_pid)"; then
      echo "Already running (pid $pid): $URL"
      exit 0
    fi
    command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required" >&2; exit 1; }
    # The loop forwards TERM to the current port-forward, so stop leaves nothing behind.
    nohup bash -c '
      trap "kill \$child 2>/dev/null; exit 0" TERM INT
      while true; do
        echo "$(date "+%H:%M:%S") connecting to svc/'"$SVC"'"
        kubectl -n '"$NS"' port-forward svc/'"$SVC"' '"$PORT"':80 &
        child=$!
        wait $child || true
        sleep 2
      done' >>"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
    echo "Started (pid $!): $URL  (log: $LOG_FILE)"
    ;;
  stop)
    if pid="$(running_pid)"; then
      kill "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      echo "Stopped (pid $pid)"
    else
      echo "Not running"
    fi
    ;;
  status)
    if pid="$(running_pid)"; then
      echo "Running (pid $pid): $URL  HTTP $(http_code)"
    else
      echo "Not running. Start it with: ./nginx_url.sh start"
    fi
    ;;
  *)
    sed -n '2,6p' "$0"
    exit 1
    ;;
esac
