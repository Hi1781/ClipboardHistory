# 更新日志 / Changelog

## v2.4.0（当前版本）—— 键盘等高再修正 + 键盘状态检测修复 + 词条文本编辑
- 优化（键盘高度）：高度改为「屏幕比例 + 保底值」动态计算并整体补足一截（iPhone 竖屏保底 302、横屏 206；iPad 竖屏保底 360、横屏 300），各机型/方向都与系统官方键盘等高，不再矮一截
- 修复（键盘扩展一直「未检测到」）：心跳改为键盘进程出现即写（不再被早期 hasFullAccess=false 跳过），viewDidAppear 再补报一次，并对共享 UserDefaults 显式 synchronize 跨进程落盘；新增完全访问标记，设置页状态细分为「已启用 / 已添加，未开完全访问 / 未检测到」
- 新增（词条编辑）：点列表词条右侧箭头弹出文本编辑窗口，底部两个动作——「保存（替换原词条）」原地更新（保留 id/标签/置顶，时间刷新重排），「另存为新词条」保留原条并新增编辑后的记录；实时字数统计、未改动时替换按钮置灰、键盘弹起按钮条自动上移
- 交互：右侧箭头改为独立可点按钮（放大点击热区），点整行仍是复制，二者互不误触；图片点箭头查看大图
- 版本 2.4.0 (build 7)

## v2.3.0 —— 修复键盘塌陷/读不到历史 + 打通 App Group 共享
- 修复（键盘塌陷，iPad 实测）：键盘高度改用 `view.heightAnchor` 约束固定（替代在 iPad 不可靠的 preferredContentSize），并在 viewDidAppear/布局/旋转时持续校正；无论是否有历史记录都与系统官方键盘等高（iPhone 竖屏 291 / 横屏 204，iPad 竖屏 320 / 横屏 264），空状态显示提示但不收缩
- 修复（iPad 顶部多余助理条）：viewDidLoad 清空 inputAssistantItem 的 leading/trailingBarButtonGroups，去掉系统撤销/重做/粘贴条与自定义 UI 重叠
- 修复（键盘读不到主 App 历史、设置显示「键盘扩展 未检测到」）：根因是裸二进制 ad-hoc 签名未带 entitlements，SideStore 重签后 App Group 不生效，主 App 与键盘各自沙盒。现用 ldid 把 `com.apple.security.application-groups` 嵌入主 App 与三个扩展的签名，设备端重签后保留，共享容器/UserDefaults/心跳全部打通
- 增强键盘逻辑：每次 viewWillAppear 重新双向同步并刷新；监听 UIPasteboard.changedNotification，键盘显示期间外部复制即时入库；共享库为空时用当前剪贴板内容兜底成临时条目，保证键盘里始终有可复制项；点按「复制并插入」、长按「仅复制」反馈更稳
- 构建：新增 ldid 授权嵌入步骤与 entitlements 断言；新增 ClipboardNotify.entitlements；版本 2.3.0 (build 6)

## v2.2.0 —— 修复扩展安装 + 键盘重构 + 六大捕获路径齐备
- 修复（安装失败根因）：键盘/Widget/通知三个 .appex 主程序由错误的 MH_DYLIB 改为正确的 MH_EXECUTE（入口 NSExtensionMain），framework 仍为 MH_DYLIB；此前 installd 因扩展类型非法拒绝安装，表现为 SideStore IdeviceGatewayError 2、只能进容器
- 修复（iLoader 报错）：弃用 zip 命令，改用规范化 zipfile 打包，标准 EOCD 位于文件末尾、无 zip64、固定时间戳、显式 unix 权限，解决 isideload「Could not find EOCD / Failed to open application archive」
- 键盘重构：systemChromeMaterial 毛玻璃、胶囊工具栏、圆角卡片历史列表；点按一键复制并插入，长按可选「仅复制」；正常浏览复制路径绝不跳转宿主 App（仅未授权遮罩可去设置）；自动适配 iPhone/iPad 宽度与高度、深色模式
- 路径1 PiP 画中画保活：隐藏循环视频 + AVPictureInPictureController，悬浮窗存活时 1.5s 轮询 changeCount
- 路径2 静音音频保活：mixWithOthers 后台播放 + 可配置低频轮询，退到后台自动启用、回前台自动停止
- 路径3 本地通知 + 新增 ClipboardNotify 通知内容扩展：后台检测到变化发通知，用户下拉时由扩展读取入库并展示
- 路径4 键盘、路径5 BGTaskScheduler、路径6 前台激活同步全部保留并联动通知；设置页新增六路径控制台
- 主 Info.plist UIBackgroundModes 增加 audio、picture-in-picture；版本 2.2.0 (build 5)

## v2.1.1 —— 修复 SideStore 签名安装失败
- 修复：四个 Mach-O 链接时显式写入 ad-hoc 代码签名槽（LC_CODE_SIGNATURE + CodeDirectory）。此前 Swift 驱动默认关闭签名，SideStore 内置 ldid 重签时缺少标准签名头，安装阶段报 Minimuxer.IdeviceGatewayError 2 / Failed to install IPA
- 修复：主 App 与两个扩展的 Info.plist 补齐 installd 必需的标准键 MinimumOSVersion、CFBundleSupportedPlatforms、DTPlatformName/DTPlatformVersion/DTSDKName/DTCompiler（此前手写 plist 缺失，会被判定为非标准包）
- 构建：Mach-O 校验新增签名槽断言，防止回归

## v2.1.0 —— LiveContainer 适配 + 权限引导
- 新增：RuntimeEnvironment 运行环境识别，多信号检测 LiveContainer 容器（LC_HOME_PATH、LC_ 环境变量、容器路径、注入镜像）
- 新增：LiveContainer 下能力降级——App Group 不可用时 UserDefaults/SQLite 自动回退到容器内沙盒，保证主 App 功能完整
- 适配：LiveContainer 官方限制（guest 无法注册键盘/Widget 扩展），引导页动态切换为容器模式说明
- 新增：首次启动原生分页「权限与使用引导」（核心用法 / 键盘开启 / 粘贴权限 / 后台刷新 / 完成），设置内可随时重看
- 新增：键盘扩展未授予「完全访问」时显示步骤引导遮罩与「去设置」，并上报授权心跳供主 App 展示状态
- 新增：设置页「权限与引导」分组，展示运行模式、键盘、后台刷新实时状态
- 优化：版本升至 2.1.0 (build 3)

## v2.0.0

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
