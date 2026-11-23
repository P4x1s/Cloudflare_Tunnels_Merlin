#!/bin/sh
# =============================================================================
# cloudflaretunnel.sh - ASUSGO softcenter plugin service/control script
# Manages a Cloudflare Tunnel (cloudflared) on the router.
#
# Usage (softcenter convention):
#   cloudflaretunnel.sh {start|stop|restart|status|health|check|log|config|version}
#
# Config is read from dbus first (written by Web UI), then from the conf file.
#
# SECURITY: the tunnel Token is never passed on the command line (would be
# visible in `ps`). It is written to a root-only token file and cloudflared is
# started with --token-file (requires cloudflared >= 2025.4.0; bundled 2026.11.1
# supports it). Args are built as a positional list to avoid word-splitting /
# parameter injection from the free-form EXTRA field.
#
# STABILITY (v1.2.1):
#   - is_running() verifies the process identity via /proc/<pid>/comm to avoid
#     PID-reuse false positives.
#   - health() inspects the recent log for an authenticated CONNECT + active
#     connection, so "RUNNING" no longer implies "tunnel actually up".
#   - check() is an idempotent watchdog suitable for cron (every 1-2 min):
#     restart only when the process is down or the tunnel has been unhealthy for
#     a sustained period. Backoff prevents restart loops.
#   - logs are rotated on start AND on every watchdog check, so a long-lived
#     healthy tunnel cannot grow the log without bound until its next restart.
# =============================================================================

set -u

BASE=/koolshare
CONFIG="$BASE/configs/cloudflaretunnel.conf"
CLOUDFLARED=$BASE/bin/cloudflared
TOKEN_FILE="$BASE/configs/cloudflaretunnel.token"
PID=/var/run/cloudflaretunnel.pid
LOG=$BASE/logs/cloudflared.log

NAME=cloudflaretunnel
VERSION=1.2.1

# 稳定性参数（可通过 conf 覆盖）
LOG_MAX_KB=${LOG_MAX_KB:-2048}
UNHEALTHY_RESTART_MIN=${UNHEALTHY_RESTART_MIN:-5}    # 连续 N 次 check 判定不健康才重启
HEALTH_STATE_FILE=/tmp/cloudflaretunnel.health       # 连续不健康计数
RESTART_STAMP=/tmp/cloudflaretunnel.lastrestart       # 上次重启时间戳（退避）
RESTART_COOLDOWN_SEC=${RESTART_COOLDOWN_SEC:-300}    # 5 分钟内最多自动重启一次

dbus_get() { dbus get "$1" 2>/dev/null; }

log() { logger -t "$NAME" "$*" 2>/dev/null; echo "[$NAME] $*"; }

load_config() {
    ENABLE=0; MODE=remote; TOKEN=""; TUNNEL_NAME=""; LOGLEVEL=info; EXTRA=""
    [ -f "$CONFIG" ] && . "$CONFIG"
    _e=$(dbus_get cloudflaretunnel_enable);    [ -n "$_e" ] && ENABLE=$_e
    _m=$(dbus_get cloudflaretunnel_mode);      [ -n "$_m" ] && MODE=$_m
    _t=$(dbus_get cloudflaretunnel_token);     [ -n "$_t" ] && TOKEN=$_t
    _n=$(dbus_get cloudflaretunnel_name);      [ -n "$_n" ] && TUNNEL_NAME=$_n
    _l=$(dbus_get cloudflaretunnel_loglevel);  [ -n "$_l" ] && LOGLEVEL=$_l
    _x=$(dbus_get cloudflaretunnel_extra);     [ -n "$_x" ] && EXTRA=$_x
}

# 进程存活 + 身份校验：PID 文件 + kill -0 + comm 名称匹配，规避 PID 复用误判。
is_running() {
    [ -f "$PID" ] || return 1
    _pid=$(cat "$PID" 2>/dev/null)
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    if [ -r "/proc/$_pid/comm" ]; then
        _comm=$(cat "/proc/$_pid/comm" 2>/dev/null)
        case "$_comm" in
            cloudflared*) : ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# 隧道连通性启发式检测：最近日志中同时出现认证成功与活跃连接，且无近期 fatal。
# cloudflared 日志关键行（logfmt）：
#   INF Authentication successful  /  INF Registered tunnel connection
#   ERR ...  /  Fatal ...
health() {
    if ! is_running; then echo "DOWN"; return; fi
    [ -f "$LOG" ] || { echo "UNKNOWN"; return; }
    _recent=$(tail -n 80 "$LOG" 2>/dev/null)
    [ -z "$_recent" ] && { echo "UNKNOWN"; return; }
    if echo "$_recent" | grep -qiE 'fatal|authentication failed|failed to dial|invalid.*token|unauthorized'; then
        echo "ERROR"
    elif echo "$_recent" | grep -qi 'Registered tunnel connection'; then
        echo "HEALTHY"
    elif echo "$_recent" | grep -qi 'Authentication successful'; then
        echo "CONNECTING"
    else
        echo "UNKNOWN"
    fi
}

# 日志轮转：超过阈值保留尾部 N 行，避免 JFFS 被写满。
rotate_log() {
    [ -f "$LOG" ] || return 0
    _kb=$(du -k "$LOG" 2>/dev/null | awk '{print $1}')
    [ -n "$_kb" ] && [ "$_kb" -gt "$LOG_MAX_KB" ] 2>/dev/null && {
        _tmp="$LOG.rot.$$"
        tail -n 500 "$LOG" > "$_tmp" 2>/dev/null && { mv "$_tmp" "$LOG"; log "log rotated (>${LOG_MAX_KB}KB)"; }
        rm -f "$_tmp"
    }
    return 0
}

