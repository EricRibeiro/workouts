// Writes thumb-crops.json: per library exercise, the crop rectangle [x, y, w, h] (unit coordinates, origin top-left)
// that holds the figure in its start and end thumbnails. Run through `./dev thumb-crops`.
//
// Usage: thumb-crops <thumbs directory> <output file>
//
// Background: the corner pixels name it. Transparent corners (the usual case) make every pixel with alpha > 8 content;
// opaque corners (a handful of images with a solid backdrop) make every pixel that differs from the corner colour by
// more than 12 in any channel content. The rectangle is the union of both frames' content bounds, grown by 4% of its
// own width and height on each side and clamped to the image. Output is sorted by id with four decimals, so reruns
// are byte-identical.

import CoreGraphics
import Foundation
import ImageIO

let alphaThreshold = 8
let colorThreshold = 12
let marginFraction = 0.04

struct Bounds {
    var minX: Int, minY: Int, maxX: Int, maxY: Int
    var width: Int, height: Int

    mutating func formUnion(_ other: Bounds) {
        minX = min(minX, other.minX)
        minY = min(minY, other.minY)
        maxX = max(maxX, other.maxX)
        maxY = max(maxY, other.maxY)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("thumb-crops: \(message)\n".utf8))
    exit(1)
}

/// Content bounds in pixels, nil when the image has no content or cannot be read.
func contentBounds(of url: URL) -> Bounds? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let w = image.width
    let h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = px.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { return nil }

    func pixel(_ x: Int, _ y: Int) -> [Int] { (0..<4).map { Int(px[(y * w + x) * 4 + $0]) } }
    let corners = [pixel(0, 0), pixel(w - 1, 0), pixel(0, h - 1), pixel(w - 1, h - 1)]
    let opaqueBackdrop = corners.allSatisfy { $0[3] > alphaThreshold && $0 == corners[0] }
    let backdrop = corners[0]

    var bounds: Bounds?
    for y in 0..<h {
        for x in 0..<w {
            let p = pixel(x, y)
            let isContent: Bool
            if opaqueBackdrop {
                isContent = (0..<4).contains { abs(p[$0] - backdrop[$0]) > colorThreshold }
            } else {
                isContent = p[3] > alphaThreshold
            }
            guard isContent else { continue }
            let here = Bounds(minX: x, minY: y, maxX: x, maxY: y, width: w, height: h)
            if bounds == nil { bounds = here } else { bounds?.formUnion(here) }
        }
    }
    return bounds
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: thumb-crops <thumbs directory> <output file>") }
let directory = URL(fileURLWithPath: args[1], isDirectory: true)
let output = URL(fileURLWithPath: args[2])

let files: [String]
do { files = try FileManager.default.contentsOfDirectory(atPath: args[1]).sorted() } catch {
    fail("cannot read \(args[1]): \(error.localizedDescription)")
}

var unionByID: [String: Bounds] = [:]
var unreadable: [String] = []
var empty: [String] = []
for file in files where file.hasSuffix("-start.png") || file.hasSuffix("-end.png") {
    let id = String(file[..<file.range(of: "-", options: .backwards)!.lowerBound])
    guard let found = contentBounds(of: directory.appendingPathComponent(file)) else {
        if CGImageSourceCreateWithURL(directory.appendingPathComponent(file) as CFURL, nil) == nil {
            unreadable.append(file)
        } else {
            empty.append(file)
        }
        continue
    }
    if unionByID[id] == nil { unionByID[id] = found } else { unionByID[id]?.formUnion(found) }
}
if !unreadable.isEmpty { fail("unreadable images: \(unreadable.joined(separator: ", "))") }
for file in empty { FileHandle.standardError.write(Data("thumb-crops: no content in \(file)\n".utf8)) }

func fixed(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }

var lines: [String] = []
for id in unionByID.keys.sorted() {
    let b = unionByID[id]!
    let x0 = Double(b.minX) / Double(b.width)
    let x1 = Double(b.maxX + 1) / Double(b.width)
    let y0 = Double(b.minY) / Double(b.height)
    let y1 = Double(b.maxY + 1) / Double(b.height)
    let mx = (x1 - x0) * marginFraction
    let my = (y1 - y0) * marginFraction
    let left = fixed(max(0, x0 - mx))
    let right = fixed(min(1, x1 + mx))
    let top = fixed(max(0, y0 - my))
    let bottom = fixed(min(1, y1 + my))
    let rect = [left, top, fixed(right - left), fixed(bottom - top)]
    lines.append("  \"\(id)\": [" + rect.map { String(format: "%.4f", $0) }.joined(separator: ", ") + "]")
}
let json = "{\n" + lines.joined(separator: ",\n") + "\n}\n"
do { try json.write(to: output, atomically: true, encoding: .utf8) } catch {
    fail("cannot write \(args[2]): \(error.localizedDescription)")
}
print("thumb-crops: \(lines.count) ids -> \(args[2])")
