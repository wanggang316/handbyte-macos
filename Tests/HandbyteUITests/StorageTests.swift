import CoreGraphics
import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Storage")
struct StorageTests {
    private func node(_ name: String, _ bytes: Int64, directory: Bool = false, children: [UsageNode] = []) -> UsageNode {
        var node = UsageNode(name: name, isDirectory: directory)
        node.allocatedBytes = bytes
        node.logicalBytes = bytes
        node.fileCount = directory ? max(1, children.count) : 1
        node.children = children
        return node
    }

    private var tree: UsageNode {
        var root = node("/Users/alice", 1000, directory: true, children: [
            node("media", 600, directory: true, children: [node("movie.mov", 500), node("song.mp3", 100)]),
            node("docs", 250, directory: true, children: [node("report.pdf", 250)]),
            node("readme.txt", 50),
        ])
        root.otherFileCount = 12
        root.otherAllocatedBytes = 100
        return root
    }

    // MARK: Treemap

    @Test func treemapFillsTheRectangleInProportionToTheValues() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let values: [Double] = [600, 250, 100, 50]
        let rects = Treemap.layout(values: values, in: bounds)

        #expect(rects.count == values.count)
        let total = values.reduce(0, +)
        for (rect, value) in zip(rects, values) {
            #expect(abs(rect.width * rect.height - value / total * 400 * 300) < 0.5)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
        }
        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                let overlap = rect.intersection(other)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test func treemapKeepsCellsCloseToSquares() {
        let rects = Treemap.layout(values: [6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        #expect(worst < 3)
    }

    @Test func treemapHandlesEmptyAndZeroInput() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(Treemap.layout(values: [], in: bounds).isEmpty)
        #expect(Treemap.layout(values: [0, 0], in: bounds) == [.zero, .zero])
        #expect(Treemap.layout(values: [5], in: bounds) == [bounds])
        #expect(Treemap.layout(values: [5, 0], in: bounds) == [bounds, .zero])
        #expect(Treemap.layout(values: [5], in: .zero) == [.zero])
    }

    // MARK: Browser

    @Test func rowsListChildrenThenTheSmallFilesWithShares() {
        let browser = StorageBrowser(rootPath: "/Users/alice", root: tree)
        #expect(browser.rows.map(\.title) == ["media", "docs", "readme.txt", "12 smaller files"])
        #expect(browser.rows.map(\.allocatedBytes) == [600, 250, 50, 100])
        #expect(browser.rows[0].share == 0.6)
        #expect(browser.rows[0].canOpen)
        #expect(!browser.rows[2].canOpen)
        #expect(browser.rows[3].path == nil)
        #expect(browser.rows[0].path == "/Users/alice/media")
    }

    @Test func openingAndLeavingAFolderMovesThroughTheTree() {
        var browser = StorageBrowser(rootPath: "/Users/alice", root: tree)
        #expect(browser.crumbs.map(\.title) == ["alice"])

        browser.open(browser.rows[0])
        #expect(browser.currentPath == "/Users/alice/media")
        #expect(browser.crumbs.map(\.title) == ["alice", "media"])
        #expect(browser.rows.map(\.title) == ["movie.mov", "song.mp3"])
        #expect(browser.rows[0].share == 500.0 / 600.0)

        browser.open(browser.rows[0])
        #expect(browser.currentPath == "/Users/alice/media")

        browser.leave(to: 0)
        #expect(browser.currentPath == "/Users/alice")
        #expect(browser.rows.count == 4)
    }

    @Test func aSkippedOrMissingFolderDoesNotOpen() {
        var skipped = node("Volumes", 0, directory: true)
        skipped.skipped = "another volume"
        let root = node("/", 10, directory: true, children: [skipped])
        var browser = StorageBrowser(rootPath: "/", root: root)
        #expect(!browser.rows[0].canOpen)
        #expect(browser.rows[0].note == "another volume")
        #expect(browser.rows[0].path == "/Volumes")
        browser.open(browser.rows[0])
        #expect(browser.currentPath == "/")
    }
}
