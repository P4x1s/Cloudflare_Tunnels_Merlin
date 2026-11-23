#!/bin/sh
# =============================================================================
# cloudflaretunnel.sh - ASUSGO softcenter plugin service/control script
# Manages a Cloudflare Tunnel (cloudflared) on the router.
#
# Usage (softcenter convention):
#   cloudflaretunnel.sh {start|stop|restart|status|config|log|version}
#
# Config is read from dbus first (written by Web UI), then from the conf file.
# =============================================================================

set -u

BASE=/koolshare
CONFIG="$BASE/configs/cloudflaretunnel.conf"
CLOUDFLARED=/opt/bin/cloudflared
PID=/var/run/cloudflaretunnel.pid
LOG=/opt/var/log/cloudflared.log

NAME=cloudflaretunnel
VERSION=1.0.0

dbus_get() { dbus get "$1" 2>/dev/null; }

log() { logger -t "$NAME" "$*" 2>/dev/null; echo "[$NAME] $*"; }

load_config() {
    # defaults
    ENABLE=0; MODE=remote; TOKEN=""; TUNNEL_NAME=""; LOGLEVEL=info; EXTRA=""

    # file config
    [ -f "$CONFIG" ] && . "$CONFIG"

    # dbus overrides (Web UI writes here)
    _e=$(dbus_get cloudflaretunnel_enable);    [ -n "$_e" ] && ENABLE=$_e
    _m=$(dbus_get cloudflaretunnel_mode);      [ -n "$_m" ] && MODE=$_m
    _t=$(dbus_get cloudflaretunnel_token);     [ -n "$_t" ] && TOKEN=$_t
    _n=$(dbus_get cloudflaretunnel_name);      [ -n "$_n" ] && TUNNEL_NAME=$_n
    _l=$(dbus_get cloudflaretunnel_loglevel);  [ -n "$_l" ] && LOGLEVEL=$_l
    _x=$(dbus_get cloudflaretunnel_extra);     [ -n "$_x" ] && EXTRA=$_x
}

is_running() {
    [ -f "$PID" ] || return 1
    _pid=$(cat "$PID" 2>/dev/null)
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    return 0
}

start() {
    load_config
    [ "$ENABLE" = "1" ] || { log "Plugin disabled (ENABLE=0)."; return 0; }
    [ -x "$CLOUDFLARED" ] || { log "ERROR: cloudflared not installed (/opt/bin/cloudflared)."; return 1; }
    is_running && { log "Already running (PID $(cat "$PID"))."; return 0; }

    mkdir -p "$(dirname "$LOG")"

    case "$MODE" in
        remote)
            [ -n "$TOKEN" ] || { log "ERROR: Token is empty. Set it in Web UI."; return 1; }
            ARGS="tunnel --loglevel $LOGLEVEL run --token $TOKEN $EXTRA"
            ;;
        local)
            [ -n "$TUNNEL_NAME" ] || { log "ERROR: Tunnel name is empty (local mode)."; return 1; }
            ARGS="tunnel --loglevel $LOGLEVEL run $TUNNEL_NAME $EXTRA"
            ;;
        *) log "ERROR: Unknown MODE=$MODE"; return 1 ;;
    esac

    # shellcheck disable=SC2086
    nohup "$CLOUDFLARED" $ARGS >> "$LOG" 2>&1 &
    echo $! > "$PID"
    sleep 2
    if is_running; then
        log "Started cloudflared (PID $(cat "$PID"))."
    else
        log "ERROR: cloudflared exited immediately; check log."
        tail -n 20 "$LOG" 2>/dev/null
        rm -f "$PID"
        return 1
    fi
}

stop() {
    if is_running; then
        _pid=$(cat "$PID")
        log "Stopping cloudflared (PID $_pid) ..."
        kill "$_pid" 2>/dev/null
        sleep 2
        kill -9 "$_pid" 2>/dev/null
        rm -f "$PID"
        log "Stopped."
    else
        log "Not running."
    fi
}

status() {
    load_config
    if is_running; then
        echo "STATUS=RUNNING"
        echo "PID=$(cat "$PID")"
    else
        echo "STATUS=STOPPED"
    fi
    echo "ENABLE=$ENABLE"
    echo "MODE=$MODE"
    echo "TOKEN_SET=$([ -n "$TOKEN" ] && echo 1 || echo 0)"
    echo "LOGLEVEL=$LOGLEVEL"
}

case "${1:-}" in
    start)    start ;;
    stop)     stop ;;
    restart)  stop; start ;;
    status)   status ;;
    log)      n=${2:-50}; tail -n "$n" "$LOG" 2>/dev/null || log "No log." ;;
    version)  echo "$NAME $VERSION" ;;
    config)   echo "CONFIG=$CONFIG"; echo "LOG=$LOG"; echo "PID=$PID" ;;
    *)        echo "Usage: $0 {start|stop|restart|status|log [n]|config|version}"; exit 1 ;;
esac
