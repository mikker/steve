import XCTest
@testable import steve

final class CLIRunnerTests: XCTestCase {
    func testDispatchCommandsAreDocumented() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Sources/steve/CLI.swift")
        let source = try String(contentsOf: sourceURL)
        let lines = source.split(separator: "\n")

        guard let switchStart = lines.firstIndex(where: { $0.contains("switch command {") }) else {
            return XCTFail("dispatch switch not found")
        }
        guard let switchEnd = lines[switchStart...].firstIndex(where: { $0.contains("default:") }) else {
            return XCTFail("dispatch switch end not found")
        }

        let regex = try NSRegularExpression(pattern: "\"([^\"]+)\"")
        let documented = Set(visibleCommands)
        var dispatched: Set<String> = []
        for line in lines[switchStart...switchEnd] where line.contains("case ") {
            let text = String(line)
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let command = String(text[range])
                if command == "--help" || command == "-h" || command == "help" {
                    continue
                }
                dispatched.insert(command)
            }
        }

        XCTAssertEqual(documented, dispatched)
    }

    func testEveryVisibleCommandHasHelpText() {
        for command in visibleCommands {
            XCTAssertNotNil(commandUsage(command), "Missing help for \(command)")
        }
    }

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

    func testRunCLIHelpSubcommand() {
        let code = runCLI(args: ["help", "find"])
        XCTAssertEqual(code, UitoolExit.success.rawValue)
    }

    func testRunCLIHelpSubcommandUnknownCommand() {
        let code = runCLI(args: ["help", "nope"])
        XCTAssertEqual(code, UitoolExit.invalidArguments.rawValue)
    }

    func testCommandHelpFlagsDoNotTreatLiteralHelpAsFlag() {
        XCTAssertFalse(hasCommandHelpFlag(["help"]))
        XCTAssertTrue(hasCommandHelpFlag(["--help"]))
        XCTAssertTrue(hasCommandHelpFlag(["-h"]))
    }
}
