# 飞牛音乐流体云适配

让**飞牛音乐**（`com.trim.music`）在 ColorOS / OPPO 手机上获得完整的**媒体流体云**支持——状态栏胶囊、锁屏媒体卡、AOD 息屏卡片、高斯模糊背景。

> 作者：**狐小墨**
> 本项目由 **DeepSeek** 编写
> 问题反馈：2374856975@qq.com

---

## 这是什么

ColorOS 的媒体流体云（状态栏那颗小小的专辑胶囊、锁屏的音乐卡片）**并不对所有音乐 App 开放**。系统在 `SystemUI` 里维护了一份**包名白名单**，只有在名单里的 App 才会被 `com.oplus.mediacontroller` 渲染成流体云卡片。

飞牛音乐不在名单里，所以即使它已经正确实现了标准 `MediaSession`（媒体控制中心里能正常显示歌名、专辑图、进度、播放控制），状态栏依然没有胶囊。

本模块做的事情只有一件：

> **把 `com.trim.music` 追加进 SystemUI 的媒体流体云白名单。**

不修改任何 APK，不修改系统分区。

---

## 工作原理

### 判定链路

逆向 `SystemUI.apk`（`classes5.dex`）后，完整链路如下：

```
SystemUI
 └ OplusMediaSeedlingController                    # 监听播放器变化
    ├ mediaSeedlingControlEx.isSupportMediaSeedlingByFeature()
    │   = !getDisableMediaSeedlingFeature() && isSupportFluidFeature()
    └ initWhiteListData() → OplusMediaRusUpdateManager
        ├ 白名单来源：RUS 云控 content://com.oplus.romupdate.provider.db/update_list
        │   字段 "app_systemui_oplus_media_controller_config"
        │   落盘 SharedPreferences("oplus_media_controller_config_sp")
        │     ├ "rus_content_key"        (StringSet, 包名列表)
        │     └ "rus_location_version_key" (int, 云控版本号)
        ├ 兜底：assets/app_systemui_oplus_media_controller_config.xml
        └ getRusWhiteList() → List<String> 包名
              ↓ PersistentConnectionManagerImpl.onConnected()
              ↓ proxy.setWhiteList(list.toString())     # AIDL 下发
                    com.oplus.mediacontroller
              ↓ SlMediaService.setWhiteList
              ↓ SlMediaCardViewModelImpl.f925t = str.split(",")
```

最终判定发生在 `com.oplus.mediacontroller` 内（`q/h.java`）：

```java
arrayList2 = this.f925t;                                    // 白名单
if (arrayList2 != null || arrayList2.contains(gVar.f545a.f610b)) {
    z3 = false;                                             // 允许展示流体云
} else {
    z3 = true;                                              // 隐藏
}
```

其中 `gVar.f545a.f610b` 是 `MediaSession` 所属的**包名**，由系统 framework 通过 `OplusMediaPlayerInfo.getPackageName()` 填充——App 自己无法伪造。

**所以唯一的开关就是包名是否在白名单里。**

### 白名单文件

```
/data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml
```

结构：

```xml
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <int name="rus_location_version_key" value="20251231" />
    <set name="rus_content_key">
        <string>[com.tencent.qqmusic, com.netease.cloudmusic, ...]</string>
    </set>
</map>
```

本模块在 `</string>` 之前插入 `, com.trim.music`。

### 三个必须做对的技术细节

#### ① 分隔符必须是 `", "`（逗号 + 空格）

SystemUI 的解析逻辑（`OplusMediaRusUpdateManager.getLocalDataToSP`）：

```java
StringsKt.replace(str, "[", "")   // 删左括号
StringsKt.replace(str, "]", "")   // 删右括号
StringsKt.replace(str, " ", "")   // 删空格
split(new String[]{","})          // 按逗号拆分
```

它会**先把所有空格删掉**再按逗号拆。所以：

- `[a, b]` → 删空格 → `a,b` → 拆成 `["a", "b"]` ✅
- `[a,b]` → 拆成 `["a", "b"]` ✅
- `[a ,b]` → 删空格 → `a,b` → 拆成 `["a", "b"]` ✅（碰巧也行）
- 但如果你只是字符串拼接而没有正确闭合，就会吞掉别人的包名 ❌

本模块用 `sed "s#\]</string>#, $TARGET]</string>#"` 精确插入，不会破坏已有条目。

