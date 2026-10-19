#!/system/bin/sh
# 飞牛音乐流体云适配 —— 环境自检
#
# 用途：在安装前后诊断本机是否支持，以及模块是否已经生效。
# 用法：
#   su -c sh check_env.sh
# 或直接用 Termux 跑（脚本会自动 su）：
#   sh check_env.sh
#
# 判定原则：只看系统能力，不看品牌。
#   ColorOS / OxygenOS / realme UI 都是同一套底层，只需判断
#   「系统里有没有媒体流体云这套组件 + 白名单结构对不对」。

MODDIR="$(cd "$(dirname "$0")" && pwd)"

[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
: "${TARGET_PKG:=com.trim.music}"
: "${SUID:=10203}"

SP=/data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml

if [ -t 1 ]; then
  R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'; B='\033[0;36m'; N='\033[0m'
else
  R=''; G=''; Y=''; B=''; N=''
fi

pass_n=0
fail_n=0
warn_n=0

ok()   { echo "  ${G}✓${N} $*"; pass_n=$((pass_n+1)); }
bad()  { echo "  ${R}✗${N} $*"; fail_n=$((fail_n+1)); }
warn() { echo "  ${Y}!${N} $*"; warn_n=$((warn_n+1)); }
info() { echo "    $*"; }

# 需要 root
if [ "$(id -u)" != "0" ]; then
  if command -v su >/dev/null 2>&1; then
    exec su -c "sh '$0'"
  fi
  echo "${R}需要 root 权限。请用 su -c sh $0 运行。${N}"
  exit 1
fi

echo ""
echo "${B}========== 飞牛音乐流体云适配 · 环境自检 ==========${N}"

# ---------- 1. Root ----------
echo ""
echo "${B}[1/5] Root 权限${N}"
ok "已获得 root"
info "SELinux: $(getenforce 2>/dev/null || echo 未知)"

# ---------- 2. 系统识别（只看是不是 ColorOS 系，不区分品牌） ----------
echo ""
echo "${B}[2/5] 系统识别${N}"
ROMVER=$(getprop ro.build.version.oplusrom 2>/dev/null)
OSVER=$(getprop ro.build.version.release 2>/dev/null)
REGION=$(getprop ro.vendor.oplus.version 2>/dev/null)

if [ -n "$ROMVER" ]; then
  # ROMVER 形如 V15.0.0 / V14.0.1 / V16.0.0
  ROM_MAJOR=$(echo "$ROMVER" | sed -n 's/^[Vv]\([0-9][0-9]*\).*/\1/p')
  ok "ColorOS 系系统（$ROMVER）"
  info "Android $OSVER${REGION:+ · 区域 $REGION}"
  if [ -n "$ROM_MAJOR" ]; then
    if [ "$ROM_MAJOR" -ge 14 ] && [ "$ROM_MAJOR" -le 17 ]; then
      ok "ColorOS $ROM_MAJOR 在支持范围内（14–17）"
    elif [ "$ROM_MAJOR" -lt 14 ]; then
      warn "ColorOS $ROM_MAJOR 低于 14，机制可能不同，需实测"
    else
      warn "ColorOS $ROM_MAJOR 高于 17，未经验证，需实测"
    fi
  fi
else
  bad "未检测到 ColorOS（ro.build.version.oplusrom 为空）"
  info "本机可能是其它厂商 ROM 或类原生系统，本模块不适用"
fi

# ---------- 3. 媒体流体云组件 ----------
echo ""
echo "${B}[3/5] 媒体流体云机制${N}"
if pm list packages 2>/dev/null | grep -q "^package:com.oplus.mediacontroller$"; then
  ok "com.oplus.mediacontroller 已就位"
  MC_VER=$(dumpsys package com.oplus.mediacontroller 2>/dev/null | grep -m1 versionName | tr -d ' ')
  [ -n "$MC_VER" ] && info "$MC_VER"
else
  bad "未找到 com.oplus.mediacontroller"
  info "系统缺少流体云组件，本模块不会生效（也不会造成副作用）"
fi

# 白名单文件
if [ -f "$SP" ]; then
  ok "白名单文件存在"
  OWNER=$(stat -c '%u:%g %a' "$SP" 2>/dev/null)
  info "属主/权限: $OWNER"
  if grep -q "rus_content_key" "$SP" 2>/dev/null; then
    ok "含 rus_content_key 字段（结构匹配）"
    COMMAS=$(sed -n '/rus_content_key/,/<\/set>/p' "$SP" 2>/dev/null | tr -cd ',' | wc -c)
    [ "${COMMAS:-0}" -gt 0 ] && info "白名单内约 $((COMMAS+1)) 个包名"
  else
    bad "缺少 rus_content_key 字段"
    info "系统结构与预期不同，可能不兼容"
  fi
else
  bad "白名单文件不存在"
  info "路径: $SP"
  info "可能系统尚未初始化该配置，尝试播放一次音乐后重试"
fi

# ---------- 4. 目标 App ----------
echo ""
echo "${B}[4/5] 目标 App（$TARGET_PKG）${N}"
if pm list packages 2>/dev/null | grep -q "^package:${TARGET_PKG}$"; then
  ok "已安装"
  APP_VER=$(dumpsys package "$TARGET_PKG" 2>/dev/null | grep -m1 versionName | tr -d ' ')
  [ -n "$APP_VER" ] && info "$APP_VER"

  if dumpsys media_session 2>/dev/null | grep -q "package=${TARGET_PKG}"; then
    ok "已注册 MediaSession（可被系统识别为播放器）"
  else
    warn "当前未注册 MediaSession"
    info "播放音乐后再检测"
  fi
else
  bad "未安装 $TARGET_PKG"
  info "若要适配其它 App，请修改 config.sh 里的 TARGET_PKG"
fi

# ---------- 5. 模块状态 ----------
echo ""
echo "${B}[5/5] 模块状态${N}"
if [ -f "$SP" ] && grep -q "$TARGET_PKG" "$SP" 2>/dev/null; then
  ok "白名单中已包含 $TARGET_PKG"
else
  warn "白名单中尚未包含 $TARGET_PKG"
  info "若模块已安装，重启手机或等待 watchdog 补回"
fi

MODDIR_SYS=/data/adb/modules/trim_music_fluid_cloud
if [ -d "$MODDIR_SYS" ]; then
  ok "模块目录存在"
  [ -f "$MODDIR_SYS/disable" ] && warn "模块被禁用（存在 disable 文件）"
  [ -f "$MODDIR_SYS/remove" ]  && warn "模块标记为待删除（存在 remove 文件）"
  WD_PID=$(cat /data/local/tmp/.trim_fluid_watchdog.pid 2>/dev/null)
  if [ -n "$WD_PID" ] && [ -d "/proc/$WD_PID" ]; then
    ok "守护进程运行中 (PID $WD_PID)"
  else
    warn "守护进程未运行"
    info "手动启动: su -c 'nohup sh $MODDIR_SYS/watchdog.sh >/dev/null 2>&1 &'"
  fi
else
  warn "模块目录不存在（尚未安装）"
fi

# ---------- 结论 ----------
echo ""
echo "${B}========== 结论 ==========${N}"
echo "  通过 $pass_n 项 · 警告 $warn_n 项 · 失败 $fail_n 项"
echo ""

if [ "$fail_n" -eq 0 ]; then
  if [ "$warn_n" -eq 0 ]; then
    echo "  ${G}系统完全符合要求，流体云应正常工作。${N}"
  else
    echo "  ${G}核心条件满足，少数项待确认（见上方 ! 标记）。${N}"
  fi
elif [ -f "$SP" ] && grep -q "$TARGET_PKG" "$SP" 2>/dev/null; then
  echo "  ${Y}白名单已写入，但仍有检查项未通过。${N}"
  echo "  若流体云已能在状态栏显示，可忽略上方 ✗。"
else
  echo "  ${R}系统不满足核心条件，模块大概率不会生效。${N}"
  echo "  最常见原因：非 ColorOS 系系统，或缺少流体云组件。"
fi

echo ""
echo "  适用系统：ColorOS / OxygenOS / realme UI（14–17）"
echo "  详见 README「兼容性」章节 · 反馈: 2374856975@qq.com"
echo ""
