#if os(Linux)

import XCTest
@testable import EngineioServerTestSuite

XCTMain([
  testCase(EngineioServerTests.allTests),
])
#endif
