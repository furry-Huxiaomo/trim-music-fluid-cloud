# 更新日志

## v1.1

### 新增

- `check_env.sh`：环境自检脚本，逐项检查 Root、系统版本、流体云组件、白名单结构、目标 App、模块状态
- `config.sh`：把目标包名提取为可配置项，改一行即可适配其它音乐 App

### 改进

- 兼容性判定改为**只看系统能力，不看品牌**：OPPO / 一加 / realme 同属一家，共用同一套 ColorOS 系底层
- 明确支持范围：ColorOS 系 14–17
- `whitelist_patch.sh` 不再硬编码包名，改为从 `config.sh` 读取
- README 重写兼容性章节，给出支持 / 需实测 / 不支持三档对照

### 文档

- README 新增「支持的 Root 管理器」章节：明确兼容 Magisk / KernelSU / APatch
- 说明模块未使用任何 Magisk 独有特性，模块目录同为 `/data/adb/modules/`
- 补充 `restorecon` 缺失时的容错说明

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
