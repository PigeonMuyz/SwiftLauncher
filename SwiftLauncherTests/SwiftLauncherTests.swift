import Foundation
import Testing
@testable import SwiftLauncher

@Test("离线 UUID 与 Mojang 约定保持稳定")
func offlineUUIDIsStable() {
    #expect(Hashing.offlineUUID(for: "Steve") == "5627dd98-e6be-3c21-b8a8-e92344183641")
}

@Test("条件参数可以解析字符串和数组")
func minecraftArgumentsDecode() throws {
    let data = Data(#"{"game":["--demo",{"rules":[{"action":"allow","os":{"name":"osx"}}],"value":["--width","1280"]}]}"#.utf8)
    let arguments = try JSONCoding.makeDecoder().decode(MinecraftArguments.self, from: data)
    #expect(arguments.game?.count == 2)
}

@Test("macOS 规则匹配")
func macOSRuleEvaluation() {
    let rules = [MinecraftRule(action: .allow, os: RuleOS(name: "osx", version: nil, arch: nil), features: nil)]
    #expect(RuleEvaluator().allows(rules))
}

@Test("旧实例自动迁移到 Java 自动选择")
func legacyInstanceUsesAutomaticJava() throws {
    let data = Data(#"""
    {
      "id":"00000000-0000-0000-0000-000000000001",
      "name":"Legacy",
      "versionID":"1.20.1",
      "javaPath":"/old/java",
      "memoryMB":4096,
      "additionalJVMArguments":[],
      "loader":"vanilla",
      "isVersionIsolated":true,
      "createdAt":"2026-06-23T00:00:00Z"
    }
    """#.utf8)
    let instance = try JSONCoding.makeDecoder().decode(LauncherInstance.self, from: data)
    #expect(instance.usesAutomaticJava)
    #expect(instance.javaPath == nil)
}

@Test("实例图标设置可以持久化")
func instanceIconRoundTrip() throws {
    let instance = LauncherInstance(
        name: "Icon Test",
        versionID: "1.20.1",
        iconFileName: "icon.png"
    )
    let data = try JSONCoding.makeEncoder().encode(instance)
    let decoded = try JSONCoding.makeDecoder().decode(LauncherInstance.self, from: data)
    #expect(decoded.iconFileName == "icon.png")
    #expect(decoded.usesAutomaticJava)
}

@Test("SHA-256 校验实现正确")
func sha256IsStable() {
    #expect(
        Hashing.sha256(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
}

@Test("SHA-512 校验实现正确")
func sha512IsStable() {
    #expect(
        Hashing.sha512(Data("abc".utf8))
            == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                + "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
    )
}

@Test("BMCLAPI 路径映射覆盖版本、资源和依赖")
func bmclEndpointMapping() {
    let manifest = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
    let asset = URL(string: "https://resources.download.minecraft.net/ab/abcdef")!
    let library = URL(string: "https://libraries.minecraft.net/com/example/demo/1.0/demo-1.0.jar")!
    #expect(
        DownloadEndpointResolver.bmclURL(for: manifest)?.absoluteString
            == "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
    )
    #expect(
        DownloadEndpointResolver.bmclURL(for: asset)?.absoluteString
            == "https://bmclapi2.bangbang93.com/assets/ab/abcdef"
    )
    #expect(
        DownloadEndpointResolver.bmclURL(for: library)?.absoluteString
            == "https://bmclapi2.bangbang93.com/maven/com/example/demo/1.0/demo-1.0.jar"
    )
}

@Test("Maven 坐标支持分类器和扩展名")
func mavenCoordinatePaths() {
    #expect(
        MavenCoordinate.path(for: "net.minecraftforge:forge:1.20.1-47.4.20:universal")
            == "net/minecraftforge/forge/1.20.1-47.4.20/forge-1.20.1-47.4.20-universal.jar"
    )
    #expect(
        MavenCoordinate.path(for: "example:artifact:1.0@zip")
            == "example/artifact/1.0/artifact-1.0.zip"
    )
}

@Test("Forge 整合包构建号会补全 Minecraft 版本")
func forgeInstallerCoordinate() {
    #expect(
        LoaderVersionResolver.installerCoordinate(
            gameVersion: "1.20.1",
            loader: .forge,
            loaderVersion: "47.3.33"
        ) == "1.20.1-47.3.33"
    )
    #expect(
        LoaderVersionResolver.installerCoordinate(
            gameVersion: "1.20.1",
            loader: .forge,
            loaderVersion: "1.20.1-47.3.33"
        ) == "1.20.1-47.3.33"
    )
}

@Test("安装诊断会报告缺少基础安装标记")
func installationDiagnosisReportsMissingBaseMarker() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftLauncherTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let fileSystem = LauncherFileSystem(root: root)
    try await fileSystem.prepare()

    let version = MinecraftVersion(
        id: "1.20.1",
        type: .release,
        url: URL(string: "https://example.com/1.20.1.json")!,
        time: .now,
        releaseTime: .now,
        sha1: "manifest-sha1",
        complianceLevel: nil
    )
    let metadata = VersionMetadata(
        id: version.id,
        type: .release,
        mainClass: "net.minecraft.client.main.Main",
        assets: nil,
        assetIndex: nil,
        downloads: [
            "client": DownloadArtifact(
                sha1: nil,
                size: nil,
                url: URL(string: "https://example.com/client.jar")!,
                path: nil
            )
        ],
        libraries: [],
        arguments: nil,
        minecraftArguments: nil,
        javaVersion: nil,
        logging: nil,
        inheritsFrom: nil
    )

    try FileManager.default.createDirectory(
        at: fileSystem.versionDirectory(version.id),
        withIntermediateDirectories: true
    )
    try JSONCoding.makeEncoder().encode(metadata)
        .write(to: fileSystem.versionJSON(version.id), options: [.atomic])

    let installer = MinecraftInstaller(
        metadataService: MojangMetadataService(),
        downloader: FileDownloadService(),
        fileSystem: fileSystem
    )
    let instance = LauncherInstance(name: "Diagnosis", versionID: version.id)
    let check = await installer.checkInstallation(instance: instance, version: version)

    #expect(!check.isComplete)
    #expect(check.issue?.errorDescription?.contains("基础安装标记") == true)
}

@Test("log4j XML 日志会转换成可读文本")
func log4jDisplayTextIsReadable() {
    let log = """
    [SwiftLauncher] 游戏版本名称：Minecraft 26.1.1
      <log4j:Event logger="net.minecraft.client.Minecraft" timestamp="1782803330384" level="INFO" thread="Render thread">
        <log4j:Message><![CDATA[Setting user: PigeonMuyz]]></log4j:Message>
      </log4j:Event>
    """
    let displayText = GameLogParser.displayText(from: log)
    #expect(displayText.contains("Setting user: PigeonMuyz"))
    #expect(!displayText.contains("<log4j:Event"))
    #expect(!displayText.contains("<![CDATA"))
}

@Test("渲染初始化日志不会被当作游戏完全启动")
func rendererLogDoesNotMeanGameReady() {
    let log = """
      <log4j:Event logger="net.minecraft.client.Minecraft" timestamp="1782803330427" level="INFO" thread="Render thread">
        <log4j:Message><![CDATA[Backend library: LWJGL version 3.4.1+2]]></log4j:Message>
      </log4j:Event>
    """
    let entries = GameLogParser.parseLogStream(log).entries
    let progress = GameLogParser.analyzeLoadProgress(entries, elapsedTime: 20, gameWindowVisible: false)
    #expect(!progress.isGameReady)
    #expect(progress.currentStage == .waitingForWindow)
}

@Test("Forge 早期窗口可见不代表游戏完全启动")
func forgeEarlyWindowDoesNotMeanGameReady() {
    let log = """
    [INFO] [main/EARLYDISPLAY] Requested GL version 4.1 got version 4.1
    [INFO] [pool-2-thread-1/EARLYDISPLAY] GL info: Apple M1 Pro GL version 4.1 Metal - 91.6, Apple
    [INFO] [main/net.minecraftforge.fml.loading.moddiscovery.ModDiscoverer] Found mod file jei.jar of type MOD
    """
    let entries = GameLogParser.parseLogStream(log).entries
    let progress = GameLogParser.analyzeLoadProgress(entries, elapsedTime: 20, gameWindowVisible: true)
    #expect(!progress.isGameReady)
    #expect(progress.currentStage == .loadingMods)
}

@Test("启动日志中的 Java module 异常会被识别为失败")
func javaModuleResolutionExceptionIsFatal() {
    let log = """
    Exception in thread "main" java.lang.module.ResolutionException: Modules minecraft and _1._20._1 export package net.minecraft.client to module fabric_asm_generated_classes
    at java.base/java.lang.module.Resolver.resolveFail(Unknown Source)
    """
    let entries = GameLogParser.parseLogStream(log).entries
    let progress = GameLogParser.analyzeLoadProgress(entries, elapsedTime: 20, gameWindowVisible: true)
    #expect(progress.hasFatalError)
    #expect(!progress.isGameReady)
    #expect(progress.currentStage == .failed)
}

@Test("Metal 调试断言会被识别为启动失败")
func metalDebugAssertionIsFatal() {
    let log = """
    [INFO] [Render thread/net.minecraft.client.sounds.SoundEngine] Sound engine started
    [INFO] [Render thread/net.minecraft.client.renderer.texture.TextureAtlas] Created: 1024x1024x0 minecraft:textures/atlas/gui.png-atlas
    -[MTLDebugRenderCommandEncoder validateCommonDrawErrors:]:6032: failed assertion `Draw Errors Validation
    Fragment Function(main0): argument _26[0] from Buffer(1) with offset(0) and length(12) has space for 12 bytes, but argument has a length(16).
    '
    """
    let entries = GameLogParser.parseLogStream(log).entries
    let progress = GameLogParser.analyzeLoadProgress(entries, elapsedTime: 20, gameWindowVisible: true)
    #expect(progress.hasFatalError)
    #expect(!progress.isGameReady)
    #expect(progress.currentStage == .failed)
    #expect(GameLogParser.extractFatalError(log)?.contains("MTLDebugRenderCommandEncoder") == true)
}

@Test("启动 Minecraft 时不会继承 Metal 调试环境变量")
func minecraftLaunchEnvironmentStripsMetalDebugVariables() {
    let environment = [
        "PATH": "/usr/bin",
        "MTL_DEBUG_LAYER": "1",
        "MTL_SHADER_VALIDATION": "1",
        "METAL_DEVICE_WRAPPER_TYPE": "1",
        "MTLCaptureEnabled": "1",
        "MTL_HUD_ENABLED": "1"
    ]
    let sanitized = MinecraftLauncher.sanitizedProcessEnvironment(environment)
    #expect(sanitized["PATH"] == "/usr/bin")
    #expect(sanitized["MTL_HUD_ENABLED"] == "1")
    #expect(sanitized["MTL_DEBUG_LAYER"] == nil)
    #expect(sanitized["MTL_SHADER_VALIDATION"] == nil)
    #expect(sanitized["METAL_DEVICE_WRAPPER_TYPE"] == nil)
    #expect(sanitized["MTLCaptureEnabled"] == nil)
}

@MainActor
@Test("下载任务暂停会阻塞 checkpoint 到继续")
func downloadJobPauseBlocksCheckpointUntilResume() async throws {
    let manager = DownloadJobManager()
    var checkpointPassed = false

    let result = await manager.run(
        kind: .gameInstall,
        title: "Pause Test",
        detail: "准备测试暂停"
    ) { reporter in
        guard let id = manager.jobs.first?.id else { return }
        manager.pause(id)
        let checkpointTask = Task { @MainActor in
            try await reporter.checkpoint()
            checkpointPassed = true
        }

        try await Task.sleep(for: .milliseconds(80))
        #expect(!checkpointPassed)
        manager.resume(id)
        try await checkpointTask.value
    }

    #expect(result.succeeded)
    #expect(checkpointPassed)
}

@MainActor
@Test("下载任务取消会让 checkpoint 抛出取消")
func downloadJobCancelMakesCheckpointThrow() async {
    let manager = DownloadJobManager()
    var didThrowCancellation = false

    let result = await manager.run(
        kind: .gameInstall,
        title: "Cancel Test",
        detail: "准备测试取消"
    ) { reporter in
        guard let id = manager.jobs.first?.id else { return }
        manager.cancel(id)
        do {
            try await reporter.checkpoint()
        } catch is CancellationError {
            didThrowCancellation = true
        } catch {
            didThrowCancellation = false
        }
    }

    if case .cancelled = result {
        #expect(true)
    } else {
        #expect(Bool(false))
    }
    #expect(didThrowCancellation)
}
