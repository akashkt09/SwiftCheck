import XCTest
@testable import DemoApp

final class ItemSorterTests: XCTestCase {
    func testSortedByScorePutsHighestScoreFirst() {
        let entries = [
            Entry(label: "Entry A", score: 589),
            Entry(label: "Entry B", score: 526),
            Entry(label: "Entry C", score: 505)
        ]

        let sorted = ItemSorter.sortedByScore(entries)

        XCTAssertEqual(sorted.map(\.label), ["Entry A", "Entry B", "Entry C"])
    }
}
