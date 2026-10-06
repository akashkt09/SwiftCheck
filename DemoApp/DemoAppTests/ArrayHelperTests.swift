import XCTest
@testable import DemoApp

final class ArrayHelperTests: XCTestCase {
    func testLastIndexIsOneLessThanCount() {
        XCTAssertEqual(ArrayHelper.lastIndex(of: [10, 20, 30]), 2)
    }
}
