#!/system/bin/sh
# 卸载时停掉守护进程
if [ -f /data/local/tmp/.trim_fluid_watchdog.pid ]; then
  _pid=$(cat /data/local/tmp/.trim_fluid_watchdog.pid 2>/dev/null)
  [ -n "$_pid" ] && kill "$_pid" 2>/dev/null
  rm -f /data/local/tmp/.trim_fluid_watchdog.pid
fi
echo "[TrimMusicFluid] 已卸载，白名单改动会由 SystemUI 后续覆盖（如需立即还原请手动编辑 SP）"
