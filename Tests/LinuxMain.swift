import XCTest
@testable import RethinkDBTests

XCTMain([
     testCase(ConnectionTests.allTests),
     testCase(ReqlAstTests.allTests)
])