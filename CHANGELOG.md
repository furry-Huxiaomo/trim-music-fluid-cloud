# 更新日志

## v1.0

首个版本。

### 功能

- 将 `com.trim.music`（飞牛音乐）加入 ColorOS 媒体流体云白名单
- 开机自动补齐（`post-fs-data.sh` + `service.sh`）
- 后台守护进程，每 5 秒检测白名单是否被 RUS 云控覆盖，自动补回（`watchdog.sh`）

### 技术要点

- 不修改任何 APK，不改系统分区，仅修改 SystemUI 的一个 SharedPreferences 文件
- 严格保持文件元数据（属主 `10203:10203`、权限 `660`、SELinux context `u:object_r:app_data_file:s0:c512,c768`）
- 写入后重启 SystemUI 进程以刷新内存缓存

### 验证环境

- OPPO PGZ110，ColorOS 15（`V15.0.0`），Android 15
- 飞牛音乐 `com.trim.music` 1.0.3（versionCode 103006）
- Magisk 96221b69-alpha
