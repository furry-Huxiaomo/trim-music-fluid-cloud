#!/system/bin/sh
# 公用函数：确保 com.trim.music 存在于 SystemUI 媒体流体云白名单
#
# 目标文件: /data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml
# 结构:
#   <map>
#     <int name="rus_location_version_key" value="20251231" />
#     <set name="rus_content_key">
#         <string>[pkg1, pkg2, ...]</string>
#     </set>
#   </map>
#
# SystemUI 解析逻辑 (OplusMediaRusUpdateManager.getLocalDataToSP):
#   先把 "[" "]" " " 全部替换成空串，再按 "," 拆分。
#   所以分隔符必须是 ", "（逗号+空格）；若写成单纯的 ","，上一个包名会吞掉下一个包名。
#
# 本脚本不 exit，可被 . source 或被 sh 调用。

SP=/data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml
TARGET=com.trim.music
SUID=10203   # com.android.systemui 的 uid/gid

_log() { echo "[TrimMusicFluid] $*"; }

_patch_whitelist() {
  if [ ! -f "$SP" ]; then
    _log "SP 不存在，跳过: $SP"
    return 0
  fi

  # 已存在就不动，避免无意义写盘触发 SystemUI 重载
  if grep -q "$TARGET" "$SP" 2>/dev/null; then
    _log "白名单已包含 $TARGET，无需处理"
    return 0
  fi

  # 在 </string> 前插入 ", $TARGET"
  _tmp="${SP}.tmp.$$"
  if ! sed "s#\]</string>#, $TARGET]</string>#" "$SP" > "$_tmp" 2>/dev/null; then
    _log "sed 失败"
    rm -f "$_tmp"
    return 1
  fi

  # 校验：插入后必须同时存在目标包名
  if ! grep -q "$TARGET" "$_tmp" 2>/dev/null; then
    _log "插入校验失败，放弃写入"
    rm -f "$_tmp"
    return 1
  fi

  # 保持属主/权限/SELinux context 与原文件一致
  chown "$SUID:$SUID" "$_tmp" 2>/dev/null
  chmod 660 "$_tmp" 2>/dev/null
  restorecon "$_tmp" 2>/dev/null

  # 原子替换
  if mv -f "$_tmp" "$SP" 2>/dev/null; then
    _log "已写入 $TARGET"
  else
    _log "替换失败"
    rm -f "$_tmp"
    return 1
  fi

  # SystemUI 内存里缓存了 whiteList（getRusWhiteList 仅在为空时读 SP），
  # 必须重启进程才会重新加载。
  _log "重启 SystemUI 以加载新白名单"
  pkill -f com.android.systemui 2>/dev/null
  return 0
}

_patch_whitelist
