# SwiftLauncher

SwiftLauncher 是使用 SwiftUI 编写的原生 macOS Minecraft Java 版启动器。

## 当前能力

- 读取 Mojang 官方版本清单与版本元数据
- 扫描本机 Java 运行时及架构
- 创建、编辑、删除和持久化独立游戏实例
- 下载并校验 client、libraries、natives、assets 与日志配置
- 生成原版 Minecraft JVM/游戏参数并启动 Java 进程
- 创建并启动 Fabric、Quilt、Forge、NeoForge 加载器实例
- 导入、启用、禁用和移除实例中的本地模组 JAR
- 本地账户与 Microsoft Device Code OAuth 登录
- Microsoft、Xbox Live、XSTS、Minecraft Services 所有权和角色链路
- 下载进度、游戏日志、Keychain 令牌存储

## 构建运行

```bash
./script/build_and_run.sh --verify
./script/verify_real_data.sh
```

脚本会在完整 Xcode 可用时使用 `xcodebuild`，否则使用 Command Line Tools 中的 Swift 编译器和当前 macOS SDK 构建可运行的 `.app`。

`verify_real_data.sh` 会实际读取 Mojang 官方数据，并下载小型 client 与资源样本进行 SHA-1 校验。

Microsoft OAuth Client ID 已内置，可通过设备代码流登录 Microsoft 账户。Minecraft Java 服务 API
会对新的第三方应用进行人工审核；在 Client ID 加入允许列表前，Minecraft 凭证交换会被拒绝。
开发者需要提交 [官方应用审核表](https://aka.ms/mce-reviewappid)。

## 数据目录

所有启动器数据保存在：

```text
~/Library/Application Support/SwiftLauncher
```

账户访问令牌不写入 JSON，仅保存在 macOS Keychain。

SwiftLauncher 不是 Mojang Studios 或 Microsoft 的官方产品，也不隶属于 PCL/HMCL。

## 开源许可证

本项目使用 [MIT License](LICENSE)。
