import XCTest
@testable import EngineioServer

class EngineioServerTests: XCTestCase {
    func testReality() {
        XCTAssert(2 + 2 == 4, "Something is severely wrong here.")
    }
}

extension EngineioServerTests {
    static var allTests: [(String, (EngineioServerTests) -> () throws -> Void)] {
        return [
           ("testReality", testReality),
        ]
    }
}
