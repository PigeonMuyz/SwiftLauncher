import CryptoKit
import Foundation

enum Hashing {
    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha1(fileAt url: URL) throws -> String {
        try sha1(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(fileAt url: URL) throws -> String {
        try sha256(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    static func sha512(_ data: Data) -> String {
        SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha512(fileAt url: URL) throws -> String {
        try sha512(Data(contentsOf: url, options: [.mappedIfSafe]))
    }

    static func offlineUUID(for username: String) -> String {
        let digest = Insecure.MD5.hash(data: Data("OfflinePlayer:\(username)".utf8))
        var bytes = Array(digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
    }
}
