#!/system/bin/sh
MODDIR=${0%/*}

# 等系统启动完成，避免过早重启 SystemUI
i=0
while [ $i -lt 120 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 1
  i=$((i+1))
done
sleep 8

sh "$MODDIR/whitelist_patch.sh"

# 后台守护进程
nohup sh "$MODDIR/watchdog.sh" >/dev/null 2>&1 &
