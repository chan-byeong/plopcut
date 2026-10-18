import Foundation
import Testing
@testable import PlopcutCore

/// Checklist L-16, spec 1.6: how a drop's source is grouped by the source filter.
@Suite struct SourceKeyTests {
    @Test func cases() {
        let cases: [(DropSource, SourceKey?)] = [
            (DropSource(appName: "Google Chrome", url: "https://www.github.com/plopcut"), .website("github.com")),
            (DropSource(url: "https://developer.apple.com/documentation"), .website("developer.apple.com")),
            (DropSource(url: "http://WWW.GitHub.COM/x"), .website("github.com")),
            (DropSource(url: "HTTPS://Example.org"), .website("example.org")),
            (DropSource(url: "https://www.www.a.com"), .website("www.a.com")),
            (DropSource(url: "  https://news.ycombinator.com/item?id=1  "), .website("news.ycombinator.com")),
            (DropSource(url: "https://www."), .website("www.")),
            (DropSource(appName: "Finder", url: "file:///Users/me/a.txt"), .app("Finder")),
            (DropSource(appName: "Mail", url: "mailto:me@example.com"), .app("Mail")),
            (DropSource(appName: "Safari", url: "https://"), .app("Safari")),
            (DropSource(appName: "Safari", url: ""), .app("Safari")),
            (DropSource(appName: "메모"), .app("메모")),
            (DropSource(appName: "Terminal", windowTitle: "zsh"), .app("Terminal")),
            (DropSource(url: "ftp://example.com"), nil),
            (DropSource(appName: "   "), nil),
            (DropSource(windowTitle: "Untitled"), nil),
            (DropSource(), nil),
        ]
        for (source, expected) in cases {
            #expect(SourceKey(source) == expected, "\(source)")
        }
    }

    @Test func websiteAndAppWithTheSameNameAreDifferentSources() {
        #expect(SourceKey.website("github.com") != SourceKey.app("github.com"))
        #expect(SourceKey.website("github.com").name == "github.com" && SourceKey.app("메모").name == "메모")
    }
}
