#!/system/bin/sh
# 编译打包 Magisk 模块 zip
#
# 用法: sh build.sh
# 产物: dist/trim_music_fluid_cloud-<version>.zip

set -e

MODDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$MODDIR"

# 从 module.prop 读版本号
VERSION=$(grep '^version=' module.prop | cut -d= -f2)
[ -z "$VERSION" ] && VERSION="unknown"

OUT="dist"
rm -rf "$OUT"
mkdir -p "$OUT"

ZIP="$OUT/trim_music_fluid_cloud-${VERSION}.zip"

# 打包（排除开发用文件）
zip -r "$ZIP" \
    module.prop \
    whitelist_patch.sh \
    post-fs-data.sh \
    service.sh \
    watchdog.sh \
    uninstall.sh \
    customize.sh \
    config.sh \
    check_env.sh \
    -x '.*' \
    -x '*.md' \
    -x 'dist/*'

echo ""
echo "===================="
echo "构建完成: $ZIP"
unzip -l "$ZIP"
echo "===================="