#### ② 文件元数据必须完整

```
属主:    10203:10203   (u0_a203，即 com.android.systemui)
权限:    660
SELinux: u:object_r:app_data_file:s0:c512,c768
```

三项任一不对，SystemUI 读到的就是旧值或空值。脚本里用 `chown` / `chmod` / `restorecon` 严格同步。

> `restorecon` 在部分精简 ROM 或 KernelSU 环境下可能不存在，脚本已做容错（失败不报错），此时 SELinux context 会继承父目录，通常不影响功能。

#### ③ 必须重启 SystemUI

```java
public final java.util.List<java.lang.String> getRusWhiteList() {
    if (this.whiteList.isEmpty()) {              // 内存缓存
        this.whiteList.addAll(getLocalDataToSP());
    }
    ...
}
```

白名单读进内存后就缓存了，写文件不会触发重读。所以补丁写入后执行 `pkill -f com.android.systemui`。

---

## 为什么这样改不影响更新

这是本项目的核心设计目标。

| 关注点 | 状态 |
|---|---|
| 飞牛音乐 APK | **完全未修改** ✅ 应用内更新照常工作 |
| SystemUI APK | **完全未修改** ✅ 无签名问题 |
| 系统分区 | **完全未修改** ✅ 无 OTA 校验问题 |
| 改动范围 | 仅一个 SystemUI 的**用户数据文件** |

飞牛音乐无论更新到哪个版本，只要包名还是 `com.trim.music`，流体云就持续可用。**白名单在系统侧，与 App 版本完全解耦。**

---

## 安装

### 支持的 Root 管理器

本模块只用 Magisk 模块规范的**基础能力**（`module.prop` + `post-fs-data.sh` + `service.sh` + `uninstall.sh`），不依赖任何 Magisk 独有特性（无 Zygisk、无 `$MAGISKTMP`、无 `magisk --clone`），因此各主流管理器都可用：

| Root 管理器 | 状态 | 说明 |
|---|---|---|
| **Magisk** | ✅ | 本项目验证环境 |
| **KernelSU / KSU Next** | ✅ | 支持 Magisk 模块规范，模块目录同为 `/data/adb/modules/` |
| **APatch** | ✅ | 同上 |

无需修改任何东西，直接刷 zip 即可。

### 前置条件

- **已 Root**（Magisk / KernelSU / APatch，见上表）
- **ColorOS 系系统 14–17**（ColorOS / OxygenOS / realme UI，详见下方「兼容性」章节）
- 目标 App 使用标准 Android MediaSession

### 步骤

1. 下载 `trim_music_fluid_cloud.zip`
2. 打开你的 Root 管理器（Magisk / KernelSU / APatch）→ 模块 → 从本地安装 → 选择 zip
3. 重启手机

重启后播放任意歌曲，状态栏应出现流体云胶囊。

### 验证是否生效

**方式一：装模块前后跑自检脚本**

```bash
su -c sh check_env.sh
```

逐项检查 Root、系统、流体云组件、白名单结构、目标 App、模块状态，最后给结论。

**方式二：直接看白名单**

```bash
su -c 'grep -c com.trim.music /data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml'
```

输出 `1` 表示已写入。

---

## 卸载

在你的 Root 管理器（Magisk / KernelSU / APatch）中移除模块并重启即可。

`uninstall.sh` 会终止后台守护进程。**注意：白名单里已写入的 `com.trim.music` 不会被自动删除**（无害，不影响其它 App）。

如需彻底还原，手动编辑该文件删掉 `, com.trim.music` 后重启 SystemUI：

```bash
su -c 'sed -i "s#, com.trim.music\]</string>#]</string>#" /data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml'
su -c 'pkill -f com.android.systemui'
```

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | Magisk 模块元信息 |
| `config.sh` | 目标包名配置（想适配其它 App 改这里） |
| `whitelist_patch.sh` | 核心补丁。幂等，可独立运行或被 source |
| `check_env.sh` | 环境自检，诊断本机是否支持 |
| `post-fs-data.sh` | 挂载阶段执行一次（此时 SystemUI 尚未启动） |
| `service.sh` | 等待 `sys.boot_completed=1` 后执行补救 + 拉起守护进程 |
| `watchdog.sh` | 每 5 秒轮询，白名单被覆盖时自动补回 |
| `uninstall.sh` | 卸载时终止守护进程 |
| `customize.sh` | 安装时提示信息 |

