import Foundation

enum LauncherError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case requestFailed(String, String)
    case checksumMismatch(String)
    case missingDownload(String)
    case missingJava
    case invalidJava(String)
    case missingAccount
    case instanceNotInstalled
    case processFailed(String)
    case microsoftClientIDMissing
    case minecraftAppRegistrationRequired
    case authentication(String)
    case unsupported(String)
    case invalidOperation(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的数据。"
        case .httpStatus(let code): "服务器请求失败（HTTP \(code)）。"
        case .requestFailed(let url, let reason): "下载失败：\(url)\n原因：\(reason)"
        case .checksumMismatch(let file): "文件校验失败：\(file)"
        case .missingDownload(let name): "版本元数据缺少下载项：\(name)"
        case .missingJava: "没有找到适合此版本的 Java。"
        case .invalidJava(let message): "Java 运行时不可用：\(message)"
        case .missingAccount: "请先选择一个游戏账户。"
        case .instanceNotInstalled: "该实例尚未安装完成。"
        case .processFailed(let message): "进程执行失败：\(message)"
        case .microsoftClientIDMissing: "应用未配置 Microsoft OAuth Client ID。"
        case .minecraftAppRegistrationRequired:
            "该 Application (client) ID 尚未加入 Minecraft Java 服务 API 允许列表。"
                + "请提交官方第三方应用审核表；这不是 Object ID 或 Tenant ID 配置错误。"
        case .authentication(let message): "账户认证失败：\(message)"
        case .unsupported(let message): "暂不支持：\(message)"
        case .invalidOperation(let message): "操作失败：\(message)"
        }
    }
}
