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
