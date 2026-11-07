// duo-guest: the helper that runs INSIDE the simulator (`xcrun simctl spawn <udid> <path> <verb> …`).
// Compiled on demand by `duo guest-build`; never checked in as a binary.
// Verbs and the vendor-HID / CoreMotion approach derive from agent-device's apple/fold-helper/Fold.m
// (MIT, Copyright (c) 2026 Callstack, v0.21.36); see THIRD-PARTY-NOTICES.md at the repository root.
//
// Contract: JSON on stdout, diagnostics on stderr.
//   exit 0   done
//   exit 2   usage error (bad verb or arguments)
//   exit 1   a HID event could not be created or dispatched
//   exit 3   CoreMotion's private angle class is missing
//   exit 4   no hinge sample within 3 s
// Panels are not a guest verb: the host reads them with the documented `devicectl device info displays`.

import Foundation

let usageText = """
    usage: duo-guest <verb> [arguments]

    verbs:
      set <closed|half-open|open|angle>       move the hinge (closed 0, half-open 130, open 180, or 0...180 degrees)
      rotate <portrait|landscape-left|landscape-right>
                                              rotate the device
      hinge [windowMs]                        read the hinge angle, optionally sampling for windowMs (0...5000)
      stream                                  print {"ready":true}, then send one hinge angle (0...180) per line of stdin
                                              as it arrives (the host paces them); exit at end of input
    """

func writeJSON(_ object: [String: Any], to handle: FileHandle) {
    let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return }
    handle.write(data)
    handle.write(Data("\n".utf8))
}

func writeError(_ message: String) {
    FileHandle.standardError.write(Data("duo-guest: \(message)\n".utf8))
}

func usageFailure(_ message: String? = nil) -> Never {
    if let message { writeError(message) }
    FileHandle.standardError.write(Data((usageText + "\n").utf8))
    exit(2)
}

/// A verb whose arguments parsed; the part of the contract that is real in A.4.
struct Request {
    var verb: String
    var parameters: [String: Any]
}

func parseAngle(_ text: String) -> Double? {
    switch text {
    case "closed": return 0
    case "half-open": return 130
    case "open": return 180
    default:
        guard let value = Double(text), value.isFinite, (0...180).contains(value) else { return nil }
        return value
    }
}

func parse(_ arguments: [String]) -> Request {
    guard let verb = arguments.first, verb != "-h", verb != "--help" else { usageFailure() }
    let rest = Array(arguments.dropFirst())
    switch verb {
    case "set":
        guard rest.count == 1, let angle = parseAngle(rest[0]) else {
            usageFailure("set needs closed, half-open, open or an angle in 0...180")
        }
        return Request(verb: verb, parameters: ["angle": angle])
    case "rotate":
        let known: Set<String> = ["portrait", "landscape-left", "landscape-right"]
        guard rest.count == 1, known.contains(rest[0]) else {
            usageFailure("rotate needs portrait, landscape-left or landscape-right")
        }
        return Request(verb: verb, parameters: ["orientation": rest[0]])
    case "hinge":
        guard rest.count <= 1 else { usageFailure("hinge takes at most one argument, windowMs") }
        var windowMs = 0
        if let text = rest.first {
            guard let value = Int(text), (0...5000).contains(value) else {
                usageFailure("hinge windowMs must be an integer in 0...5000")
            }
            windowMs = value
        }
        return Request(verb: verb, parameters: ["windowMs": windowMs])
    case "stream":
        guard rest.isEmpty else { usageFailure("stream takes no arguments") }
        return Request(verb: verb, parameters: [:])
    default:
        usageFailure("unknown verb '\(verb)'")
    }
}

let request = parse(Array(CommandLine.arguments.dropFirst()))

// CoreMotion's private angle manager, looked up at runtime so no private header is needed.
// Mirrors Fold.m `readHinge`: the manager delivers the current angle on subscription and then each change,
// so after `windowMs` the latest sample is where the hinge is now.
final class AngleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var received = false
    private var angle = Double.nan
    private var valid = false
    let sampled = DispatchSemaphore(value: 0)

    func record(angle: Double, valid: Bool) {
        lock.lock()
        self.angle = angle
        self.valid = valid
        let first = !received
        received = true
        lock.unlock()
        if first { sampled.signal() }
    }

    var latest: (angle: Double, valid: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (angle, valid)
    }
}

