import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Smart Clean")
struct SmartCleanTests {
    let derived = Fixtures.candidate(path: "/Users/alice/Library/Developer/Xcode/DerivedData/App", rule: Fixtures.rule(id: "xcode-derived", category: .xcode, area: "xcode"), bytes: 600)
    let cache = Fixtures.candidate(path: "/Users/alice/Library/Caches/go-build", rule: Fixtures.rule(id: "go-build", category: .devCache, area: "packages"), bytes: 200)
    let inner = Fixtures.candidate(path: "/Users/alice/Library/Caches/go-build/00", rule: Fixtures.rule(id: "go-build", category: .devCache, area: "packages"), bytes: 50)
    let pub = Fixtures.candidate(path: "/Users/alice/.pub-cache", rule: Fixtures.rule(id: "pub-cache", category: .devCache, safety: .review, area: "packages"), bytes: 100)
    let chrome = Fixtures.candidate(path: "/Users/alice/Library/Caches/Google/Chrome", rule: Fixtures.rule(id: "chrome-cache", area: "browsers"), bytes: 300, eligibility: .blocked(reason: "com.google.Chrome is running"))
    let backup = Fixtures.candidate(path: "/Users/alice/Library/Application Support/MobileSync/Backup/a", rule: Fixtures.rule(id: "ios-backups", category: .other, safety: .review, area: "files", rebuildable: false), bytes: 900)

    @Test func takesOnlySafeEligibleItemsOnceAndSumsByArea() {
        let plan = SmartCleanPlan(candidates: [derived, cache, inner, pub, chrome, backup])
        #expect(Set(plan.selection.map(\.id)) == [derived.id, cache.id])
        #expect(plan.areas.map(\.id) == ["xcode", "packages", "browsers", "files"])
        #expect(plan.safeBytes == 800)
        #expect(plan.reviewBytes == 1000)
        #expect(plan.skippedBytes == 300)
        let browsers = plan.areas.first { $0.id == "browsers" }
        #expect(browsers?.skippedReason == "com.google.Chrome is running")
        #expect(plan.areas.first { $0.id == "xcode" }?.title == "Xcode build data")
    }

    @Test func removalByDataClassRemovesCachesAndTrashesTheRest() throws {
        let byData = try #require(CleanConfirmation.actions(for: .byData, acknowledged: false))
        #expect(byData(cache) == .removePermanently)
        #expect(byData(backup) == .trash)
        let trash = try #require(CleanConfirmation.actions(for: .trash, acknowledged: false))
        #expect(trash(cache) == .trash)
        #expect(CleanConfirmation.actions(for: .removePermanently, acknowledged: false) == nil)
        let permanent = try #require(CleanConfirmation.actions(for: .removePermanently, acknowledged: true))
        #expect(permanent(backup) == .removePermanently)
        #expect(AppSettings().deletionMode == .byData)
    }
}
