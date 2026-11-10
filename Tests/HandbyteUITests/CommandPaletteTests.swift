import Testing
@testable import HandbyteUI

@Suite("Command palette")
struct CommandPaletteTests {
    @Test func emptyQueryListsEverything() {
        #expect(PaletteCommand.matching("").count == PaletteCommand.all.count)
    }

    @Test func everyWordMustMatchAndTitleStartsComeFirst() {
        #expect(PaletteCommand.matching("clean").first?.action == .smartClean)
        #expect(PaletteCommand.matching("restore").map(\.action) == [.show(.history)])
        #expect(PaletteCommand.matching("uninstall").map(\.action) == [.show(.apps)])
        #expect(PaletteCommand.matching("zzz").isEmpty)
        #expect(PaletteCommand.matching("go storage").map(\.action) == [.show(.storage)])
    }
}
