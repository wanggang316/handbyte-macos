import Foundation
import Testing
@testable import HandbyteCore

/// One case of `Conformance/cleanup`. The cases are shared with the Go CLI;
/// see `Conformance/README.md`.
private struct CleanupCase: Decodable {
    struct File: Decodable {
        let path: String
        let bytes: Int
    }

    struct Expectation: Decodable {
        let path: String
        let rule: String
        let category: String
        let safety: String
    }

    let name: String
    let projectRoots: [String]
    let files: [File]
    let expect: [Expectation]
}

private func cleanupCases() throws -> [(file: String, value: CleanupCase)] {
    let directory = try #require(Bundle.module.url(forResource: "Conformance", withExtension: nil))
        .appending(path: "cleanup", directoryHint: .isDirectory)
    let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".json") }
        .sorted()
    return try names.map { name in
        let data = try Data(contentsOf: directory.appending(path: name))
        return (name, try JSONDecoder().decode(CleanupCase.self, from: data))
    }
}

@Test func cleanupScansMatchTheSharedConformanceCases() async throws {
    let cases = try cleanupCases()
    #expect(!cases.isEmpty)
    for (file, value) in cases {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        for entry in value.files {
            try home.writeFile(entry.path, size: entry.bytes)
        }
        var configuration = ScanConfiguration(home: home.url)
        configuration.minimumSize = 0
        configuration.projectRoots = value.projectRoots
        configuration.skipProjectScan = value.projectRoots.isEmpty

        let result = await DiskScanner().collect(configuration)

        let prefix = home.url.path.hasSuffix("/") ? home.url.path : home.url.path + "/"
        let got = result.candidates.map { candidate in
            let relative = String(candidate.url.path.dropFirst(prefix.count))
            return [relative, candidate.rule.id, candidate.rule.category.catalogID, candidate.rule.safety.catalogName]
                .joined(separator: " | ")
        }
        let want = value.expect.map { [$0.path, $0.rule, $0.category, $0.safety].joined(separator: " | ") }
        #expect(got.sorted() == want.sorted(), "\(file): \(value.name)")
    }
}