typealias ClassBoolIMP = @convention(c) (AnyClass, Selector) -> Bool
typealias InstanceBoolIMP = @convention(c) (AnyObject, Selector) -> Bool
typealias InstanceFloatIMP = @convention(c) (AnyObject, Selector) -> Float
typealias InstanceVoidIMP = @convention(c) (AnyObject, Selector) -> Void
typealias StartIMP = @convention(c) (AnyObject, Selector, OperationQueue, AnyObject) -> Void

func readHinge(windowMs: Int) -> Never {
    dlopen("/System/Library/Frameworks/CoreMotion.framework/CoreMotion", RTLD_NOW)
    let isAvailable = Selector(("isAvailable"))
    let start = Selector(("startAngleUpdatesToQueue:handler:"))
    guard let managerClass = NSClassFromString("CMAngleManager") as? NSObject.Type,
        let availableMethod = class_getClassMethod(managerClass, isAvailable),
        unsafeBitCast(method_getImplementation(availableMethod), to: ClassBoolIMP.self)(managerClass, isAvailable),
        let startMethod = class_getInstanceMethod(managerClass, start)
    else {
        writeError("CMAngleManager is not available in this simulator runtime")
        exit(3)
    }
    let startIMP = unsafeBitCast(method_getImplementation(startMethod), to: StartIMP.self)
    let manager = managerClass.init()
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let box = AngleBox()
    let angleSelector = Selector(("angleDegrees"))
    let validSelector = Selector(("isAngleValid"))
    // The real handler also receives an NSError; the block declares only the sample, as Fold.m does.
    let handler: @convention(block) (AnyObject?) -> Void = { sample in
        guard let sample, sample.responds(to: angleSelector) else { return }
        let angle = unsafeBitCast(
            class_getMethodImplementation(object_getClass(sample), angleSelector),
            to: InstanceFloatIMP.self
        )(
            sample,
            angleSelector
        )
        var valid = false
        if sample.responds(to: validSelector) {
            valid = unsafeBitCast(
                class_getMethodImplementation(object_getClass(sample), validSelector),
                to: InstanceBoolIMP.self
            )(
                sample,
                validSelector
            )
        }
        box.record(angle: Double(angle), valid: valid)
    }
    startIMP(manager, start, queue, unsafeBitCast(handler, to: AnyObject.self))
    let timedOut = box.sampled.wait(timeout: .now() + 3) == .timedOut
    if !timedOut && windowMs > 0 { Thread.sleep(forTimeInterval: Double(windowMs) / 1000) }
    let stop = Selector(("stopAngleUpdates"))
    if manager.responds(to: stop) {
        unsafeBitCast(class_getMethodImplementation(managerClass, stop), to: InstanceVoidIMP.self)(manager, stop)
    }
    queue.waitUntilAllOperationsAreFinished()
    if timedOut {
        writeError("CMAngleManager delivered no hinge sample within 3 seconds")
        exit(4)
    }
    let reading = box.latest
    let rounded = (reading.angle * 1000).rounded() / 1000
    writeJSON(["version": 1, "angleDegrees": rounded, "angleValid": reading.valid], to: FileHandle.standardOutput)
    exit(0)
}

if request.verb == "hinge", let windowMs = request.parameters["windowMs"] as? Int {
    readHinge(windowMs: windowMs)
}

// Xcode's Device Hub protocol: a vendor-defined HID event (page 0xff61, usage 0x5b) carrying a serialized
// dictionary. The simulator guest routes `hinge-slider-control` to its simulated hinge sensor. Ported from
// Fold.m `sendControl`; the private IOKit entry points are resolved at runtime.
typealias SerializeFn = @convention(c) (UnsafeRawPointer, UInt) -> UnsafeRawPointer?
typealias CreateEventFn =
    @convention(c) (
        UnsafeRawPointer?, UInt64, UInt32, UInt32, UInt32, UnsafePointer<UInt8>?, CFIndex, UInt32
    ) -> UnsafeRawPointer?
typealias CreateClientFn = @convention(c) (UnsafeRawPointer?) -> UnsafeRawPointer?
typealias DispatchFn = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Void

struct HIDSender {
    let serialize: SerializeFn
    let createEvent: CreateEventFn
    let dispatch: DispatchFn
    let client: UnsafeRawPointer

