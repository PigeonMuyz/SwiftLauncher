# SwiftLauncher 大改任务表

## 维护规则

- 完成任何一项重构、验证或删除工作后，立即更新本文件。
- checkbox 只在对应代码或文档真实完成后勾选。
- 多个 AI 并行时，先看本文件再动手，避免重复拆同一块代码。
- 每个阶段完成后，在该阶段下面补一行简短备注：改了哪些文件、是否 build/test。

## 0. 基线与研究

- [x] 创建 `docs/` 并加入 `.gitignore`
- [x] clone `suhang12332/Swift-Craft-Launcher.git` 到 `docs/Swift-Craft-Launcher`
- [x] 研究参考项目的资源列表、筛选、下载和安装结构
- [x] 研究参考项目的实例管理和启动入口结构
- [x] 研究当前项目的 Sidebar 实例卡片实现
- [x] 研究当前项目的整合包导入问题
- [x] 研究当前项目的启动流程问题
- [x] 研究参考项目 Microsoft 账户头像和离线头像机制
- [x] 写入 `PLAN.md`
- [x] 写入 `TASK.md`

备注：参考项目只作为 ignored docs 源码，不作为当前项目代码提交。

## 1. 根布局和 Sidebar 改造

- [ ] 从 `AppSection` 移除 `home`
- [ ] 调整 `LauncherStore.selection` 默认值，避免启动后进入首页
- [ ] 从 `ContentView` 移除首页专属 toolbar
- [ ] 将新建实例、日志、刷新、设置等动作重新分配到 Sidebar、详情页 toolbar 或菜单
- [ ] 新建 `SidebarBottomPanel`
- [ ] 抽出 `InstanceSwitchCard`
- [ ] 新建 `AccountSwitchCard`
- [ ] 新建 `LaunchGameCard`
- [ ] 按自上而下顺序渲染：实例切换卡片、用户切换卡片、开始游戏卡片按钮
- [ ] 删除或弃用 `HomeView`
- [ ] build 验证根布局

## 2. 账户头像和用户切换

- [ ] 扩展 `PlayerAccount`，增加头像或皮肤来源字段，并保证旧 `accounts.json` 可解码
- [ ] 修改 Microsoft profile 响应模型，读取 `skins` 和可选 `capes`
- [ ] Microsoft 登录成功时保存 active skin URL
- [ ] Microsoft refresh 时同步更新 username、profileID、skin URL 和 token 过期时间
- [ ] 实现离线 UUID 到默认皮肤名的稳定映射
- [ ] 添加默认皮肤资源：`alex`、`ari`、`efe`、`kai`、`makena`、`noor`、`steve`、`sunny`、`zuri`
- [ ] 新增皮肤头像裁剪/缓存组件
- [ ] `AccountsView` 使用 Minecraft 头像替换 SF Symbols 头像
- [ ] `AccountSwitchCard` 支持展开账户列表、切换账户、添加账户入口
- [ ] build 验证账户列表和用户卡片

## 3. 资源浏览模块

- [ ] 新增 `ResourceType`
- [ ] 新增 `ResourceFilterState`
- [ ] 新增 `ResourceDetailState`
- [ ] 新增 `ResourceStore`
- [ ] 从 `DownloadsView` 拆出远程资源浏览
- [ ] 保留下载任务列表，但与资源浏览解耦
- [ ] 实现资源类型切换：模组、资源包、光影、整合包、数据包
- [ ] 实现版本、分类、加载器、环境筛选 chip
- [ ] 当前实例变化时自动应用版本和 Loader 筛选
- [ ] 实现资源卡片列表和分页加载
- [ ] build 验证资源浏览页面

## 4. 资源安装与本地资源管理

- [ ] 补齐 Modrinth categories/game versions/loaders 接口
- [ ] 补齐 Modrinth project detail/version detail 接口
- [ ] 复用并整理现有 Modrinth 依赖安装计划
- [ ] 安装弹窗显示兼容版本、文件、必选依赖、可选依赖
- [ ] 扫描实例内已安装资源并建立 installed state
- [ ] 资源卡片显示安装、已安装、可更新、删除、启用/禁用状态
- [ ] 统一 mods/resourcepacks/shaderpacks 的本地管理视图
- [ ] build 验证安装流程

## 5. 整合包导入/下载重构

- [ ] 新增 `ModpackInstallCoordinator`
- [ ] 新增统一 `ModpackIndexParser`
- [ ] 支持 Modrinth `.mrpack`
- [ ] 支持 CurseForge `manifest.json` 文件下载
- [ ] 保留 Prism/MultiMC 和 `.minecraft` 导入能力
- [ ] 实现 overrides/client-overrides 安全复制
- [ ] 实现文件、依赖、游戏安装分阶段进度
- [ ] 失败时清理临时目录和未完成实例
- [ ] build 验证整合包导入

## 6. 启动流程修复

- [ ] 新增启动 preflight
- [ ] 启动前检查账户、实例、Java、核心文件、Loader、natives、assets
- [ ] macOS JVM 参数补齐 `-XstartOnFirstThread`
- [ ] 审计并修正 classpath 去重逻辑
- [ ] 整合 Loader JVM/game 参数
- [ ] 实例级运行状态替代单一 process ID 展示
- [ ] 停止按钮接入 Sidebar 开始游戏卡片
- [ ] 退出码、日志、crash-reports 关联到 UI
- [ ] build 验证启动流程

## 7. 测试与收尾

- [ ] 测试离线头像映射
- [ ] 测试 Modrinth facets 构造
- [ ] 测试整合包 index parser
- [ ] 测试安全路径复制
- [ ] 测试启动命令参数
- [ ] 删除无引用首页代码
- [ ] 清理废弃状态和未使用资源
- [ ] 最终 SwiftPM build

