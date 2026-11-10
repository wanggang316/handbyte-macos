import Foundation
import os
import Testing
@testable import HandbyteCore

/// One case of `Conformance/usage`, shared with the Go CLI.
private struct UsageCase: Decodable {
    struct File: Decodable {
        let path: String
        let bytes: Int
    }

    struct Link: Decodable {
        let path: String
        let target: String
    }

    struct Child: Decodable {
        let name: String
        let dir: Bool
        let files: Int
        let logicalBytes: Int64
    }

    struct Expectation: Decodable {
        let files: Int
        let logicalBytes: Int64
        let children: [Child]
        let largestFiles: [String]
    }

    let name: String
    let files: [File]
    let hardLinks: [Link]?
    let clones: [Link]?
    let symlinks: [Link]?
    let expect: Expectation
}

@Suite("Usage")
struct UsageTests {
    @Test func scansMatchTheSharedConformanceCases() async throws {
        let directory = try #require(Bundle.module.url(forResource: "Conformance", withExtension: nil))
            .appending(path: "usage", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        #expect(!names.isEmpty)
        for name in names {
            let value = try JSONDecoder().decode(UsageCase.self, from: Data(contentsOf: directory.appending(path: name)))
            let home = try TemporaryHome()
            defer { home.cleanUp() }
            for file in value.files {
                try home.writeFile(file.path, size: file.bytes)
            }
            for link in value.hardLinks ?? [] {
                try home.hardLink(link.path, to: link.target)
            }
            var cloned = true
            for link in value.clones ?? [] {
                cloned = try home.clone(link.path, of: link.target) && cloned
            }
            // A case with clones needs a volume that can clone.
            guard cloned else { continue }
            for link in value.symlinks ?? [] {
                // The text of the link is the target as written in the case.
                try FileManager.default.createSymbolicLink(
                    atPath: home.url.appending(path: link.path).path, withDestinationPath: link.target
                )
            }

            let result = try #require(await UsageScanner().scan(home.url))

            #expect(result.root.fileCount == value.expect.files, "\(name)")
            #expect(result.root.logicalBytes == value.expect.logicalBytes, "\(name)")
            #expect(!result.root.incomplete && !result.cancelled, "\(name)")
            let got = result.root.children.map { "\($0.name) dir=\($0.isDirectory) files=\($0.fileCount) logical=\($0.logicalBytes)" }
            let want = value.expect.children.map { "\($0.name) dir=\($0.dir) files=\($0.files) logical=\($0.logicalBytes)" }
            #expect(got == want, "\(name): \(value.name)")
            let prefix = home.url.path + "/"
            let largest = result.largest.prefix(value.expect.largestFiles.count).map { String($0.path.dropFirst(prefix.count)) }
            #expect(largest == value.expect.largestFiles, "\(name)")
        }
    }

    @Test func unreadableDirectoryMarksTheParentChain() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("ok/a", size: 100)
        try home.writeFile("outer/locked/secret", size: 100)
        try home.makeUnreadable("outer/locked")

        let result = try #require(await UsageScanner().scan(home.url))

        let outer = try #require(result.root.children.first { $0.name == "outer" })
        let locked = try #require(outer.children.first { $0.name == "locked" })
        #expect(result.root.incomplete && outer.incomplete && locked.incomplete)
        #expect(locked.error != nil)
        #expect(result.root.children.first { $0.name == "ok" }?.incomplete == false)
        #expect(result.root.fileCount == 1)
    }

    @Test func smallFilesAreSummedAndTheListOfLargestIsBounded() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        for index in 0..<30 {
            try home.writeFile(String(format: "many/f%02d", index), size: 1000 + index * 5000)
        }
        var options = UsageScanner.Options()
        options.filesPerDirectory = 4
        options.largestFiles = 3

        let result = try #require(await UsageScanner().scan(home.url, options: options))

