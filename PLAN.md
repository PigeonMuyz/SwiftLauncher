# SwiftLauncher 大改计划

## 协作约定

- `PLAN.md` 记录目标架构、参考依据和阶段拆分；`TASK.md` 记录可执行任务和完成状态。
- 每完成一项重构或验证，必须同步更新 `TASK.md` 的 checkbox，并在备注里写明改动范围。
- `docs/Swift-Craft-Launcher` 是参考实现源码，已被 `.gitignore` 忽略，只用于研究和对照，不直接作为当前项目源码提交。
- 当前项目是 SwiftPM macOS App；参考项目是 Xcode 工程，并依赖 `CFModrinthAdapterKit` 等组件。迁移时只吸收结构和业务逻辑，避免机械照搬工程形态。
- 保留现有 Launcher 里已经好用的实例卡片选择体验，参考项目只作为资源列表、下载、整合包导入、启动流程和头像机制的依据。

## 产品目标

这次改造要把 SwiftLauncher 从“首页驱动”改成“实例驱动”：

1. 彻底移除首页作为主入口。
2. 主窗口仍然保持左侧 Sidebar + 右侧内容区的 macOS 桌面结构。
3. 左下角固定成为三张自上而下的操作卡片：
   - 实例切换卡片
   - 用户切换卡片
   - 开始游戏卡片按钮
4. 资源浏览、模组下载、资源包、光影、整合包导入都围绕当前实例工作。
5. 账户头像要使用 Minecraft 皮肤头像，而不是系统 `person.crop.circle` 图标。
6. 启动游戏和导入整合包必须从“可用但分散”改成“有 preflight、有进度、有失败边界”的流程。

## 参考项目研究结论

### 资源列表与下载

参考项目的资源页由三部分组成：

- `ResourceFilterState` 管理版本、分类、加载器、环境、排序和分页状态。
- `CategoryContentView` 渲染左侧筛选 chip，支持版本、分类、加载器和资源类型专属筛选。
- `ModrinthDetailView` 负责 Modrinth 搜索、分页、列表卡片和项目详情跳转。

它的优点是筛选状态、搜索状态、安装状态相互独立，资源卡片只负责展示。当前 SwiftLauncher 的 `DownloadsView` 已经具备 Modrinth 搜索和安装基础，但文件过大，应该拆成资源浏览模块。

目标拆分：

- `Models/ResourceType.swift`
- `Stores/ResourceStore.swift`
- `Views/Resources/ResourceBrowserView.swift`
- `Views/Resources/ResourceFilterSidebar.swift`
- `Views/Resources/ResourceListView.swift`
- `Views/Resources/ResourceCardView.swift`
- `Views/Resources/ResourceInstallSheet.swift`
- `Services/ModrinthService.swift` 继续保留，但补齐分类、版本、加载器、project detail、分页和安装状态扫描。

### 实例管理

参考项目把资源类型和游戏实例都放进 Sidebar，并用 toolbar 暴露启动、打开目录、导出、删除等动作。

当前 SwiftLauncher 的底部实例卡片体验更好，后续应保留并升级：

- 实例卡片继续在 Sidebar 左下角。
- 展开后显示其他实例、新建实例、导入实例、实例设置。
- 当前实例变化时，资源页自动切换到该实例上下文。
- 原首页里的实例状态和启动入口迁移到 Sidebar 底部卡片区。

### 账户头像与用户切换

参考项目的头像机制如下：

- Microsoft 正版账户登录后，请求 `https://api.minecraftservices.com/minecraft/profile`，响应模型包含 `skins`，使用第一个 skin URL 作为头像来源。
- 离线账户使用 `OfflinePlayer:<username>` 的 MD5 UUID，再把 UUID 稳定映射到 9 个默认皮肤名：`alex`、`ari`、`efe`、`kai`、`makena`、`noor`、`steve`、`sunny`、`zuri`。
- `MinecraftSkinUtils` 支持 `.url`、`.asset`、`.local` 三种皮肤来源，加载 64x64 皮肤 PNG 后裁剪头部和帽子层，并使用 `NSCache` 缓存渲染结果。
- 默认皮肤资源放在 `Assets.xcassets` 中。

当前 SwiftLauncher 的差距：

- `PlayerAccount` 只有 username、profileID、kind、tokenExpiresAt，没有头像/皮肤 URL 字段。
- Microsoft profile 解码只取 id/name，没有取 skins。
- `AccountsView` 和首页账户卡片只用 SF Symbols 系统头像。
- 当前资源目录只有 `LauncherBackground.png`，没有默认皮肤资产。

目标实现：

