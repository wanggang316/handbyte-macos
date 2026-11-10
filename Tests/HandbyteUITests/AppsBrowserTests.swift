import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Apps browser")
struct AppsBrowserTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func app(_ name: String, size: Int64, daysAgo: Double?) -> InstalledApp {
        var app = InstalledApp(url: URL(filePath: "/Applications/\(name).app"), name: name, bundleID: "com.example.\(name.lowercased())",
                               version: "1", source: .direct, caskToken: nil, zap: [], isSystem: false, architectures: ["arm64"])
        app.size = size
        app.lastUsed = daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        return app
    }

    @Test func filtersSortAndSearch() {
        var browser = AppsBrowser(apps: [app("Notes", size: 300, daysAgo: 400), app("Mail", size: 900, daysAgo: 1), app("Old", size: 10, daysAgo: nil)])
        #expect(browser.rows(now: now).map(\.name) == ["Notes", "Mail", "Old"])
        browser.filter = .unused
        #expect(browser.rows(now: now).map(\.name) == ["Notes"])
        browser.filter = .largest
        #expect(browser.rows(now: now).map(\.name) == ["Mail", "Notes", "Old"])
        browser.query = "no"
        #expect(browser.rows(now: now).map(\.name) == ["Notes"])
        browser.setSize(5, for: "/Applications/Mail.app")
        #expect(browser.totalSize == 315)
    }

    @Test func leftoversGroupByAppAndSortBySize() {
        func item(_ id: String, _ size: Int64) -> AppFiles.Leftover {
            var l = AppFiles.Leftover(url: URL(filePath: "/h/\(id)"), bundleID: id, fileClass: "data", isDirectory: true)
            l.size = size
            return l
        }
        let groups = LeftoverGroup.group([item("net.a.App", 1), item("net.b.App", 5), item("net.a.App.helper", 1)])
        #expect(groups.map(\.bundleID) == ["net.b.App", "net.a.App"])
        #expect(groups[1].items.count == 2 && groups[1].size == 2)
    }
}
