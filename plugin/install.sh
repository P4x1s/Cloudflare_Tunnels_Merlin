#!/bin/sh
# =============================================================================
# ASUSGO / koolshare softcenter plugin installer
# Plugin : cloudflaretunnel (Cloudflare Tunnel)
# Installed paths (koolshare layout):
#   /koolshare/scripts/cloudflaretunnel.sh       管理/服务脚本
#   /koolshare/webs/Module_cloudflaretunnel.asp  Web 管理页面
#   /koolshare/init.d/S99cloudflaretunnel.sh     开机自启
#   /koolshare/configs/cloudflaretunnel.conf     配置文件
#   /koolshare/bin/cloudflaretunnel              兼容旧调用的软链接
#   /opt/bin/cloudflared                         由 opkg 安装的隧道程序
# =============================================================================

# 被软件中心调用时会传入 1（安装）/0（卸载）
ACTION="$1"

BASE=/koolshare
SCRIPT="$BASE/scripts/cloudflaretunnel.sh"
WEB="$BASE/webs/Module_cloudflaretunnel.asp"
INITD="$BASE/init.d/S99cloudflaretunnel.sh"
CONFIG="$BASE/configs/cloudflaretunnel.conf"
BINLINK="$BASE/bin/cloudflaretunnel"
LOG=/opt/var/log/cloudflared.log
PID=/var/run/cloudflaretunnel.pid

log() { echo "[cloudflaretunnel] $*"; logger -t cloudflaretunnel "$*" 2>/dev/null; }

set_db() {
    # koolshare dbus helper
    [ -n "$1" ] && [ -n "$2" ] && dbus set "$1" "$2" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 卸载
# ---------------------------------------------------------------------------
uninstall() {
    log "Uninstalling cloudflaretunnel ..."

    [ -f "$SCRIPT" ] && "$SCRIPT" stop 2>/dev/null

    rm -f "$SCRIPT" "$WEB" "$INITD" "$CONFIG" "$BINLINK" "$PID"

    # 移除软件中心菜单注册（幂等）
    dbus remove softcenter_module_cloudflaretunnel 2>/dev/null
    dbus remove cloudflaretunnel_enable 2>/dev/null
    dbus remove cloudflaretunnel_mode 2>/dev/null
    dbus remove cloudflaretunnel_token 2>/dev/null
    dbus remove cloudflaretunnel_name 2>/dev/null
    dbus remove cloudflaretunnel_loglevel 2>/dev/null
    dbus remove cloudflaretunnel_extra 2>/dev/null

    log "Uninstall done. cloudflared (opkg) package not removed."
}

# ---------------------------------------------------------------------------
# 安装
# ---------------------------------------------------------------------------
install() {
    log "Installing cloudflaretunnel ..."

    # 1. 路径存在性检查
    [ -d "$BASE/scripts" ] || { log "ERROR: /koolshare not found, not a softcenter firmware."; exit 1; }

    # 2. 依赖：Entware / opkg 与 cloudflared
    if [ ! -x /opt/bin/cloudflared ]; then
        if command -v opkg >/dev/null 2>&1; then
            log "Installing cloudflared via opkg ..."
            opkg update >/dev/null 2>&1
            opkg install cloudflared >/dev/null 2>&1 || log "WARN: opkg install cloudflared failed, install manually."
        else
            log "WARN: opkg not found (Entware missing). Install Entware then cloudflared."
        fi
    else
        log "cloudflared already installed."
    fi

    # 3. 落盘本插件随包文件
    mkdir -p "$BASE/scripts" "$BASE/webs" "$BASE/init.d" "$BASE/configs" "$BASE/bin" "$(dirname "$LOG")"

    # 假设随包文件与 install.sh 同目录
    SRC=$(cd "$(dirname "$0")" && pwd)
    copy_if_needed() {
        _s="$1"; _d="$2"
        if [ -f "$_s" ]; then
            [ "$_s" = "$_d" ] && return 0        # 已解压到目标位置，无需复制
            cp "$_s" "$_d" 2>/dev/null || log "WARN: copy $_s -> $_d failed"
        else
            log "WARN: $_s missing (package may be partially extracted)"
        fi
    }
    copy_if_needed "$SRC/scripts/cloudflaretunnel.sh" "$SCRIPT"
    copy_if_needed "$SRC/webs/Module_cloudflaretunnel.asp" "$WEB"
    copy_if_needed "$SRC/init.d/S99cloudflaretunnel.sh" "$INITD"
    chmod 755 "$SCRIPT" "$INITD" 2>/dev/null

    # 兼容旧调用：/koolshare/bin/cloudflaretunnel -> 主脚本
    [ -f "$SCRIPT" ] && ln -sf "$SCRIPT" "$BINLINK" 2>/dev/null

    # 4. 默认配置
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

    # 5. 写 dbus 默认值（软件中心依赖）
    set_db cloudflaretunnel_enable   0
    set_db cloudflaretunnel_mode     remote
    set_db cloudflaretunnel_token    ""
    set_db cloudflaretunnel_name     ""
    set_db cloudflaretunnel_loglevel info
    set_db cloudflaretunnel_extra    ""
    set_db softcenter_module_cloudflaretunnel "1"

    log "Install done. Enable and set token in the Web UI."
}

case "$ACTION" in
    1|install|installed)   install ;;
    0|uninstall|remove)    uninstall ;;
    *)                     install ;;
esac