        let many = try #require(result.root.children.first)
        #expect(many.children.count == 4)
        #expect(many.otherFileCount == 26)
        #expect(many.fileCount == 30)
        let kept = many.children.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        #expect(kept + many.otherAllocatedBytes == many.allocatedBytes)
        #expect(result.largest.map { URL(filePath: $0.path).lastPathComponent } == ["f29", "f28", "f27"])
    }

    @Test func cancelledScanKeepsThePartialResult() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        for index in 0..<20 {
            try home.writeFile("d\(index)/sub/file", size: 100)
        }
        let url = home.url
        let task = Task { await UsageScanner().scan(url) }
        task.cancel()
        let result = try #require(await task.value)
        #expect(result.cancelled)
        #expect(result.root.incomplete)
    }

    @Test func progressReportsEachTopLevelEntry() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("a/x", size: 5000)
        try home.writeFile("b/y", size: 9000)
        try home.writeFile("c.bin", size: 100)
        let last = OSAllocatedUnfairLock<UsageProgress?>(initialState: nil)

        let result = try #require(await UsageScanner().scan(home.url) { progress in
            last.withLock { $0 = progress }
        })

        let progress = try #require(last.withLock { $0 })
        #expect(progress.fileCount == 3)
        #expect(progress.allocatedBytes == result.root.allocatedBytes)
        #expect(progress.top.map(\.name) == ["a", "b", "c.bin"])
        #expect(progress.top.filter { !$0.done }.isEmpty)
        let topBytes = progress.top.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        #expect(topBytes == result.root.allocatedBytes)
    }

    @Test func thePathOfTheResultKeepsThePrivatePrefix() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        #expect(home.url.path.hasPrefix("/private/"))
        let alias = URL(filePath: String(home.url.path.dropFirst("/private".count)), directoryHint: .isDirectory)
        let result = try #require(await UsageScanner().scan(alias))
        #expect(result.path == home.url.path(percentEncoded: false).replacing(/\/$/, with: ""))
        #expect(UsageScanner.physicalPath(URL(filePath: "/var")) == "/private/var")
    }

    @Test func fullClonesCountOnce() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("a/original", size: 100_000)
        guard try home.clone("a/copy", of: "a/original"), try home.clone("b/copy", of: "a/original") else { return }
        var options = UsageScanner.Options()
        options.workers = 3

        let single = try #require(await UsageScanner().scan(home.path("a")))
        let result = try #require(await UsageScanner().scan(home.url, options: options))

        let size = try home.allocatedBytes("a/original")
        #expect(size > 0)
        #expect(result.root.allocatedBytes == size)
        #expect(result.root.fileCount == 3)
        #expect(result.root.logicalBytes == 300_000)
        #expect(!result.root.mayShare)
        // In one directory, the name that sorts first carries the size.
        #expect(single.root.children.map { "\($0.name)=\($0.allocatedBytes)" } == ["copy=\(size)", "original=0"])
    }

    @Test func partialClonesCountInFullAndMayShare() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("original", size: 100_000)
        guard try home.clone("dir/changed", of: "original") else { return }
        let handle = try FileHandle(forWritingTo: home.url.appending(path: "dir/changed"))
        try handle.write(contentsOf: Data("changed".utf8))
        try handle.close()

        let result = try #require(await UsageScanner().scan(home.url))

        let dir = try #require(result.root.children.first { $0.name == "dir" })
        let changed = try #require(dir.children.first)
        let original = try #require(result.root.children.first { $0.name == "original" })
        #expect(original.allocatedBytes > 0 && changed.allocatedBytes > 0)
        #expect(result.root.allocatedBytes == original.allocatedBytes + changed.allocatedBytes)
        #expect(changed.mayShare && original.mayShare && dir.mayShare && result.root.mayShare)
        #expect(result.largest.allSatisfy { $0.mayShare })
    }

    @Test func plainFilesHaveNoMark() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        try home.writeFile("a/x", size: 5000)

        let result = try #require(await UsageScanner().scan(home.url))

        #expect(!result.root.mayShare)
        #expect(result.root.children.allSatisfy { !$0.mayShare })
    }

    @Test func aFileIsNotATree() async throws {
        let home = try TemporaryHome()
        defer { home.cleanUp() }
        let file = try home.writeFile("file", size: 10)
        let result = await UsageScanner().scan(file)
        #expect(result == nil)
    }
}
