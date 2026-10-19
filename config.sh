# 目标配置
#
# 想适配其它音乐 App？把 TARGET_PKG 改成那个 App 的包名即可，无需改脚本。
# 适用系统：ColorOS / OxygenOS / realme UI（14–17），只看系统能力不看品牌。
# 查询包名: pm list packages | grep -i <关键词>

# 要加入流体云白名单的包名
TARGET_PKG=com.trim.music

# com.android.systemui 的 uid/gid。这是 Android 上的固定值，不需要修改。
SUID=10203
