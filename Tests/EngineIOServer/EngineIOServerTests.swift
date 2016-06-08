import XCTest
@testable import EngineIOServer

class EngineIOServerTests: XCTestCase {
    func testReality() {
        XCTAssert(2 + 2 == 4, "Something is severely wrong here.")
    }
}

extension EngineIOServerTests {
    static var allTests: [(String, (EngineIOServerTests) -> () throws -> Void)] {
        return [
           ("testReality", testReality),
        ]
    }
}
