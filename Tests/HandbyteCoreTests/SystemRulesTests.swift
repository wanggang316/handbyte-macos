import Foundation
import Testing
@testable import HandbyteCore

@Suite("System rules")
struct SystemRulesTests {
    @Test func theCommandIsTheSameAsInTheCLI() throws {
        let rule = try #require(SystemRule.all.first { $0.id == "system-crash-reports" })
        #expect(rule.shellCommand == "'/usr/bin/find' '/Library/Logs/DiagnosticReports' '-xdev' '-type' 'f' '(' '-name' '*.ips' '-o' '-name' '*.diag' '-o' '-name' '*.crash' '-o' '-name' '*.hang' '-o' '-name' '*.spin' '-o' '-name' '*.panic' ')' '-mtime' '+30' '-print' '-delete'")
    }

    @Test func measureCountsOnlyOldMatchingRegularFiles() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let old = Date().addingTimeInterval(-40 * 86_400)
        for name in ["a.ips", "Retired/b.diag", "c.txt"] {
            try home.writeFile("logs/" + name, size: 5000)
            try home.setModificationDate(old, of: "logs/" + name)
        }
        try home.writeFile("logs/new.ips", size: 5000)
        let rule = try #require(SystemRule.all.first { $0.id == "system-crash-reports" })
        let result = rule.measure(root: home.path("logs").fileSystemPath)
        #expect(result.files == 2)
        #expect(result.bytes >= 10_000)
        #expect(!result.partial)
    }

    @Test func theUnifiedLogRuleNeedsReviewAndRunsTheFixedCommand() throws {
        let rule = try #require(SystemRule.all.first { $0.id == "system-unified-log" })
        #expect(rule.needsReview)
        #expect(rule.shellCommand == "'/usr/bin/log' 'erase' '--all'")
        #expect(SystemRule.all.filter { !$0.needsReview }.allSatisfy { $0.command == nil && !$0.names.isEmpty })
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("db/Persist/a.tracev3", size: 5000)
        try home.writeFile("db/Special/b.tracev3", size: 5000)
        let measured = rule.measure(root: home.path("db").fileSystemPath)
        #expect(measured.files == 2)
        #expect(measured.bytes >= 10000)
    }
}
