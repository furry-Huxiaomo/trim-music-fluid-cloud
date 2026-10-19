#!/system/bin/sh
# 每 5 秒轮询白名单文件，缺失 com.trim.music 就补回。
# 覆盖场景：
#   1) SystemUI 启动时用云端 RUS 数据回写白名单（云端版本号更高时）
#   2) 应用清除数据 / 恢复出厂后 SP 重建
#   3) 系统 OTA 后配置重置
# 用轮询而不是 inotify：SystemUI 是整体覆盖写，且 inotifywait 在 Magisk 环境不一定可用。
MODDIR=${0%/*}
SP=/data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml
TARGET=com.trim.music

# 防止重复启动
if [ -f "/data/local/tmp/.trim_fluid_watchdog.pid" ]; then
  _old=$(cat "/data/local/tmp/.trim_fluid_watchdog.pid" 2>/dev/null)
  if [ -n "$_old" ] && [ -d "/proc/$_old" ]; then
    exit 0
  fi
fi
echo $$ > /data/local/tmp/.trim_fluid_watchdog.pid

while true; do
  sleep 5
  [ -f "$SP" ] || continue
  if ! grep -q "$TARGET" "$SP" 2>/dev/null; then
    echo "[TrimMusicFluid] watchdog: 白名单缺失 $TARGET，补回"
    sh "$MODDIR/whitelist_patch.sh"
  fi
done
