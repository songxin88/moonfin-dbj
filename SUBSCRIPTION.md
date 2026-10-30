# 订阅源模块说明

在 Moonfin（Flutter，Emby / Jellyfin 客户端）中新增的一套**独立订阅源模块**，
用于饭太硬 / TVBox 格式的 JSON 配置源（含多仓）。原有媒体库功能、UI、动画、
配色、播放器控制界面全部保持不变。

## 模块位置

```
lib/subscription/
├── models/subscription_models.dart     # 纯数据模型（配置 / 站点 / 影片 / 线路 / 集）
├── data/tvbox_api.dart                 # TVBox 协议：XML 与 JSON 接口、解析、播放地址
├── data/subscription_store.dart        # 本地持久化（SharedPreferences）
├── state/subscription_controller.dart  # 订阅源状态：仓库、当前源、观看记录
└── ui/
    ├── main_screen.dart                # 未登录主界面（添加媒体库 / 添加订阅源 + 底部导航）
    ├── sources_manager_screen.dart     # 订阅源管理：添加 / 编辑 / 删除 / 刷新 / 多仓线路
    ├── subscription_home_screen.dart   # 订阅源首页：站点、分类、搜索、视频卡片、继续观看
    ├── subscription_detail_screen.dart # 详情页：海报、简介、线路切换、选集
    └── subscription_player_screen.dart # 播放器：media_kit 居中播放（BoxFit.contain）
```

对 Moonfin 原有代码的改动只有路由与入口（最小侵入，便于后续合并官方 main）：

| 文件 | 改动 |
| --- | --- |
| `lib/ui/navigation/destinations.dart` | 新增 `/main`、`/subscription`、`/subscription/sources`、`/subscription/detail`、`/subscription/player` |
| `lib/ui/navigation/app_router.dart` | 注册上述路由；未登录时放行 `/main` 与 `/subscription` |
| `lib/ui/screens/auth/startup_screen.dart` | 没有任何媒体服务器时进入 `/main`（原为服务器选择页） |
| `lib/preference/bottom_nav_tabs.dart` 等底部导航文件 | 媒体库首页底部导航新增“订阅”标签 |

## 打开主界面

未添加任何媒体服务器时，App 启动会进入 **主界面 `/main`**：

- 顶部两张卡片：**添加媒体库**（跳转 Emby / Jellyfin 服务器添加页）、**添加订阅源**
- 底部导航栏三个标签：**媒体库** / **订阅** / **我的**
  - 媒体库：添加媒体库、已有服务器列表（点击直接进入）
  - 订阅：订阅源列表（点击切换当前源并进入）、最近观看、添加 / 管理
  - 我的：订阅源管理、媒体服务器、清空观看记录、关于（支持范围说明）
- 已登录媒体库时，原 Moonfin 首页（Home）底部导航也新增了“订阅”入口

## 怎么添加订阅源

方式一（主界面）：

1. 主界面点击 **添加订阅源**
2. 粘贴订阅地址（`http(s)://...` 的 TVBox / 饭太硬配置），名称可留空自动生成
3. 若是**多仓**配置，会弹出线路列表，选择一条线路后自动设为当前源
4. 保存后点击 **订阅源** 进入浏览

方式二（已登录媒体库）：

1. 首页底部导航点 **订阅**
2. 右上角 `+` 添加；`☰` 打开订阅源管理

也支持直接粘贴 JSON 内容（自动识别 base64 编码的配置）。

## 订阅源管理

入口 `/subscription/sources`，支持：

- **添加 / 编辑（名称与地址）/ 删除 / 刷新**
- **设为当前**（首页浏览的是当前源）
- **多仓线路切换**（`urls` 字段中的 `Depot` 列表）

## 支持范围

| 类型 | 支持情况 |
| --- | --- |
| `type 0`  XML 接口（`ac=videolist`） | 支持：站点、分类、列表、详情、搜索 |
| `type 1` / `type 4` JSON 接口（MacCMS `api.php/provide/vod`） | 支持：`ac=list` / `ac=detail`、分类、搜索、详情 |
| `type 3` JS / Python / PHP / JAR 爬虫（`csp_` 前缀） | **不支持**：需要 TVBox 原生内核，UI 中显示为锁定态 |
| 播放地址 | 直链（m3u8 / mp4 / flv 等）直接播放；`xx://` 协议走 `parses` 解析接口（GET，失败回退 POST）；magnet / ed2k / thunder / ftp 不支持 |
| 选集 / 多线路 | 支持：`vod_play_from` 按 `$$$` 分线路，`vod_play_url` 按 `$$$` 分组、`#` 分集 |

## 数据与播放

- 订阅源配置、当前源、观看记录全部保存在本机（SharedPreferences），不写入 Emby / Jellyfin。
- 视频卡片复用 Moonfin 的 `MediaCard`，详情页沿用 Moonfin 设计 token（配色 / 间距 / 字体）。
- 播放器为独立页面，视频 `BoxFit.contain` 居中显示，加黑边填充，不拉伸、不裁切；
  控制层为独立实现（点击画面显隐、进度条、下一集、选集），不会改动 Moonfin 原生播放页。
- 播放使用 media_kit（与 Moonfin 一致的播放内核）。

## 编译

```bash
flutter pub get
flutter build apk --release
```

产物为 Android 手机端（竖屏），`android/` 配置未做改动。
