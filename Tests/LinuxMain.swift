#if os(Linux)

import XCTest
@testable import EngineIOServerTestSuite

XCTMain([
  testCase(EngineIOServerTests.allTests),
])
#endif
