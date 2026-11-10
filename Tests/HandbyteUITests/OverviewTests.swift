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

    @Test func purgeableSpaceIsTheDifferenceOfTheTwoFreeValues() {
        #expect(VolumeUsage(totalBytes: 500, availableBytes: 200, immediatelyAvailableBytes: 150).purgeableBytes == 50)
        #expect(VolumeUsage(totalBytes: 500, availableBytes: 200).purgeableBytes == 0)
        #expect(VolumeUsage(totalBytes: 500, availableBytes: 200, immediatelyAvailableBytes: 250).purgeableBytes == 0)
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

@Suite("Volume breakdown")
struct VolumeBreakdownTests {
    let volume = VolumeUsage(totalBytes: 500, availableBytes: 200)

    @Test func withoutAResultTheUsedSpaceIsOnePart() {
        let parts = VolumeBreakdown.parts(volume: volume, home: nil)
        #expect(parts == [.init(id: "other", title: "Used", bytes: 300)])
    }

    @Test func theHomeCategoriesComeFirstAndTheRestIsOnePart() {
        let home = UsageSummary(path: "/Users/alice", scannedAt: .now, allocatedBytes: 150, categories: [
            CategoryTotal(id: "developer", allocatedBytes: 90, logicalBytes: 0),
            CategoryTotal(id: "media", allocatedBytes: 40, logicalBytes: 0),
            CategoryTotal(id: "other", allocatedBytes: 20, logicalBytes: 0),
        ])
        let parts = VolumeBreakdown.parts(volume: volume, home: home)
        #expect(parts.map(\.id) == ["developer", "media", "other"])
        #expect(parts.map(\.title) == ["Developer", "Media", "System and other"])
        #expect(parts.map(\.bytes) == [90, 40, 170])
    }

    @Test func aHomeLargerThanTheUsedSpaceLeavesNoRest() {
        let home = UsageSummary(path: "/", scannedAt: .now, categories: [CategoryTotal(id: "media", allocatedBytes: 400, logicalBytes: 0)])
        #expect(VolumeBreakdown.parts(volume: volume, home: home).map(\.id) == ["media"])
    }
}