### 守护进程为什么必要

`rus_location_version_key` 是 RUS 云控版本号。如果 OPPO 推送一个**版本号更高**的配置，SystemUI 会用云端数据覆盖白名单，`com.trim.music` 就消失了。

`watchdog.sh` 每 5 秒检查一次，发现缺失立即补回并重启 SystemUI。这样即使云控下发新版本，也能在几秒内恢复。

用轮询而不是 `inotify`：SystemUI 是整体覆盖写，且 `inotifywait` 在 Magisk 环境下不一定可用。

---

## 兼容性

### 判定原则：只看系统，不看品牌

OPPO、一加、realme 同属一家，共用同一套系统底层。它们的中文版系统（ColorOS / OxygenOS / realme UI）都是同一个东西的不同叫法，SystemUI、流体云组件、白名单结构完全一致。

所以本模块的兼容性判断只看两件事：

1. 系统里有没有 **`com.oplus.mediacontroller`**（流体云组件）
2. 白名单文件的**路径与字段结构**是否匹配

两者都满足就能用，与设备叫 OPPO 还是一加无关。

### ✅ 支持：ColorOS 系 14–17

| 系统版本 | 状态 |
|---|---|
| **ColorOS 14** | 支持 |
| **ColorOS 15** | 支持（本项目验证环境） |
| **ColorOS 16** | 支持 |
| **ColorOS 17** | 支持 |

适用于基于该系统的 OPPO / 一加 / realme 中文版机型。

### ⚠️ 需实测

| 情况 | 说明 |
|---|---|
| **ColorOS 13 及更早** | 早期实现不同，白名单机制可能不适用 |
| **海外版（无媒体流体云）** | 部分海外机型没有 `com.oplus.mediacontroller` |

这类设备装上去**不会报错也不会损坏系统**：脚本发现文件不存在会直接跳过，只会没效果。

### ❌ 不支持

| 系统 | 原因 |
|---|---|
| **小米 / 红米（HyperOS）** | 「焦点通知」是小米自研机制 |
| **vivo / iQOO（OriginOS）** | 「原子通知」是另一套实现 |
| **华为 / 荣耀（鸿蒙）** | 「实况窗」是另一套实现 |
| **原生 Android / 类原生 ROM** | 没有流体云功能 |
| **未 Root 的设备** | 无法访问 SystemUI 私有数据 |

各家的「类流体云」功能虽然长得像，但内部实现完全不同。

### 自检：不用猜，直接跑

```bash
su -c sh check_env.sh
```

逐项检查 Root、系统版本、流体云组件、白名单结构、目标 App、模块状态，最后给结论。

输出示例（本项目验证机）：

```
[2/5] 系统识别
  ✓ ColorOS 系系统（V15.0.0）
    Android 15 · 区域 cn
  ✓ ColorOS 15 在支持范围内（14–17）

[3/5] 媒体流体云机制
  ✓ com.oplus.mediacontroller 已就位
  ✓ 白名单文件存在
  ✓ 含 rus_content_key 字段（结构匹配）
```

### 支持其它音乐 App

不限于飞牛音乐。编辑 `config.sh` 改一行即可：

```sh
TARGET_PKG=com.example.music    # 换成目标 App 的包名
```

前提是目标 App 使用**标准 Android MediaSession**（即至少能在系统媒体控制中心里正常显示）。查询包名：

```bash
pm list packages | grep -i music
```

### 关于「让 App 官方适配」

如果希望飞牛音乐**官方**支持流体云（无需 Root），正确路径是：

1. 由**厂商主体**向 OPPO 申请泛在卡片服务
2. OPPO 审核通过后分配服务 ID，并在云端下发 UPK
3. App 侧接入 `SeedlingSupportSDK` 上报播放状态

个人开发者无法走通这条路——技术接入本身无门槛，但 UPK 必须由 OPPO 云端下发，`eventCode` 也需要 OPPO 分配。

另一条路是让 OPPO 把 `com.trim.music` 直接加进上述白名单，这同样需要厂商对接。

---

## 致谢

- 本项目由 **DeepSeek** 编写
- 逆向分析基于 ColorOS 15（`V15.0.0`，Android 15）实机验证

---

## 许可证

MIT License

---

**问题反馈**：2374856975@qq.com
