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
            let lowerLogger = logger.lowercased()
            let lowerMessage = message.lowercased()
            return lowerLogger.contains("moddiscovery")
                || lowerMessage.contains("found mod file")
                || lowerMessage.contains("loading mod")
                || lowerMessage.contains("loading mods")
        }

        var modName: String? {
            guard message.contains("Found mod file") else { return nil }
            let pattern = #"Found mod file (.+?)\.jar"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let range = Range(match.range(at: 1), in: message) {
                return String(message[range])
            }
            return nil
        }

        var hasRendererStarted: Bool {
            message.contains("Backend library:")
                || message.contains("OpenGL Version:")
                || message.contains("Created:") && message.contains("textures")
                || message.contains("Sound engine started")
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
            case waitingForWindow = "等待游戏窗口..."
            case ready = "加载完成"
            case failed = "启动失败"

            var progress: Double {
                switch self {
                case .initializing: return 0.10
                case .scanningMods: return 0.28
                case .loadingMods: return 0.50
                case .buildingClasspath: return 0.68
                case .startingGame: return 0.82
                case .waitingForWindow: return 0.92
                case .ready: return 1.0
                case .failed: return 0.0
                }
            }
        }
    }

    static func parseXMLLog(_ xmlContent: String) -> [LogEntry] {
        eventRecords(in: xmlContent).map(\.entry)
    }

    static func parseLogStream(
        _ logContent: String,
        previousEntryCount: Int = 0
    ) -> (entries: [LogEntry], newEntriesCount: Int) {
        let allEntries = parseLogEntries(logContent)
        let newEntries = allEntries.count - previousEntryCount
        return (allEntries, max(0, newEntries))
    }

    static func displayText(from logContent: String) -> String {
        let records = eventRecords(in: logContent)
        guard !records.isEmpty else { return logContent }

        var lines: [String] = []
        var cursor = 0
        let nsString = logContent as NSString

        for record in records {
            appendRawLines(
                from: nsString.substring(with: NSRange(location: cursor, length: record.range.location - cursor)),
                to: &lines
            )
            lines.append(displayLine(for: record.entry))
            cursor = record.range.location + record.range.length
        }

        if cursor < nsString.length {
            appendRawLines(
                from: nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor)),
                to: &lines
            )
        }

        return lines.joined(separator: "\n")
    }

    static func extractFatalError(_ logContent: String) -> String? {
        let entries = parseLogEntries(logContent)
        if let fatal = entries.first(where: { $0.level == .fatal }) {
            return fatal.message
        }

        let plainText = displayText(from: logContent)
        if plainText.contains("Exception in thread") {
            let lines = plainText.split(separator: "\n", omittingEmptySubsequences: false)
            var errorLines: [String] = []
            var foundException = false

            for line in lines {
                let lineString = String(line)
                if lineString.contains("Exception in thread") {
                    foundException = true
                    errorLines.append(lineString)
                } else if foundException {
                    let trimmed = lineString.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("at ") || trimmed.hasPrefix("Caused by:") || trimmed.hasPrefix("[STDERR]:") {
                        if errorLines.count < 8 { errorLines.append(lineString) }
                    } else if !trimmed.isEmpty {
                        break
                    }
                }
            }
            if !errorLines.isEmpty { return errorLines.joined(separator: "\n") }
        }

        return nil
    }

    static func analyzeLoadProgress(
        _ entries: [LogEntry],
        previousProgress: Double = 0,
        elapsedTime: TimeInterval = 0,
        gameWindowVisible: Bool = false
    ) -> GameLoadProgress {
        var progress = GameLoadProgress()
        var rendererStarted = false

        for entry in entries {
            if entry.isModLoading {
                progress.modsFound += entry.modName == nil ? 0 : 1
            }

            if entry.message.contains("Scanning mod candidates") {
                progress.currentStage = .scanningMods
            } else if entry.isModLoading {
                progress.currentStage = .loadingMods
            } else if entry.message.localizedCaseInsensitiveContains("building")
                || entry.message.localizedCaseInsensitiveContains("module layer")
                || entry.message.localizedCaseInsensitiveContains("classpath") {
                progress.currentStage = .buildingClasspath
            } else if entry.message.localizedCaseInsensitiveContains("launching")
                || entry.message.localizedCaseInsensitiveContains("starting")
                || entry.hasRendererStarted {
                progress.currentStage = .startingGame
            }

            rendererStarted = rendererStarted || entry.hasRendererStarted

            if entry.level == .fatal {
                progress.hasFatalError = true
                progress.currentStage = .failed
                progress.lastError = entry.message
            } else if entry.level == .error {
                progress.lastError = entry.message
            }
        }

        let logContent = entries.map(\.message).joined(separator: "\n")
        if containsFatalSignal(logContent) {
            progress.hasFatalError = true
            progress.currentStage = .failed
            progress.lastError = extractFatalError(logContent) ?? progress.lastError
        }

        if !progress.hasFatalError {
            if gameWindowVisible {
                progress.currentStage = .ready
                progress.isGameReady = true
            } else if rendererStarted {
                progress.currentStage = .waitingForWindow
            }
        }

        if progress.hasFatalError {
            progress.totalProgress = max(previousProgress, 0.02)
        } else if progress.isGameReady {
            progress.totalProgress = 1
        } else {
            let estimated = min(0.92, 0.10 + elapsedTime / 55.0 * 0.72)
            progress.totalProgress = max(previousProgress, progress.currentStage.progress, estimated)
        }

        return progress
    }

    private struct EventRecord {
        let range: NSRange
        let entry: LogEntry
    }

    private static func parseLogEntries(_ logContent: String) -> [LogEntry] {
        let records = eventRecords(in: logContent)
        var entries: [LogEntry] = []
        var cursor = 0
        let nsString = logContent as NSString

        for record in records {
            entries += rawEntries(
                from: nsString.substring(with: NSRange(location: cursor, length: record.range.location - cursor))
            )
            entries.append(record.entry)
            cursor = record.range.location + record.range.length
        }

        if cursor < nsString.length {
            entries += rawEntries(
                from: nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor))
            )
        }

        return entries
    }

    private static func eventRecords(in logContent: String) -> [EventRecord] {
        let pattern = #"<log4j:Event\s+logger="([^"]*)"\s+timestamp="(\d+)"\s+level="(\w+)"\s+thread="([^"]*)">\s*<log4j:Message>(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))</log4j:Message>\s*</log4j:Event>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsString = logContent as NSString
        return regex.matches(in: logContent, range: NSRange(location: 0, length: nsString.length)).compactMap { match in
            guard match.numberOfRanges == 7 else { return nil }
            let logger = nsString.substring(with: match.range(at: 1))
            let timestampString = nsString.substring(with: match.range(at: 2))
            let levelString = nsString.substring(with: match.range(at: 3))
            let thread = nsString.substring(with: match.range(at: 4))
            let cdataRange = match.range(at: 5)
            let plainRange = match.range(at: 6)
            let messageRange = cdataRange.location != NSNotFound ? cdataRange : plainRange

            guard let timestampMilliseconds = Double(timestampString),
                  let level = LogLevel(rawValue: levelString),
                  messageRange.location != NSNotFound else { return nil }

            let message = decodeXMLText(nsString.substring(with: messageRange))
            return EventRecord(
                range: match.range,
                entry: LogEntry(
                    timestamp: Date(timeIntervalSince1970: timestampMilliseconds / 1000.0),
                    level: level,
                    logger: logger,
                    thread: thread,
                    message: message
                )
            )
        }
    }

    private static func rawEntries(from rawText: String) -> [LogEntry] {
        rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                LogEntry(
                    timestamp: .distantPast,
                    level: level(forRawLine: line),
                    logger: "raw",
                    thread: "",
                    message: line
                )
            }
    }

    private static func appendRawLines(from rawText: String, to lines: inout [String]) {
        let rawLines = rawText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        lines.append(contentsOf: rawLines)
    }

    private static func displayLine(for entry: LogEntry) -> String {
        let source = entry.logger.isEmpty ? entry.thread : "\(entry.thread)/\(entry.logger)"
        return "[\(entry.level.rawValue)] [\(source)] \(entry.message)"
    }

    private static func level(forRawLine line: String) -> LogLevel {
        let lower = line.lowercased()
        if lower.contains("fatal") || lower.contains("exception in thread") { return .fatal }
        if lower.contains("error") || lower.contains("exception") || lower.contains("failed") { return .error }
        if lower.contains("warn") { return .warn }
        return .info
    }

    private static func containsFatalSignal(_ text: String) -> Bool {
        text.contains("Exception in thread")
            || text.contains("java.lang.NoClassDefFoundError")
            || text.contains("java.lang.UnsatisfiedLinkError")
            || text.contains("Failed to locate library")
    }

    private static func decodeXMLText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
