import Foundation

struct GameLogParser {
    enum LogLevel: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        case fatal = "FATAL"

        var priority: Int {
            switch self {
            case .info: return 0
            case .warn: return 1
            case .error: return 2
            case .fatal: return 3
            }
        }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let logger: String
        let thread: String
        let message: String

        var isModLoading: Bool {
            logger.contains("moddiscovery") || message.contains("Found mod file")
        }

        var modName: String? {
            if message.contains("Found mod file") {
                let pattern = #"Found mod file (.+?)\.jar"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                   let range = Range(match.range(at: 1), in: message) {
                    return String(message[range])
                }
            }
            return nil
        }

        var isGameReady: Bool {
            message.contains("Minecraft window") ||
            message.contains("OpenGL Version:") ||
            message.contains("Loaded") && message.contains("mods")
        }
    }

    struct GameLoadProgress {
        var currentStage: LoadStage = .initializing
        var modsFound: Int = 0
        var totalProgress: Double = 0.0
        var lastError: String?
        var isGameReady: Bool = false
        var hasFatalError: Bool = false

        enum LoadStage: String {
            case initializing = "初始化中..."
            case scanningMods = "扫描 Mod 文件..."
            case loadingMods = "加载 Mod..."
            case buildingClasspath = "构建类路径..."
            case startingGame = "启动游戏..."
            case ready = "完成"
            case failed = "启动失败"

            var progress: Double {
                switch self {
                case .initializing: return 0.1
                case .scanningMods: return 0.3
                case .loadingMods: return 0.5
                case .buildingClasspath: return 0.7
                case .startingGame: return 0.9
                case .ready: return 1.0
                case .failed: return 0.0
                }
            }
        }
    }

    // 解析 XML 格式的 log4j 日志
    static func parseXMLLog(_ xmlContent: String) -> [LogEntry] {
        var entries: [LogEntry] = []

        let pattern = #"<log4j:Event logger="([^"]*)" timestamp="(\d+)" level="(\w+)" thread="([^"]*)">[\s\S]*?<log4j:Message><!\[CDATA\[([\s\S]*?)\]\]></log4j:Message>"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return entries }

        let nsString = xmlContent as NSString
        let matches = regex.matches(in: xmlContent, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges == 6 else { continue }

            let logger = nsString.substring(with: match.range(at: 1))
            let timestampStr = nsString.substring(with: match.range(at: 2))
            let levelStr = nsString.substring(with: match.range(at: 3))
            let thread = nsString.substring(with: match.range(at: 4))
            let message = nsString.substring(with: match.range(at: 5))

            guard let timestampMs = Double(timestampStr),
                  let level = LogLevel(rawValue: levelStr) else { continue }

            let timestamp = Date(timeIntervalSince1970: timestampMs / 1000.0)

            entries.append(LogEntry(
                timestamp: timestamp,
                level: level,
                logger: logger,
                thread: thread,
                message: message
            ))
        }

        return entries
    }

    // 从日志中提取致命错误
    static func extractFatalError(_ logContent: String) -> String? {
        // 检查是否有 Exception
        if logContent.contains("Exception in thread") {
            let lines = logContent.split(separator: "\n")
            var errorLines: [String] = []
            var foundException = false

            for line in lines {
                let lineStr = String(line)
                if lineStr.contains("Exception in thread") {
                    foundException = true
                    errorLines.append(lineStr)
                } else if foundException {
                    if lineStr.starts(with: "\tat ") || lineStr.starts(with: "\t") {
                        if errorLines.count < 5 {  // 只保留前几行堆栈
                            errorLines.append(lineStr)
                        }
                    } else if !lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                        break
                    }
                }
            }

            if !errorLines.isEmpty {
                return errorLines.joined(separator: "\n")
            }
        }

        // 检查 FATAL 级别日志
        if let fatalMatch = logContent.range(of: #"level="FATAL".*?<log4j:Message><!\[CDATA\[(.*?)\]\]>"#, options: .regularExpression) {
            return String(logContent[fatalMatch])
        }

        return nil
    }

    // 分析加载进度
    static func analyzeLoadProgress(_ entries: [LogEntry]) -> GameLoadProgress {
        var progress = GameLoadProgress()

        for entry in entries {
            // 检测加载阶段
            if entry.message.contains("Scanning mod candidates") {
                progress.currentStage = .scanningMods
            } else if entry.message.contains("Found mod file") {
                progress.modsFound += 1
                if progress.currentStage == .scanningMods || progress.currentStage == .initializing {
                    progress.currentStage = .loadingMods
                }
            } else if entry.message.contains("Building") || entry.message.contains("module layer") {
                progress.currentStage = .buildingClasspath
            } else if entry.message.contains("Launching") || entry.message.contains("Starting") {
                progress.currentStage = .startingGame
            } else if entry.isGameReady {
                progress.currentStage = .ready
                progress.isGameReady = true
            }

            // 检测致命错误
            if entry.level == .fatal {
                progress.hasFatalError = true
                progress.currentStage = .failed
                progress.lastError = entry.message
            } else if entry.level == .error {
                progress.lastError = entry.message
            }
        }

        // 检测日志中的 Exception
        let logContent = entries.map { $0.message }.joined(separator: "\n")
        if logContent.contains("Exception in thread") || logContent.contains("java.lang.") {
            progress.hasFatalError = true
            progress.currentStage = .failed
        }

        progress.totalProgress = progress.currentStage.progress
        return progress
    }

    // 实时解析日志流
    static func parseLogStream(_ logContent: String, previousEntryCount: Int = 0) -> (entries: [LogEntry], newEntriesCount: Int) {
        let allEntries = parseXMLLog(logContent)
        let newEntries = allEntries.count - previousEntryCount
        return (allEntries, max(0, newEntries))
    }
}
