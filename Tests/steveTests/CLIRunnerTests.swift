import XCTest
@testable import steve

final class CLIRunnerTests: XCTestCase {
    func testRunCLIUnknownCommand() {
        let code = runCLI(args: ["nope", "--quiet"])
        XCTAssertEqual(code, UitoolExit.invalidArguments.rawValue)
    }

    func testRunCLINoArgsShowsUsage() {
        let code = runCLI(args: [])
        XCTAssertEqual(code, UitoolExit.success.rawValue)
    }

    func testRunCLIGlobalHelp() {
        let code = runCLI(args: ["-h"])
        XCTAssertEqual(code, UitoolExit.success.rawValue)
    }
}
