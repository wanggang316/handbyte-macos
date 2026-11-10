import Foundation
import Testing
import HandbyteCore
@testable import HandbyteUI

@Suite("Overview")
struct OverviewTests {
    let safe = Fixtures.candidate(path: "/Users/alice/Library/Caches/safe", bytes: 3_000_000_000)
    let review = Fixtures.candidate(
        path: "/Users/alice/dev/app/node_modules",
        rule: Fixtures.rule(id: "artifact:node_modules", category: .projectBuild, safety: .review),
        bytes: 2_000_000_000
    )
    let blocked = Fixtures.candidate(
        path: "/Users/alice/Library/Caches/blocked", bytes: 9_000_000_000, eligibility: .blocked(reason: "Owner is running")
    )
    let volume = VolumeUsage(totalBytes: 500_000_000_000, availableBytes: 200_000_000_000)

    @Test func sectionsAreInTopBarOrderAndOnlyBuiltOnesOpen() {
        #expect(AppSection.allCases.map(\.title) == ["Overview", "Clean", "Apps", "Storage", "History"])
        #expect(AppSection.allCases.filter(\.isAvailable) == [.overview, .clean, .storage])
        for section in AppSection.allCases where !section.isAvailable {
            #expect(!section.plannedSummary.isEmpty, "\(section)")
        }
    }

    @Test func volumeUsageGivesTheUsedFraction() {
        #expect(volume.usedBytes == 300_000_000_000)
        #expect(volume.usedFraction == 0.6)
        #expect(VolumeUsage(totalBytes: 0, availableBytes: 0).usedFraction == 0)
        #expect(VolumeUsage(totalBytes: 100, availableBytes: 500).usedFraction == 0)
    }

    @Test func beforeAScanTheHeroShowsFreeSpaceAndOffersAScan() {
        let summary = OverviewSummary(candidates: nil, volume: volume)
        #expect(summary.heroBytes == 200_000_000_000)
        #expect(summary.heroLabel == "free")
        #expect(summary.primaryAction == .scan)
        #expect(summary.detail == "Not scanned yet")
    }

    @Test func afterAScanTheHeroCountsOnlySafeEligibleItems() {
        let summary = OverviewSummary(candidates: [safe, review, blocked], volume: volume)
        #expect(summary.heroBytes == 3_000_000_000)
        #expect(summary.heroLabel == "safe to clean")
        #expect(summary.primaryAction == .review)
        #expect(summary.safeCount == 1)
        #expect(summary.reviewBytes == 2_000_000_000)
    }

    @Test func aScanWithNothingSafeSaysSoAndOffersAnotherScan() {
        let summary = OverviewSummary(candidates: [blocked], volume: volume)
        #expect(summary.heroBytes == 0)
        #expect(summary.heroLabel == "safe to clean")
        #expect(summary.primaryAction == .scan)
        #expect(summary.detail == "Nothing safe to clean was found")
    }

    @Test func withoutVolumeDataTheHeroHasNoNumber() {
        let summary = OverviewSummary(candidates: nil, volume: nil)
        #expect(summary.heroBytes == nil)
        #expect(summary.primaryAction == .scan)
    }
}
