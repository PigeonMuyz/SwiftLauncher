import Foundation

struct RuleEvaluator: Sendable {
    let features: [String: Bool]

    init(features: [String: Bool] = [:]) {
        self.features = features
    }

    func allows(_ rules: [MinecraftRule]?) -> Bool {
        guard let rules, !rules.isEmpty else { return true }
        var allowed = false
        for rule in rules where matches(rule) {
            allowed = rule.action == .allow
        }
        return allowed
    }

    private func matches(_ rule: MinecraftRule) -> Bool {
        if let os = rule.os {
            if let name = os.name, name != "osx" { return false }
            if let architecture = os.arch {
                let current = ProcessInfo.processInfo.machineArchitecture
                if architecture == "x86", !current.contains("x86") { return false }
                if architecture == "arm64", current != "arm64" { return false }
            }
            if let version = os.version,
               let expression = try? NSRegularExpression(pattern: version),
               expression.firstMatch(
                   in: ProcessInfo.processInfo.operatingSystemVersionString,
                   range: NSRange(ProcessInfo.processInfo.operatingSystemVersionString.startIndex..., in: ProcessInfo.processInfo.operatingSystemVersionString)
               ) == nil {
                return false
            }
        }

        if let requiredFeatures = rule.features {
            for (name, value) in requiredFeatures where features[name, default: false] != value {
                return false
            }
        }
        return true
    }
}

extension ProcessInfo {
    var machineArchitecture: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}
