#!/bin/sh
# softcenter init.d startup hook for cloudflaretunnel
# Self-contained: no Entware / /opt dependency. Just wait for network then start.

sleep 15
[ -x /koolshare/scripts/cloudflaretunnel.sh ] || exit 0
/koolshare/scripts/cloudflaretunnel.sh start >/dev/null 2>&1
exit 0
