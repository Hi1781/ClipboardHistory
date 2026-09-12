# 更新日志 / Changelog

## v2.0.0（当前版本）

### v1.0 —— 基础能力
- 主 App 剪贴历史列表（insetGrouped 原生风格、下拉刷新、左滑删除/敏感标记、上下文菜单）
- 自定义键盘扩展，唤起即双向同步
- ClipKit 共享框架：App Group 共享、AES-256 加密 JSON 存储、去重、自动清理
- 进入 App / 唤起键盘：剪贴板有内容则导入历史，为空则回填最新一条

### v1.1 —— 检索 / 预览 / 云 / 小组件
- 新增：全局搜索（UISearchController，多关键字 AND、类型 Scope）
- 新增：长按/上下文菜单全屏预览（文本可滚动、图片自适应）
- 新增：原生 App 图标与 AccentColor 资源
- 新增：iCloud 同步（CloudKit 私有库，仅文本；KVS 同步设置；未登录静默降级）
- 新增：桌面 Widget（小/中/大/锁屏，展示最近一条，点击进 App）

### v1.2 —— 组织 / 批量 / 语音
- 新增：固定置顶（置顶优先排序、独立图标、清理时受保护）
- 新增：分类标签（多标签、横向标签筛选栏、标签管理页）
- 新增：批量管理（编辑模式多选、批量置顶/打标签/删除）
- 新增：Siri / 快捷指令（App Intents：复制最新、搜索复制、清空、打开）
- 新增：键盘内搜索与类型筛选

### v2.0 —— 存储 / 安全 / 后台 / 多端
- 新增：SQLite 持久化（libsqlite3 直连，WAL，索引；正文/图片字段级 AES-256 加密）
- 新增：主密钥迁移到 iOS Keychain（kSecAttrAccessibleAfterFirstUnlock）
- 新增：v1.0 加密 JSON → SQLite 一次性自动迁移（旧文件改名备份不删除）
- 新增：后台监听（BGTaskScheduler 后台刷新 + 前台近实时 changeCount 轮询）
- 新增：App Intents 体系化、Widget 时间线
- 新增：macOS Catalyst 支持（iPhone/iPad/Apple Silicon Mac 通用）
- 优化：统一触感反馈、最大条数上限、空状态/横幅/Toast 组件化
- 适配：iPhone + iPad 全尺寸、横竖屏、深色模式、动态字体

## 后续规划（Roadmap）
见 [README.md](README.md)「下一步优化」。
