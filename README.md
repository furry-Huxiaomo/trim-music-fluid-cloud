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

### 前置条件

- **已 Root**（Magisk / KernelSU / APatch）
- **ColorOS** 系统（本模块针对 ColorOS 15 / Android 15 验证，理论上 ColorOS 14+ 通用）
- 目标 App 包名为 `com.trim.music`

### 步骤

1. 下载 `trim_music_fluid_cloud.zip`
2. 打开 Magisk → 模块 → 从本地安装 → 选择 zip
3. 重启手机

重启后播放任意歌曲，状态栏应出现流体云胶囊。

### 验证是否生效

```bash
su -c 'grep -c com.trim.music /data/user_de/0/com.android.systemui/shared_prefs/oplus_media_controller_config_sp.xml'
```

输出 `1` 表示已写入。

---

## 卸载

在 Magisk 中移除模块并重启即可。

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
| `whitelist_patch.sh` | 核心补丁。幂等，可独立运行或被 source |
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

## 适用范围与限制

### 可以用的场景

- 你自己 Root 过的 OPPO / OnePlus / realme 设备
- 任何包名为 `com.trim.music` 的音乐 App

### 不适用的场景

- **未 Root 的设备**——无法访问 SystemUI 私有数据
- **想给其他用户使用**——每个用户都需要自己 Root 并装模块
- **非 ColorOS 系统**——白名单机制是 OPPO 独有的

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
- 逆向分析基于 ColorOS 15（`V15.0.0`，Android 15，PGZ110）实机

---

## 许可证

MIT License

---

**问题反馈**：2374856975@qq.com
