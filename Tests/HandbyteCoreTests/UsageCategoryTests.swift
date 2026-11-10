import Foundation
import Testing
@testable import HandbyteCore

/// One case of `Conformance/categories`, shared with the Go CLI.
private struct CategoryCase: Decodable {
    struct File: Decodable {
        let path: String
        let bytes: Int
    }

    let name: String
    let projectRoots: [String]
    let files: [File]
    let expect: [String: Int64]
}

@Suite("Usage categories")
struct UsageCategoryTests {
    @Test func categoriesMatchTheSharedConformanceCases() async throws {
        let directory = try #require(Bundle.module.url(forResource: "Conformance", withExtension: nil))
            .appending(path: "categories", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        #expect(!names.isEmpty)
        for name in names {
            let value = try JSONDecoder().decode(CategoryCase.self, from: Data(contentsOf: directory.appending(path: name)))
            let home = try TemporaryHome()
            defer { home.cleanUp() }
            for file in value.files {
                try home.writeFile(file.path, size: file.bytes)
            }
            var options = UsageScanner.Options()
            options.filesPerDirectory = 1
            let result = try #require(await UsageScanner().scan(home.url, options: options))
            let paths = StorageCatalog.shared.paths(home: home.url, projectRoots: value.projectRoots)
            let totals = UsageCategories.totals(of: result, paths: paths)
            let got = Dictionary(uniqueKeysWithValues: totals.map { ($0.id, $0.logicalBytes) })
            #expect(got == value.expect, "\(name): \(value.name)")
        }
    }

    @Test func categoriesSumToTheRoot() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        for (index, path) in ["Movies/a", "Movies/b", "Library/Caches/x/y", "Library/z", "top", "Library/Application Support/q"].enumerated() {
            try home.writeFile(path, size: 1000 * (index + 1))
        }
        var options = UsageScanner.Options()
        options.filesPerDirectory = 1
        let result = try #require(await UsageScanner().scan(home.url, options: options))
        let totals = UsageCategories.totals(of: result, paths: StorageCatalog.shared.paths(home: home.url, projectRoots: []))
        #expect(totals.reduce(0) { $0 + $1.allocatedBytes } == result.root.allocatedBytes)
        #expect(totals.reduce(0) { $0 + $1.logicalBytes } == result.root.logicalBytes)
        #expect(totals.map(\.allocatedBytes) == totals.map(\.allocatedBytes).sorted(by: >))
    }

    @Test func catalogHasTheTitlesAndTheOtherCategory() {
        #expect(StorageCatalog.shared.title(of: "media") == "Media")
        #expect(StorageCatalog.shared.title(of: "other") == "Other")
        #expect(StorageCatalog.shared.categories.map(\.id).contains("developer"))
    }

    @Test func summariesAreKeptPerFolderNewestFirst() throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let file = home.url.appending(path: "usage.json")
        let store = UsageSummaryStore(fileURL: file)
        #expect(store.load(path: "/a") == nil)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<(UsageSummaryStore.limit + 2) {
            try store.save(UsageSummary(path: "/f\(index)", scannedAt: base.addingTimeInterval(Double(index) * 60), allocatedBytes: Int64(index)))
        }
        #expect(store.load(path: "/f0") == nil)
        #expect(store.load(path: "/f9")?.allocatedBytes == 9)
        try store.save(UsageSummary(path: "/f9", scannedAt: base.addingTimeInterval(3600), allocatedBytes: 99))
        #expect(store.load(path: "/f9")?.allocatedBytes == 99)

        try Data("{not json".utf8).write(to: file)
        #expect(store.load(path: "/f9") == nil)
        try store.save(UsageSummary(path: "/a", scannedAt: base))
        #expect(store.load(path: "/a") != nil)
    }
}
