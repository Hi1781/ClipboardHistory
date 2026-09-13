# ClipboardHistory · 剪贴板历史
一款适配 iPhone / iPad（并可通过 Catalyst 运行于 Apple Silicon Mac）的**轻量化剪贴板历史工具**。
UI 与键盘遵循 Apple Human Interface Guidelines，原生、简约、实用。

> 非越狱、不依赖私有后台捕获。进入 App 或唤起键盘时自动完成双向同步：
> **剪贴板有内容 → 导入历史；剪贴板为空 → 回填最新一条**；列表可直接下滑翻找全部历史。

---

## 一、功能总览（v2.0）

| 模块 | 能力 |
| --- | --- |
| 双向同步 | 进入 App / 唤起键盘自动导入或回填；changeCount 去重，避免重复弹窗 |
| 历史浏览 | insetGrouped 列表、下拉刷新、左滑删除/置顶/敏感、长按预览、上下文菜单 |
| 搜索 | 全局搜索（多关键字 AND）+ 类型 Scope（全部/文本/链接/图片），键盘内同步支持 |
| 组织 | 固定置顶、多标签分类、横向标签筛选、标签管理 |
| 批量管理 | 编辑模式多选，批量置顶 / 打标签 / 删除 |
| 键盘扩展 | 独立剪贴历史面板，点按插入/复制，支持搜索、类型筛选、置顶标识 |
| Widget | 桌面小/中/大组件与锁屏组件，展示最近一条记录 |
| Siri / 快捷指令 | 复制最新、搜索并复制、清空历史、打开 App（App Intents） |
| 后台监听 | BGTaskScheduler 后台刷新 + 前台近实时轮询（受系统调度，非 7×24 静默） |
| 存储 | SQLite（WAL + 索引），正文/图片字段级 AES-256 加密 |
| 密钥 | 主密钥存于 iOS Keychain；旧版加密 JSON 首次启动自动迁移 |
| 云同步 | iCloud CloudKit 私有库（仅文本），未登录/未开通时静默降级为纯本地 |
| 多端 | iPhone、iPad、横竖屏、深色模式、动态字体、macOS Catalyst |
| 隐私 | 数据默认不出设备；敏感记录不参与自动回填；本地加密 |

### 关于「实时获取剪贴板」的能力边界（重要）
iOS 沙盒与隐私机制下，**非越狱设备无法做到 App 完全后台时静默实时读取剪贴板**（iOS 14+ 读取还会有系统提示）。本项目采用合规路径最大化捕获率：

1. **前台/键盘唤起即时同步**（主路径，可靠）；
2. **前台近实时轮询** changeCount（设置中开启「后台监听」）；
3. **BGTaskScheduler 后台刷新**（系统按用电情况调度，非定长周期）；
4. iCloud / App Group 让主 App、键盘、Widget 共享同一份数据。

需要真正 7×24 全局捕获只能越狱或使用私有 API（本项目不采用，也无法通过侧载长期稳定运行）。

---

## 二、工程结构
```
ClipboardHistoryApp/
├── ClipKit/                    # 共享框架（模型 / SQLite / 同步 / 密钥 / 云 / 后台）
│   ├── ClipItem.swift          # 数据模型 + 排序 + UIColor/UIImage 扩展
│   ├── ClipDatabase.swift      # SQLite 层（字段级加密）
│   ├── ClipStore.swift         # 存储门面（缓存/搜索/置顶/标签/批量/迁移）
│   ├── PasteboardSync.swift    # 双向同步核心
│   ├── KeychainHelper.swift    # Keychain 主密钥
│   ├── CryptoHelper.swift      # SHA256 / AES-CBC / PBKDF2
│   ├── BackgroundMonitor.swift # 后台任务 + 前台轮询
│   ├── ICloudSyncManager.swift # CloudKit 同步
│   ├── HapticHelper.swift      # 统一触感
│   └── AppGroupConfig.swift    # App Group / 默认设置
├── ClipboardHistory/           # 主 App
│   ├── App/                    # AppDelegate / SceneDelegate
│   ├── Features/History/       # 列表、Cell、预览、通用 UI 组件
│   ├── Features/Settings/      # 设置
│   ├── Features/Tags/          # 标签管理
│   ├── Intents/                # App Intents（Siri/快捷指令）
│   └── Resources/              # Info.plist / Assets.xcassets(AppIcon)
├── ClipboardKeyboard/          # 键盘扩展
└── ClipboardWidget/            # WidgetKit 小组件
```
**Target / Bundle ID**

| Target | 类型 | Bundle ID |
| --- | --- | --- |
| ClipboardHistory | application | `com.clipboard.history` |
| ClipboardKeyboard | app-extension | `com.clipboard.history.keyboard` |
| ClipboardWidget | app-extension | `com.clipboard.history.widget` |
| ClipKit | framework | `com.clipboard.kit` |

App Group：`group.com.clipboard.history`（三个可执行端共享）。最低系统：iOS 16.0。

---

## 三、SideStore / AltStore 侧载安装

1. 在 iPhone 安装 SideStore（或 AltStore）；
2. 把 `*-unsigned.ipa` 传到手机（iCloud / 文件 App / 本地 HTTP）；
3. SideStore 中选择该 IPA，**在设备本地完成全部签名与安装**（使用你的 Apple ID，免费账号 7 天重签）；
4. 首次使用键盘：设置 → 通用 → 键盘 → 添加新键盘 → 剪贴板键盘，并打开「完全访问」
   （App Group 共享读写需要完全访问）。

---

## 四、下一步优化（Roadmap）

**稳定性 / 兼容**
- 用匹配版本 toolchain 在真实 Xcode 环境跑通 CI，补充单元测试（ClipStore 搜索/置顶/迁移用例）。
- Crash 上报与日志分级（os_log），键盘内存占用与图片解码缓存治理。

**功能**
- 富类型扩展：富文本/RTF、文件 URL、多段剪贴板；图片标注与 OCR（VisionKit）。
- 验证码自动识别（短信验证码一键填入，键盘内高亮）。
- 智能收藏夹、按来源 App 分组、Universal Clipboard（Handoff）联动。
- iCloud 全量同步（含图片，采用 CKAsset）与冲突合并策略；可选 WebDAV 自建同步。
- 锁屏 Live Activity / 灵动岛展示最近复制状态。
- iPad：分栏（UISplitViewController）、拖拽（Drag & Drop）、键盘快捷键。

**安全**
- 可选「主密码 / Face ID 解锁」，敏感项单独加密；剪贴板过期自动清空（自毁计时器）。
- 安全擦除（多次覆写）与数据库加密升级（SQLCipher 或 iOS Data Protection 分级）。

**体验**
- 自定义键盘主题、字号、列表密度；VoiceOver 全量无障碍审计与动态字体校验。
- 本地化（英文/日文）与导出（JSON/CSV/文本备份分享）。