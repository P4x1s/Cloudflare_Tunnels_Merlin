#!/bin/sh
# ASUSGO / koolshare softcenter uninstall entry for cloudflaretunnel
# Simply delegates to install.sh with the uninstall argument.
DIR=$(cd "$(dirname "$0")" && pwd)
if [ -f "$DIR/install.sh" ]; then
    chmod +x "$DIR/install.sh" 2>/dev/null
    exec "$DIR/install.sh" 0
else
    echo "[cloudflaretunnel] install.sh not found; performing minimal cleanup."
    /koolshare/scripts/cloudflaretunnel.sh stop 2>/dev/null
    # 清理看门狗 cron 与健康状态临时文件
    _cron=/var/spool/cron/crontabs/root
    if [ -f "$_cron" ]; then
        _tmp="$_cron.ct.$$"
        grep -v "cloudflaretunnel-watchdog" "$_cron" > "$_tmp" 2>/dev/null && cat "$_tmp" > "$_cron" 2>/dev/null
        rm -f "$_tmp"
        killall -HUP cron 2>/dev/null || killall -HUP crond 2>/dev/null || true
    fi
    rm -f /tmp/cloudflaretunnel.health /tmp/cloudflaretunnel.lastrestart
    rm -f /koolshare/scripts/cloudflaretunnel.sh \
          /koolshare/webs/Module_cloudflaretunnel.asp \
          /koolshare/init.d/S99cloudflaretunnel.sh \
          /koolshare/configs/cloudflaretunnel.conf \
          /koolshare/configs/cloudflaretunnel.token \
          /koolshare/bin/cloudflaretunnel \
          /var/run/cloudflaretunnel.pid
    dbus remove softcenter_module_cloudflaretunnel 2>/dev/null
    exit 0
fi
