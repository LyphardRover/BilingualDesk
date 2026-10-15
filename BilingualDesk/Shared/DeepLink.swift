// File: BilingualDesk/Shared/DeepLink.swift
// Targets: App, Widget
import Foundation

/// 小组件与 App 之间唯一的两种链接（02 §12）。
/// - `book`：bilingualdesk://read/<书 UUID>
/// - `card`：bilingualdesk://card/<词卡 UUID>
enum DeepLink: Equatable, Sendable {
    case book(UUID)
    case card(UUID)

    private static let readHost = "read"
    private static let cardHost = "card"

    /// DL-2：严格解析。任何一项不满足都返回 nil（格式不对的链接直接忽略，不提示）。
    init?(url: URL) {
        // scheme 不分大小写等于 bilingualdesk
        guard let scheme = url.scheme,
              scheme.lowercased() == SharedConfiguration.urlScheme.lowercased() else { return nil }
        // query、fragment、user、password、port 都必须为 nil
        guard url.query == nil, url.fragment == nil, url.user == nil,
              url.password == nil, url.port == nil else { return nil }
        // host 不分大小写为 read 或 card
        guard let host = url.host?.lowercased() else { return nil }
        // pathComponents 去掉 "/" 后恰好 1 个元素，且是合法 UUID（大小写均可）
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1, let id = UUID(uuidString: components[0]) else { return nil }

        switch host {
        case Self.readHost:
            self = .book(id)
        case Self.cardHost:
            self = .card(id)
        default:
            return nil
        }
    }

    /// DL-1：构造链接，UUID 用大写的 uuidString。
    var url: URL {
        let host: String
        let id: UUID
        switch self {
        case .book(let bookID):
            host = Self.readHost
            id = bookID
        case .card(let cardID):
            host = Self.cardHost
            id = cardID
        }
        // scheme、host、UUID 都是固定的 ASCII 字符，这里的 URL 一定能构造成功。
        return URL(string: "\(SharedConfiguration.urlScheme)://\(host)/\(id.uuidString)")!
    }
}
