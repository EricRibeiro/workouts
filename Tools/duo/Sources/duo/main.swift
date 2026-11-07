import DuoKit
import Foundation

let usage = """
    usage: duo <command> [options]

    commands:
      panels --udid <udid>    list the device's displays: name, lit or dark, pixel size, point size, orientation

      screenshot <path> --udid <udid> [--display lit|outer|inner] [--settle [--timeout <seconds>]]
                              capture one panel (default: the lit one) to a PNG and print its size; --settle repeats
                              the capture until two consecutive ones are identical, so the PNG is the settled one
      settle --udid <udid> [--timeout <seconds>]
                              capture the lit panel every 300 ms until two consecutive captures hash equal (SHA-256);
                              exit 1 with a message when the timeout (default 10 s) passes first

      hinge --udid <udid> [--window-ms 0...5000] [--json]
                              read the hinge angle: angle, validity, pose (closed, half-open, open) and lit panel
      fold <closed|half-open|open|degrees> --udid <udid> [--png <path>]
                              move the hinge, verify it by hinge reads and the lit panel, optionally screenshot it
      orient <portrait|landscape-left|landscape-right> --udid <udid> [--png <path>]
                              rotate the device, verify by devicectl orientation and the lit panel, optionally screenshot
      pose <closed-portrait|closed-landscape|open-wide|open-tall> --udid <udid> [--png <path> [--settle [--timeout <s>]]]
                              fold + orient + verify in one call (open-wide = open portrait 951x669 pt, open-tall =
                              open landscape-left 669x951 pt), optionally screenshot the lit panel (settled with --settle)
      home --udid <udid> [--png <path>]
                              go to the Home screen (launches SpringBoard) and confirm with a lit-panel screenshot
      guest-build         compile the in-simulator helper (cached per source and Xcode) and print its path

    options:
      -h, --help              show this help
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("duo: \(message)\n".utf8))
    exit(1)
}

func usageError(_ message: String? = nil) -> Never {
    let text = (message.map { "duo: \($0)\n" } ?? "") + usage + "\n"
    FileHandle.standardError.write(Data(text.utf8))
    exit(2)
}

/// Value of `--name <value>` or `--name=<value>`; nil when absent.
func option(_ name: String, in arguments: [String]) -> String? {
    for (index, argument) in arguments.enumerated() {
        if argument == name { return index + 1 < arguments.count ? arguments[index + 1] : nil }
        if argument.hasPrefix(name + "=") { return String(argument.dropFirst(name.count + 1)) }
    }
    return nil
}

/// Exits 2 when any `-`-prefixed argument is not one of `known` (as `--name` or `--name=value`).
func rejectUnknownOptions(_ arguments: [String], known: Set<String>) {
    for argument in arguments where argument.hasPrefix("-") {
        let name = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
        if !known.contains(name) { usageError("unknown option \(argument)") }
    }
}

/// Seconds from `--timeout`, default `Settle.defaultTimeout`; exits 2 when it is not a positive number.
func settleTimeout(in arguments: [String]) -> TimeInterval {
    guard let text = option("--timeout", in: arguments) else { return Settle.defaultTimeout }
    guard let value = Double(text), value > 0, value <= 600 else {
        usageError("--timeout must be a number of seconds in 0...600")
    }
    return value
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "-h" || arguments.first == "--help" {
    print(usage)
    exit(0)
}
guard let verb = arguments.first else { usageError() }
let rest = Array(arguments.dropFirst())

switch verb {
case "panels":
    rejectUnknownOptions(rest, known: ["--udid"])
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("panels needs --udid <udid>") }
    do {
        let displays = try Devicectl().displays(udid: udid)
        for line in Panels.table(displays) { print(line) }
    } catch {
        fail("\(error)")
    }
case "hinge":
    rejectUnknownOptions(rest, known: ["--udid", "--window-ms", "--json"])
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("hinge needs --udid <udid>") }
    var windowMs = 0
    if let text = option("--window-ms", in: rest) {
        guard let value = Int(text), (0...5000).contains(value) else {
            usageError("--window-ms must be an integer in 0...5000")
        }
        windowMs = value
    }
    guard let root = GuestBuilder.defaultRepositoryRoot() else { fail("\(DuoError.repositoryNotFound)") }
    do {
        let guest = try GuestBuilder(repositoryRoot: root).build()
        let report = try Hinge.read(udid: udid, windowMs: windowMs, guestPath: guest.path)
        print(rest.contains("--json") ? report.json : report.text)
    } catch {
        fail("\(error)")
    }
case "fold":
    rejectUnknownOptions(Array(rest.dropFirst()), known: ["--udid", "--png"])
    guard let argument = rest.first, !argument.hasPrefix("-"), let target = FoldTarget.parse(argument) else {
        usageError("fold needs closed, half-open, open or an angle in 0...180")
    }
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("fold needs --udid <udid>") }
    guard let root = GuestBuilder.defaultRepositoryRoot() else { fail("\(DuoError.repositoryNotFound)") }
    do {
        let guest = try GuestBuilder(repositoryRoot: root).build()
        let result = try Fold.run(target: target, udid: udid, guestPath: guest.path, png: option("--png", in: rest))
        print(result.summary)
    } catch {
        fail("\(error)")
    }
case "orient":
    rejectUnknownOptions(Array(rest.dropFirst()), known: ["--udid", "--png"])
    guard let argument = rest.first, let target = TargetOrientation(rawValue: argument) else {
        usageError("orient needs portrait, landscape-left or landscape-right")
    }
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("orient needs --udid <udid>") }
    guard let root = GuestBuilder.defaultRepositoryRoot() else { fail("\(DuoError.repositoryNotFound)") }
    do {
        let guest = try GuestBuilder(repositoryRoot: root).build()
        let result = try Orient.run(target: target, udid: udid, guestPath: guest.path, png: option("--png", in: rest))
        print(result.summary)
    } catch {
        fail("\(error)")
    }
case "pose":
    rejectUnknownOptions(Array(rest.dropFirst()), known: ["--udid", "--png", "--settle", "--timeout"])
    guard let argument = rest.first, let pose = NamedPose(rawValue: argument) else {
        usageError("pose needs \(NamedPose.usageList)")
    }
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("pose needs --udid <udid>") }
    guard let root = GuestBuilder.defaultRepositoryRoot() else { fail("\(DuoError.repositoryNotFound)") }
    do {
        let guest = try GuestBuilder(repositoryRoot: root).build()
        let result = try PoseCommand.run(
            pose: pose,
            udid: udid,
            guestPath: guest.path,
            png: option("--png", in: rest),
            settle: rest.contains("--settle") ? settleTimeout(in: rest) : nil
        )
        print(result.summary)
    } catch {
        fail("\(error)")
    }
case "home":
    rejectUnknownOptions(rest, known: ["--udid", "--png"])
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("home needs --udid <udid>") }
    do {
        let result = try Home.run(udid: udid, png: option("--png", in: rest))
        print(option("--png", in: rest) == nil ? "home: lit panel \(result.display.name)" : result.summary)
    } catch {
        fail("\(error)")
    }
case "guest-build":
    rejectUnknownOptions(rest, known: [])
    guard rest.isEmpty else { usageError("guest-build takes no arguments") }
    guard let root = GuestBuilder.defaultRepositoryRoot() else { fail("\(DuoError.repositoryNotFound)") }
    do {
        print(try GuestBuilder(repositoryRoot: root).build().path)
    } catch {
        fail("\(error)")
    }
case "settle":
    rejectUnknownOptions(rest, known: ["--udid", "--timeout"])
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("settle needs --udid <udid>") }
    let timeout = settleTimeout(in: rest)
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("duo-settle-\(getpid()).png").path
    defer { try? FileManager.default.removeItem(atPath: scratch) }
    do {
        let (shot, settled) = try Screenshot.captureSettled(path: scratch, udid: udid, timeout: timeout)
        print("settle: lit panel \(shot.display.name), \(settled.summary)")
    } catch {
        fail("\(error)")
    }
case "screenshot":
    rejectUnknownOptions(Array(rest.dropFirst()), known: ["--udid", "--display", "--settle", "--timeout"])
    guard let path = rest.first, !path.hasPrefix("-") else { usageError("screenshot needs a <path>") }
    guard let udid = option("--udid", in: rest), !udid.isEmpty else { usageError("screenshot needs --udid <udid>") }
    var selector = DisplaySelector.lit
    if let name = option("--display", in: rest) {
        guard let parsed = DisplaySelector(rawValue: name) else {
            usageError("--display must be lit, outer or inner (got '\(name)')")
        }
        selector = parsed
    }
    do {
        if rest.contains("--settle") {
            let (shot, settled) = try Screenshot.captureSettled(
                path: path,
                udid: udid,
                selector: selector,
                timeout: settleTimeout(in: rest)
            )
            print(shot.summary + "\n" + settled.summary)
        } else {
            print(try Screenshot.capture(path: path, udid: udid, selector: selector).summary)
        }
    } catch {
        fail("\(error)")
    }
default:
    usageError("unknown command '\(verb)'")
}
