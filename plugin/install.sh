#!/bin/sh
# =============================================================================
# ASUSGO / koolshare softcenter plugin installer
# Plugin : cloudflaretunnel (Cloudflare Tunnel)
# SELF-CONTAINED: no Entware / opkg required. cloudflared binary is bundled.
#
# Installed paths (koolshare layout):
#   /koolshare/scripts/cloudflaretunnel.sh       管理/服务脚本
#   /koolshare/webs/Module_cloudflaretunnel.asp  Web 管理页面
#   /koolshare/init.d/S99cloudflaretunnel.sh     开机自启
#   /koolshare/configs/cloudflaretunnel.conf     配置文件
#   /koolshare/bin/cloudflared                   内置静态二进制（armv7l）
#   /koolshare/bin/cloudflaretunnel              兼容旧调用的软链接
#   /koolshare/logs/cloudflared.log              运行日志
# =============================================================================

# 被软件中心调用时会传入 1（安装）/0（卸载）
ACTION="$1"

BASE=/koolshare
SCRIPT="$BASE/scripts/cloudflaretunnel.sh"
WEB="$BASE/webs/Module_cloudflaretunnel.asp"
INITD="$BASE/init.d/S99cloudflaretunnel.sh"
CONFIG="$BASE/configs/cloudflaretunnel.conf"
TOKEN_FILE="$BASE/configs/cloudflaretunnel.token"
BIN="$BASE/bin/cloudflared"
BINLINK="$BASE/bin/cloudflaretunnel"
LOG="$BASE/logs/cloudflared.log"
PID=/var/run/cloudflaretunnel.pid
CRON_FILE=/var/spool/cron/crontabs/root
CRON_TAG="# cloudflaretunnel-watchdog"
HEALTH_STATE_FILE=/tmp/cloudflaretunnel.health
RESTART_STAMP=/tmp/cloudflaretunnel.lastrestart

log() { echo "[cloudflaretunnel] $*"; logger -t cloudflaretunnel "$*" 2>/dev/null; }

set_db() {
    [ -n "$1" ] && [ -n "$2" ] && dbus set "$1" "$2" 2>/dev/null
}

# 仅在键不存在时写默认值：覆盖安装/升级不能清空用户已保存的 Token 与开关。
set_db_default() {
    _v=$(dbus get "$1" 2>/dev/null)
    [ -z "$_v" ] && set_db "$1" "$2"
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
uninstall() {
    log "Uninstalling cloudflaretunnel ..."

    [ -f "$SCRIPT" ] && "$SCRIPT" stop 2>/dev/null

    # 移除看门狗 cron 条目（按标记过滤，不影响其他计划任务）
    if [ -f "$CRON_FILE" ]; then
        _tmp="$CRON_FILE.ct.$$"
        grep -v "$CRON_TAG" "$CRON_FILE" > "$_tmp" 2>/dev/null && cat "$_tmp" > "$CRON_FILE" 2>/dev/null
        rm -f "$_tmp"
        killall -HUP cron 2>/dev/null || killall -HUP crond 2>/dev/null || true
    fi
    rm -f "$HEALTH_STATE_FILE" "$RESTART_STAMP"

    # 只删除本插件文件（含 root-only 凭证文件，防止 Token 残留）
    rm -f "$SCRIPT" "$WEB" "$INITD" "$CONFIG" "$TOKEN_FILE" "$BIN" "$BINLINK" "$PID" "$LOG"

    dbus remove softcenter_module_cloudflaretunnel 2>/dev/null
    dbus remove cloudflaretunnel_enable 2>/dev/null
    dbus remove cloudflaretunnel_mode 2>/dev/null
    dbus remove cloudflaretunnel_token 2>/dev/null
    dbus remove cloudflaretunnel_name 2>/dev/null
    dbus remove cloudflaretunnel_loglevel 2>/dev/null
    dbus remove cloudflaretunnel_extra 2>/dev/null

    log "Uninstall done."
}

# ---------------------------------------------------------------------------
# 安装
# ---------------------------------------------------------------------------
install() {
    log "Installing cloudflaretunnel (self-contained, no Entware) ..."

    [ -d "$BASE/scripts" ] || { log "ERROR: /koolshare not found, not a softcenter firmware."; exit 1; }

    mkdir -p "$BASE/scripts" "$BASE/webs" "$BASE/init.d" "$BASE/configs" "$BASE/bin" "$(dirname "$LOG")"

    SRC=$(cd "$(dirname "$0")" && pwd)
    copy_if_needed() {
        _s="$1"; _d="$2"
        if [ -f "$_s" ]; then
            [ "$_s" = "$_d" ] && return 0
            cp "$_s" "$_d" 2>/dev/null || log "WARN: copy $_s -> $_d failed"
        else
            log "WARN: $_s missing (package may be partially extracted)"
        fi
    }

    # 内置二进制（随包提供）
    copy_if_needed "$SRC/bin/cloudflared-linux-arm" "$BIN"
    if [ -f "$BIN" ]; then
        chmod 755 "$BIN"
        log "Bundled cloudflared installed: $("$BIN" --version 2>&1 | head -n 1)"
    else
        log "ERROR: bundled cloudflared binary missing; plugin cannot run."
    fi

    # 脚本 / Web / 自启
    copy_if_needed "$SRC/scripts/cloudflaretunnel.sh" "$SCRIPT"
    copy_if_needed "$SRC/webs/Module_cloudflaretunnel.asp" "$WEB"
    copy_if_needed "$SRC/init.d/S99cloudflaretunnel.sh" "$INITD"
    chmod 755 "$SCRIPT" "$INITD" 2>/dev/null

    [ -f "$SCRIPT" ] && ln -sf "$SCRIPT" "$BINLINK" 2>/dev/null

    # 默认配置
    if [ ! -f "$CONFIG" ]; then
        cat > "$CONFIG" <<EOF
# cloudflaretunnel runtime config
ENABLE=0
MODE=remote
TOKEN=""
NAME=""
LOGLEVEL=info
EXTRA=""
EOF
        chmod 600 "$CONFIG"
    fi

    # dbus 默认值：仅在键不存在时写入，避免升级/覆盖安装清空用户配置。
    # 旧 local 模式迁移为 remote（v1.2.0 起仅支持该模式）。
    _m=$(dbus get cloudflaretunnel_mode 2>/dev/null)
    [ "$_m" = "remote" ] || set_db cloudflaretunnel_mode remote
    set_db_default cloudflaretunnel_enable   0
    set_db_default cloudflaretunnel_token    ""
    set_db_default cloudflaretunnel_name     ""
    set_db_default cloudflaretunnel_loglevel info
    set_db_default cloudflaretunnel_extra    ""
    set_db softcenter_module_cloudflaretunnel "1"

    log "Install done. No Entware needed. Enable and set token in the Web UI."
}

case "$ACTION" in
    1|install|installed)   install ;;
    0|uninstall|remove)    uninstall ;;
    *)                     install ;;
esac
