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
}
