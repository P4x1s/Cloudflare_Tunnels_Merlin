#!/bin/sh
# =============================================================================
# cloudflaretunnel.sh - ASUSGO softcenter plugin service/control script
# Manages a Cloudflare Tunnel (cloudflared) on the router.
#
# Usage (softcenter convention):
#   cloudflaretunnel.sh {start|stop|restart|status|config|log|version}
#
# Config is read from dbus first (written by Web UI), then from the conf file.
#
# SECURITY: the tunnel Token is never passed on the command line (would be
# visible in `ps`). It is written to a root-only token file and cloudflared is
# started with --token-file (requires cloudflared >= 2025.4.0; bundled 2026.11.1
# supports it). Args are built as a positional list to avoid word-splitting /
# parameter injection from the free-form EXTRA field.
# =============================================================================

set -u

BASE=/koolshare
CONFIG="$BASE/configs/cloudflaretunnel.conf"
CLOUDFLARED=$BASE/bin/cloudflared
TOKEN_FILE="$BASE/configs/cloudflaretunnel.token"
PID=/var/run/cloudflaretunnel.pid
LOG=$BASE/logs/cloudflared.log

NAME=cloudflaretunnel
VERSION=1.1.1

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

# 将 Token 写入仅 root 可读的凭证文件；不回显、不进入进程命令行。
write_token_file() {
    umask 077
    printf '%s' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null
}

start() {
    load_config
    [ "$ENABLE" = "1" ] || { log "Plugin disabled (ENABLE=0)."; return 0; }
    [ -x "$CLOUDFLARED" ] || { log "ERROR: cloudflared not installed (bundled /koolshare/bin/cloudflared)."; return 1; }
    is_running && { log "Already running (PID $(cat "$PID"))."; return 0; }

    mkdir -p "$(dirname "$LOG")" "$(dirname "$TOKEN_FILE")"

    # 用位置参数构建完整命令，避免 $ARGS 无引号展开造成的分词/注入问题
    set -- tunnel --loglevel "$LOGLEVEL" --no-autoupdate
    case "$MODE" in
        remote)
            [ -n "$TOKEN" ] || { log "ERROR: Token is empty. Set it in Web UI."; return 1; }
            write_token_file || { log "ERROR: cannot write token file."; return 1; }
            set -- "$@" run --token-file "$TOKEN_FILE"
            ;;
        local)
            [ -n "$TUNNEL_NAME" ] || { log "ERROR: Tunnel name is empty (local mode)."; return 1; }
            set -- "$@" run "$TUNNEL_NAME"
            ;;
        *) log "ERROR: Unknown MODE=$MODE"; return 1 ;;
    esac

    # EXTRA 为用户可控的附加参数：按空白安全拆分后逐个追加，不做 glob 展开
    if [ -n "$EXTRA" ]; then
        set -f
        for _x in $EXTRA; do set -- "$@" "$_x"; done
        set +f
    fi

    nohup "$CLOUDFLARED" "$@" >> "$LOG" 2>&1 &
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
    # Token 落入凭证文件后随服务生命周期清理
    rm -f "$TOKEN_FILE"
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
    config)   echo "CONFIG=$CONFIG"; echo "LOG=$LOG"; echo "PID=$PID"; echo "TOKEN_FILE=$TOKEN_FILE" ;;
    *)        echo "Usage: $0 {start|stop|restart|status|log [n]|config|version}"; exit 1 ;;
esac
