#!/bin/sh
# softcenter init.d startup hook for cloudflaretunnel
# Self-contained: no Entware / /opt dependency.
# v1.2.0: wait for time/network readiness, then start and install watchdog cron.

SCRIPT=/koolshare/scripts/cloudflaretunnel.sh
CRON_TAG="# cloudflaretunnel-watchdog"
CRON_FILE=/var/spool/cron/crontabs/root
WATCHDOG_LINE="*/2 * * * * $SCRIPT check >/dev/null 2>&1 $CRON_TAG"

[ -x "$SCRIPT" ] || exit 0

# 1) 等待时间同步：cloudflared 基于 TLS，系统时间偏差过大会导致认证失败。
#    梅林固件重启后 NTP 同步可能需要数十秒；最多等待约 60 秒。
_i=0
while [ $_i -lt 30 ]; do
    _year=$(date +%Y 2>/dev/null)
    case "$_year" in
        20[2-9][0-9]) break ;;
    esac
    sleep 2
    _i=$((_i + 1))
done

# 2) 等待网络就绪：轮询公网 IP 连通性（最多约 60 秒），替代固定 sleep 15。
_i=0
while [ $_i -lt 30 ]; do
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 \
       || ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1; then
        break
    fi
    sleep 2
    _i=$((_i + 1))
done

# 3) 启动服务
"$SCRIPT" start >/dev/null 2>&1

# 4) 安装看门狗 cron（幂等：已有则跳过；每 2 分钟执行一次 check）
if [ -d "$(dirname "$CRON_FILE")" ]; then
    if ! grep -q "$CRON_TAG" "$CRON_FILE" 2>/dev/null; then
        { echo "$WATCHDOG_LINE"; } >> "$CRON_FILE" 2>/dev/null
        logger -t cloudflaretunnel "watchdog cron installed" 2>/dev/null
        # 尝试通知 cron 重载（不同固件实现不一，失败不影响）
        killall -HUP cron 2>/dev/null || killall -HUP crond 2>/dev/null || true
    fi
fi

exit 0
