import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Cleanup hint")
struct CleanupHintTests {
    let home = URL(filePath: "/Users/alice", directoryHint: .isDirectory)
    var hints: CleanupHints {
        CleanupHints(rules: Catalog.rules, home: home, projectRoots: ["~/dev"])
    }

    @Test func aPresetLocationIsCoveredByItsRule() {
        #expect(hints.rule(for: "/Users/alice/Library/Caches/go-build")?.id == "go-build")
        #expect(hints.rule(for: "/Users/alice/.npm/_cacache")?.id == "npm-cache")
    }

    @Test func aChildOfAnExpandedPresetIsCoveredAndTheMoreSpecificRuleWins() {
        #expect(hints.rule(for: "/Users/alice/Library/Caches/com.example.app")?.id == "library-caches")
        #expect(hints.rule(for: "/Users/alice/Library/Developer/Xcode/DerivedData/App-abc")?.id == "xcode-derived")
        // The folder that holds the children is not a target itself.
        #expect(hints.rule(for: "/Users/alice/Library/Caches") == nil)
    }

    @Test func buildOutputIsCoveredOnlyBelowAProjectRoot() {
        #expect(hints.rule(for: "/Users/alice/dev/web/node_modules")?.id == "artifact:node_modules")
        #expect(hints.rule(for: "/Users/alice/Music/node_modules") == nil)
        #expect(hints.rule(for: "/Users/alice/dev") == nil)
    }

    @Test func otherFoldersAreNotCovered() {
        #expect(hints.rule(for: "/Users/alice/Documents") == nil)
        #expect(hints.rule(for: "/Users/alice/Downloads") == nil)
        #expect(hints.rule(for: "/Users/alice/Library/Developer/Xcode/Archives") == nil)
        #expect(hints.rule(for: "/Users/alice/Library/Caches/Google") == nil)
        #expect(hints.rule(for: "/Users/alice/Library/Caches/Google/Chrome")?.id == "chrome-cache")
        #expect(hints.rule(for: "/Users/alice/Library/Application Support/Google/Chrome/Profile 2/Code Cache")?.id == "chrome-profile-cache")
        #expect(hints.rule(for: "/Users/alice/Library/Application Support/Google/Chrome/Profile 2/Cookies") == nil)
        #expect(hints.rule(for: "/Users/alice/Library") == nil)
        #expect(hints.rule(for: "/Users/alice/Library/Caches/go-build/00") == nil)
    }
}
