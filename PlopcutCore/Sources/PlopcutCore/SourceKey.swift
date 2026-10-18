import Foundation

/// The unit the source filter groups drops by (spec 1.6, PLO-103): a website by its host, otherwise the app.
/// A website and an app with the same name are different sources.
public enum SourceKey: Hashable, Sendable {
    case website(String)
    case app(String)

    /// An http(s) URL with a host gives a website: the host lowercased, minus one leading `www.` (subdomains stay).
    /// Otherwise a non-blank app name gives an app. Without either the drop has no source.
    public init?(_ source: DropSource) {
        if let host = Self.webHost(source.url) {
            self = .website(host)
        } else if let app = source.appName, !app.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self = .app(app)
        } else {
            return nil
        }
    }

    public var name: String {
        switch self {
        case .website(let name), .app(let name): name
        }
    }

    private static func webHost(_ value: String?) -> String? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty
        else { return nil }
        let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return stripped.isEmpty ? host : stripped
    }
}