# 将 Token 写入仅 root 可读的凭证文件；不回显、不进入进程命令行。
write_token_file() {
    umask 077
    printf '%s' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE" 2>/dev/null
}

reset_health() { rm -f "$HEALTH_STATE_FILE"; }

start() {
    load_config
    [ "$ENABLE" = "1" ] || { log "Plugin disabled (ENABLE=0)."; return 0; }
    [ -x "$CLOUDFLARED" ] || { log "ERROR: cloudflared not installed (bundled /koolshare/bin/cloudflared)."; return 1; }
    is_running && { log "Already running (PID $(cat "$PID"))."; return 0; }

    mkdir -p "$(dirname "$LOG")" "$(dirname "$TOKEN_FILE")"
    rotate_log

    set -- tunnel --loglevel "$LOGLEVEL" --no-autoupdate
    case "$MODE" in
        remote)
            [ -n "$TOKEN" ] || { log "ERROR: Token is empty. Set it in Web UI."; return 1; }
            write_token_file || { log "ERROR: cannot write token file."; return 1; }
            set -- "$@" run --token-file "$TOKEN_FILE"
            ;;
        *) log "ERROR: Unknown MODE=$MODE (only 'remote' is supported in this build)."; return 1 ;;
    esac

    if [ -n "$EXTRA" ]; then
        set -f
        for _x in $EXTRA; do set -- "$@" "$_x"; done
        set +f
    fi

    nohup "$CLOUDFLARED" "$@" >> "$LOG" 2>&1 &
    echo $! > "$PID"
    date +%s > "$RESTART_STAMP" 2>/dev/null
    reset_health
    sleep 3
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
    rm -f "$TOKEN_FILE"
    reset_health
}

restart() { stop; start; }

# 看门狗单次检查（供 cron 每 1-2 分钟调用，幂等）：
#   - 进程不在：立即拉起（受重启冷却限制）
#   - 隧道持续不健康达到阈值：重启
check() {
    load_config
    # v1.2.1 patch: rotate on every watchdog tick, not only on start.
    # Otherwise a tunnel that stays healthy for weeks keeps appending to the
    # log until the next restart, defeating the JFFS size guard.
    rotate_log
    [ "$ENABLE" = "1" ] || { echo "DISABLED"; return 0; }

    if ! is_running; then
        if _cooldown_ok; then
            log "watchdog: process down, restarting."
            start && echo "RESTARTED_DOWN"
        else
            echo "COOLDOWN"
        fi
        return 0
    fi

    _h=$(health)
    case "$_h" in
        HEALTHY)
            reset_health
            echo "HEALTHY"
            ;;
        DOWN)
            # is_running 已确认进程存在，这里 DOWN 属于瞬时竞态，忽略
            echo "RACY"
            ;;
        *)
            _bad=$(cat "$HEALTH_STATE_FILE" 2>/dev/null)
            case "$_bad" in ''|*[!0-9]*) _bad=0 ;; esac
            _bad=$((_bad + 1))
            echo "$_bad" > "$HEALTH_STATE_FILE"
            if [ "$_bad" -ge "$UNHEALTHY_RESTART_MIN" ]; then
                if _cooldown_ok; then
                    log "watchdog: tunnel $_h for $_bad checks, restarting."
                    restart && echo "RESTARTED_UNHEALTHY"
                    reset_health
                else
                    echo "COOLDOWN"
                fi
            else
                echo "UNHEALTHY_$_bad/$UNHEALTHY_RESTART_MIN"
            fi
            ;;
    esac
    return 0
}

# 重启冷却：距上次（自动/手动）启动不足 N 秒则拒绝再次自动重启，避免重启风暴。
_cooldown_ok() {
    _now=$(date +%s 2>/dev/null)
    _last=$(cat "$RESTART_STAMP" 2>/dev/null)
    [ -z "$_now" ] && return 0
    case "$_last" in ''|*[!0-9]*) return 0 ;; esac
    _diff=$((_now - _last))
    [ "$_diff" -ge "$RESTART_COOLDOWN_SEC" ]
}

status() {
    load_config
    if is_running; then
        echo "STATUS=RUNNING"
        echo "PID=$(cat "$PID")"
    else
        echo "STATUS=STOPPED"
    fi
    echo "TUNNEL=$(health)"
    echo "ENABLE=$ENABLE"
    echo "MODE=$MODE"
    echo "TOKEN_SET=$([ -n "$TOKEN" ] && echo 1 || echo 0)"
    echo "LOGLEVEL=$LOGLEVEL"
    echo "VERSION=$VERSION"
}

case "${1:-}" in
    start)    start ;;
    stop)     stop ;;
    restart)  restart ;;
    status)   status ;;
    health)   health ;;
    check)    check ;;
    log)      n=${2:-50}; tail -n "$n" "$LOG" 2>/dev/null || log "No log." ;;
    version)  echo "$NAME $VERSION" ;;
    config)   echo "CONFIG=$CONFIG"; echo "LOG=$LOG"; echo "PID=$PID"; echo "TOKEN_FILE=$TOKEN_FILE" ;;
    *)        echo "Usage: $0 {start|stop|restart|status|health|check|log [n]|config|version}"; exit 1 ;;
esac