    init?() {
        dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            let runtimeDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
            guard let pointer = dlsym(runtimeDefault, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let serialize = symbol("IOCFSerialize", as: SerializeFn.self),
            let createEvent = symbol("IOHIDEventCreateVendorDefinedEvent", as: CreateEventFn.self),
            let createClient = symbol("IOHIDEventSystemClientCreate", as: CreateClientFn.self),
            let dispatch = symbol("IOHIDEventSystemClientDispatchEvent", as: DispatchFn.self),
            let client = createClient(nil)
        else { return nil }
        self.serialize = serialize
        self.createEvent = createEvent
        self.dispatch = dispatch
        self.client = client
    }

    func release() {
        Unmanaged<AnyObject>.fromOpaque(client).release()
    }

    func sendControl(source: String, type: String, value: NSObject) -> Bool {
        let payload =
            [
                "provider": "com.apple.Virtualization.VirtualMachines", "source": source, "type": type,
                "value": value,
            ] as NSDictionary
        // The raw pointers below do not keep their objects alive, so pin both until the calls that read them return.
        let dataPointer = withExtendedLifetime(payload) { serialize(Unmanaged.passUnretained(payload).toOpaque(), 1) }
        guard let dataPointer else { return false }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeRetainedValue()
        let created = withExtendedLifetime(data) {
            createEvent(
                nil,
                mach_absolute_time(),
                0xff61,
                0x5b,
                0,
                CFDataGetBytePtr(data),
                CFDataGetLength(data),
                0
            )
        }
        guard let event = created else { return false }
        dispatch(client, event)
        Unmanaged<AnyObject>.fromOpaque(event).release()
        return true
    }
}

func setHinge(angle: Double) -> Never {
    guard let sender = HIDSender() else {
        writeError("IOKit's HID event entry points are not available in this simulator runtime")
        exit(1)
    }
    // Fold.m's runFrames sends `@(angle)`, a double, for every frame; so does this.
    let sent = sender.sendControl(source: "hinge-slider-control", type: "range", value: NSNumber(value: angle))
    sender.release()
    guard sent else {
        writeError("Unable to create simulator HID event")
        exit(1)
    }
    writeJSON(["version": 1, "ok": true, "angle": angle], to: FileHandle.standardOutput)
    exit(0)
}

if request.verb == "set", let angle = request.parameters["angle"] as? Double {
    setHinge(angle: angle)
}

// Fold.m `runRotate`: the same vendor event, source `orientation-picker-control`, an enum whose value is the
// orientation name itself. The control has no upside-down value.
func rotate(to orientation: String) -> Never {
    guard let sender = HIDSender() else {
        writeError("IOKit's HID event entry points are not available in this simulator runtime")
        exit(1)
    }
    let sent = sender.sendControl(source: "orientation-picker-control", type: "enum", value: orientation as NSString)
    sender.release()
    guard sent else {
        writeError("Unable to create simulator HID event")
        exit(1)
    }
    writeJSON(["version": 1, "ok": true, "orientation": orientation], to: FileHandle.standardOutput)
    exit(0)
}

if request.verb == "rotate", let orientation = request.parameters["orientation"] as? String {
    rotate(to: orientation)
}

// `duo fold --keyframes`: the host owns the 60 Hz schedule (absolute deadlines) and writes each frame's angle to
// our stdin; we hold one HID client open and dispatch each line the moment it arrives. Fold.m's `runFrames` did the
// pacing in-process with `mach_wait_until`; doing it here instead would duplicate the schedule outside the tested kit.
// A per-frame `simctl spawn` is far too slow for 60 Hz, hence one long-lived process.
func stream() -> Never {
    guard let sender = HIDSender() else {
        writeError("IOKit's HID event entry points are not available in this simulator runtime")
        exit(1)
    }
    writeJSON(["version": 1, "ready": true], to: FileHandle.standardOutput)
    var frames = 0
    while let line = readLine() {
        guard let angle = Double(line.trimmingCharacters(in: .whitespaces)), angle.isFinite, (0...180).contains(angle)
        else {
            writeError("stream: '\(line)' is not an angle in 0...180")
            exit(2)
        }
        guard sender.sendControl(source: "hinge-slider-control", type: "range", value: NSNumber(value: angle)) else {
            writeError("Unable to create simulator HID event")
            exit(1)
        }
        frames += 1
    }
    sender.release()
    writeJSON(["version": 1, "ok": true, "frames": frames], to: FileHandle.standardOutput)
    exit(0)
}

if request.verb == "stream" {
    stream()
}

writeError("internal error: verb '\(request.verb)' has no handler")
exit(70)