- 扩展 `PlayerAccount`，增加可持久化的 `avatarSource` 或 `skinURL`。
- Microsoft 登录和 refresh 时保存 active skin URL。
- 本地账户通过现有 `Hashing.offlineUUID(for:)` 生成的 UUID 映射默认皮肤名。
- 新增 `MinecraftSkinAvatarView`，负责加载远程/本地/内置默认皮肤并裁剪头像。
- 新增用户切换卡片，显示头像、用户名、账户类型和展开列表。

### 整合包导入与下载

参考项目的 `ModPackInstallCoordinator` 是完整事务：

1. 准备临时目录。
2. 下载或解压整合包。
3. 解析 Modrinth `.mrpack` 或 CurseForge `manifest.json`。
4. 创建实例目录。
5. 复制 overrides。
6. 下载整合包文件。
7. 下载依赖。
8. 安装 Minecraft / Loader。
9. 成功后清理临时目录，失败时尽量回滚。

当前 SwiftLauncher 的 `InstanceImportService` 已经能处理 `.mrpack`、Prism/MultiMC、`.minecraft` 和一部分 CurseForge manifest，但问题是：

- CurseForge manifest 的 files 没有真正完整下载。
- 导入实例和安装核心游戏分散在不同流程里，失败状态不够清晰。
- 进度没有按 overrides/files/dependencies/game install 分阶段。
- Modrinth 依赖安装与整合包导入没有形成统一管线。

目标是新增 `ModpackInstallCoordinator`，把导入、下载、创建实例和安装游戏合成一个可追踪流程。

### 启动流程

当前 `MinecraftInstaller` 和 `MinecraftLauncher` 已经有安装检查、Java 运行时、版本元数据、Loader 元数据和命令构建。后续要重点修：

- 启动前 preflight：账户、实例、Java、核心文件、Loader、natives、assets。
- macOS 启动参数补齐 `-XstartOnFirstThread`。
- classpath 去重逻辑审计，避免错误丢掉 loader 依赖。
- 进程状态从单个 process ID 升级为实例级运行状态。
- 退出码、日志路径、crash-reports 关联到 UI。

## 阶段计划

### Phase 1：根布局和 Sidebar 改造

- 从 `AppSection` 移除 `home`。
- 调整默认选择到资源/实例相关页面。
- 将 `HomeView` 中的账户选择、启动按钮、实例摘要迁移到 Sidebar 底部卡片区。
- 新建 `SidebarBottomPanel`，内部包含 `InstanceSwitchCard`、`AccountSwitchCard`、`LaunchGameCard`。
- `AccountsView` 保留为账户管理详情页，但不再承担“当前账户切换”的主入口。

### Phase 2：账户头像系统

- 扩展账户模型和持久化兼容逻辑。
- 修改 Microsoft profile 解码，读取 skins/capes。
- 增加默认皮肤资产。
- 实现皮肤头像裁剪和缓存。
- 把 `AccountsView`、用户切换卡片、后续启动提示中的账户图标替换成 Minecraft 头像。

### Phase 3：资源浏览模块

- 引入 `ResourceType`、`ResourceFilterState`、`ResourceDetailState`。
- 拆分 `DownloadsView`，让下载任务列表和资源浏览分离。
- 按当前实例自动设置 Minecraft 版本和 Loader 筛选。
- 实现参考项目风格的资源卡片、筛选 chip、分页加载、安装按钮。

### Phase 4：资源安装与本地资源管理

- 保留当前 Modrinth 依赖安装能力，补齐 project detail 和版本选择。
- 扫描当前实例已安装资源，显示已安装/可更新/已禁用状态。
- 统一 mods/resourcepacks/shaderpacks 的本地列表、启用禁用、删除和打开目录。
- 资源页支持“远程浏览”和“本地管理”切换。

### Phase 5：整合包导入/下载重构

- 新建 `ModpackInstallCoordinator`。
- 抽象 `ModpackIndexParser`，支持 Modrinth 和 CurseForge。
- 补齐 CurseForge 文件下载策略。
- 按阶段显示进度：准备、overrides、文件、依赖、游戏安装、完成。
- 失败时提供可读错误，并清理未完成实例或临时目录。

### Phase 6：启动流程修复

- 新增启动 preflight。
- 修正 macOS JVM 参数。
- 审计 classpath 构建和 Loader 参数合并。
- 整合游戏进程状态、停止按钮、日志窗口和崩溃报告入口。
- Sidebar 的开始游戏卡片根据状态显示：开始、安装中、启动中、运行中、停止。

### Phase 7：验证与收尾

- 给纯逻辑补测试：离线头像映射、Modrinth facets、整合包 parser、安全路径复制、启动命令参数。
- 每个阶段至少运行一次 SwiftPM build。
- 删除废弃 `HomeView` 和无引用的首页专属状态。
- 更新 `TASK.md` 全部状态。

