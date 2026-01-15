import XCTest
@testable import steve

final class CLIRunnerTests: XCTestCase {
    func testRunCLIUnknownCommand() {
        let code = runCLI(args: ["nope", "--quiet"])
        XCTAssertEqual(code, UitoolExit.invalidArguments.rawValue)
    }
}
