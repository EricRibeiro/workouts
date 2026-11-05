import Foundation

/// Output of one finished process.
public struct ProcessOutput: Sendable, Equatable {
    public var status: Int32
    public var stdout: Data
    public var stderr: String

    public init(status: Int32, stdout: Data, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs a host process. Tests substitute a fake that returns fixtures.
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, arguments: [String]) throws -> ProcessOutput
}

/// Runs real processes (`/usr/bin/xcrun …`). A process that outlives `timeout` gets SIGTERM, then SIGKILL two seconds
/// later, and the call throws `DuoError.timedOut`, so a hung `simctl` or `devicectl` can never hang `duo`.
public struct SystemProcessRunner: ProcessRunning {
    public var timeout: TimeInterval
    /// Grace period between SIGTERM and SIGKILL.
    public var killGrace: TimeInterval

    public init(timeout: TimeInterval = 60, killGrace: TimeInterval = 2) {
        self.timeout = timeout
        self.killGrace = killGrace
    }

    public func run(_ executable: String, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        // stderr goes to a file so a chatty child can never fill the pipe while we block reading stdout.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("duo-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errorURL) }
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        process.standardOutput = stdout
        process.standardError = errorHandle
        try process.run()

        let expired = ExpiryFlag()
        let pid = process.processIdentifier
        let terminate = DispatchWorkItem {
            expired.set()
            process.terminate()
        }
        let kill = DispatchWorkItem { Darwin.kill(pid, SIGKILL) }
        let queue = DispatchQueue.global(qos: .userInitiated)
        queue.asyncAfter(deadline: .now() + timeout, execute: terminate)
        queue.asyncAfter(deadline: .now() + timeout + killGrace, execute: kill)

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        terminate.cancel()
        kill.cancel()
        try? errorHandle.close()
        if expired.isSet {
            let command = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
            throw DuoError.timedOut(command: command, seconds: timeout)
        }
        let message = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
        return ProcessOutput(status: process.terminationStatus, stdout: data, stderr: message)
    }
}

private final class ExpiryFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

public enum DuoError: Error, Equatable, CustomStringConvertible {
    case commandFailed(command: String, status: Int32, stderr: String)
    case timedOut(command: String, seconds: TimeInterval)
    case undecodable(command: String, reason: String)
    case noDisplays
    case litPanelCount(Int, names: [String])
    case panelNotFound(DisplaySelector, available: [String])
    case lockTimeout(path: String)
    case guestSourceMissing(path: String)
    case repositoryNotFound
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .commandFailed(let command, let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) failed with exit status \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        case .timedOut(let command, let seconds):
            return "\(command) timed out after \(String(format: "%g", seconds)) s"
        case .undecodable(let command, let reason):
            return "could not decode the output of \(command): \(reason)"
        case .noDisplays:
            return "the device reported no displays"
        case .litPanelCount(let count, let names):
            let list = names.isEmpty ? "none" : names.joined(separator: ", ")
            return "expected exactly one lit panel, found \(count) (lit: \(list))"
        case .panelNotFound(let selector, let available):
            return "no \(selector.rawValue) panel among displays: \(available.joined(separator: ", "))"
        case .lockTimeout(let path):
            return "timed out waiting for the lock at \(path); remove it if no duo process is running"
        case .guestSourceMissing(let path):
            return "guest source not found at \(path)"
        case .verificationFailed(let message):
            return message
        case .repositoryNotFound:
            return "run duo from inside the workouts checkout (Tools/duo/Guest/DuoGuest.swift not found)"
        }
    }
}

/// One entry of `devicectl device info displays` (`result.displays[]`). Unknown fields are ignored.
public struct Display: Sendable, Equatable, Decodable {
    public var name: String
    public var displayId: Int?
    public var uniqueId: String?
    public var active: Bool?
    public var backlightState: String?
    /// Pixels, `[width, height]`.
    public var nativeSize: [Double]?
    public var pointScale: Double?
    /// `rot0`, `rot90`, `rot180`, `rot270`.
    public var currentOrientation: String?
    /// The orientation `nativeSize` is expressed in.
    public var nativeOrientation: String?
    public var primary: Bool?
    /// True when the JSON has `type.integrated` (the panel is built in rather than external).
    public var integrated: Bool

    private enum CodingKeys: String, CodingKey {
        case name, displayId, uniqueId, active, backlightState, nativeSize, pointScale, currentOrientation,
            nativeOrientation, primary, type
    }

    private enum TypeKeys: String, CodingKey {
        case integrated
    }

    public init(
        name: String,
        displayId: Int? = nil,
        uniqueId: String? = nil,
        active: Bool? = nil,
        backlightState: String? = nil,
        nativeSize: [Double]? = nil,
        pointScale: Double? = nil,
        currentOrientation: String? = nil,
        nativeOrientation: String? = nil,
        primary: Bool? = nil,
        integrated: Bool = false
    ) {
        self.name = name
        self.displayId = displayId
        self.uniqueId = uniqueId
        self.active = active
        self.backlightState = backlightState
        self.nativeSize = nativeSize
        self.pointScale = pointScale
        self.currentOrientation = currentOrientation
        self.nativeOrientation = nativeOrientation
        self.primary = primary
        self.integrated = integrated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        displayId = try container.decodeIfPresent(Int.self, forKey: .displayId)
        uniqueId = try container.decodeIfPresent(String.self, forKey: .uniqueId)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        backlightState = try container.decodeIfPresent(String.self, forKey: .backlightState)
        nativeSize = try container.decodeIfPresent([Double].self, forKey: .nativeSize)
        pointScale = try container.decodeIfPresent(Double.self, forKey: .pointScale)
        currentOrientation = try container.decodeIfPresent(String.self, forKey: .currentOrientation)
        nativeOrientation = try container.decodeIfPresent(String.self, forKey: .nativeOrientation)
        primary = try container.decodeIfPresent(Bool.self, forKey: .primary)
        if let type = try? container.nestedContainer(keyedBy: TypeKeys.self, forKey: .type) {
            integrated = type.contains(.integrated)
        } else {
            integrated = false
        }
    }
}

private struct DisplaysDocument: Decodable {
    struct Result: Decodable {
        var displays: [Display]
    }
    var result: Result
}

/// Wrapper for the documented `xcrun devicectl …` calls.
public struct Devicectl: Sendable {
    public var runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// `xcrun devicectl device info displays --device <udid> --json-output -`
    public func displays(udid: String) throws -> [Display] {
        let arguments = ["devicectl", "device", "info", "displays", "--device", udid, "--json-output", "-", "--quiet"]
        let command = "xcrun " + arguments.joined(separator: " ")
        let output = try runner.run("/usr/bin/xcrun", arguments: arguments)
        guard output.status == 0 else {
            throw DuoError.commandFailed(command: command, status: output.status, stderr: output.stderr)
        }
        return try Self.decodeDisplays(output.stdout, command: command)
    }

    public static func decodeDisplays(_ data: Data, command: String = "devicectl device info displays") throws
        -> [Display]
    {
        do {
            return try JSONDecoder().decode(DisplaysDocument.self, from: data).result.displays
        } catch {
            throw DuoError.undecodable(command: command, reason: String(describing: error))
        }
    }
}
