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
