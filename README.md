# SwiftLauncher

SwiftLauncher 是使用 SwiftUI 编写的原生 macOS Minecraft Java 版启动器。

## 当前能力

- 读取 Mojang 官方版本清单与版本元数据
- 按 Mojang 元数据精确匹配 Java 主版本，并可自动下载校验 Temurin 运行时
- 支持实例自动 Java 模式和用户自定义 Java Home / `bin/java`
- 创建、编辑、删除和持久化独立游戏实例
- 导入 Modrinth 整合包、Prism/MultiMC/CurseForge 导出包与其他启动器的 `.minecraft`，随后自动补全游戏核心
- 共享并校验 client、libraries、natives、assets 与日志配置，多个实例复用同一官方基础版本
- 启动前检查基础版本、加载器增量层与实例文件，缺失时自动补全
- 生成原版 Minecraft JVM/游戏参数并启动 Java 进程
- 创建并启动 Fabric、Quilt、Forge、NeoForge 加载器实例
- 导入、启用、禁用和移除实例中的本地模组 JAR
- 在下载中心按实例版本与加载器搜索 Modrinth，安装模组及其必需前置
- 支持 Mojang 官方、BMCLAPI 镜像和“官方优先、失败自动回退”下载源
- 本地账户与 Microsoft Device Code OAuth 登录
- Microsoft、Xbox Live、XSTS、Minecraft Services 所有权和角色链路
- 下载进度、游戏日志、Keychain 令牌存储
- 自动读取整合包图标、提供加载器区分的方块图标，也可自定义实例名称和图片

## 构建运行

```bash
./script/build_and_run.sh --verify
./script/verify_real_data.sh
```

脚本会在完整 Xcode 可用时使用 `xcodebuild`，否则使用 Command Line Tools 中的 Swift 编译器和当前 macOS SDK 构建可运行的 `.app`。

`verify_real_data.sh` 会实际读取 Mojang 与 BMCLAPI 数据、查询 Modrinth，并下载小型 client 与资源样本进行 SHA-1 校验。

Microsoft OAuth Client ID 已内置，可通过设备代码流登录 Microsoft 账户。Minecraft Java 服务 API
会对新的第三方应用进行人工审核；在 Client ID 加入允许列表前，Minecraft 凭证交换会被拒绝。
开发者需要提交 [官方应用审核表](https://aka.ms/mce-reviewappid)。

## 数据目录

所有启动器数据保存在：

```text
~/Library/Application Support/SwiftLauncher
```

其中 `minecraft` 保存跨实例共享的官方版本、依赖库和资源，`runtimes` 保存启动器托管的
Java，`instances/<UUID>` 只保存该实例的加载器描述、图标、natives 和隔离游戏目录。

账户访问令牌不写入 JSON，仅保存在 macOS Keychain。

SwiftLauncher 不是 Mojang Studios 或 Microsoft 的官方产品，也不隶属于 PCL/HMCL。

## 开源许可证

本项目使用 [MIT License](LICENSE)。
