#!/bin/sh
# softcenter init.d startup hook for cloudflaretunnel
# Called by /koolshare/init.d/ during boot. Wait for Entware (/opt) then start.

sleep 15
[ -x /koolshare/scripts/cloudflaretunnel.sh ] || exit 0
/koolshare/scripts/cloudflaretunnel.sh start >/dev/null 2>&1
exit 0
